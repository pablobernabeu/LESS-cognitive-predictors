# `paper_2_plasticity/scripts` — the Paper 2 pipeline

Numbered scripts, run in order. The stage-by-stage table, saying what each one produces
and whether it runs locally or on the cluster, is in
[`../README.md`](../README.md#pipeline-scripts-run-in-order) and is the authority. This
file covers the conventions and the two scripts that must not be run.

## Conventions

`_config.R` is sourced first by every script and defines the session mapping (cognitive
pre/post is S1 against S5, neural pre/post S2 against S6), the executive-function task
definitions, and the model-ID naming that every downstream file depends on. After it, a
script sources whichever of [`../../_shared/R/`](../../_shared/R/README.md) it needs.

A letter suffix marks a script added beside an existing stage, which is why it does not
take a number of its own. `08b` rebuilds the projpred solution path from an
already-computed `varsel` object,
so that a crash after the multi-day cross-validation does not force a re-run. `09b` and
`09c` are the two model comparisons; `09c`, which leaves out whole participants, is the
one the Discussion rests on.

## Two scripts that must not be submitted

`09_compare_aperiodic.R`, and the `hpc/10_compare_aperiodic.slurm` that submits it, are
kept for reference only. That earlier comparison put the two models on different samples
(56 participants against 50), which `loo_compare()` rejects, and the script writes to the
same output file as `09b`. Running it would overwrite the artefact the manuscript reads.

## Where the data are

Inputs come from `../../data/`, which is **read-only**: no script here may write inside
it, and `les_assert_readonly_data()` stops any that tries. Paths resolve through
`../../_shared/R/00_paths.R`, so nothing hard-codes a location.

The resting-state recordings are not a separate tree. They sit inside the task-EEG tree as
`data/raw data/EEG/Session 2/Export/<ppt>_RS_eyes_{closed,open}.{txt,vhdr}`. They are
BrainVision ASCII exports, which `eegUtils` cannot read, so script 03 parses them in base
R and computes its own Welch PSD. How that was established is recorded in
[`../../_shared/hpc/reconnaissance/`](../../_shared/hpc/reconnaissance/README.md). Session
2 is the only resting-state recording that exists, which is why Part B's resting-state
block auto-skips.

Derived datasets go to `../data_derived/`, which is not in version control.
Manuscript-facing tables go to `../results/`; see [its readme](../results/README.md).

## Dependencies

R packages are pinned in `../../renv.lock`, which describes the cluster fitting
environment and must not be restored on the rendering box. `projpred` and `eegUtils` are
installed on the cluster and absent from the rendering box, so steps 3, 7 and 8 are
cluster-only for that reason as well as for their runtime. Step 8's selection uses the
latent projection, because projpred's traditional projection fits submodels with
`lme4::glmer`, which crashes on this random-effects structure.

## Reproducing the results

Run the local stages in numerical order, submit the cluster stages as the jobs in
[`../hpc/`](../hpc/README.md), pull `../results/*.csv` back, and re-render. Two ordering
constraints are easy to trip over: step 12 reads `_resting_state_psd.csv`, which step 10
writes, and step 04's aperiodic variant reads `07_aperiodic_features.csv`, which step 07
writes. `../results/_provenance.csv` is written whenever step 04 runs; until it has, the
manuscript prints `pending` in place of each version, as its availability section
explains.
