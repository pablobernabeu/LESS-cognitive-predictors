# Paper 2 — HPC / SLURM submission scripts (Oxford ARC / HTC)

Bayesian model fitting for Paper 2 (*Cognitive Predictors and Neuroplasticity in
Intensive Multilingual Learning*) runs on Oxford's SLURM clusters, under environment
modules rather than a container. Every heavy job to date has run on ARC, including the
predictor and pre/post fits and the projpred selection. HTC was adopted in principle on
2026-06-30, since every job here is single-node, which is HTC's high-throughput remit,
but the move was deliberately not made at the time because CmdStan would have to be
rebuilt on HTC first. Treat HTC as the intended destination for new work rather than as
a description of where the current results came from. To send a job there, submit with
`sbatch --clusters=htc --account=educ-intract <script>.slurm`, standard QoS only and
never `--qos=priority`. A plain `sbatch` with no `--clusters` goes to the login node's
default cluster, which is ARC, so the recipes below submit to ARC as they stand.
Each job sources
[`_shared/hpc/arc_env.sh`](../../_shared/hpc/arc_env.sh), which runs
`module load R/4.5.1-gfbf-2025a` (R 4.5.1, GCC 14.2.0), points project-space
`R_LIBS_USER` / `CMDSTAN` / `LES_DATA_ROOT` / `LES_STORE` (shared across both clusters at
the same path), `cd`s to the `~/new_LESS` code root, and pins `CXXFLAGS_OPTIM = -O1` into
`$CMDSTAN/make/local`. GCC 14.2.0 raises an internal compiler error on Stan's `reduce_sum`
templates at `-O2` and above, so every Part A and Part B fit was compiled at `-O1`. See
[`../../HPC_RUNBOOK.md`](../../HPC_RUNBOOK.md) for the full layout + render workflow, and
its "internal compiler error" section for the measurements behind the pin.

### Software environment

The exact versions behind whatever sits in `results/` are recorded at fit time in
`results/_provenance.csv` (R, platform, brms, cmdstanr, rstan, StanHeaders, posterior, loo,
projpred, bayesplot, mgcv, MASS, dplyr, CmdStan, and the seeds) by
`_shared/R/04_provenance.R`. Two stages write it: stage 2a (`04_fit_predictors.slurm`) and
stage 6 (`09_aperiodic_model.slurm`, whose first step re-runs the same script). `05`, `06`,
`07`, `08`, `09b` and `09c` do not, so a run confined to those leaves the file as the last Part A
run left it, and a results tree in which neither 2a nor 6 has run carries no provenance file
at all. In that case the manuscript prints `*[version pending a pipeline run]*` in place of
each version and explains it in Data and code availability.

The repository's `renv.lock` pins the R side of this environment, snapshotted on the cluster
across both the project library and the R module's own, so `renv::restore()` rebuilds it.
CmdStan, the compiler and the `-O1` pin are not R packages and are not in the lockfile;
`00_install_dependencies.slurm` installs unpinned from CRAN and is a bootstrap rather than a
restore.

## One-time setup

The Bayesian + resting-state-EEG toolchain (brms + CmdStan, posterior, bayesplot,
tidybayes, bayestestR, papaja, eegUtils, osfr) installs into the project-space
library `/data/educ-intract/educ1242/new_LESS/Rlib/R-4.5` via the shared installer. Run
only one of the two `00` scripts; it is identical to Paper 1's.

```bash
# as written this goes to the default cluster (ARC); prepend
# --clusters=htc --account=educ-intract to build on HTC instead
sbatch paper_2_plasticity/hpc/00_install_dependencies.slurm
```

## Pipeline (in order)

| Stage | Script | Partition | What |
|------:|--------|:---------:|------|
| 1a | `01_extract_cognitive.slurm` | short | Stroop / digit-span / ASRT indices (S1, S5) → `cognitive_indices.rds` |
| 1b | `02_extract_trajectory.slurm` | short | judgement-accuracy trajectory + baseline cognition → `learning_trajectory.rds` |
| 1c | `03_extract_rseeg.slurm` | short | optional — posterior band power + IAF from the local Session-2 recordings (S2 only) → `resting_state_eeg.rds` |
| 2a | `04_fit_predictors.slurm` | long | **Part A** joint trajectory model: pooled + gender-only sensitivity. Trailing sbatch arguments pass straight to the R script, which accepts `pooled`, `gender`, `aperiodic` and `aperiodic_gender`, so `… 04_fit_predictors.slurm gender` fits the gender-only stratum alone (stage 6 below passes the two aperiodic arguments) |
| 2b | `05_fit_prepost.slurm` | medium | **Part B** pre/post: cognition S1↔S5 (rs-EEG S2↔S6 auto-skips — see Part B in the top-level README). Trailing arguments select a subset: `cognition`, `eeg` or `joint` |
| 3  | `06_summaries.slurm` | short | pooled diagnostics/summaries + attainment + reliability CSVs |
| 4  | `07_aperiodic.slurm` | short | specparam/aperiodic decomposition of the resting-state PSD (exponent/offset + 1/f-adjusted band power) |
| 5  | `08_projpred.slurm` | long | projection-predictive selection over the raw-band Part A reference model (participant-grouped, search-validated K-fold CV) |
| 6  | `09_aperiodic_model.slurm` | long | fits the de-confounded (aperiodic) Part A reference model, then runs projpred over it |
| 7  | `09b_compare_commonsample.slurm` | short | refits the raw-band Part A model on the aperiodic model's common 50-participant sample, then compares the two by PSIS-LOO on identical observations, within each of the pooled/gender-only strata |
| 8  | `09c_compare_grouped.slurm` | long | compares the same two models by participant-grouped K-fold CV, the criterion the Discussion rests on. Submit after 09b, whose cached common-sample refits it requires; 40 refits at about an hour each, hence `long` |

`10_compare_aperiodic.slurm` is superseded and must not be submitted. Its
`09_compare_aperiodic.R` compared models fitted to different samples (56 vs 50
participants), which `loo_compare` cannot do. Stage 7 above replaced it on 2026-07-11.

Two utility scripts sit outside the pipeline:

- `08b_recover.slurm` — re-extracts the projpred solution-path CSV and summary from a
  cached `varsel` object. Minutes, no cross-validation and no sampling. Use it after a
  `08`/`09` run whose CV completed but whose path extraction failed.
- `install_eegutils.slurm` — a standalone fallback for installing eegUtils, which the
  shared `00` installer already handles. Nothing in either pipeline loads eegUtils (see
  the note on `03` below), so this is only for the reconnaissance scripts in
  `_shared/hpc/reconnaissance/`.

### Submit everything with dependency chaining

```bash
cd ~/new_LESS
bash paper_2_plasticity/hpc/submit_all.sh                # toolchain already installed
bash paper_2_plasticity/hpc/submit_all.sh with_install   # install toolchain first
```

The chain covers stages 1a to 3 only. Stages 4 to 8 (`07`, `08`, `09`, `09b`, `09c`) are
submitted by hand, in that order.

`04`/`05` depend (afterok) on the cognitive/trajectory extractions and not on the
resting-state EEG step, so a missing or blocked `03` does not stall the pipeline. The
models are then fit with the cognitive predictors only, and the Session-2 rs-EEG
baseline predictors enter Part A automatically if `resting_state_eeg.rds` exists when
`04` starts. Part B's rs-EEG pre/post models skip either way, there being no
Session-6 recording to pair with.

`submit_all.sh` calls plain `sbatch`, so the whole chain goes to the default cluster
(ARC), and it takes no option for redirecting it. Running the chain on HTC would mean
editing the script to pass `--clusters=htc --account=educ-intract` at every call site.
Note that `sbatch --parsable` then returns `<jobid>;htc` rather than a bare number, and
that has to be trimmed before it can go into a `--dependency` spec.

## The resting-state EEG step (`03`) — notes

Resting-state recordings (established 2026-06-13 by direct reconnaissance of the
actual data) live in the same task-EEG tree as the other sessions
(`data/raw data/EEG/Session 2/Export/<lab_ID>_RS_eyes_{closed,open}.vhdr`), already
local, so there is no OSF fetch, no `osfr` and no network step. They are BrainVision
Analyzer ASCII exports, which `eegUtils::import_raw()` cannot read, so `03`
parses them directly in base R (`data.table::fread`) and computes the PSD with a
self-contained Welch estimator, validated against the Berger effect (posterior
alpha higher eyes-closed than eyes-open). Resting-state EEG was recorded at
Session 2 only, no Session-6 recording exists, so it serves as a baseline
(S2) predictor in Part A and Part B's rs-EEG pre/post auto-skips accordingly. To
include rs-EEG predictors in the Part A model, ensure `03` finished before `04`
(or re-run `04` afterwards).

## Outputs

- Derived data → `$LES_STORE/paper_2_plasticity/data_derived/` (`/data/.../store/...`)
- Fitted models + diagnostics → `$LES_STORE/paper_2_plasticity/results/`
- Pooled CSVs read by the manuscript → `…/results/_pooled_*.csv`, `_attainment.csv`, `_reliability.csv`
- Per-job logs → `paper_2_plasticity/hpc/logs/`

## Analysis-variant switches

Every variant is opt-in through the environment, exported on the submission line
(`sbatch --export=ALL,VAR=value …`). With none set the pipeline reproduces the default
artefacts exactly, and each variant writes its own tagged files, so a variant run never
clashes with the reported one.

| Variable | Value | Stage | Artefact tag | What it selects |
|----------|-------|-------|--------------|-----------------|
| `LES_PRIOR_SET` | `weak` | 2a (`04`) | `_weakprior` | the weakly-informative sensitivity baseline for Part A. Part B is weakly-informative by design, there being no verified training-plasticity effect sizes. |
| `LES_P2_IAF_RESOLVED` | `1` | 2a (`04`) | `_iafres` | drop participants 12 and 41, whose alpha peak specparam cannot resolve, from the model. It is scoped to the gender-only stratum, so submit it with that stratum argument: `sbatch --export=ALL,LES_P2_IAF_RESOLVED=1 paper_2_plasticity/hpc/04_fit_predictors.slurm gender`. Submitted without an argument it also revisits the pooled fit, which the switch leaves untagged and unchanged but whose convergence, summary and posterior-predictive artefacts are rewritten for nothing. |
| `LES_P2_SIGN_ALIGNED` | `1` | 2b (`05`) | `_signaligned` | sign-flip Stroop interference before the within-measure z-scoring, so that a positive session effect means improvement on all three cognitive indices in the joint pre/post model. It fits as `p2_cognition_prepost_joint_signaligned` and never touches the reported joint fit: `sbatch --export=ALL,LES_P2_SIGN_ALIGNED=1 paper_2_plasticity/hpc/05_fit_prepost.slurm joint` |

Re-run `06_summaries.slurm` after any variant run: it pools every fit artefact present, so
the summary CSVs come to carry the variants alongside the reported fits.

## Then render

Pull `…/store/paper_2_plasticity/results/*.csv` back to the dev box and render
`paper_2_neuroplasticity.qmd` (see `paper_1_transfer/README.md` for the
`R_PROFILE_USER` + TinyTeX recipe). Placeholders populate automatically.
