# HPC runbook — fitting both papers on Oxford's SLURM service

The Bayesian fits run on Oxford's SLURM service under the `educ-intract` project group.
Its two clusters, ARC and HTC, both use environment modules, with no Singularity
container, and access is by SSH key.
`arc` in the recipes below is a host alias, not a name the service publishes. Define one in
your own `~/.ssh/config` before running anything here, and use its name everywhere below,
including in the `scp` recipes. From outside the university network the alias needs a
`ProxyJump` through the service's gateway host, the login node being reachable directly
only from inside that network. If your key carries a passphrase, an interactive `ssh` will
prompt for it unless the key is already loaded in `ssh-agent`, which is worth arranging
before any scripted polling.

**ARC or HTC.** The project `/data` space is mounted at the same path on both, so
`_shared/hpc/arc_env.sh` serves either and no job script has to change. Only the
submission line differs. A plain `sbatch`, which is what every recipe below and both
`submit_all.sh` scripts use, goes to the login node's default cluster, ARC, where
project access comes through the `educ-intract` unix group and no `--account` is
needed. Since 2026-06-30 the preferred target for these single-node jobs is HTC,
submitted as `sbatch --clusters=htc --account=educ-intract <script>.slurm`, standard
QoS only and never `--qos=priority`. HTC requires the `--account`. Driving a whole
`submit_all.sh` chain there would mean threading those flags through every call site in
the script, so the chains as they stand run on ARC. The per-paper `hpc/README.md` files
carry the per-stage recipes.

## Project layout (the "scripts on personal disk, heavy material in /data" split)

```
~/new_LESS/                                   PERSONAL DISK -- code only
   _shared/{R,hpc,install_bayesian_dependencies.R}
   paper_1_transfer/{scripts,hpc,*.qmd,references.bib,...}
   paper_2_plasticity/{scripts,hpc,*.qmd,references.bib,...}
   LESS Project.Rproj                          here::here() sentinel

$LES_PROJECT/                                 PROJECT SPACE (shared, multi-project)
   new_LESS/                                    LESS's own folder -- heavy material
      data/                                     read-only inputs   (LES_DATA_ROOT)
      Rlib/R-4.5/                               R package library  (R_LIBS_USER)
      cmdstan/cmdstan-*/                        Stan toolchain     (CMDSTAN)
      store/paper_{1,2}_*/{data_derived,results,figures}   model outputs (LES_STORE)
```

The project-space root, `LES_PROJECT`, is shared with other projects, so everything LESS
owns sits under its own `new_LESS/` level. `arc_env.sh` is the one place that root is
written out; it sets `LES_BASE` to that folder and derives every other variable from it.

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
#   $LES_BASE/data   (read-only; LES_DATA_ROOT)
# The legacy loaders read it by paths relative to the CODE root ("data/..."), so
# arc_env.sh creates the pointer on that side, automatically, on every job:
#   ~/new_LESS/data -> $LES_BASE/data
# There is no $LES_PROJECT/data; the data tree lives only under $LES_BASE.
# toolchain -> project-space library + CmdStan. Two routes:
#   reproduction: restore renv.lock and build CmdStan 2.39.0 (put renv.lock beside the
#   code root first; see below)
sbatch _shared/hpc/00_restore_environment.slurm
#   bootstrap: an unpinned library where none exists (brms, cmdstanr, eegUtils, papaja,
#   ...), which is how the library was first built; shared with Paper 2 -- run ONE only
sbatch paper_1_transfer/hpc/00_install_dependencies.slurm
```

Either job builds into `Rlib/R-4.5` and `cmdstan/` (both need the gfbf/2025a GCC compiler
from the R module + outbound network — both confirmed available). If a compute node
ever lacks network, run the step on the `interactive` partition: `srun -p interactive --pty
bash`, then `source _shared/hpc/arc_env.sh` followed by the job's `Rscript` lines.

The bootstrap installer pins nothing. `install_if_missing()` skips any package that is already
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

`_shared/hpc/00_restore_environment.slurm` runs exactly those two lines as a batch job on
the `short` partition, so nothing has to be typed on a login node; submit it once, before
any fitting job.

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
the first argument to bootstrap an unpinned toolchain first; the pinned route is
`_shared/hpc/00_restore_environment.slurm`, submitted on its own before the chain.
Partitions are set per stage in the job scripts:

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
`$LES_BASE/store` (note the `new_LESS/` level inside `LES_BASE`). Render with the dev-box
recipe (TinyTeX; see `paper_1_transfer/README.md`):

```bash
cd /path/to/your/clone
# The cluster root is the value LES_BASE takes in _shared/hpc/arc_env.sh, written out here
# because this recipe runs on the dev box, where that script is not sourced.
scp "arc:/data/educ-intract/educ1242/new_LESS/store/paper_1_transfer/results/*.csv" paper_1_transfer/results/
scp "arc:/data/educ-intract/educ1242/new_LESS/store/paper_2_plasticity/results/*.csv" paper_2_plasticity/results/
quarto render paper_1_transfer/paper_1_morphosyntax.qmd
quarto render paper_2_plasticity/paper_2_neuroplasticity.qmd
```

The `*[pending model fit]*` placeholders populate automatically.

`paper_1_transfer/results/` and `paper_2_plasticity/results/` are the only trees the
manuscripts read. `_shared/R/00_paths.R` resolves to them whenever `LES_STORE` is
unset, which is the case on the dev box. The root-level `store/` is a partial pull-back
from early July, not part of the layout, and nothing writes to it locally. Every CSV it
holds now has a counterpart in the two `results/` trees, so it can be removed.

## 3. Paper-2 resting-state EEG (optional)

The Session-2 resting recordings already live in the local task-EEG tree, as
BrainVision ASCII exports under `data/raw data/EEG/Session 2/Export/`.
`paper_2_plasticity/scripts/03_extract_resting_state_eeg.R` parses them in base R and
computes the PSD with a self-contained Welch estimator, because eegUtils' `import_raw`
does not read ASCII. It needs no OSF download, no eegUtils and no network, so it runs on
any batch node (`paper_2_plasticity/hpc/03_extract_rseeg.slurm`, `short` partition). It
writes `paper_2_plasticity/data_derived/resting_state_eeg.rds`; `04`/`05` fit the
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

`_shared/hpc/deploy_to_cluster.sh` does that check for you, and it is the recommended
way to sync code:

```bash
bash _shared/hpc/deploy_to_cluster.sh paper_2_plasticity    # or paper_1_transfer, _shared, all
```

It refuses to copy anything while a job of that paper is running or pending, it holds
back `09_run_decoding.R` and `08_decoding.slurm` unless `LES_ALLOW_DECODING_DEPLOY=1` is
exported (their content is what the decoding cache fingerprint is computed over, so
copying either invalidates every banked permutation), it refuses a job script that
carries CRLF line endings, and it verifies every file by checksum on both sides after
copying. `LES_DEPLOY_ANYWAY=1` overrides the live-job check for a job you have checked by
hand. It copies code only: never data, never the store, never a fit.

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

The author blocks, ORCIDs, correspondence address, CRediT statement and funding are
filled in. What still needs a decision from the authors is listed, item by item, in
[`AUTHOR_TASKS.txt`](AUTHOR_TASKS.txt) at the repository root; the manuscripts mark the
same points in the text with the bracketed-italic convention (`*[...]*`), so a render
shows every one of them in place. Search either `.qmd` for `*[` to find them.
