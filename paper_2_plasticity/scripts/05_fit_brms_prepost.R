# =============================================================================
# paper_2_plasticity/scripts/05_fit_brms_prepost.R
# Phase 3b -- Part B: pre/post CHANGE models  [HPC]
# =============================================================================
#
# Pre/post change, as Gaussian multilevel models with a by-participant random effect.
# The DV is z-scored per measure, so the shared weakly-informative prior is calibrated
# and the session effect is in SD units. Three blocks of models:
#
#   COGNITION  (S1 vs S5; data from 01_extract_cognitive_indices.R):
#     z(index) ~ session_prepost + (1 | participant_lab_ID)
#     one model per index (stroop_interference, digit_span, asrt_learning) -- does
#     intensive multilingual training change executive function / statistical learning?
#
#   JOINT COGNITION  (the same S1 vs S5 data, all three indices at once):
#     z(index) ~ session_prepost * measure + (1 + session_prepost | participant_lab_ID)
#     one model (p2_cognition_prepost_joint), with DIGIT SPAN as the reference level, so
#     each session_prepost:measure term is how much less that measure changed. This is
#     the within-model specificity test the manuscript reports; the logic and its limits
#     are set out at fit_cognition_prepost_joint() below. It is fitted alongside the
#     per-index models whenever the script runs with no argument or with "cognition".
#
#   RESTING-STATE EEG  (S2 vs S6; data from 03_extract_resting_state_eeg.R, IF present):
#     z(band power) ~ session_prepost + (1 | participant_lab_ID)
#     one model per band (delta/theta/alpha/beta/gamma) and IAF.
#     NOT ESTIMATED: resting-state EEG was recorded at Session 2 only, so there is no
#     Session-6 recording to pair it with (see _config.R's eeg_prepost entry and
#     03_extract_resting_state_eeg.R). Every model here exits at the two-session guard in
#     .fit_prepost_one, and neither manuscript reports an rs-EEG pre/post. The branch is
#     kept so the pipeline degrades gracefully if a Session-6 recording is ever added.
#
# session_prepost is +/-0.5 contrast coded (pre = -0.5, post = +0.5) so its coefficient
# is the standardised pre->post change. Part B uses a weakly-informative regularising
# prior throughout: the shared Gaussian baseline (les_priors_gaussian_weak) for the joint
# model, and that same set minus the lkj `cor` term for the intercept-only per-measure
# models, which carry no correlation parameter for it to match. It is built inline in
# .fit_prepost_one for that reason. Unlike Part A, Part B does not move to informative
# priors, because the training-change literature for these measures is too sparse to
# anchor one. The reasoning and its citations sit next to the prior below.
#
# USAGE (HPC)
#   Rscript 05_fit_brms_prepost.R             # cognition (per-index + joint); rs-EEG skips
#   Rscript 05_fit_brms_prepost.R cognition   # cognition only (per-index + joint)
#   Rscript 05_fit_brms_prepost.R eeg         # rs-EEG only (nothing is fitted; see above)
#   Rscript 05_fit_brms_prepost.R joint       # joint model only; with LES_P2_SIGN_ALIGNED=1
#                                             # it is the sign-aligned variant (_signaligned)
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "01_bayesian_settings.R"))
  source(here::here("_shared", "R", "02_diagnostics.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  library(dplyr)
})

.les_z <- function(x) {
  s <- stats::sd(x, na.rm = TRUE)
  if (is.na(s) || s == 0) return(rep(0, length(x)))
  as.numeric(scale(x))
}

# Fit one pre/post Gaussian model: z(measure) ~ session_prepost + (1 | participant).
.fit_prepost_one <- function(dat, measure, sessions, model_id) {
  d <- dat %>%
    filter(session %in% sessions, !is.na(.data[[measure]])) %>%
    mutate(z_value = .les_z(.data[[measure]]),
           # +/-0.5 contrast: earlier session = -0.5 (pre), later = +0.5 (post)
           session_prepost = ifelse(session == sessions[1], -0.5, 0.5),
           participant_lab_ID = factor(participant_lab_ID))
  if (dplyr::n_distinct(d$participant_lab_ID) < 5 || dplyr::n_distinct(d$session) < 2) {
    message("[p2-prepost] skipping ", model_id, " (insufficient pre/post data)"); return(invisible(NULL))
  }
  message(sprintf("[p2-prepost] fitting %s (n=%d obs, %d participants)",
                  model_id, nrow(d), dplyr::n_distinct(d$participant_lab_ID)))
  # An intercept-only random effect (1 | participant) has NO correlation parameter, so
  # the shared Gaussian prior's lkj(2) "cor" term is dropped here -- brms rejects a prior
  # that matches no model parameter. This is the weakly-informative baseline minus that
  # single term. Unlike Part A's tiered informative priors, Part B intentionally keeps
  # weakly-informative priors throughout: the pre/post literature for training-induced
  # change in these specific cognitive/rs-EEG measures over a comparable multilingual
  # training regime is too sparse for a literature-derived informative prior, so a
  # generic regularising prior is the honest choice (Schad, Betancourt & Vasishth 2021,
  # doi:10.1037/met0000275; Depaoli & van de Schoot 2017, doi:10.1037/met0000065).
  # Disclosed in the manuscript's Priors section.
  prepost_prior <- c(
    brms::prior(normal(0, 1),         class = "b"),
    brms::prior(normal(0, 1),         class = "Intercept"),
    brms::prior(student_t(3, 0, 2.5), class = "sd"),
    brms::prior(student_t(3, 0, 2.5), class = "sigma")
  )
  fit <- les_brm(
    formula = z_value ~ session_prepost + (1 | participant_lab_ID),
    data    = d,
    family  = gaussian(),
    prior   = prepost_prior,
    file    = paper2_results(model_id)
  )
  conv <- les_check_convergence(fit, label = model_id,
                                save_to = paper2_results(paste0(model_id, "_convergence.rds")))
  les_posterior_summary(fit, save_to = paper2_results(paste0(model_id, "_summary.rds")))
  invisible(fit)
}

fit_cognition_prepost <- function() {
  cog <- readRDS(paper2_derived("cognitive_indices.rds"))
  # 01_extract drops records with no enrolled-participant mapping; assert that here
  # so an unlinked record can never re-enter the z-scoring silently.
  stopifnot(!any(is.na(cog$participant_lab_ID)))
  for (measure in c("stroop_interference", "digit_span", "asrt_learning")) {
    .fit_prepost_one(cog, measure, sessions = LES_P2_COG_SESSIONS,           # c(1, 5)
                     model_id = paste0(LES_P2_MODELS[["cog_prepost"]], "_", measure))
  }
}

# JOINT pre/post model across the three indices -- each variable as an internal control
# for the others. The study has no no-training control group, so a pre->post change is
# confounded with generic threats shared by any uncontrolled retest (practice/retest
# effects, regression to the mean, maturation, expectancy; Shadish, Cook & Campbell, 2002;
# Calamia, Markon & Tranel, 2012; Barnett, van der Pols & Dobson, 2005). Those threats act
# BROADLY across co-administered, equally-retested measures, so we model the three together,
# z-scored within measure, with DIGIT SPAN as the reference level: the `session_prepost`
# coefficient is its pre->post change, and each `session_prepost:measure` term is how much
# LESS that measure changed. Credibly negative interactions mean the working-memory change
# exceeds the co-administered controls -- a within-model SPECIFICITY test that shields the
# effect against the SHARED confounds. It does NOT replace a control group and cannot rule
# out a digit-span-specific practice effect (see manuscript Discussion; Boot et al., 2013).
#
# OPT-IN SIGN-ALIGNED VARIANT (LES_P2_SIGN_ALIGNED=1)
# stroop_interference is incongruent minus congruent RT (higher = WORSE inhibition),
# whereas digit_span and asrt_learning are higher = better / more learning (see the
# index orientation in _config.R). In the joint model the session_prepost:measure
# contrast for Stroop therefore compares a change on a reversed scale against digit
# span. With the switch on, the Stroop values are sign-flipped BEFORE the within-
# measure z-scoring, so a positive session effect means improvement on all three
# indices and the contrasts compare like with like. The fit is written under its own
# model id (p2_cognition_prepost_joint_signaligned) and never touches the reported
# joint fit; the factor level keeps its name, so the parameter names are unchanged.
# The per-index models are not affected: under a flip their session coefficient would
# only change sign, which is not a new estimate. With the variable unset every path
# and value is exactly what it was.
les_p2_sign_aligned <- function() identical(Sys.getenv("LES_P2_SIGN_ALIGNED"), "1")
les_p2_sign_tag     <- function() if (les_p2_sign_aligned()) "_signaligned" else ""

fit_cognition_prepost_joint <- function() {
  cog <- readRDS(paper2_derived("cognitive_indices.rds"))
  # 01_extract drops records with no enrolled-participant mapping; assert that here
  # so an unlinked record can never re-enter the z-scoring silently.
  stopifnot(!any(is.na(cog$participant_lab_ID)))
  measures <- c("digit_span", "stroop_interference", "asrt_learning")
  long <- do.call(rbind, lapply(measures, function(m) {
    d <- cog[cog$session %in% LES_P2_COG_SESSIONS & !is.na(cog[[m]]), , drop = FALSE]
    data.frame(participant_lab_ID = d$participant_lab_ID, session = d$session,
               measure = m, value = d[[m]], stringsAsFactors = FALSE)
  }))
  if (les_p2_sign_aligned()) {
    flip <- long$measure == "stroop_interference"
    long$value[flip] <- -long$value[flip]
    message("[p2-prepost] LES_P2_SIGN_ALIGNED=1: stroop_interference sign-flipped before ",
            "z-scoring (", sum(flip), " values), so higher = better on all three indices")
  }
  long <- long %>%
    group_by(measure) %>% mutate(z_value = .les_z(value)) %>% ungroup() %>%
    mutate(session_prepost = ifelse(session == LES_P2_COG_SESSIONS[1], -0.5, 0.5),
           measure = stats::relevel(factor(measure), ref = "digit_span"),
           participant_lab_ID = factor(participant_lab_ID))
  if (dplyr::n_distinct(long$participant_lab_ID) < 5) {
    message("[p2-prepost] skipping joint model (insufficient data)"); return(invisible(NULL))
  }
  model_id <- paste0("p2_cognition_prepost_joint", les_p2_sign_tag())
  message(sprintf("[p2-prepost] fitting %s (n=%d obs, %d participants, 3 measures)",
                  model_id, nrow(long), dplyr::n_distinct(long$participant_lab_ID)))
  # A by-participant random slope IS present here, so the shared Gaussian prior's lkj 'cor'
  # term is valid (contrast with the single-measure intercept-only models above).
  fit <- les_brm(
    formula = z_value ~ session_prepost * measure + (1 + session_prepost | participant_lab_ID),
    data    = long,
    family  = gaussian(),
    prior   = les_priors_gaussian_weak(),
    file    = paper2_results(model_id)
  )
  les_check_convergence(fit, label = model_id,
                        save_to = paper2_results(paste0(model_id, "_convergence.rds")))
  les_posterior_summary(fit, save_to = paper2_results(paste0(model_id, "_summary.rds")))
  invisible(fit)
}

fit_rseeg_prepost <- function() {
  rseeg_path <- paper2_derived("resting_state_eeg.rds")
  if (!file.exists(rseeg_path)) {
    message("[p2-prepost] resting_state_eeg.rds not found -- run 03 on the HPC first; skipping rs-EEG pre/post.")
    return(invisible(NULL))
  }
  rs <- readRDS(rseeg_path) %>%
    group_by(participant_lab_ID, session) %>%          # average over eyes-open/closed
    summarise(across(c(delta, theta, alpha, beta, gamma, iaf), ~ mean(.x, na.rm = TRUE)),
              .groups = "drop")
  for (measure in c("delta", "theta", "alpha", "beta", "gamma", "iaf")) {
    .fit_prepost_one(rs, measure, sessions = LES_P2_NEURAL_SESSIONS,         # c(2, 6)
                     model_id = paste0(LES_P2_MODELS[["eeg_prepost"]], "_", measure))
  }
}

# =============================================================================
# Entry point
# =============================================================================
.run <- function() {
  which <- commandArgs(trailingOnly = TRUE)
  if (length(which) == 0 || "cognition" %in% which) { fit_cognition_prepost(); fit_cognition_prepost_joint() }
  # "joint" refits the joint model alone (used for the opt-in sign-aligned variant, so
  # the per-index artefacts are not re-derived and rewritten in the same run).
  if ("joint" %in% which && !("cognition" %in% which)) fit_cognition_prepost_joint()
  if (length(which) == 0 || "eeg" %in% which)       fit_rseeg_prepost()
  message("[p2-prepost] done.")
}

if (sys.nframe() == 0L) .run()
