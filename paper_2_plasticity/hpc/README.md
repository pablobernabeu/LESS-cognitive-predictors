# Paper 2 — HPC / SLURM submission scripts (Oxford ARC / HTC)

Bayesian model fitting for Paper 2 (*Cognitive and Resting-State EEG Predictors of
Intensive Multilingual Learning*) runs on Oxford's SLURM clusters, under environment
modules, with no container involved. The Part A predictor fits, the Part B pre/post fits
and the projpred selection behind the shipped results ran on ARC. The sign-aligned Part B
sensitivity fit (`p2_cognition_prepost_joint_signaligned`, in `_pooled_convergence.csv`)
ran on HTC on 2026-09-02 under the same modules and the same CmdStan tree, and the
IAF-resolved Part A refit is queued there. HTC was adopted in principle on 2026-06-30,
since every job here is single-node, which is HTC's high-throughput remit. The move was
deferred at the time in the expectation that CmdStan would need rebuilding on HTC, which
the September run showed to be unnecessary. To send a job there, submit with
`sbatch --clusters=htc --account=educ-intract <script>.slurm`, standard QoS only and never
`--qos=priority`. A plain `sbatch` with no `--clusters`, which is what `submit_all.sh`
issues, goes to the login node's default cluster, which is ARC, so the recipes below
submit to ARC as they stand. The canonical statement of the rule is the "ARC or HTC"
section of [`../../HPC_RUNBOOK.md`](../../HPC_RUNBOOK.md). Each job sources
[`_shared/hpc/arc_env.sh`](../../_shared/hpc/arc_env.sh), which loads the R module,
points `R_LIBS_USER` / `CMDSTAN` / `LES_DATA_ROOT` / `LES_STORE` at the project space
and `cd`s to the `~/new_LESS` code root. CmdStan is built at `-O1` because of a GCC
14.2.0 compiler crash; see the header of `arc_env.sh`.

### Software environment

The exact versions behind whatever sits in `results/` are recorded at fit time in
`results/_provenance.csv` by `_shared/R/04_provenance.R`: the R and platform versions, the
versions of every package in `LES_PROVENANCE_PKGS` (`_shared/R/04_provenance.R`), the
CmdStan version and the seeds. Two stages write it: stage 2a (`04_fit_predictors.slurm`)
and stage 6 (`09_aperiodic_model.slurm`, whose first step re-runs the same script). `05`,
`06`, `07`, `08`, `09b` and `09c` do not, so a run confined to those leaves the file as the
last Part A run left it. The reported Part A fits predate the mechanism, so the file now in
`results/` was rebuilt from the version stamps inside the fitted objects by
`06b_recover_provenance.slurm` (its `record_source` row says so), and the next completed
`04` run overwrites it with a record written at fit time. Where the file is absent the
manuscript prints `*[version pending a pipeline run]*` in place of each version and
explains it in Data and code availability. Every fit also carries its own record: the
fitting scripts write `<model>_fitmeta.rds` (sample size, prior set, R, brms, cmdstanr and
CmdStan versions), which stage 3 pools into `results/_pooled_fit_metadata.csv`.

The repository's `renv.lock` pins the R side of this environment, snapshotted on the cluster
across both the project library and the R module's own, so `renv::restore()` rebuilds it.
CmdStan, the compiler and the `-O1` pin are not R packages and are not in the lockfile.
`_shared/hpc/00_restore_environment.slurm` runs that restore and installs the pinned
CmdStan, and is the reproduction route (`submit_all.sh with_restore` chains the pipeline
on it). `00_install_dependencies.slurm` installs unpinned from CRAN and only bootstraps a
library where none exists.

## One-time setup

The Bayesian + resting-state-EEG toolchain (brms + CmdStan, posterior, bayesplot,
tidybayes, bayestestR, papaja, eegUtils, osfr) installs into the project-space
library `$LES_BASE/Rlib/R-4.5` via the shared installer. Run only one of the two `00`
scripts; it is identical to Paper 1's. To reproduce the recorded environment, submit
`_shared/hpc/00_restore_environment.slurm` instead.

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
| 3  | `06_summaries.slurm` | short | pooled diagnostics/summaries + attainment + reliability CSVs, the pre/post sample sizes, the realised prior specification and the pooled per-fit metadata |
| 4  | `07_aperiodic.slurm` | short | specparam/aperiodic decomposition of the resting-state PSD (exponent/offset + 1/f-adjusted band power) |
| 5  | `08_projpred.slurm` | long | projection-predictive selection over the raw-band Part A reference model (participant-grouped, search-validated K-fold CV) |
| 6  | `09_aperiodic_model.slurm` | long | fits the de-confounded (aperiodic) Part A reference model, then runs projpred over it |
| 7  | `09b_compare_commonsample.slurm` | short | refits the raw-band Part A model on the aperiodic model's common 50-participant sample, then compares the two by PSIS-LOO on identical observations, within each of the pooled/gender-only strata |
| 8  | `09c_compare_grouped.slurm` | long | compares the same two models by participant-grouped K-fold CV, the criterion the Discussion rests on. Submit after 09b, whose cached common-sample refits it requires; 40 refits at about an hour each, hence `long` |
| 9  | `10_descriptives.slurm` | short | the descriptive tables the manuscript and the supplement inject: cognitive and predictor descriptives, the raw predictor values, the predictor correlations, the resting-state descriptives and spectra, the accuracy trajectory and the task specifications, then the gamma transmission fractions. Needs stages 1a to 1c only, not the fits |
| 10 | `11_predictor_reliability.slurm` | short | permutation split-half reliability of the three baseline cognitive indices → `_predictor_reliability.csv`. Needs stage 1a only, against whose indices the script self-validates |
| 11 | `13_extract_task_durations.slurm` | short | participant-level elapsed durations for home tasks and laboratory-session phases, written to both papers' `results/` |

Stages 9 and 10 write no fit and invalidate none, so they can be rerun at any point once
their inputs exist. They are the only route to those artefacts: before they existed the
three scripts behind them were run by hand.

`10_compare_aperiodic.slurm` is superseded and must not be submitted; it exits at once
unless `LES_ALLOW_SUPERSEDED=1` is exported, and then writes only a `_naive` file the
manuscript never reads. See [`../scripts/README.md`](../scripts/README.md) for why.

Three utility scripts sit outside the pipeline:

- `08b_recover.slurm` — re-extracts the projpred solution-path CSV and summary from a
  cached `varsel` object. Minutes, no cross-validation and no sampling. Use it after a
  `08`/`09` run whose CV completed but whose path extraction failed.
- `06b_recover_provenance.slurm` — rebuilds `results/_provenance.csv` from the version
  stamps inside the four cached Part A fits, because those fits predate the provenance
  mechanism. Post-processing only, minutes, no sampling. The file now in `results/` is its
  output, and the next completed `04` run overwrites it with a record written at fit time.
- `install_eegutils.slurm` — a standalone fallback for installing eegUtils, which the
  shared `00` installer already handles. Nothing in either pipeline loads eegUtils (see
  the note on `03` below), so this is only for the reconnaissance scripts in
  `_shared/hpc/reconnaissance/`.

### Submit everything with dependency chaining

```bash
cd ~/new_LESS
bash paper_2_plasticity/hpc/submit_all.sh                # environment already in place
bash paper_2_plasticity/hpc/submit_all.sh with_restore   # restore the pinned environment first
bash paper_2_plasticity/hpc/submit_all.sh with_install   # bootstrap an unpinned library first
```

The chain covers stages 1a to 3 only. Stages 4 to 8 (`07`, `08`, `09`, `09b`, `09c`) are
submitted by hand, in that order, and so are the two descriptive stages 9 and 10 (`10`,
`11`), which the chain does not reach because they depend on stage 1 alone.

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

- Derived data → `$LES_STORE/paper_2_plasticity/data_derived/` (`$LES_BASE/store/...`)
- Fitted models + diagnostics → `$LES_STORE/paper_2_plasticity/results/`
- Pooled CSVs read by the manuscript → `…/results/_pooled_*.csv`, `_attainment.csv`, `_reliability.csv`
- Per-job logs → `paper_2_plasticity/hpc/logs/`

## Analysis-variant switches

Every variant is opt-in through the environment, exported on the submission line
(`sbatch --export=ALL,VAR=value …`). With none set the pipeline reproduces the default
artefacts exactly. Every variant writes its own tagged fit, convergence, summary and
metadata files. One file is not tagged. `results/_provenance.csv` is rewritten at the end
of every `04` run whatever switches are set, so a sensitivity run leaves it describing that
run, and `recorded_utc` says which run wrote it. **Export `LES_PROVENANCE_SKIP=1` with
every stage-04 variant**, which the two recipes below now do. It is the only reliable
remedy: the file is not in version control, so it cannot be restored from there, and the
reported Part A fits predate the mechanism, so re-running the reported stage would not
write an authentic record either. If a variant does overwrite it, rebuild it with
`06b_recover_provenance.slurm`, which reconstructs the record from the version stamps
inside the cached fits. The cost of missing this is not cosmetic: the manuscript reads
`record_source` to decide what it says about the record, and with a variant's fit-time
record in place it states that the reported models were fitted on the day the variant ran.

| Variable | Value | Stage | Artefact tag | What it selects |
|----------|-------|-------|--------------|-----------------|
| `LES_STRICT_INPUTS` | `1` | 1 (`01`) | none | fail closed when a Session 1 or Session 5 export folder is missing, where the default warns, writes the indices without that session and lets `05` skip Part B with a message: `sbatch --export=ALL,LES_STRICT_INPUTS=1 paper_2_plasticity/hpc/01_extract_cognitive.slurm` |
| `LES_PROVENANCE_SKIP` | `1` | 2a (`04`) | none | skip the run-level provenance write, so a variant run leaves `results/_provenance.csv` as the reported run left it. The per-fit `<model>_fitmeta.rds` records are written regardless. |
| `LES_PRIOR_SET` | `weak` | 2a (`04`) | `_weakprior` | the weakly-informative sensitivity baseline for Part A. Submit it with the provenance guard, as above: `sbatch --export=ALL,LES_PRIOR_SET=weak,LES_PROVENANCE_SKIP=1 paper_2_plasticity/hpc/04_fit_predictors.slurm`. Part B is weakly-informative by design, there being no verified training-plasticity effect sizes. |
| `LES_P2_IAF_RESOLVED` | `1` | 2a (`04`) | `_iafres` | drop participants 12 and 41, whose alpha peak specparam cannot resolve, from the model. It is scoped to the gender-only stratum, so submit it with that stratum argument, and with the provenance guard, because stage 04 rewrites `results/_provenance.csv` whatever else is set: `sbatch --export=ALL,LES_P2_IAF_RESOLVED=1,LES_PROVENANCE_SKIP=1 paper_2_plasticity/hpc/04_fit_predictors.slurm gender`. Submitted without the guard on 2026-09-06, it left the record describing the sensitivity run, and the manuscript then stated that the reported models had been fitted that day; `06b_recover_provenance.slurm` put it back. Submitted without an argument it also revisits the pooled fit, which the switch leaves untagged and unchanged but whose convergence, summary and posterior-predictive artefacts are rewritten for nothing. |
| `LES_P2_STROOP_TEST_ONLY` | `1` | 1a (`01`), 10 (`11`) | `_stroop_testonly` | drop the rows the Gorilla export marks as practice before computing the Stroop index, which by default includes the practice block (the export records it in the same response zone as the test trials). Writes `cognitive_indices_stroop_testonly.rds` and `_predictor_reliability_stroop_testonly.csv`; the reported artefacts are untouched and the manuscript does not read the variant. Both stages take the switch, and the second needs the tagged indices the first writes, so chain them: `JID=$(sbatch --parsable --export=ALL,LES_P2_STROOP_TEST_ONLY=1 paper_2_plasticity/hpc/01_extract_cognitive.slurm)` then `sbatch --dependency=afterok:$JID --export=ALL,LES_P2_STROOP_TEST_ONLY=1 paper_2_plasticity/hpc/11_predictor_reliability.slurm` |
| `LES_P2_SIGN_ALIGNED` | `1` | 2b (`05`) | `_signaligned` | sign-flip Stroop interference before the within-measure z-scoring, so that a positive session effect means improvement on all three cognitive indices in the joint pre/post model. It fits as `p2_cognition_prepost_joint_signaligned` and never touches the reported joint fit: `sbatch --export=ALL,LES_P2_SIGN_ALIGNED=1 paper_2_plasticity/hpc/05_fit_prepost.slurm joint` |

Re-run `06_summaries.slurm` after any variant run: it pools every fit artefact present, so
the summary CSVs come to carry the variants alongside the reported fits.

## Then render

Pull `…/store/paper_2_plasticity/results/*.csv` back to the dev box and render
`paper_2_neuroplasticity.qmd` (see `paper_1_transfer/README.md` for the
`R_PROFILE_USER` + TinyTeX recipe). Placeholders populate automatically.
