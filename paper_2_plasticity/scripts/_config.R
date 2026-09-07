# =============================================================================
# paper_2_plasticity/scripts/_config.R
# Analysis grid & constants for Paper 2
#   "Cognitive and Resting-State EEG Predictors of Intensive Multilingual Learning"
# =============================================================================
#
# Paper 2 relates baseline executive-function, statistical-learning and resting-state
# EEG measures to artificial-language learning (Part A) and tests pre/post change in
# cognition, Sessions 1 vs 5 (Part B). Resting-state EEG exists for Session 2 only, so
# no neural pre/post is estimated.
# This file is the single source of truth for the indices, sessions and naming the
# pipeline shares; it is kept separate from the numbered extraction/fitting scripts.
# =============================================================================

if (!exists("data_path"))            source(here::here("_shared", "R", "00_paths.R"))
if (!exists("cognitive_ef_path"))    source(here::here("_shared", "R", "03_data_manifest.R"))

# --- Sessions (reuse the shared single-source-of-truth from the data manifest) --
# Cognitive pre/post = S1 vs S5; neural (resting-state EEG) pre/post = S2 vs S6.
LES_P2_COG_SESSIONS    <- LES_COG_PREPOST       # c(1, 5)
LES_P2_NEURAL_SESSIONS <- LES_NEURAL_PREPOST    # c(2, 6)

# --- Executive-function / statistical-learning tasks -------------------------
# Each task's raw Gorilla exports live in cognitive_ef_path("Session <n>"); the
# file-name glob matches BOTH the per-participant ("qdvg4 Stroop.csv") and the
# batch ("Stroop 1.csv") exports. Files are read NON-recursively so the duplicate
# "Mini English/" subfolder under Session 1 is ignored, and rows are de-duplicated
# (some participants, e.g. wbij5, appear in both a named and a numbered export).
LES_P2_COG_TASKS <- list(
  stroop     = list(pattern = "Stroop",               index = "stroop_interference"),
  digit_span = list(pattern = "digit span",           index = "digit_span"),
  asrt       = list(pattern = "serial reaction time", index = "asrt_learning")
)
# The three index names, in task order, named by task key. Scripts that need a different
# order (digit span first as a reference level or a reporting order) index this vector by
# key, so a renamed index changes in one place.
LES_P2_COG_INDICES <- vapply(LES_P2_COG_TASKS, function(t) t$index, character(1))

# --- Trimming policy (carried over verbatim from the validated legacy
#     data/importation and preprocessing/preprocess *.R scripts) ----------------
LES_P2_RT_MIN          <- 50      # ms
LES_P2_RT_MAX          <- 5000    # ms
LES_P2_SD_CUTOFF       <- 3       # within-cell SD trim (Berger & Kiefer style; 3 SD)
LES_P2_MIN_OBS_STROOP  <- 50      # min retained trials per participant (Stroop)
LES_P2_MIN_OBS_ASRT    <- 100     # min retained trials per participant (ASRT)

# --- Index orientation (for prior signs and interpretation) ------------------
# stroop_interference = mean RT(incongruent) - mean RT(congruent)
#                       [higher = worse inhibition]
# digit_span          = sum of correct forward+backward trials
#                       [higher = better WM]
# asrt_learning       = mean RT(low-prob) - mean RT(high-prob)
#                       [higher = more statistical learning]

# --- Model identifiers the manuscript references -----------------------------
# Part A is a JOINT multilevel model of the judgement-accuracy trajectory (NOT a derived
# slope; see README.md, Part A). It is fit on the pooled 3-property data and, as a sensitivity
# analysis, restricted to gender agreement (full S2/3/4/6 coverage, near-stable trajectory).
LES_P2_MODELS <- c(
  # Part A: correct ~ time * (cognition + rs-EEG bands) + REs
  predictive        = "p2_predictive_trajectory",
  # Part A sensitivity: gender agreement only
  predictive_gender = "p2_predictive_trajectory_gender",
  # Part A de-confounded variant: raw band power replaced by 1/f-adjusted oscillatory
  # power + aperiodic exponent/offset (specparam; Donoghue et al. 2020), from 07.
  predictive_aperiodic        = "p2_predictive_trajectory_aperiodic",
  predictive_aperiodic_gender = "p2_predictive_trajectory_aperiodic_gender",
  # Part B: cognitive index ~ session (S1 vs S5), one model per index, suffixed "_<index>"
  cog_prepost       = "p2_cognition_prepost",
  # Part B: the three indices in one model, session * measure, digit span as reference
  cog_prepost_joint = "p2_cognition_prepost_joint",
  # INACTIVE: resting-state EEG was recorded at Session 2 only (there is no Session-6
  # resting recording; see 03_extract_resting_state_eeg.R and the manifest), so no rs-EEG
  # pre/post is estimated and neither manuscript reports one. This identifier is retained
  # only so the pipeline degrades gracefully if a Session-6 resting recording is ever added.
  eeg_prepost       = "p2_restingstate_prepost"           # (not fitted: single neural session)
)

# A model id with its variant tags appended, so the suffixes a sensitivity refit adds
# ("_iafres", "_weakprior", "_signaligned") are composed in one place. `tags` are
# concatenated in the order given; an empty vector returns the bare id.
les_p2_model_id <- function(key, tags = character()) {
  id <- LES_P2_MODELS[[key]]
  if (is.null(id)) stop("[paper2/_config] unknown model key: ", key)
  paste0(id, paste(tags, collapse = ""))
}
# Property for the Part A gender-only sensitivity analysis (guards against the pooled
# trajectory being an artefact of difficulty-confounded property composition).
LES_P2_SENSITIVITY_PROPERTY <- "gender_agreement"

# --- Resting-state EEG frequency bands (Hz) ----------------------------------
LES_P2_EEG_BANDS <- list(
  delta = c(1, 4), theta = c(4, 8), alpha = c(8, 13),
  beta  = c(13, 30), gamma = c(30, 45)
)
# The resting-state measures script 03 writes per recording: the five band powers, in
# band order, plus the individual alpha frequency.
LES_P2_RS_MEASURES <- c(names(LES_P2_EEG_BANDS), "iaf")
# Search window (Hz, inclusive) for the individual alpha frequency, shared by the argmax
# estimator in 03, the specparam peak in 07 and the resolvable-peak count in 10. It reaches
# below the 8 Hz lower edge of the alpha band; the note above les_iaf() in 03 says why.
LES_P2_IAF_SEARCH_HZ <- c(7, 13)

# --- Per-fit record of the analysed sample and the fitting environment --------
#
# Mirrors les_p1_write_fit_meta() in paper_1_transfer/scripts/_config.R without the
# mis-filter exclusion fields, which have no bearing on Paper 2's data. Called by the
# fitting scripts with the data frame passed to brms, after all filtering and listwise
# deletion, so n_obs and n_participants measure the analysed sample directly. The
# environment is recorded per fit because results/_provenance.csv is written once per
# invocation and only by script 04, so a fit produced by 05, 09b or a later refit of one
# model would otherwise carry no version record of its own. Script 06 pools these
# records into results/_pooled_fit_metadata.csv.
les_p2_write_fit_meta <- function(dat, model_id, path,
                                  prior_set = Sys.getenv("LES_PRIOR_SET",
                                                         unset = "informative")) {
  .ver <- function(p) tryCatch(as.character(utils::packageVersion(p)),
                               error = function(e) NA_character_)
  rec <- data.frame(
    model            = model_id,
    n_obs            = nrow(dat),
    n_participants   = length(unique(as.character(dat$participant_lab_ID))),
    prior_set        = prior_set,
    r_version        = paste0(R.version$major, ".", R.version$minor),
    brms_version     = .ver("brms"),
    cmdstanr_version = .ver("cmdstanr"),
    cmdstan_version  = tryCatch(as.character(cmdstanr::cmdstan_version()),
                                error = function(e) NA_character_),
    fitted_utc       = format(Sys.time(), tz = "UTC", usetz = TRUE),
    stringsAsFactors = FALSE
  )
  if (exists("les_assert_readonly_data")) les_assert_readonly_data(path)
  saveRDS(rec, path)
  invisible(rec)
}

cat(sprintf("[paper2/_config] cognitive sessions S%s; neural sessions S%s; %d EF tasks.\n",
            paste(LES_P2_COG_SESSIONS, collapse="/"),
            paste(LES_P2_NEURAL_SESSIONS, collapse="/"),
            length(LES_P2_COG_TASKS)))
