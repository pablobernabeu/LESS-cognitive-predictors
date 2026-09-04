# `paper_2_plasticity/figures` — diagnostic images written by the fits

Every figure in Paper 2 is drawn at render time by an R chunk in the `.qmd`, from the CSVs
in [`../results/`](../results/README.md), and lands in `paper_2_neuroplasticity_files/`.
Nothing in this folder is read by the manuscript, and the folder is empty in a fresh
clone.

What arrives here comes from the cluster, and is diagnostic:

| Pattern | Written by |
|---------|------------|
| `<model_tag>_ppc.png` | The posterior predictive check for one Part A model, written by step 4 on every fitting run. |
| `07_aperiodic_fit_<ppt>.png` | Observed resting-state PSD with the fitted aperiodic component overlaid, for a few example participants, written by step 7. |

Both sets are read by eye, alongside `les_check_convergence()` in
[`../../_shared/R/02_diagnostics.R`](../../_shared/R/02_diagnostics.R). The aperiodic fit
plots are worth a look before trusting the de-confounded Part A variant, since a poor 1/f
fit is not visible in the coefficient table.

The folder is created on demand by `paper2_figures()` in
[`../../_shared/R/00_paths.R`](../../_shared/R/00_paths.R), so it does not have to exist
before a run.
