# `_shared/R` — the modules both pipelines source

Seven modules, sourced by name from each paper's `scripts/`, and one standalone script,
`write_codebook.R`, run by hand. They are not a package and there is nothing to install. A
script that needs a module calls `source()` on it after `_config.R` has set the project
root.

| Module | What it provides |
|--------|------------------|
| `00_paths.R` | Every path in the compendium. `data_path()`, `paper1_results()`, `paper2_derived()` and the rest resolve against the project root, which `here::here()` finds by searching upwards for `LESS Project.Rproj`. On the cluster the roots come from `LES_DATA_ROOT` and `LES_STORE`. This module is what makes the pipelines runnable from any working directory on any machine, and it replaced the legacy scripts' hard-coded container paths. |
| `01_bayesian_settings.R` | The brms and Stan configuration that must be identical across the two papers: the cmdstanr backend with `reduce_sum` threading, iteration and chain counts, and the literature-derived priors. Each block cites the source that motivates it. The `LES_PRIOR_SET=weak` and `LES_REQUIRE_CMDSTANR=1` environment switches are read here; `LES_PRIOR_PREDICTIVE=1` is read by Paper 1's fitting scripts, which then call `les_prior_predictive_check()`. |
| `02_diagnostics.R` | The single convergence standard both papers report against. `les_check_convergence()` is a hard pass/fail gate on rank-normalised split-R̂ < 1.01, bulk and tail ESS, and divergences, with thresholds from Vehtari et al. (2021). Also `les_save_ppc()`, `les_prior_predictive_check()` and `les_prior_sensitivity()`. The `LES_TREEDEPTH_FROM_CONTROL=1` switch, which reports the tree-depth count under the cmdstanr backend, is read here. |
| `03_data_manifest.R` | The map from the logical data names to their real folders, so a change in the physical layout is absorbed here instead of in every script. It also holds the read-only contract: `les_assert_readonly_data()` is called on every pipeline write path and stops the script if the path resolves inside `data/`. The mapping is not yet complete; the header names the call sites that still reach the tree directly. |
| `04_provenance.R` | Writes `results/_provenance.csv` at fit time, recording the versions actually loaded by that run together with the seeds. A lockfile cannot do this job, because it records what a library held when it was snapshotted, carries no seeds, and cannot cover CmdStan or the compiler. |
| `05_funnel.R` | The shared participant-flow figure generator. The drawing is shared so the two figures look identical; the content is paper-specific, because the two papers draw on different stages of the same cohort. |
| `06_helpers.R` | Small helpers both pipelines share: `les_zscore()`, the one z-score standardiser (Paper 1 keeps an all-NA column NA; Paper 2 passes `all_na = "zero"`), and `les_participant_folds()`, the participant-grouped fold builder used by Paper 2's projpred selection and its participant-grouped model comparison. Sourced with `source(here::here("_shared", "R", "06_helpers.R"))`. |
| `write_codebook.R` | Opt-in, run by hand on the rendering box after the CSVs are pulled. Lists every manuscript-facing results CSV, reads its header and column classes, joins `codebook_descriptions.csv` and writes `results/CODEBOOK.md` in each paper. Not called by any pipeline stage. |

## Data, dependencies, reproducibility

These modules read no data of their own. They resolve paths into `../../data/`, which is
read-only, and into each paper's `results/` and `data_derived/`. Their package
dependencies are brms, cmdstanr and Stan, plus `here`, `posterior`, `bayesplot` and, for
the funnel figure, `ggplot2` with `depictr` optional, all pinned in `../../renv.lock` at
the versions the cluster library holds. `01_bayesian_settings.R`
stops with a pointer to `../install_bayesian_dependencies.R` if brms is missing.

For the full picture — where the data live, how the environment is provisioned, and the
order the stages run in — see [`../README.md`](../README.md) and each paper's readme.
