# =============================================================================
# paper_2_plasticity/scripts/_config.R
# Analysis grid & constants for Paper 2
#   "Cognitive Predictors and Neuroplasticity in Intensive Multilingual Learning"
# =============================================================================
#
# Paper 2 relates baseline executive-function / statistical-learning ability and
# resting-state EEG to artificial-language learning, and tests pre->post change in
# cognition (Sessions 1 vs 5) and in resting-state neural activity (Sessions 2 vs 6).
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

# --- Trimming policy (carried over verbatim from the validated legacy
#     data/importation and preprocessing/preprocess *.R scripts) ----------------
LES_P2_RT_MIN          <- 50      # ms
LES_P2_RT_MAX          <- 5000    # ms
LES_P2_SD_CUTOFF       <- 3       # within-cell SD trim (Berger & Kiefer style; 3 SD)
LES_P2_MIN_OBS_STROOP  <- 50      # min retained trials per participant (Stroop)
LES_P2_MIN_OBS_ASRT    <- 100     # min retained trials per participant (ASRT)

# --- Index orientation (for prior signs and interpretation) ------------------
# stroop_interference = mean RT(incongruent) - mean RT(congruent)  [higher = worse inhibition]
# digit_span          = sum of correct forward+backward trials      [higher = better WM]
# asrt_learning       = mean RT(low-prob) - mean RT(high-prob)       [higher = more statistical learning]

# --- Model identifiers the manuscript references -----------------------------
# Part A is a JOINT multilevel model of the judgement-accuracy trajectory (NOT a derived
# slope; see README.md, Part A). It is fit on the pooled 3-property data and, as a sensitivity
# analysis, restricted to gender agreement (full S2/3/4/6 coverage, near-stable trajectory).
LES_P2_MODELS <- c(
  predictive        = "p2_predictive_trajectory",         # Part A: correct ~ time * (cognition + rs-EEG bands) + REs
  predictive_gender = "p2_predictive_trajectory_gender",  # Part A sensitivity: gender agreement only
  # Part A de-confounded variant: raw band power replaced by 1/f-adjusted oscillatory
  # power + aperiodic exponent/offset (specparam; Donoghue et al. 2020), from 07.
  predictive_aperiodic        = "p2_predictive_trajectory_aperiodic",
  predictive_aperiodic_gender = "p2_predictive_trajectory_aperiodic_gender",
  cog_prepost       = "p2_cognition_prepost",             # Part B: cognitive index ~ session (S1 vs S5)
  # INACTIVE: resting-state EEG was recorded at Session 2 only (there is no Session-6
  # resting recording; see 03_extract_resting_state_eeg.R and the manifest), so no rs-EEG
  # pre/post is estimated and neither manuscript reports one. This identifier is retained
  # only so the pipeline degrades gracefully if a Session-6 resting recording is ever added.
  eeg_prepost       = "p2_restingstate_prepost"           # (not fitted: single neural session)
)
# Property for the Part A gender-only sensitivity analysis (guards against the pooled
# trajectory being an artefact of difficulty-confounded property composition).
LES_P2_SENSITIVITY_PROPERTY <- "gender_agreement"

# --- Resting-state EEG frequency bands (Hz) ----------------------------------
LES_P2_EEG_BANDS <- list(
  delta = c(1, 4), theta = c(4, 8), alpha = c(8, 13),
  beta  = c(13, 30), gamma = c(30, 45)
)

cat(sprintf("[paper2/_config] cognitive sessions S%s; neural sessions S%s; %d EF tasks.\n",
            paste(LES_P2_COG_SESSIONS, collapse="/"),
            paste(LES_P2_NEURAL_SESSIONS, collapse="/"),
            length(LES_P2_COG_TASKS)))
