# HPC runbook — fitting both papers on Oxford's SLURM service

> **Note for this repository.** This runbook covers the cluster setup for the whole LESS
> project, which produced two papers from one dataset and one shared environment. It is
> reproduced unchanged in each paper's repository, because the layout, the environment,
> the transfer recipes and the troubleshooting apply equally to both. Stages named under
> `paper_1_transfer/` belong to the companion paper and live in
> <https://github.com/pablobernabeu/LESS-morphosyntactic-transfer>. They are kept here so the picture of the
> cluster is complete, and they are not part of this repository.

The Bayesian fits run on Oxford's SLURM service, reached at `arc-login.arc.ox.ac.uk`,
as user `educ1242` in project group `educ-intract`. Its two clusters, ARC and HTC, both
use environment modules rather than a Singularity container, and access is by SSH key.
`arc` is a host alias in the author's `~/.ssh/config`, not a name the service publishes: it
resolves to `educ1242@arc-login.arc.ox.ac.uk` and reaches it by `ProxyJump` through
`gateway.arc.ox.ac.uk`, which is what makes it work from off the university network. Because
the key it uses carries a passphrase, `ssh arc` prompts unless that key is already loaded in
`ssh-agent`, so scripted polling goes through a second alias configured for unattended use.
On any other machine, define an equivalent alias first, with `ProxyJump` through
`gateway.arc.ox.ac.uk`, and use its name everywhere below, including in the `scp` recipes. A
bare `educ1242@arc-login.arc.ox.ac.uk` reaches the login node only from inside the Oxford
network.

**ARC or HTC.** The project `/data` space is mounted at the same path on both, so
`_shared/hpc/arc_env.sh` serves either and no job script has to change. Only the
submission line differs. A plain `sbatch`, which is what every recipe below and both
`submit_all.sh` scripts use, goes to the login node's default cluster, ARC, where
project access comes through the `educ-intract` unix group and no `--account` is
needed. Since 2026-06-30 the preferred target for these single-node jobs is HTC,
submitted as `sbatch --clusters=htc --account=educ-intract <script>.slurm`, standard
QoS only and never `--qos=priority`. HTC requires the `--account`. Driving a whole
`submit_all.sh` chain there would mean threading those flags through every call site in
the script, so the chains as they stand run on ARC, as does the long decoding array
12664261. The per-paper `hpc/README.md` files carry the per-stage recipes.

## Project layout (the "scripts on personal disk, heavy material in /data" split)

```
~/new_LESS/                                   PERSONAL DISK -- code only
   _shared/{R,hpc,install_bayesian_dependencies.R}
   paper_1_transfer/{scripts,hpc,*.qmd,references.bib,...}
   paper_2_plasticity/{scripts,hpc,*.qmd,references.bib,...}
   LESS Project.Rproj                          here::here() sentinel

/data/educ-intract/educ1242/                  PROJECT SPACE (shared, multi-project)
   new_LESS/                                    LESS's own folder -- heavy material
      data/                                     read-only inputs   (LES_DATA_ROOT)
      Rlib/R-4.5/                               R package library  (R_LIBS_USER)
      cmdstan/cmdstan-*/                        Stan toolchain     (CMDSTAN)
      store/paper_{1,2}_*/{data_derived,results,figures}   model outputs (LES_STORE)
```

The `/data/educ-intract/educ1242` root is shared with other projects, so everything
LESS owns sits under its own `new_LESS/` level. `arc_env.sh` sets `LES_BASE` to that
folder and derives every other variable from it.

`_shared/hpc/arc_env.sh` is sourced at the top of every job and is the **single
source of truth** for this split: it `module load`s R, points `R_LIBS_USER` /
`CMDSTAN` / `LES_DATA_ROOT` / `LES_STORE` at the project space, and `cd`s to the
code root. `_shared/R/00_paths.R` reads `LES_DATA_ROOT` / `LES_STORE` (falling
back to a single self-contained tree on the dev box), so **no analysis script
hard-codes a cluster path**.

## 0. One-time setup (already done; here for reproducibility)

```bash
ssh arc                                     # key-based, non-interactive
# code -> personal disk:
#   (from the dev box)  scp -r _shared paper_1_transfer paper_2_plasticity \
#                              "LESS Project.Rproj" arc:new_LESS/
# data -> lives in the project space as a real directory:
#   /data/educ-intract/educ1242/new_LESS/data   (read-only; LES_DATA_ROOT)
# The legacy loaders read it by paths relative to the CODE root ("data/..."), so
# arc_env.sh creates the pointer on that side, automatically, on every job:
#   /home/educ1242/new_LESS/data -> /data/educ-intract/educ1242/new_LESS/data
# There is no /data/educ-intract/educ1242/data; an earlier version of this file
# described such a move, which was never the live layout.
# toolchain -> project-space library + CmdStan (brms, cmdstanr, eegUtils, osfr, papaja, ...):
sbatch paper_1_transfer/hpc/00_install_dependencies.slurm   # shared with Paper 2 -- run ONE only
```

The installer builds into `Rlib/R-4.5` and `cmdstan/` (needs the gfbf/2025a GCC compiler
from the R module + outbound network — both confirmed available). If a compute node
ever lacks network, run it on the `interactive` partition: `srun -p interactive --pty
bash`, then `source _shared/hpc/arc_env.sh && Rscript _shared/install_bayesian_dependencies.R`.

The installer pins nothing. `install_if_missing()` skips any package that is already
present and otherwise takes the current CRAN release, cmdstanr comes from the Stan
R-universe head, and `install_cmdstan()` is called without a `version=`. Running it again
today would therefore build a newer environment than the one the reported fits came from.
Rebuild against the record instead. The environment of record is the module `R/4.5.1-gfbf-2025a`
(R 4.5.1 on `x86_64-pc-linux-gnu`, GCC 14.2.0, OpenBLAS 0.3.29, FlexiBLAS 3.4.5) with
CmdStan 2.39.0 under `$LES_BASE/cmdstan/cmdstan-2.39.0`, compiled with
`CXXFLAGS_OPTIM = -O1` (see the `cc1plus` ICE section below). The R packages are pinned in
the repository's `renv.lock`, snapshotted on the cluster across the whole library search
path, so the way to rebuild that side is a restore.

Two things about the layout govern how that restore has to be written. First, the `scp` in
the block above copies `_shared`, the two paper directories and the `.Rproj` sentinel, and
nothing else. The code root on the cluster therefore carries no `.Rprofile`, no `renv/` and
no `renv.lock`, and `arc_env.sh` `cd`s into that code root before anything else runs. renv
is never activated at job time, so both the lockfile and the target library have to be
named explicitly. Second, the library argument must name the whole search path, and not
`R_LIBS_USER` alone. The snapshot was taken across both trees, so a restore that cannot see
the R module's own library would reinstall the hundred-odd packages the lockfile pinned
from it.

```bash
# renv.lock is not part of the scp above, so put it beside the code root once,
# from the dev box:  scp renv.lock arc:new_LESS/
source _shared/hpc/arc_env.sh
Rscript --vanilla -e 'renv::restore(lockfile = "renv.lock", library = .libPaths(), prompt = FALSE)'
Rscript --vanilla -e 'cmdstanr::install_cmdstan(version = "2.39.0", dir = Sys.getenv("CMDSTAN_INSTALL_DIR"))'
```

CmdStan needs that explicit version because `arc_env.sh` otherwise takes the highest
`cmdstan-*` directory it finds, so a newer tree left beside 2.39.0 would be selected
instead. Either keep only the version you mean to use, or export
`LES_CMDSTAN_VERSION=2.39.0`, which pins the tree and fails the job outright if it is
absent. What a given run actually used is written at fit time to
`paper_*/results/_provenance.csv` by `_shared/R/04_provenance.R`, and that file, not this
one, is authoritative for a completed run.

## 1. Submit the pipelines (from `~/new_LESS`)

```bash
cd ~/new_LESS
bash paper_1_transfer/hpc/submit_all.sh        # 01/02 extract -> 03/04 fit -> 05 summarise
bash paper_2_plasticity/hpc/submit_all.sh      # 01/02(/03) extract -> 04/05 fit -> 06 summarise
squeue -u "$USER"                              # track
```

`submit_all.sh` chains the stages with `--dependency=afterok`. Pass `with_install` as
the first argument to (re)provision the toolchain first. Partitions are set per stage
in the job scripts:

| Partition | Stages |
|---|---|
| `long` | The ERP, accuracy and Part A fits, the decoding array, projpred, and Paper 2's `09c` participant-grouped comparison, whose 40 refits run for about 40 hours. |
| `medium` | The single-trial ERP extraction, and Part B. |
| `short` | Everything else: the remaining extractions (accuracy, cognitive indices, trajectory, rs-EEG, aperiodic decomposition), the summaries, the projpred recovery job and the `09b` common-sample comparison. |

The per-stage tables in
[`paper_1_transfer/hpc/README.md`](paper_1_transfer/hpc/README.md) and
[`paper_2_plasticity/hpc/README.md`](paper_2_plasticity/hpc/README.md) list them.

These two chains cover only the core extract → fit → summarise path. The later and
longest-running stages are submitted by hand: Paper 1's `07`/`07b` grand averages and
the `08_decoding.slurm` array, and Paper 2's `07` aperiodic, `08` projpred, `09`
aperiodic-model, `09b` common-sample comparison and `09c` participant-grouped
comparison, in that order. `08_decoding.slurm` has two stages,
and the cross-property stage needs `--array=0`, `--export=ALL,LES_DECODE_STAGE=cross_property`
and an explicit `-o` log path, or it starts three tasks racing to write the same files
and clobbers a running element's log. The two `hpc/README.md` files above are the
authority for all of this.

**Prior-sensitivity run** (weakly-informative baseline): submit with
`--export=ALL,LES_PRIOR_SET=weak` (e.g. `sbatch --export=ALL,LES_PRIOR_SET=weak …`);
cached fits are tagged `*_weakprior*` so the two runs never clash.

## 2. Pull results back and render (dev box)

Outputs land in `$LES_STORE/paper_{1,2}_*/results/`, where `LES_STORE` is
`/data/educ-intract/educ1242/new_LESS/store` — note the `new_LESS/` level, which the
paths below carried incorrectly before 2026-08. Render with the dev-box recipe
(TinyTeX; see `paper_1_transfer/README.md`):

```bash
cd /path/to/your/clone                      # on the author's box: /c/Users/pablob/new_LESS
scp "arc:/data/educ-intract/educ1242/new_LESS/store/paper_1_transfer/results/*.csv" paper_1_transfer/results/
scp "arc:/data/educ-intract/educ1242/new_LESS/store/paper_2_plasticity/results/*.csv" paper_2_plasticity/results/
quarto render paper_1_transfer/paper_1_morphosyntax.qmd
quarto render paper_2_plasticity/paper_2_neuroplasticity.qmd
```

The `*[pending model fit]*` placeholders populate automatically.

`paper_1_transfer/results/` and `paper_2_plasticity/results/` are the only trees the
manuscripts read. `_shared/R/00_paths.R` resolves to them whenever `LES_STORE` is
unset, which is the case on the dev box. The root-level `store/` is a partial
pull-back from early July, not part of the layout, and nothing writes to it locally.
Do not delete it without checking first: `store/paper_2_plasticity/results/07_aperiodic_features.csv`
and `07_aperiodic_peaks.rds` currently have no counterpart in
`paper_2_plasticity/results/`, and `04_fit_brms_predictors.R` reads the former.

## 3. Paper-2 resting-state EEG (optional)

The Session-2 resting recordings already live in the local task-EEG tree, as
BrainVision ASCII exports under `data/raw data/EEG/Session 2/Export/`.
`paper_2_plasticity/scripts/03_extract_resting_state_eeg.R` parses them in base R and
computes the PSD with a self-contained Welch estimator, because eegUtils' `import_raw`
does not read ASCII. It needs no OSF download, no eegUtils and no network, so it runs on
any batch node (`paper_2_plasticity/hpc/03_extract_rseeg.slurm`, `short` partition). Its
output is already present on the dev box as
`paper_2_plasticity/data_derived/resting_state_eeg.rds`. `04`/`05` fit the
cognitive-only models without it and include the rs-EEG predictors automatically once
that file exists.

## Do not scp a script that a running job is executing

`Rscript file.R` does not read the whole file up front. It parses and evaluates one
expression at a time, holding an offset into the file. Overwriting that file while a job
is running shifts the content underneath the offset, and when the interpreter reaches the
end it reads a fragment of a line and dies with a parse error such as

    Error: unexpected ')' in "age == "crossprop")"

which is the tail of `if (stage == "crossprop") {`.

This happened on 2026-08-06: `09_run_decoding.R` was synced while decoding array 12664261
had been running since 2026-08-01. The array element that was mid-run finished all of its
work and wrote every artefact, then failed at the very end with a non-zero exit. Nothing
was lost, but the failure propagated: the cross-property job chained with
`--dependency=afterok` could no longer start, and had to be submitted by hand.

Before syncing, check what is running (`squeue -u $USER`) and which scripts those jobs
invoke. If a job is executing the file, either wait, or copy to a new name and submit the
new name. The risk is highest for the long decoding and fitting jobs, which can hold a
file open for a week or more.

## Troubleshooting

### `internal compiler error: Segmentation fault ... cc1plus` when fitting

GCC 14.2.0, the compiler in the `R/4.5.1-gfbf-2025a` toolchain, segfaults while
instantiating Stan's `reduce_sum` templates at `-O2` and `-O3`. Because `les_brm()`
uses within-chain threading, every model compile hits it, and the fit job dies within
seconds. It is a compiler crash, not a resource limit: it reproduces on a compute node
with an unlimited stack, unlimited virtual memory and 100 GB free in `/tmp`, at under
2 GB peak RSS.

`_shared/hpc/arc_env.sh` pins `CXXFLAGS_OPTIM = -O1` in `$CMDSTAN/make/local` to avoid
it, so sourcing the env in any job script is enough. `-O1` is the only level that
compiles with threading on. If you would rather keep `-O3`, the alternative is to drop
threading, but that changes the `reduce_sum` reduction order and so the exact posterior
draws, whereas the optimisation level does not.

To re-measure after a toolchain upgrade:
`sbatch paper_1_transfer/hpc/99_diagnose_ice.slurm` compiles one ERP cell at several
optimisation levels, with and without threading, and reports which combinations build.

### A job "COMPLETED" in seconds without fitting anything

`les_brm()` uses `file_refit = "on_change"`, so an unchanged dataset legitimately
reuses its cached fit. Verb–object number agreement has data only from Sessions 4 and 6,
so the mis-filtered Session-3 exclusion removes nothing from it and its six cells
correctly reuse their cached fits. Check the `.Rout` log: a genuine reuse still prints
real convergence diagnostics.

Never treat an exit code or a marker file as evidence that a data-changing job did what
it claimed. `paper_1_transfer/scripts/03_fit_brms_erp.R` records, for every fit, what
data it was actually fitted to (`*_fitmeta.rds`, pooled by step 05 into
`_pooled_fit_metadata.csv`), and the Paper 1 manuscript prints a visible marker on its
exclusion claim until every reported fit backs it up. Run
`Rscript --vanilla paper_1_transfer/scripts/test_exclusion_guard.R` after touching that
logic. The `--vanilla` keeps the project `.Rprofile` out of the way, which matters in a
working copy whose renv library has been populated. `Rscript` is not on the dev box's PATH,
so use the full-path invocation given in `paper_1_transfer/README.md`.

## Before submission (manuscripts)

Both `.qmd` carry placeholder author blocks (`[Author One]`, `author.one@example.org`,
`[Institution]`) — fill these in.
