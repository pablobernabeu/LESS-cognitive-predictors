# =============================================================================
# paper_2_plasticity/scripts/04_fit_brms_predictors.R
# Phase 3b -- Part A: predictors of the learning trajectory (JOINT model)  [HPC]
# =============================================================================
#
# MODEL (established 2026-06-10 from a methods review; see README.md, Part A)
# ---------------------------------------------------------------------------
# A SINGLE Bayesian multilevel Bernoulli model of trial-level grammaticality-
# judgement accuracy, in which the learning RATE is the by-participant random slope
# for session/time and the baseline individual-difference predictors enter as
# INTERACTIONS with time -- NOT a two-stage "extract a slope then regress it"
# design (which biases predictor effects via regression dilution and understates
# uncertainty; Gelman 2005; Humberg, Grund & Nestler 2024; Barrett et al. 2019).
#
#   POOLED:   correct ~ z_session_time * grammatical_property
#                     + z_session_time * (cognitive + rs-EEG predictors)
#                     + (1 + z_session_time | participant_lab_ID)
#   GENDER-ONLY sensitivity (LES_P2_SENSITIVITY_PROPERTY): drop the property terms
#     (single property, full S2/3/4/6 coverage, near-stable trajectory) to confirm
#     the predictor effects are not an artefact of difficulty-confounded pooling.
#
# We report BOTH the learning RATE (the predictor x time interactions) and
# ATTAINMENT (modelled end-of-training accuracy) at the summary stage (06), and
# assess the reliability of the by-participant rate/attainment there.
#
# PREDICTORS
#   Cognitive (baseline S1, from 02): z_digit_span, z_stroop, z_asrt.
#   Resting-state EEG (baseline S2, from 03, IF AVAILABLE): z_alpha, z_theta,
#     z_beta, z_delta, z_gamma, z_iaf. Until 03 has run on the HPC, the model is
#     fit with the cognitive predictors only; the rs-EEG terms are added
#     automatically once resting_state_eeg.rds exists.
#
# PRIORS
#   INFORMATIVE, tiered, established from a citation-verified review (see
#   les_p2_partA_priors below for the per-predictor magnitudes + DOIs). Because every
#   cited effect is an ATTAINMENT correlation (not a learning-rate effect), the small
#   informative prior sits on each predictor's MAIN effect and is shrunk near-zero on
#   its x time (learning-rate) interaction. The weakly-informative baseline is retained
#   as the sensitivity analysis (run with LES_PRIOR_SET=weak; file names are then tagged
#   so the two runs never clash). Sampler/backend/threading: _shared/R/01_bayesian_settings.R.
#
# USAGE (HPC)
#   Rscript 04_fit_brms_predictors.R          # pooled + gender-only sensitivity
#   Rscript 04_fit_brms_predictors.R pooled   # pooled only
#   Rscript 04_fit_brms_predictors.R gender   # gender-only only
#   Rscript 04_fit_brms_predictors.R aperiodic         # de-confounded (specparam) pooled
#   Rscript 04_fit_brms_predictors.R aperiodic_gender  # de-confounded gender-only
# The two aperiodic variants are opt-in and are NOT fitted when no argument is given.
# hpc/09_aperiodic_model.slurm passes both.
#
# DE-CONFOUNDED (APERIODIC) VARIANT -- pre-specification note (added 2026-07-02)
# -------------------------------------------------------------------------------
# `aperiodic = TRUE` fits a SECOND Part A reference model that replaces raw rs-EEG
# band power with the specparam/aperiodic decomposition (07_extract_aperiodic.R;
# Donoghue et al. 2020's argument that raw band power conflates periodic and
# aperiodic/1-over-f activity). Honesty check: the raw-band model's result (band
# powers largely uninformative, with a suggestive individual-alpha-frequency signal)
# was already known and written into the manuscript before this variant's code was
# written. The variant is a robustness check motivated by Donoghue et al.'s
# de-confounding argument, which holds independently of what the raw-band model showed.
# It is not a blinded pre-registration.
#
# To keep this an honest robustness check rather than a second, unacknowledged
# "sweep" for a nicer story (an internal audit, 2026-07-02, flagged exactly this
# researcher-degrees-of-freedom risk), THREE commitments apply whenever this
# variant's results are drafted into the manuscript:
#   (1) Report the raw and aperiodic models' predictor estimates AND their
#       08_projpred_selection.R rankings side by side (main text + SI), regardless
#       of which looks more favourable -- never let the choice of which to show be
#       made silently.
#   (2) Run 09b_compare_aperiodic_commonsample.R (PSIS-LOO comparison, within each of
#       the pooled and gender-only strata, on the aperiodic model's common
#       50-participant sample; it supersedes 09_compare_aperiodic.R, whose comparison
#       spanned different row sets) and report its elpd_diff/preferred_model as the
#       primary, quantified basis for which characterisation the Discussion
#       emphasises, rather than an implicit author judgement call.
#   (3) Frame any aperiodic-model predictor ranking as relative to the raw-band
#       ranking and the loo_compare verdict (e.g. "under the loo-preferred
#       [raw/de-confounded] characterisation, ..."), never as a standalone finding.
#
# AMENDMENT TO COMMITMENT (2), 2026-08-12
# ---------------------------------------
# 09b's PSIS-LOO comparison is still run and still reported, as committed. It is no
# longer the sole basis for the Discussion, because it leaves out one TRIAL at a time
# while the two models differ only in predictors that are constant within a participant,
# so it is close to blind to the difference under test (the reasoning and the measured
# near-zero differences are set out in 09c_compare_aperiodic_grouped.R). On the date
# above, 09c_compare_aperiodic_grouped.R was added to compare the same two models by
# participant-grouped K-fold cross-validation, the criterion matched to the
# between-participant estimand, and the manuscript reports both, anchoring the
# characterisation to the grouped comparison. The amendment is recorded here so the
# departure from the commitment as first written is visible rather than silent.
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "01_bayesian_settings.R"))
  source(here::here("_shared", "R", "02_diagnostics.R"))
  source(here::here("_shared", "R", "04_provenance.R"))
  source(here::here("_shared", "R", "06_helpers.R"))           # les_zscore()
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  library(dplyr)
})

# The resting-state predictors in the order the fitted formula lists them. This order is
# kept as it is, and not taken from LES_P2_RS_MEASURES, because it fixes the column order
# of the design matrix and with it the coefficient indices in the generated Stan code, on
# which brms's file_refit = "on_change" cache keys; a reordering would refit every cached
# model. The set is asserted against the config so a renamed measure cannot drift.
.les_p2_rs_terms <- c("alpha", "theta", "beta", "delta", "gamma", "iaf")
stopifnot(setequal(.les_p2_rs_terms, LES_P2_RS_MEASURES))

# --- Opt-in: IAF-resolved sensitivity refit (LES_P2_IAF_RESOLVED=1) -----------
#
# 03_extract_resting_state_eeg.R keeps the plain argmax as the IAF estimator, and
# defends that choice against the specparam peak frequency, but records one residual
# problem it cannot solve at the estimator level: for two participants specparam finds
# no alpha peak at all, so any value in the 7-13 Hz search range is spurious for them
# and the argmax pins both at the 7 Hz floor, at the extreme of the predictor's range.
# That script asks in terms for IAF-based claims to be "checked for sensitivity to
# their exclusion rather than silently resting on an imputed boundary value".
#
# This switch is that check. Participant 23 is deliberately NOT excluded: they also sit
# at 7 Hz, but specparam puts their peak at 7.21 Hz, so their low argmax is correct and
# dropping them would remove a genuine observation.
#
# Scope. The filter applies to the GENDER-ONLY stratum only, which is the stratum the
# switch is specified for, and the fits it produces are tagged "_iafres" so they can
# neither overwrite nor shadow the reported ones. With the variable unset every path
# below is unchanged, so the default run is byte-identical.
#
# The predictors are deliberately NOT re-standardised after the exclusion. z-scoring
# runs over every recording that has the measure (see les_p2_load_partA_data), before
# the join, the listwise deletion and the gender-only filter, so a coefficient is per
# standard deviation of the measured sample. Keeping that convention is what makes the
# refit's coefficients directly comparable with the reported ones instead of merely
# similar-looking numbers on a silently rescaled predictor.
LES_P2_IAF_UNRESOLVED <- c(12L, 41L)

# The two ids above are a fact derived from two artefacts: script 07 finds no specparam
# alpha peak for them, and script 03's argmax sits at the floor of the search window.
# They are typed, so a re-run of 07 or 03 under different settings could invalidate the
# refit's definition without any script noticing. This check derives the same set from
# the artefacts on disk and stops on disagreement. It is called where the list is used
# (the IAF-resolved branch of fit_paper2_partA), and it is skipped when either artefact
# is absent, so the default run is unchanged.
les_p2_check_iaf_unresolved <- function() {
  ap_path <- paper2_results("07_aperiodic_features.csv")
  rs_path <- paper2_derived("resting_state_eeg.rds")
  if (!file.exists(ap_path) || !file.exists(rs_path)) {
    message("[p2-partA] IAF-unresolved list not checked: an artefact it derives from is ",
            "absent (", basename(ap_path), ", ", basename(rs_path), ").")
    return(invisible(FALSE))
  }
  ap <- utils::read.csv(ap_path, stringsAsFactors = FALSE)
  ap <- ap[ap$session == LES_P2_NEURAL_SESSIONS[1] & ap$condition == "eyes_closed", ]
  rs <- readRDS(rs_path)
  rs <- rs[rs$session == LES_P2_NEURAL_SESSIONS[1] & rs$condition == "eyes_closed", ]
  no_peak <- ap$participant_lab_ID[is.na(ap$specparam_iaf)]
  floored <- rs$participant_lab_ID[is.finite(rs$iaf) &
                                     abs(rs$iaf - LES_P2_IAF_SEARCH_HZ[1]) < 1e-9]
  derived <- sort(as.integer(intersect(no_peak, floored)))
  if (!setequal(derived, LES_P2_IAF_UNRESOLVED)) {
    stop("[p2-partA] LES_P2_IAF_UNRESOLVED = {", paste(LES_P2_IAF_UNRESOLVED, collapse = ", "),
         "} but the artefacts give {", paste(derived, collapse = ", "),
         "} (no specparam alpha peak and argmax IAF at the floor of the search window). ",
         "Re-derive the list before running the IAF-resolved refit.", call. = FALSE)
  }
  invisible(TRUE)
}

les_p2_iaf_resolved <- function() identical(Sys.getenv("LES_P2_IAF_RESOLVED"), "1")
les_p2_iaf_tag      <- function() if (les_p2_iaf_resolved()) "_iafres" else ""

# --- Load the trajectory DV + baseline predictors (cognition; rs-EEG if present) -
# aperiodic = TRUE additionally joins the specparam-decomposed rs-EEG predictors
# (07_extract_aperiodic.R): the aperiodic exponent/offset and the 1/f-ADJUSTED
# oscillatory band power, which replace the raw band power in the de-confounded
# Part A variant. Raw band power conflates periodic and aperiodic (1/f) activity, so
# the parameterised quantities are the scientifically correct neural predictors
# (Donoghue et al. 2020). The raw-model path is unchanged when aperiodic = FALSE.
les_p2_load_partA_data <- function(aperiodic = FALSE) {
  traj <- readRDS(paper2_derived("learning_trajectory.rds"))

  rseeg_path <- paper2_derived("resting_state_eeg.rds")
  if (file.exists(rseeg_path)) {
    # Baseline (S2) EYES-CLOSED resting-state band power + IAF -- eyes-closed is the
    # standard resting measure (alpha/IAF are suppressed and unreliable eyes-open) --
    # z-scored across participants -> between-participant predictors (x time).
    # As with the cognitive predictors in 02, the z-scoring runs over every recording
    # that has the measure, before the join, the listwise deletion below and the
    # gender-only filter, so a coefficient is per standard deviation of the measured
    # sample rather than of the fitted subsample. les_zscore(all_na = "zero") turns an
    # all-NA measure into zeros, which is what this pipeline has always done.
    rs <- readRDS(rseeg_path) %>%
      filter(session == LES_P2_NEURAL_SESSIONS[1], condition == "eyes_closed") %>%  # S2 baseline
      group_by(participant_lab_ID) %>%
      summarise(across(dplyr::all_of(LES_P2_RS_MEASURES), ~ mean(.x, na.rm = TRUE)),
                .groups = "drop") %>%
      mutate(across(dplyr::all_of(LES_P2_RS_MEASURES), ~ les_zscore(.x, all_na = "zero"),
                    .names = "z_{.col}")) %>%
      select(participant_lab_ID, dplyr::starts_with("z_"))
    # Harmonise the join-key type: the trajectory stores participant_lab_ID as a factor,
    # while 03 writes integer IDs; coerce both to character so the merge is type-safe.
    rs$participant_lab_ID   <- as.character(rs$participant_lab_ID)
    traj$participant_lab_ID <- as.character(traj$participant_lab_ID)
    traj <- left_join(traj, rs, by = "participant_lab_ID")
  } else {
    message("[p2-partA] resting_state_eeg.rds not found -- fitting with cognitive predictors only ",
            "(run 03 on the HPC to add the rs-EEG predictors).")
  }

  # --- De-confounded (specparam) rs-EEG predictors, for the aperiodic variant ----
  # 07_extract_aperiodic.R parses participant_lab_ID from the same _RS_eyes_*.vhdr
  # filenames as 03, so this join keys identically to the raw rs-EEG join above.
  if (aperiodic) {
    ap_path <- paper2_results("07_aperiodic_features.csv")
    if (!file.exists(ap_path))
      stop("[p2-partA] aperiodic = TRUE but ", basename(ap_path), " not found -- ",
           "run 07_extract_aperiodic.R on the HPC first.")
    ap <- utils::read.csv(ap_path, stringsAsFactors = FALSE) %>%
      filter(session == LES_P2_NEURAL_SESSIONS[1], condition == "eyes_closed") %>%  # S2 baseline
      group_by(participant_lab_ID) %>%
      summarise(across(c(aperiodic_exponent, aperiodic_offset,
                         theta_adj, alpha_adj, beta_adj, specparam_iaf),
                       ~ mean(.x, na.rm = TRUE)), .groups = "drop") %>%
      mutate(z_aperiodic_exponent = les_zscore(aperiodic_exponent, all_na = "zero"),
             z_aperiodic_offset   = les_zscore(aperiodic_offset, all_na = "zero"),
             z_theta_adj          = les_zscore(theta_adj, all_na = "zero"),
             z_alpha_adj          = les_zscore(alpha_adj, all_na = "zero"),
             z_beta_adj           = les_zscore(beta_adj, all_na = "zero"),
             z_specparam_iaf      = les_zscore(specparam_iaf, all_na = "zero")) %>%
      select(participant_lab_ID, dplyr::starts_with("z_"))
    ap$participant_lab_ID   <- as.character(ap$participant_lab_ID)
    traj$participant_lab_ID <- as.character(traj$participant_lab_ID)
    traj <- left_join(traj, ap, by = "participant_lab_ID")
  }

  traj
}

# Which standardised predictors are actually present (and not all-NA) in the data.
# aperiodic = TRUE swaps the raw band-power candidates for the de-confounded set:
# aperiodic exponent/offset + 1/f-adjusted theta/alpha/beta power + specparam IAF.
les_p2_partA_predictors <- function(dat, aperiodic = FALSE) {
  cand <- if (aperiodic)
    c("z_digit_span", "z_stroop", "z_asrt",
      "z_aperiodic_exponent", "z_aperiodic_offset",
      "z_theta_adj", "z_alpha_adj", "z_beta_adj", "z_specparam_iaf")
  else
    c("z_digit_span", "z_stroop", "z_asrt", paste0("z_", .les_p2_rs_terms))
  present <- intersect(cand, names(dat))
  present[vapply(present, function(p) any(!is.na(dat[[p]])), logical(1))]
}

les_p2_partA_formula <- function(predictors, include_property) {
  pred_term <- paste(predictors, collapse = " + ")
  prop_term <- if (include_property) "z_session_time * grammatical_property + " else ""
  stats::as.formula(paste0(
    "correct ~ ", prop_term,
    "z_session_time * (", pred_term, ")",
    " + (1 + z_session_time | participant_lab_ID)"
  ))
}

# --- Informative Part A priors (standardised logit scale) ---------------------
# Established from a citation-verified review. All cited effects are ATTAINMENT/concurrent
# correlations, NOT learning-rate effects, so the (small) informative prior sits on the
# predictor MAIN effect and is SHRUNK toward zero on its x time interaction (the
# learning-rate term):
#   * Working memory / digit span -- small POSITIVE; meta rho = .255 overall, but
#     simple/storage (digit) span is the weak end, r ~= .15 (Linck, Osthus, Koeth &
#     Bunting 2014, doi:10.3758/s13423-013-0565-2; Kurokawa 2026,
#     doi:10.1075/itl.25009.kur).
#   * Statistical learning (ASRT) -- small POSITIVE; meta r ~= .16 (Zhou, Boeve &
#     Bogaerts 2024, doi:10.3917/anpsy1.243.0283; Misyak & Christiansen 2012,
#     doi:10.1111/j.1467-9922.2010.00626.x).
#   * Inhibition (Stroop) -- NEAR-ZERO regularising; preregistered replication failure +
#     large nulls (Huensch 2024, doi:10.1017/S0272263124000238; Dick et al. 2019,
#     doi:10.1038/s41562-019-0609-3; Linck & Weiss 2015, doi:10.1177/2158244015607352).
#   * Resting-state EEG bands / IAF -- EVIDENCE GAP in the verified review -> near-zero
#     regularising, direction not established.
# (DOIs are from the review and are Crossref-verified before entering references.bib.)
les_p2_partA_priors <- function(predictors) {
  pr <- c(
    brms::prior(normal(1, 1),         class = "Intercept"),  # accuracy well above chance
    brms::prior(normal(0, 1),         class = "b"),           # property, time, property x time
    brms::prior(student_t(3, 0, 2.5), class = "sd"),          # generous by-participant SDs
    brms::prior(lkj(2),               class = "cor")
  )
  add <- function(coef, m, s) {
    brms::prior_string(sprintf("normal(%s, %s)", m, s), class = "b", coef = coef)
  }
  if ("z_digit_span" %in% predictors)
    pr <- c(pr, add("z_digit_span", 0.10, 0.25), add("z_session_time:z_digit_span", 0.05, 0.15))
  if ("z_asrt" %in% predictors)
    pr <- c(pr, add("z_asrt", 0.10, 0.20),       add("z_session_time:z_asrt", 0.05, 0.15))
  if ("z_stroop" %in% predictors)
    pr <- c(pr, add("z_stroop", 0.00, 0.15),     add("z_session_time:z_stroop", 0.00, 0.10))
  # rs-EEG bands / IAF -- raw AND specparam-decomposed (aperiodic exponent/offset,
  # 1/f-adjusted band power): all EVIDENCE-GAP predictors, so near-zero regularising,
  # direction not established. The aperiodic names are absent in the raw model, so
  # adding them here leaves the raw-model priors unchanged. The order is the formula's
  # (.les_p2_rs_terms), so the prior rows keep their positions.
  for (b in intersect(c(paste0("z_", .les_p2_rs_terms),
                        "z_aperiodic_exponent","z_aperiodic_offset",
                        "z_theta_adj","z_alpha_adj","z_beta_adj","z_specparam_iaf"),
                      predictors))
    pr <- c(pr, add(b, 0.00, 0.25), add(paste0("z_session_time:", b), 0.00, 0.15))
  pr
}

fit_paper2_partA <- function(gender_only = FALSE, aperiodic = FALSE) {
  dat <- les_p2_load_partA_data(aperiodic = aperiodic)
  if (gender_only) dat <- dat %>% filter(grammatical_property == LES_P2_SENSITIVITY_PROPERTY)

  # Opt-in IAF-resolved sensitivity refit; see LES_P2_IAF_UNRESOLVED above. Applies to
  # the gender-only stratum, and fails closed rather than quietly producing a tagged fit
  # that is identical to the untagged one: if neither participant is in the data, a
  # "_iafres" artefact would misrepresent an unchanged sample as an exclusion refit.
  iaf_tag <- ""
  if (les_p2_iaf_resolved()) {
    if (gender_only) {
      les_p2_check_iaf_unresolved()
      drop <- as.character(dat$participant_lab_ID) %in% as.character(LES_P2_IAF_UNRESOLVED)
      if (!any(drop))
        stop("[p2-partA] LES_P2_IAF_RESOLVED=1 but neither participant ",
             paste(LES_P2_IAF_UNRESOLVED, collapse = " nor "),
             " is present in the gender-only data; the refit would be the reported model ",
             "under a sensitivity-analysis name.")
      message(sprintf("[p2-partA] LES_P2_IAF_RESOLVED=1: dropping %d rows from %d of the %d ",
                      sum(drop),
                      length(unique(as.character(dat$participant_lab_ID)[drop])),
                      length(LES_P2_IAF_UNRESOLVED)),
              "participants with no specparam-resolvable alpha peak.")
      dat <- dat[!drop, , drop = FALSE]
      iaf_tag <- les_p2_iaf_tag()
    } else {
      message("[p2-partA] LES_P2_IAF_RESOLVED=1 is scoped to the gender-only stratum; ",
              "this fit is unaffected and keeps its reported, untagged identity.")
    }
  }

  preds <- les_p2_partA_predictors(dat, aperiodic = aperiodic)
  if (!length(preds)) stop("No usable Part A predictors found in the trajectory data.")

  dat <- dat %>%
    mutate(participant_lab_ID = factor(participant_lab_ID)) %>%
    tidyr::drop_na(dplyr::all_of(c("correct", "z_session_time", preds)))

  model_key <- if (aperiodic) {
    if (gender_only) "predictive_aperiodic_gender" else "predictive_aperiodic"
  } else {
    if (gender_only) "predictive_gender" else "predictive"
  }
  model_id <- LES_P2_MODELS[[model_key]]
  message(sprintf("[p2-partA] fitting %s | %s%s | predictors: %s",
                  model_id, if (gender_only) "gender-only" else "pooled",
                  if (aperiodic) " | de-confounded (specparam)" else "",
                  paste(preds, collapse = ", ")))

  # Tag order is iaf -> prior, so the prior tag stays the LAST component of the name and
  # anything matching on that suffix keeps working. The prior tag is "" (informative) or
  # "_weakprior" (the sensitivity baseline).
  model_tag <- les_p2_model_id(model_key, c(iaf_tag, les_prior_tag()))
  # Informative (les_p2_partA_priors) by default; LES_PRIOR_SET=weak selects the
  # weakly-informative sensitivity baseline.
  prior_set <- if (LES_PRIOR_SET() == "weak") {
    les_priors_bernoulli_weak()
  } else {
    les_p2_partA_priors(preds)
  }

  fit <- les_brm(
    formula = les_p2_partA_formula(preds, include_property = !gender_only),
    data    = dat,
    family  = bernoulli(),
    prior   = prior_set,
    file    = paper2_results(model_tag)
  )

  conv <- les_check_convergence(fit, label = model_id,
                                save_to = paper2_results(paste0(model_tag, "_convergence.rds")))
  les_posterior_summary(fit, save_to = paper2_results(paste0(model_tag, "_summary.rds")))
  try(les_save_ppc(fit, paper2_figures(paste0(model_tag, "_ppc.png")), type = "bars"),
      silent = TRUE)
  # Per-fit record of the analysed sample and the fitting environment (see _config.R).
  les_p2_write_fit_meta(dat, model_tag, paper2_results(paste0(model_tag, "_fitmeta.rds")))

  message(sprintf("[p2-partA] %s | converged = %s | max Rhat = %.4f | divergences = %d",
                  model_id, conv$passed, conv$max_rhat, conv$n_divergent))
  invisible(fit)
}

# =============================================================================
# Entry point
# =============================================================================
.run <- function() {
  which <- commandArgs(trailingOnly = TRUE)
  none <- length(which) == 0
  # Default (no args) fits ONLY the raw-band models, so existing behaviour is byte-identical.
  # The de-confounded specparam variants are opt-in via the explicit aperiodic* args.
  if (none || "pooled" %in% which)   fit_paper2_partA(gender_only = FALSE, aperiodic = FALSE)
  if (none || "gender" %in% which)   fit_paper2_partA(gender_only = TRUE,  aperiodic = FALSE)
  if ("aperiodic" %in% which)        fit_paper2_partA(gender_only = FALSE, aperiodic = TRUE)
  if ("aperiodic_gender" %in% which) fit_paper2_partA(gender_only = TRUE,  aperiodic = TRUE)
  # Record the environment that actually produced these fits (see 04_provenance.R). The
  # file is untagged and rewritten by every run of this script whatever variant switches
  # are set, so a sensitivity run leaves it describing that run. LES_PROVENANCE_SKIP=1
  # leaves the run-level record alone; the per-fit records above are written regardless.
  if (!identical(Sys.getenv("LES_PROVENANCE_SKIP"), "1")) {
    try(les_write_provenance(paper2_results(), seeds = list(LES_SEED = LES_SEED)),
        silent = TRUE)
  }
  message("[p2-partA] done.")
}

if (sys.nframe() == 0L) .run()
