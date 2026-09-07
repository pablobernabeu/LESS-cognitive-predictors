# Paper 2 — Cognitive and Resting-State EEG Predictors of Intensive Multilingual Learning

Bayesian (brms) analysis of baseline cognitive/statistical-learning ability and
resting-state EEG as predictors of the artificial-language training trajectory
(Part A), plus pre/post change in cognition across the training period (Part B; a
resting-state pre/post cannot be estimated, see Known risks). Reuses the shared
infrastructure in
[`../_shared/R/`](../_shared/R/README.md) (paths, brms settings and priors, diagnostics)
and Paper 1's rendering recipe (see
[`../paper_1_transfer/README.md`](../paper_1_transfer/README.md)).

Target venue: *Bilingualism: Language and Cognition*, whose requirements are recorded in
[`journal_requirements.json`](journal_requirements.json). The manuscript is measured
against them: 150-word abstract, 9,000-word body excluding abstract, references, tables
and figures, and at most five tables and five figures, with anything further going to
online supplementary material.

## Pipeline (`scripts/`, run in order)

| Step | Script | Runs | What |
|---|---|---|---|
| config | `scripts/_config.R` | — | sessions (cognitive S1/5, neural S2/6), EF task definitions and index names, resting-state measure names and bands, the IAF search window, model-ID naming and the per-fit metadata record |
| 1 | `scripts/01_extract_cognitive_indices.R` | local/HPC | Stroop interference, digit span, ASRT learning indices |
| 2 | `scripts/02_extract_learning_trajectory.R` | **HPC** | tidy trial-/session-level training-accuracy data (feeds the Part A joint model) |
| 3 | `scripts/03_extract_resting_state_eeg.R` | **HPC** | Welch PSD → band power (delta/theta/alpha/beta/gamma) + individual alpha frequency (IAF), baseline (S2) only |
| 4 | `scripts/04_fit_brms_predictors.R` | **HPC** | Part A: joint Bernoulli multilevel model of the training-accuracy trajectory (pooled + gender-only sensitivity; raw-band and de-confounded/aperiodic variants) |
| 5 | `scripts/05_fit_brms_prepost.R` | **HPC** | Part B: pre/post change in cognition (S1 vs S5) and resting-state EEG (S2 vs S6, auto-skips — see Known risks) |
| 6 | `scripts/06_summaries.R` | **HPC** | pooled convergence/posterior-summary CSVs, end-of-training attainment, by-participant rate/intercept reliability, the pre/post fitted sample sizes (`_prepost_ns.csv`), the realised prior specification (`_prior_specification.csv`) and, where the fits carry one, the pooled per-fit sample and environment records (`_pooled_fit_metadata.csv`) |
| 6b | `scripts/06b_recover_provenance.R` | **HPC** | opt-in recovery of `_provenance.csv` from the fitted objects, for fits that predate the provenance mechanism. Already run; the file in `results/` is its output, marked by its `record_source` row |
| 7 | `scripts/07_extract_aperiodic.R` | **HPC** | specparam/aperiodic decomposition (Donoghue et al. 2020) of the resting-state PSD: exponent/offset + 1/f-adjusted band power |
| 8 | `scripts/08_projpred_selection.R` | **HPC** | projection-predictive variable selection over the Part A reference model(s); participant-grouped, search-validated K-fold CV |
| 8b | `scripts/08b_recover_projpred_path.R` | **HPC** | rebuilds the solution-path CSV and summary from an already-computed `*_projpred_varsel.rds`, so a crash after the multi-day CV does not force a re-run. Already run; kept as the provenance record of the path CSVs now in `results/` |
| 9b | `scripts/09b_compare_aperiodic_commonsample.R` | **HPC** | PSIS-LOO comparison between the raw-band and de-confounded (aperiodic) Part A reference models, within each of the pooled/gender-only strata. The raw-band model is refitted on the aperiodic model's 50-participant sample, so the two are evaluated on identical observations |
| 9c | `scripts/09c_compare_aperiodic_grouped.R` | **HPC** | the same two models compared by participant-grouped K-fold CV on the common sample (`_aperiodic_kfold_compare.csv`). Leaving out whole participants is what makes the comparison sensitive to predictors that are constant within a participant, which leaving out single trials cannot be |
| 10 | `scripts/10_extract_descriptives.R` | local | observed descriptives the manuscript injects and the descriptive figures read: cognitive indices, predictor descriptives, values (`_predictor_values.csv`) and correlations, resting-state band power and PSD, the grammaticality-judgement accuracy trajectory, and the observed task structure (`_task_specs.csv`) |
| 11 | `scripts/11_extract_predictor_reliability.R` | local | permutation split-half reliability (Spearman–Brown corrected) of the three baseline cognitive predictors |
| 12 | `scripts/12_extract_gamma_attenuation.R` | local | share of each participant's 30–45 Hz background power that survives the 30 Hz acquisition low-pass (`_gamma_attenuation.csv`), which the manuscript's gamma disclosure injects. Reads `_resting_state_psd.csv` from step 10 |
| 13 | `scripts/13_extract_task_durations.R` | local/HPC | participant-level home-task and laboratory-phase durations, written to both papers' `results/` |

Each folder below this one carries a readme of its own:
[`scripts/`](scripts/README.md) for the conventions and the ordering constraints,
[`results/`](results/README.md) for what the manuscript reads and what writes it,
[`figures/`](figures/README.md) for the diagnostic images, and
[`hpc/`](hpc/README.md) for the submission recipes.

`scripts/09_compare_aperiodic.R` and `hpc/10_compare_aperiodic.slurm` are superseded and
must not be submitted; [`scripts/README.md`](scripts/README.md) says why and how they are
guarded.

## Part A — predictive model (see script headers for full detail)

A single Bayesian multilevel Bernoulli model of trial-level training accuracy, with
the learning rate as a by-participant random slope for session/time and the baseline
predictors entered as interactions with time:

```
correct ~ z_session_time * grammatical_property
        + z_session_time * (cognitive + rs-EEG predictors)
        + (1 + z_session_time | participant_lab_ID)
```

Estimating the learning rate and the predictor effects in one model avoids the
two-stage alternative, in which a slope is extracted per participant and then
regressed on the predictors. That design biases the predictor effects through
regression dilution and understates uncertainty.

The model reports both the learning rate (the predictor × time interactions) and
attainment (modelled end-of-training accuracy). Priors are informative and tiered,
established from a citation-verified methods review (see `04_fit_brms_predictors.R`'s
header for the per-predictor magnitudes and DOIs).

**Gender-only sensitivity:** Part A is also re-fit restricted to gender agreement
(the property with full S2/3/4/6 coverage and a near-stable trajectory) to confirm
predictor effects are not an artefact of difficulty-confounded property composition.

**De-confounded (aperiodic) robustness check:** a second Part A reference model
(`predictive_aperiodic`/`_gender`) replaces raw rs-EEG band power with the
specparam/aperiodic decomposition (Donoghue et al. 2020). It is a robustness check on the
same analysis, and it is emphatically not a second, independent discovery pass. The
pre-specification note in `04_fit_brms_predictors.R`'s header sets out three drafting
commitments that keep it an honest one. Report both models' estimates and projpred
rankings side by side. Settle which characterisation the Discussion emphasises by a
quantified model comparison, never by author preference. Never frame the aperiodic ranking
as a standalone finding.

Both comparisons are reported. The pre-specified one is
`09b_compare_aperiodic_commonsample.R`'s PSIS-LOO on the common sample, and it is
retained. It leaves out one trial at a time, though, while the six predictors separating
the two models are constant within a participant, so it is close to blind to what is being
compared. `09c_compare_aperiodic_grouped.R` leaves out whole participants, and it is that
participant-grouped comparison the Discussion rests on. Apply the same commitments to any
future model variant added alongside an existing reference model.

**Projection-predictive selection:** `08_projpred_selection.R` ranks predictors by
retained predictive performance after projection, using participant-grouped
K-fold CV with the whole forward search re-run per fold (`validate_search=TRUE`),
the standard guard against selection-induced optimism. Two projpred specifics,
each documented in the script header, matter here. (1) The K-fold reference refits
must go through `cvfits=`, built via `run_cvfun()`. A `folds=` argument to `cv_varsel()`
does not exist in projpred's API and is silently ignored, which reintroduces participant
leakage. (2) The selection uses the latent projection
(`get_refmodel(fit, latent = TRUE)`; Catalina, Bürkner & Vehtari 2021). The
reference model is a multilevel Bernoulli model with a correlated random slope,
and projpred's *traditional* projection fits such submodels with `lme4::glmer`,
which crashes on this random-effects structure (an `nAGQ`/PIRLS incompatibility).
The latent projection fits submodels on the linear-predictor scale via
`lme4::lmer`, avoiding the crash entirely, and is the general route projpred offers
where its traditional projection is unavailable or fails (Catalina, Bürkner & Vehtari
2021; McLatchie, Rögnvaldsson, Weber & Vehtari 2025). The Bayesian (Stan) reference
model is unchanged. Only projpred's projection method differs.

## Part B — pre/post change

Cognition (S1 vs S5): three measures fit individually, plus a joint model across
measures (shared partial pooling, used for the specificity contrasts). The
resting-state EEG block (S2 vs S6) auto-skips, because resting-state EEG was recorded
at Session 2 only and no Session-6 recording exists on ARC or OSF. `fit_rseeg_prepost()`
is retained for structural parity with the cognition pipeline and produces zero fitted
models against the current dataset. The rs-EEG measures instead enter Part A as
baseline predictors. If a future data-collection wave adds a genuine Session-6 resting
recording, refactor this into a joint band × session_prepost model (mirroring
`fit_cognition_prepost_joint`) before reporting any band-specific result standalone.

Part B intentionally uses weakly-informative priors throughout, unlike Part A's
tiered informative priors. The pre/post literature for training-induced change in
these specific measures over a comparable training regime is too sparse for a
literature-derived informative prior (Schad, Betancourt & Vasishth 2021; Depaoli &
van de Schoot 2017). This is disclosed in the manuscript's Priors section.

## Manuscript

`paper_2_neuroplasticity.qmd` (apaquarto) renders at any time and reads only the
machine-written summary CSVs, so no statistic is transcribed by hand. Same rendering
recipe as Paper 1 (see its README). The results loading and the reporting helpers live
in `manuscript_setup.R`, which the manuscript's setup chunk sources, so that
`supplement.qmd`, the online supplementary material the journal receives as a separate
file (Sections S1 to S8 and Figures S1 and S2), renders from the same artefacts with the
same accessors: `quarto render paper_2_plasticity/supplement.qmd`. Helpers shared with
Paper 1 (the figure theme, the number formatters and the demographic and provenance
accessors) sit in [`../_shared/R/06_manuscript_helpers.R`](../_shared/R/06_manuscript_helpers.R).

**Environment.** Fitting and rendering are separate environments and should not be
conflated. The fits run on Oxford's ARC and HTC clusters under environment modules, with
no container involved. [`../_shared/hpc/arc_env.sh`](../_shared/hpc/arc_env.sh) loads
`R/4.5.1-gfbf-2025a` and points `R_LIBS_USER` at the project library
`$LES_BASE/Rlib/R-4.5`. CmdStan is built at `-O1` because of a GCC 14.2.0 compiler crash;
see the header of `arc_env.sh`. The per-stage recipes are in
[`hpc/README.md`](hpc/README.md) and the layout in [`../HPC_RUNBOOK.md`](../HPC_RUNBOOK.md).
Rendering happens on the Windows dev box under a different R and a different Quarto, both
recorded in [`../paper_1_transfer/README.md`](../paper_1_transfer/README.md). Versions are
not restated here. `results/_provenance.csv`, written by
[`../_shared/R/04_provenance.R`](../_shared/R/04_provenance.R) whenever
`scripts/04_fit_brms_predictors.R` runs, holds the R and platform versions, the versions of
every package in `LES_PROVENANCE_PKGS` (`_shared/R/04_provenance.R`), the CmdStan version
and the seeds. The R side of the same environment is pinned in the repository's
`renv.lock`. Until a run of that script, or of the recovery script
`06b_recover_provenance.R`, has written the file, the manuscript prints
`*[version pending a pipeline run]*` in place of each version, as its Data and code
availability section explains. The file now in `results/` was written by the recovery
script, which its `record_source` row records.

## Known risks / notes

1. Session mapping: cognitive pre/post is S1 vs S5, neural pre/post S2 vs S6.
2. Cognitive predictors are kept out of Paper 1 so the two papers stay distinct.
3. Resting-state EEG pre/post (Part B) cannot be estimated with the current
   dataset, which has Session 2 only. See Part B above.
