# Cognitive Predictors and Neuroplasticity in Intensive Multilingual Learning

Research compendium for a Bayesian study of what predicts artificial-language learning.
Baseline cognitive ability and resting-state EEG were measured before training, and the
question is which of them forecast the learning trajectory over an intensive multi-session
regime (Part A), and what changed in cognition and resting-state activity across that
period (Part B).

The rendered manuscript is [`paper_2_plasticity/paper_2_neuroplasticity.pdf`](paper_2_plasticity/paper_2_neuroplasticity.pdf).
The study was preregistered at <https://osf.io/tjr54>.

**You can reproduce every number, table and figure in the paper from this repository
alone.** The machine-written summary tables the manuscript reads are committed under
`paper_2_plasticity/results/`, and no statistic is transcribed by hand: the manuscript
computes each one at render time from those files. Re-fitting the models from raw data is a
separate, much heavier job that needs a cluster; see *Re-fitting the models* below.

## Layout

| Path | What it holds |
|---|---|
| `paper_2_plasticity/` | The paper. `scripts/` (numbered, run in order), `hpc/` (SLURM jobs), `results/` (the tables the manuscript reads), `figures/`, the `.qmd` and its `references.bib`. Each subfolder has its own readme. |
| `_shared/` | Code shared with the companion paper: path resolution, brms settings and priors, convergence diagnostics, the read-only contract over the data, the provenance record, the participant-flow figure. |
| `HPC_RUNBOOK.md` | Cluster layout, job submission, pulling results back, and the failure modes worth knowing about. |
| `renv.lock` | The R packages of the **fitting** environment, pinned at the versions the cluster library held. |

## Where the data are

The raw electroencephalographic recordings are far too large for a git repository and are
deposited on OSF at <https://osf.io/tq7vy>. The resting-state recordings are not a separate
tree: they sit inside the task-EEG tree as
`Session 2/Export/<ppt>_RS_eyes_{closed,open}.{txt,vhdr}`. They are BrainVision ASCII
exports, which `eegUtils` cannot read, so `paper_2_plasticity/scripts/03_extract_resting_state_eeg.R`
parses them in base R and computes its own Welch PSD. Session 2 is the only resting-state
recording that exists, which is why Part B's resting-state block auto-skips rather than
reporting a pre/post contrast it cannot estimate.

Nothing here writes to the raw data: the read-only contract is enforced at run time by
`les_assert_readonly_data()` in `_shared/R/03_data_manifest.R`.

Everything the paper depends on that is derived from those recordings is committed under
`paper_2_plasticity/results/`, with a readme there explaining what writes each file and
what reads it.

## Reproducing the manuscript

You need [Quarto](https://quarto.org) and R. The apaquarto extension is vendored under
`paper_2_plasticity/_extensions/`, so it needs no separate install.

```bash
quarto render paper_2_plasticity/paper_2_neuroplasticity.qmd --to apaquarto-pdf
```

Two things are worth knowing before the first run.

**Do not run `renv::restore()` to render.** `renv.lock` pins the Linux cluster environment
in which the models were fitted (R 4.5.1, brms 2.23.0, cmdstanr 0.9.0). Rendering happens
in a different environment by design and needs far less: `rmarkdown`, `knitr`, `here`,
`dplyr` and `ggplot2`. The project `.Rprofile` activates renv only when both
`renv/activate.R` and a populated `renv/library/` are present, so a fresh clone stays on
the system library and renders without any of this getting in the way.

**PDF output needs a few LaTeX packages** beyond a bare TinyTeX: `koma-script`,
`footnotehyper`, `fontawesome5` and `pdfcol`. The engine is lualatex. `--to apaquarto-html`
needs none of them and is the quicker way to check a change.

One figure is optional. `depictr` (not on CRAN, `pak::pak('pablobernabeu/depictr')`)
supplies the theme and the colourblind-safe Okabe–Ito palette. Without it every figure
still renders, falling back to `theme_minimal()` and hand-coded colours.

## Re-fitting the models

The fits are cluster work. `HPC_RUNBOOK.md` gives the layout and
`paper_2_plasticity/hpc/README.md` the per-stage submission recipes; the stage table is in
`paper_2_plasticity/README.md` and the conventions in `paper_2_plasticity/scripts/README.md`.

Two ordering constraints are easy to trip over. Step 12 reads `_resting_state_psd.csv`,
which step 10 writes, and step 04's aperiodic variant reads `07_aperiodic_features.csv`,
which step 07 writes. One script must never be submitted:
`scripts/09_compare_aperiodic.R`, kept for reference only, compares two models fitted on
different samples, which `loo_compare()` rejects, and it writes to the same file as the
correct comparison in `09b`.

`paper_2_plasticity/results/_provenance.csv`, written by `_shared/R/04_provenance.R`
whenever the Part A predictor models are fitted, records the software versions that run
actually loaded together with the seed. Where any other account of the environment
disagrees with it, it is right. CmdStan, the GCC toolchain and the `CXXFLAGS_OPTIM = -O1`
pin are not R packages, so no lockfile can carry them; they are set in
`_shared/hpc/arc_env.sh` and explained in the runbook.

## The companion paper

A second paper draws on the same cohort, asking how three morphosyntactic properties are
processed across training and how the first language shapes that. It has its own compendium
at <https://github.com/pablobernabeu/LESS-morphosyntactic-transfer> and shares the
`_shared/` code and the cohort definition, but no result. Each paper is self-contained.

## Licence

CC BY 4.0. See [`Licence.md`](Licence.md).
