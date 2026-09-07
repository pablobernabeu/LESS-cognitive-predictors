# Codebook for `paper_2_plasticity/results`

This file is machine-written by `_shared/R/write_codebook.R` and is not edited by hand. It lists every manuscript-facing CSV in this folder and, for each column, the R class that `read.csv()` infers from the first 200 rows (a column that is entirely NA within those rows reads as `logical`), a description taken from `_shared/R/codebook_descriptions.csv`, and the script that writes the file. To regenerate it after pulling the CSVs from the cluster, run `Rscript _shared/R/write_codebook.R` from the project root. Descriptions are added or corrected in `_shared/R/codebook_descriptions.csv`; a column still marked `(description pending)` needs one. The row counts are those of the files present when the codebook was generated.

## `_accuracy_trajectory_descriptives.csv`

663 data row(s), 8 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `level` | character | Aggregation level of the row: 'group_cell' (session x property x mini-language), 'participant_cell' (participant x session x property x mini-language) or 'participant' (participant x session, properties pooled). | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `session` | integer | ERP session (2, 3, 4 or 6). | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `grammatical_property` | character | snake_case property key; NA on 'participant' rows. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `mini_language` | character | 'Mini-English' or 'Mini-Norwegian'. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `participant_lab_ID` | integer | Lab ID; NA on 'group_cell' rows. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `n` | integer | Scored judgement trials in the cell; on 'group_cell' rows the sum over participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `mean_accuracy` | numeric | Proportion of correct judgements; on 'group_cell' rows the mean of the participant means. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `se` | numeric | Standard error: on 'group_cell' rows the SD of the participant means divided by the square root of the number of participants; on participant rows the binomial sqrt(p (1 - p) / n). | paper_2_plasticity/scripts/10_extract_descriptives.R |

## `_aperiodic_kfold_compare.csv`

2 data row(s), 12 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `stratum` | character | 'pooled' (the three properties) or 'gender' (gender agreement only). One row per stratum. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `raw_model` | character | Id of the raw band-power model refitted on the common sample ('<id>_commonsample'). | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `aperiodic_model` | character | Id of the specparam (aperiodic) model. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `criterion` | character | 'participant-grouped K-fold'. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `k` | integer | Number of participant folds. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `n_obs` | integer | Judgement trials in the common sample. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `n_participants` | integer | Participants in the common sample. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `elpd_diff_aperiodic_minus_raw` | numeric | Difference in K-fold expected log pointwise predictive density, aperiodic minus raw, summed over trials; positive favours the aperiodic model. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `se_diff` | numeric | Participant-clustered standard error of the difference: the square root of n_participants times the SD of the per-participant sums of the pointwise differences. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `se_naive_independent` | numeric | Standard error from loo::loo_compare, which treats trials as independent. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `se_inflation_from_clustering` | numeric | se_diff divided by se_naive_independent. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |
| `preferred_model` | character | 'aperiodic' or 'raw' when \|elpd_diff\| exceeds twice se_diff, otherwise 'neither clearly preferred (\|elpd_diff\| <= 2*clustered SE)'. | paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R |

## `_aperiodic_loo_compare.csv`

2 data row(s), 8 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `stratum` | character | 'pooled' (the three properties) or 'gender' (gender agreement only). One row per stratum. | paper_2_plasticity/scripts/09b_compare_aperiodic_commonsample.R |
| `raw_model` | character | Id of the raw band-power reference model; the comparison uses its refit on the common sample, cached as '<id>_commonsample'. | paper_2_plasticity/scripts/09b_compare_aperiodic_commonsample.R |
| `aperiodic_model` | character | Id of the specparam (aperiodic) model. | paper_2_plasticity/scripts/09b_compare_aperiodic_commonsample.R |
| `n_obs` | integer | Judgement trials in the common sample. | paper_2_plasticity/scripts/09b_compare_aperiodic_commonsample.R |
| `n_participants` | integer | Participants in the common sample. | paper_2_plasticity/scripts/09b_compare_aperiodic_commonsample.R |
| `elpd_diff_aperiodic_minus_raw` | numeric | Difference in PSIS-LOO expected log pointwise predictive density, aperiodic minus raw, on identical observations; positive favours the aperiodic model. | paper_2_plasticity/scripts/09b_compare_aperiodic_commonsample.R |
| `se_diff` | numeric | Standard error of the difference from loo::loo_compare. | paper_2_plasticity/scripts/09b_compare_aperiodic_commonsample.R |
| `preferred_model` | character | 'aperiodic' or 'raw' when \|elpd_diff\| exceeds twice se_diff, otherwise 'neither clearly preferred (\|elpd_diff\| <= 2*SE)'. | paper_2_plasticity/scripts/09b_compare_aperiodic_commonsample.R |

## `_attainment.csv`

2 data row(s), 5 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `model` | character | Raw band-power Part A model: 'p2_predictive_trajectory' or 'p2_predictive_trajectory_gender'. One row per model. | paper_2_plasticity/scripts/06_summaries.R |
| `quantity` | character | 'end_training_attainment_accuracy'. | paper_2_plasticity/scripts/06_summaries.R |
| `median` | numeric | Posterior median of the population-level expected judgement accuracy (proportion correct) at the maximum z_session_time, with every predictor at 0 (its mean) and averaged over properties. | paper_2_plasticity/scripts/06_summaries.R |
| `ci_low` | numeric | 2.5th percentile of that posterior (lower bound of the equal-tailed 95% credible interval). | paper_2_plasticity/scripts/06_summaries.R |
| `ci_high` | numeric | 97.5th percentile of that posterior (upper bound of the equal-tailed 95% credible interval). | paper_2_plasticity/scripts/06_summaries.R |

## `_cognitive_descriptives.csv`

6 data row(s), 8 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `session` | integer | 1 (baseline) or 5 (post-training). One row per session x index. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `index` | character | 'digit_span' (number of correct forward and backward trials), 'stroop_interference' (mean incongruent minus congruent response time, in milliseconds) or 'asrt_learning' (mean low- minus high-probability triplet response time, in milliseconds). | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `n` | integer | Participants with a value. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `mean` | numeric | Mean over those participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `sd` | numeric | Standard deviation over those participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `median` | numeric | Median over those participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `min` | numeric | Minimum over those participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `max` | numeric | Maximum over those participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |

## `_flow_inconsistencies.csv`

5 data row(s), 4 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `check` | character | Name of the consistency check that fired: 'data_without_attendance:<stage>', 'non_monotonic_attendance', 'language_parity_mismatch', 'duplicate_lab_ID', 'duplicate_home_ID', 'missing_lab_ID', 'enrolled_no_attendance', 'erp_without_accuracy', 'accuracy_without_erp', 'incomplete_predictor_set' or 'flow_total_mismatch'. One row per detected inconsistency. Written to both papers by Paper 1's flow audit. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `severity` | character | 'error', 'warning' or 'info'. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `participant_lab_ID` | integer | Lab ID of the participant concerned; NA for 'flow_total_mismatch', which is a property of a stage. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `detail` | character | Free-text statement of the inconsistency. | paper_1_transfer/scripts/00b_audit_participant_flow.R |

## `_gamma_attenuation.csv`

60 data row(s), 6 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `participant_lab_ID` | integer | Lab ID. One row per participant with an eyes-closed resting-state spectrum. | paper_2_plasticity/scripts/12_extract_gamma_attenuation.R |
| `aperiodic_offset` | numeric | Offset of the aperiodic fit to the eyes-closed occipito-parietal spectrum over 2 to 40 Hz: the log10 power at 1 Hz in the model log10 P(f) = offset - exponent * log10 f. | paper_2_plasticity/scripts/12_extract_gamma_attenuation.R |
| `aperiodic_exponent` | numeric | Exponent of that fit (the slope of log10 power against log10 frequency, sign reversed). | paper_2_plasticity/scripts/12_extract_gamma_attenuation.R |
| `retained_fraction` | numeric | Share of the extrapolated 30 to 45 Hz aperiodic power passed by a two-pass (zero-phase) fourth-order Butterworth 30 Hz low-pass, power response [1 + (f / 30)^8]^-2. | paper_2_plasticity/scripts/12_extract_gamma_attenuation.R |
| `retained_fraction_singlepass` | numeric | The same share under the single-pass response [1 + (f / 30)^8]^-1, an upper bound on retention. | paper_2_plasticity/scripts/12_extract_gamma_attenuation.R |
| `observed_over_extrapolated` | numeric | Observed 30 to 45 Hz power summed over frequency bins divided by the extrapolated aperiodic power over the same bins. | paper_2_plasticity/scripts/12_extract_gamma_attenuation.R |

## `_participant_matrix.csv`

65 data row(s), 15 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `participant_lab_ID` | integer | Integer lab ID from the participant key. One row per participant in the key. Written to both papers by Paper 1's flow audit. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `participant_home_ID` | character | Home (online-battery) ID string from the participant key. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `language_recorded` | character | Mini-language recorded in the participant key: 'Mini-English' or 'Mini-Norwegian'. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `attended_S1` | logical | TRUE when the Session-1 date cell in the participant key is filled. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `attended_S2` | logical | TRUE when the Session-2 date cell in the participant key is filled. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `attended_S3` | logical | TRUE when the Session-3 date cell in the participant key is filled. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `attended_S4` | logical | TRUE when the Session-4 date cell in the participant key is filled. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `attended_S5` | logical | TRUE when the Session-5 date cell in the participant key is filled. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `attended_S6` | logical | TRUE when the Session-6 date cell in the participant key is filled. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `usable_accuracy` | logical | TRUE when the participant appears in any accuracy_<property>.rds (Paper 1 judgement data). | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `usable_erp` | logical | TRUE when the participant appears in EEG_trial_count_per_condition.csv, in any grammaticality category. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `battery_baseline` | logical | TRUE when at least one Session-1 cognitive index is present. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `trajectory` | logical | TRUE when the participant appears in learning_trajectory.rds. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `joint_predictor` | logical | TRUE when both battery_baseline and trajectory hold. | paper_1_transfer/scripts/00b_audit_participant_flow.R |
| `usable_rseeg` | logical | TRUE when joint_predictor holds and the eyes-closed resting-state record carries every band power and the IAF. | paper_1_transfer/scripts/00b_audit_participant_flow.R |

## `_participants.csv`

18 data row(s), 7 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `metric` | character | Name of the demographic quantity: n_enrolled, n_mini_english, n_mini_norwegian, n_lhq3, age_years, sex_female, sex_male, sex_nonbinary, sex_undisclosed, hand_right, hand_left, hand_reported_n, eng_aoa_listen, eng_aoa_4mod, eng_years, eng_l2_proficiency, multilingual_diversity, n_other_language. One row per metric, computed over the analysed participants with an LHQ3 record unless the note says otherwise. Written to both papers by Paper 1's participant extractor. | paper_1_transfer/scripts/00_extract_participants.R |
| `value` | numeric | A count for the n_*, sex_* and hand_* rows; the mean over participants with a value for the continuous rows (years for age_years, eng_aoa_listen, eng_aoa_4mod and eng_years; a 0 to 1 self-rating for eng_l2_proficiency; the LHQ3 score for multilingual_diversity). | paper_1_transfer/scripts/00_extract_participants.R |
| `sd` | numeric | Standard deviation across participants for the continuous rows; NA for counts. | paper_1_transfer/scripts/00_extract_participants.R |
| `n` | integer | Denominator: participants with a value (continuous rows) or the reference count of a count row (n_lhq3 for the sex rows, participants with a handedness response for the hand rows); NA where no denominator is stated. | paper_1_transfer/scripts/00_extract_participants.R |
| `vmin` | numeric | Minimum across participants for the continuous rows; NA for counts. | paper_1_transfer/scripts/00_extract_participants.R |
| `vmax` | numeric | Maximum across participants for the continuous rows; NA for counts. | paper_1_transfer/scripts/00_extract_participants.R |
| `note` | character | Source and definition of the metric. | paper_1_transfer/scripts/00_extract_participants.R |

## `_participants_other_languages.csv`

8 data row(s), 2 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `language` | character | A language named in LHQ3 item 7 beyond Norwegian and English, with any parenthetical qualifier dropped and in title case. One row per language, ordered by n_participants. Written to both papers by Paper 1's participant extractor. | paper_1_transfer/scripts/00_extract_participants.R |
| `n_participants` | integer | Distinct analysed participants naming that language. | paper_1_transfer/scripts/00_extract_participants.R |

## `_pooled_convergence.csv`

12 data row(s), 7 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `model` | character | Model id from the artefact file name: the Part A trajectory models 'p2_predictive_trajectory', 'p2_predictive_trajectory_gender', 'p2_predictive_trajectory_aperiodic' and 'p2_predictive_trajectory_aperiodic_gender' (with '_weakprior' for the weak-prior sensitivity fits) and the Part B pre/post models 'p2_cognition_prepost_<index>' and 'p2_cognition_prepost_joint' (with '_signaligned' for the sign-aligned variant). One row per fitted model. | paper_2_plasticity/scripts/06_summaries.R |
| `max_rhat` | numeric | Largest rank-normalised split R-hat over every parameter of the fit. | paper_2_plasticity/scripts/06_summaries.R |
| `min_ess_bulk` | numeric | Smallest bulk effective sample size over every parameter of the fit. | paper_2_plasticity/scripts/06_summaries.R |
| `min_ess_tail` | numeric | Smallest tail effective sample size over every parameter of the fit. | paper_2_plasticity/scripts/06_summaries.R |
| `n_divergent` | integer | Divergent transitions after warm-up, summed over chains. | paper_2_plasticity/scripts/06_summaries.R |
| `n_treedepth` | logical | Iterations that saturated max_treedepth; NA under the cmdstanr backend, where the ceiling cannot be read from the fit object. | paper_2_plasticity/scripts/06_summaries.R |
| `passed` | logical | TRUE when max_rhat < 1.01, min_ess_bulk > 400, min_ess_tail > 400 and n_divergent == 0. | paper_2_plasticity/scripts/06_summaries.R |

## `_pooled_posterior_summaries.csv`

170 data row(s), 6 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `parameter` | character | brms population-level term with the 'b_' prefix removed. Part A: z_session_time is the z-scored 0 to 3 growth-curve code of Sessions 2, 3, 4 and 6; z_<predictor> are the baseline predictors z-scored across participants; grammatical_property enters as treatment dummies against the reference level 'differential_object_marking'. Part B: session_prepost is -0.5 (pre) or +0.5 (post) and measure enters as dummies against the reference level 'digit_span'. One row per parameter per model. | paper_2_plasticity/scripts/06_summaries.R |
| `median` | numeric | Posterior median: on the logit scale for the Bernoulli Part A models, in SD units of the within-measure z-scored index for the Gaussian Part B models. | paper_2_plasticity/scripts/06_summaries.R |
| `ci_low` | numeric | 2.5th percentile of the posterior (lower bound of the equal-tailed 95% credible interval). | paper_2_plasticity/scripts/06_summaries.R |
| `ci_high` | numeric | 97.5th percentile of the posterior (upper bound of the equal-tailed 95% credible interval). | paper_2_plasticity/scripts/06_summaries.R |
| `pd` | numeric | Probability of direction: the larger of the posterior mass above zero and below zero. | paper_2_plasticity/scripts/06_summaries.R |
| `model` | character | Model id from the artefact file name (see _pooled_convergence.csv). | paper_2_plasticity/scripts/06_summaries.R |

## `_predictor_correlations.csv`

81 data row(s), 4 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `var1` | character | First predictor of the pair: digit_span, stroop_interference, asrt_learning, delta, theta, alpha, beta, gamma or iaf. One row per ordered pair (81 rows). | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `var2` | character | Second predictor of the pair. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `r` | numeric | Pearson correlation over the joint predictor frame (participants with a baseline battery and an eyes-closed resting-state record), pairwise complete. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `n` | integer | Participants with both values. | paper_2_plasticity/scripts/10_extract_descriptives.R |

## `_predictor_descriptives.csv`

9 data row(s), 7 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `predictor` | character | Baseline Part A predictor: 'digit_span' (correct trials), 'stroop_interference' (milliseconds), 'asrt_learning' (milliseconds), 'delta', 'theta', 'alpha', 'beta' or 'gamma' (absolute eyes-closed band power in squared microvolts, the occipito-parietal Welch power spectral density integrated over 1-4, 4-8, 8-13, 13-30 and 30-45 Hz) or 'iaf' (individual alpha frequency in Hz, the spectral peak within 7 to 13 Hz). One row per predictor over the joint predictor frame. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `n` | integer | Participants with a value. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `mean` | numeric | Mean over those participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `sd` | numeric | Standard deviation over those participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `median` | numeric | Median over those participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `min` | numeric | Minimum over those participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `max` | numeric | Maximum over those participants. | paper_2_plasticity/scripts/10_extract_descriptives.R |

## `_predictor_reliability.csv`

3 data row(s), 7 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `predictor` | character | 'digit_span', 'stroop_interference' or 'asrt_learning'. One row per predictor. | paper_2_plasticity/scripts/11_extract_predictor_reliability.R |
| `session` | integer | Session at which reliability is estimated (1, the baseline). | paper_2_plasticity/scripts/11_extract_predictor_reliability.R |
| `n_participants` | integer | Enrolled participants whose index could be recomputed from the trial-level data. | paper_2_plasticity/scripts/11_extract_predictor_reliability.R |
| `r_half` | numeric | Pearson correlation across participants between the index computed on two random halves of each participant's trials, averaged over the random splits. | paper_2_plasticity/scripts/11_extract_predictor_reliability.R |
| `reliability_sb` | numeric | r_half corrected to full test length by the Spearman-Brown formula, 2r / (1 + r). | paper_2_plasticity/scripts/11_extract_predictor_reliability.R |
| `n_splits` | integer | Number of random splits averaged (LES_REL_SPLITS, 500 by default). | paper_2_plasticity/scripts/11_extract_predictor_reliability.R |
| `seed` | integer | Seed the random splits were drawn under (LES_REL_SEED, 20260724 by default), so the table is reproducible. | paper_2_plasticity/scripts/11_extract_predictor_reliability.R |

## `_predictor_values.csv`

557 data row(s), 3 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `participant_lab_ID` | integer | Lab ID. One row per participant x predictor with a value. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `predictor` | character | Predictor name as in _predictor_descriptives.csv. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `value` | numeric | Raw value in the units given for that predictor in _predictor_descriptives.csv. | paper_2_plasticity/scripts/10_extract_descriptives.R |

## `_prepost_ns.csv`

10 data row(s), 4 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `model` | character | Pre/post model id: 'p2_cognition_prepost_<index>' or 'p2_cognition_prepost_joint' (with '_signaligned' for the sign-aligned variant). One row per model x session. | paper_2_plasticity/scripts/06_summaries.R |
| `session` | character | 'pre' (Session 1) or 'post' (Session 5). | paper_2_plasticity/scripts/06_summaries.R |
| `n_participants` | integer | Distinct participants in the fitted data at that session. | paper_2_plasticity/scripts/06_summaries.R |
| `n_obs` | integer | Rows of the fitted data at that session: one per participant for the per-index models, one per participant x measure for the joint model. | paper_2_plasticity/scripts/06_summaries.R |

## `_prior_sensitivity.csv`

44 data row(s), 13 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `parameter` | character | brms population-level term with the 'b_' prefix removed (see _pooled_posterior_summaries.csv). One row per parameter per informative/weak model pair. No pipeline stage writes this file; its columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `median_inf` | numeric | Posterior median under the informative priors, on the logit scale. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `ci_low_inf` | numeric | 2.5th percentile of the posterior under the informative priors. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `ci_high_inf` | numeric | 97.5th percentile of the posterior under the informative priors. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `pd_inf` | numeric | Probability of direction under the informative priors. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `median_weak` | numeric | Posterior median under the weakly informative priors (the '_weakprior' fit). | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `ci_low_weak` | numeric | 2.5th percentile of the posterior under the weakly informative priors. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `ci_high_weak` | numeric | 97.5th percentile of the posterior under the weakly informative priors. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `pd_weak` | numeric | Probability of direction under the weakly informative priors. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `median_shift` | numeric | median_inf minus median_weak, on the logit scale. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `ci_width_inf` | numeric | ci_high_inf minus ci_low_inf. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `ci_width_weak` | numeric | ci_high_weak minus ci_low_weak. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |
| `model` | character | Id of the informative fit: 'p2_predictive_trajectory' or 'p2_predictive_trajectory_gender'. | none in the pipeline (columns follow les_prior_sensitivity() in _shared/R/02_diagnostics.R) |

## `_prior_specification.csv`

250 data row(s), 12 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `prior` | character | Prior distribution as brms::prior_summary() reports it, for example 'normal(0, 1)'; empty when brms uses its flat default for that class. One row per prior per model. | paper_2_plasticity/scripts/06_summaries.R |
| `class` | character | Parameter class: 'b' (population-level coefficient), 'Intercept', 'sd' (group-level standard deviation), 'sigma' (residual standard deviation) or 'L' (Cholesky factor of the group-level correlation matrix). | paper_2_plasticity/scripts/06_summaries.R |
| `coef` | character | Coefficient the prior applies to; empty for a class-wide prior. | paper_2_plasticity/scripts/06_summaries.R |
| `group` | character | Grouping factor for 'sd' and 'L' priors ('participant_lab_ID'); empty otherwise. | paper_2_plasticity/scripts/06_summaries.R |
| `resp` | logical | Response variable the prior belongs to; empty for these single-response models. | paper_2_plasticity/scripts/06_summaries.R |
| `dpar` | logical | Distributional parameter the prior belongs to; empty for these models. | paper_2_plasticity/scripts/06_summaries.R |
| `nlpar` | logical | Non-linear parameter the prior belongs to; empty for these models. | paper_2_plasticity/scripts/06_summaries.R |
| `lb` | integer | Lower bound of the parameter: 0 for 'sd' and 'sigma'; empty otherwise. | paper_2_plasticity/scripts/06_summaries.R |
| `ub` | logical | Upper bound of the parameter; empty for these models. | paper_2_plasticity/scripts/06_summaries.R |
| `tag` | logical | brms prior tag; empty for these models. | paper_2_plasticity/scripts/06_summaries.R |
| `source` | character | 'user' when the prior was set in the fitting script, 'default' when supplied by brms. | paper_2_plasticity/scripts/06_summaries.R |
| `model` | character | Model id (see _pooled_convergence.csv). | paper_2_plasticity/scripts/06_summaries.R |

## `_projpred_path.csv`

62 data row(s), 15 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `model` | character | Reference model whose forward search the row belongs to. One row per submodel size per model; the per-model files p2_<model>_projpred_path.csv are pooled here. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `size` | integer | Number of terms in the submodel; 0 is the intercept-only submodel. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `predictor` | character | Term added at this step of the full-data forward search: '(Intercept)' at size 0; group-level terms appear as '(1 \| participant_lab_ID)' and '(z_session_time \| participant_lab_ID)'. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `elpd` | numeric | Cross-validated expected log pointwise predictive density of the submodel on the response scale, summed over trials. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `elpd_se` | numeric | Standard error of elpd. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `elpd_diff` | numeric | elpd minus the reference model's elpd (the projpred convention); negative means worse than the reference model. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `elpd_diff_se` | numeric | Standard error of elpd_diff. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `acc` | numeric | Cross-validated classification accuracy (proportion of trials predicted correctly) of the submodel; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `acc_se` | numeric | Standard error of acc; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `acc_diff` | numeric | acc minus the reference model's accuracy; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `suggested_size` | integer | Submodel size proposed by projpred::suggest_size(stat = 'elpd'): the smallest size whose elpd difference to the reference model is within one standard error of zero; repeated on every row of the model. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `is_suggested` | logical | TRUE on the row whose size equals suggested_size. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `n_folds` | integer | Participant-grouped cross-validation folds (K). | paper_2_plasticity/scripts/08_projpred_selection.R |
| `n_participants` | integer | Participants in the reference fit. | paper_2_plasticity/scripts/08_projpred_selection.R |
| `cv_prop_diag` | numeric | Proportion of cross-validation folds in which the predictor entered at this size occupied the same rank in the fold-wise search, a ranking-stability diagnostic; NA for path files produced without it. | paper_2_plasticity/scripts/08_projpred_selection.R |

## `_provenance.csv`

18 data row(s), 4 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `component` | character | What the row records: 'R', 'platform', an R package name (brms, cmdstanr, rstan, StanHeaders, posterior, loo, projpred, bayesplot, mgcv, MASS, dplyr), 'CmdStan', 'seed:LES_SEED', and, when the file was recovered by 06b_recover_provenance.R, 'record_source', 'fits_written_utc' and 'fits_recorded'. One row per component. | paper_2_plasticity/scripts/06b_recover_provenance.R (recovered) or _shared/R/04_provenance.R via 04_fit_brms_predictors.R (fit time) |
| `version` | character | Version string, seed value, or the text of a record row. | paper_2_plasticity/scripts/06b_recover_provenance.R (recovered) or _shared/R/04_provenance.R via 04_fit_brms_predictors.R (fit time) |
| `source` | character | Where the value was read from when the file was recovered by 06b: 'fitted object', 'project library', 'job environment', 'shared settings', 'this script' or 'file system'. Absent when the file is written at fit time by _shared/R/04_provenance.R. | paper_2_plasticity/scripts/06b_recover_provenance.R (recovered) or _shared/R/04_provenance.R via 04_fit_brms_predictors.R (fit time) |
| `recorded_utc` | character | UTC time of the write; the same on every row. | paper_2_plasticity/scripts/06b_recover_provenance.R (recovered) or _shared/R/04_provenance.R via 04_fit_brms_predictors.R (fit time) |

## `_reliability.csv`

4 data row(s), 5 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `model` | character | 'p2_predictive_trajectory' or 'p2_predictive_trajectory_gender'. One row per model x by-participant effect. | paper_2_plasticity/scripts/06_summaries.R |
| `effect` | character | By-participant random effect: 'Intercept' (level at the mean session) or 'z_session_time' (learning rate). | paper_2_plasticity/scripts/06_summaries.R |
| `group_sd` | numeric | Posterior mean of the group-level standard deviation (tau) of that effect. | paper_2_plasticity/scripts/06_summaries.R |
| `mean_posterior_se` | numeric | Mean over participants of the posterior standard deviation of the shrunken by-participant deviation. | paper_2_plasticity/scripts/06_summaries.R |
| `reliability` | numeric | Variance of the posterior-mean by-participant deviations divided by tau squared. | paper_2_plasticity/scripts/06_summaries.R |

## `_resting_state_psd.csv`

10680 data row(s), 4 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `participant_lab_ID` | integer | Lab ID. One row per participant x condition x frequency bin. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `condition` | character | 'eyes_closed' or 'eyes_open'. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `freq_hz` | numeric | Frequency in Hz, 0.5 Hz bins from 1 to 45 Hz (Welch estimate with 2 s Hann segments and 50% overlap at 500 Hz). | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `power` | numeric | Power spectral density in squared microvolts per Hz, averaged over the eight occipito-parietal channels (O1, Oz, O2, P3, Pz, P4, P7, P8). | paper_2_plasticity/scripts/10_extract_descriptives.R |

## `_rseeg_descriptives.csv`

14 data row(s), 9 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `condition` | character | 'eyes_closed' or 'eyes_open'. One row per condition x band, plus one 'alpha_peak_count' row per condition. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `band` | character | 'delta', 'theta', 'alpha', 'beta' or 'gamma' (band power in squared microvolts), 'iaf' (individual alpha frequency in Hz) or 'alpha_peak_count'. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `n` | integer | Recordings with a value. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `mean` | numeric | Mean over recordings; NA on the 'alpha_peak_count' rows. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `sd` | numeric | Standard deviation over recordings; NA on the 'alpha_peak_count' rows. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `median` | numeric | Median over recordings; NA on the 'alpha_peak_count' rows. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `min` | numeric | Minimum over recordings; NA on the 'alpha_peak_count' rows. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `max` | numeric | Maximum over recordings; NA on the 'alpha_peak_count' rows. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `n_participants_with_resolvable_alpha_peak` | integer | Recordings whose IAF lies strictly inside 7 to 13 Hz; filled on the 'alpha_peak_count' rows only. | paper_2_plasticity/scripts/10_extract_descriptives.R |

## `_sample_flow.csv`

13 data row(s), 7 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `stage` | character | Participant-flow stage key: 'enrolled', 'attended_S1' to 'attended_S6', 'usable_accuracy', 'battery_baseline', 'trajectory', 'joint_predictor', 'usable_erp' or 'usable_rseeg'. One row per stage. Written to both papers by Paper 1's participant extractor. | paper_1_transfer/scripts/00_extract_participants.R |
| `order` | integer | Display order of the stage in the flow figure. | paper_1_transfer/scripts/00_extract_participants.R |
| `label` | character | Stage label printed in the flow figure. | paper_1_transfer/scripts/00_extract_participants.R |
| `n_total` | integer | Participants at that stage; NA when the source object is absent. | paper_1_transfer/scripts/00_extract_participants.R |
| `n_mini_english` | integer | Participants at that stage assigned Mini-English; NA where the stage is not split by language. | paper_1_transfer/scripts/00_extract_participants.R |
| `n_mini_norwegian` | integer | Participants at that stage assigned Mini-Norwegian; NA where the stage is not split by language. | paper_1_transfer/scripts/00_extract_participants.R |
| `source` | character | The file or rule the count derives from. | paper_1_transfer/scripts/00_extract_participants.R |

## `_task_specs.csv`

7 data row(s), 4 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `task` | character | 'asrt', 'digit_span' or 'stroop'. One row per task x specification. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `spec` | character | Specification name: 'n_blocks', 'modal_trials_per_block', 'trials_per_block', 'scored_trials', 'test_trials', 'congruent_trials' or 'incongruent_trials'. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `value` | integer | The value, read from the Session-1 raw exports except where the note says it is the preregistered design value. | paper_2_plasticity/scripts/10_extract_descriptives.R |
| `note` | character | How the value was obtained and what it excludes. | paper_2_plasticity/scripts/10_extract_descriptives.R |

## `_training_gate_flow.csv`

4 data row(s), 7 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `session` | integer | ERP session (2, 3, 4 or 6). One row per session. Written to both papers by Paper 1's gate reconstruction. | paper_1_transfer/scripts/00d_extract_training_gate_flow.R |
| `grammatical_property` | character | Always 'ALL': the comprehension gate was applied per session and cannot be resolved per property. | paper_1_transfer/scripts/00d_extract_training_gate_flow.R |
| `n_attempted` | integer | Subjects with an interpretable gate outcome (n_passed_attempt1 + n_passed_attempt2 + n_failed_gate). At Session 6, which had no gate, subjects with scored judgements. | paper_1_transfer/scripts/00d_extract_training_gate_flow.R |
| `n_passed_attempt1` | integer | Subjects who passed the >80% post-training comprehension test on the first attempt. | paper_1_transfer/scripts/00d_extract_training_gate_flow.R |
| `n_passed_attempt2` | integer | Subjects who failed the first attempt and passed the second. | paper_1_transfer/scripts/00d_extract_training_gate_flow.R |
| `n_failed_gate` | integer | Subjects who failed both attempts. | paper_1_transfer/scripts/00d_extract_training_gate_flow.R |
| `note` | character | Session-specific statement of how the counts were reconstructed and what they exclude. | paper_1_transfer/scripts/00d_extract_training_gate_flow.R |

## `p2_predictive_trajectory_aperiodic_projpred_path.csv`

20 data row(s), 14 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `model` | character | Reference model whose forward search the file records; the file name carries the same value. One row per submodel size. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `size` | integer | Number of terms in the submodel; 0 is the intercept-only submodel. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `predictor` | character | Term added at this step of the full-data forward search: '(Intercept)' at size 0; group-level terms appear as '(1 \| participant_lab_ID)' and '(z_session_time \| participant_lab_ID)'. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd` | numeric | Cross-validated expected log pointwise predictive density of the submodel on the response scale, summed over trials. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd_se` | numeric | Standard error of elpd. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd_diff` | numeric | elpd minus the reference model's elpd (the projpred convention); negative means worse than the reference model. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd_diff_se` | numeric | Standard error of elpd_diff. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `acc` | numeric | Cross-validated classification accuracy (proportion of trials predicted correctly) of the submodel; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `acc_se` | numeric | Standard error of acc; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `acc_diff` | numeric | acc minus the reference model's accuracy; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `suggested_size` | integer | Submodel size proposed by projpred::suggest_size(stat = 'elpd'): the smallest size whose elpd difference to the reference model is within one standard error of zero; repeated on every row. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `is_suggested` | logical | TRUE on the row whose size equals suggested_size. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `n_folds` | integer | Participant-grouped cross-validation folds (K). | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `n_participants` | integer | Participants in the reference fit. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |

## `p2_predictive_trajectory_gender_projpred_path.csv`

22 data row(s), 15 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `model` | character | Reference model whose forward search the file records; the file name carries the same value. One row per submodel size. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `size` | integer | Number of terms in the submodel; 0 is the intercept-only submodel. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `predictor` | character | Term added at this step of the full-data forward search: '(Intercept)' at size 0; group-level terms appear as '(1 \| participant_lab_ID)' and '(z_session_time \| participant_lab_ID)'. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd` | numeric | Cross-validated expected log pointwise predictive density of the submodel on the response scale, summed over trials. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd_se` | numeric | Standard error of elpd. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd_diff` | numeric | elpd minus the reference model's elpd (the projpred convention); negative means worse than the reference model. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd_diff_se` | numeric | Standard error of elpd_diff. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `acc` | numeric | Cross-validated classification accuracy (proportion of trials predicted correctly) of the submodel; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `acc_se` | numeric | Standard error of acc; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `acc_diff` | numeric | acc minus the reference model's accuracy; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `cv_prop_diag` | numeric | Proportion of cross-validation folds in which the predictor entered at this size occupied the same rank in the fold-wise search, a ranking-stability diagnostic; NA for path files produced without it. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `suggested_size` | integer | Submodel size proposed by projpred::suggest_size(stat = 'elpd'): the smallest size whose elpd difference to the reference model is within one standard error of zero; repeated on every row. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `is_suggested` | logical | TRUE on the row whose size equals suggested_size. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `n_folds` | integer | Participant-grouped cross-validation folds (K). | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `n_participants` | integer | Participants in the reference fit. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |

## `p2_predictive_trajectory_projpred_path.csv`

20 data row(s), 14 column(s).

| Column | Class | Description | Writer script |
|---|---|---|---|
| `model` | character | Reference model whose forward search the file records; the file name carries the same value. One row per submodel size. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `size` | integer | Number of terms in the submodel; 0 is the intercept-only submodel. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `predictor` | character | Term added at this step of the full-data forward search: '(Intercept)' at size 0; group-level terms appear as '(1 \| participant_lab_ID)' and '(z_session_time \| participant_lab_ID)'. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd` | numeric | Cross-validated expected log pointwise predictive density of the submodel on the response scale, summed over trials. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd_se` | numeric | Standard error of elpd. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd_diff` | numeric | elpd minus the reference model's elpd (the projpred convention); negative means worse than the reference model. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `elpd_diff_se` | numeric | Standard error of elpd_diff. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `acc` | numeric | Cross-validated classification accuracy (proportion of trials predicted correctly) of the submodel; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `acc_se` | numeric | Standard error of acc; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `acc_diff` | numeric | acc minus the reference model's accuracy; NA where projpred did not return it. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `suggested_size` | integer | Submodel size proposed by projpred::suggest_size(stat = 'elpd'): the smallest size whose elpd difference to the reference model is within one standard error of zero; repeated on every row. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `is_suggested` | logical | TRUE on the row whose size equals suggested_size. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `n_folds` | integer | Participant-grouped cross-validation folds (K). | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |
| `n_participants` | integer | Participants in the reference fit. | paper_2_plasticity/scripts/08_projpred_selection.R (the pooled raw-band and aperiodic files were produced by 08b_recover_projpred_path.R) |

