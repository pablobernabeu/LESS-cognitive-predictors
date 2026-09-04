# =============================================================================
# 03_data_manifest.R  --  Logical -> physical map for the shared, read-only data
# =============================================================================
#
# The project brief describes the shared data under three logical names:
#     data/eeg_erp_single_trials/   data/eeg_resting_state/   data/cognitive_behavioral/
# The established workspace, however, already stores these under their own
# (heavier, validated) folder names. Rather than MOVE hundreds of gigabytes of
# EEG data -- which would break the legacy pipeline and risk data loss -- this
# manifest maps each logical name onto the real location, so that a change in the
# physical layout can be absorbed here rather than in every script. The mapping is not
# yet complete. A few scripts still reach the tree directly, passing a literal folder or
# file name to data_path(): Paper 1's 00, 00b, 00c and 07c, and Paper 2's 03, 07 and 10.
# Those call sites would have to be updated as well.
#
# READ-ONLY CONTRACT
# ------------------
# The paper pipelines must never WRITE inside data/. All derived datasets are
# written under paper_1_transfer/data_derived/ or paper_2_plasticity/data_derived/
# (see 00_paths.R). `les_assert_readonly_data()` enforces this at run time: every
# pipeline write path is passed through it before the write, and it stops the script if
# the path resolves inside data/.
# =============================================================================

if (!exists("data_path")) source(here::here("_shared", "R", "00_paths.R"))

# --- Logical data stores ------------------------------------------------------

# (1) ERP single-trial data (Gorilla/BrainVision exports for the sentence task),
#     used by Paper 1. Real location: data/raw data/EEG/Session {2,3,4,6}/Export.
erp_single_trials_path <- function(...) data_path("raw data", "EEG", ...)

# (2) Resting-state EEG (Paper 2). Recorded at SESSION 2 ONLY (baseline; confirmed by
#     direct reconnaissance 2026-06-13 -- there is no Session-6 resting recording). The
#     per-condition BrainVision ASCII exports live INSIDE the task-EEG tree at
#     data/raw data/EEG/Session 2/Export/<ppt>_RS_eyes_{closed,open}.{vhdr,txt}; script 03
#     reads them directly (base R), so this accessor points at that same tree.
resting_state_eeg_path <- function(...) data_path("raw data", "EEG", ...)

# (3) Cognitive & behavioural data (Paper 2 indices + Paper 1 accuracy).
cognitive_ef_path     <- function(...) data_path("raw data", "executive functions", ...)
behavioural_lab_path  <- function(...) data_path("raw data", "behavioural data from lab sessions", ...)

# --- Shared keys --------------------------------------------------------------
# Participant <-> session <-> group lookup table (lab IDs; odd = Mini-English,
# even = Mini-Norwegian) used across both papers.
participant_key_csv <- function() data_path("Participant IDs and session progress.csv")

# Language History Questionnaire (LHQ3) exports, used for the participant
# demographics table (age, sex, handedness, English age-of-acquisition and
# years-of-use, self-rated proficiency, multilingual diversity). Two workbooks:
# "Aggregate Scores" holds the derived per-participant scores (Age, Gender,
# L2 Proficiency, Multilingual Language Diversity); "Raw Data" holds the raw
# item responses, including the item-7 language-history block (per-language,
# per-modality age of first use and years of use) and item-6 handedness.
lhq3_path <- function(...) data_path("raw data", "language history", ...)

# --- Session design (single source of truth) ---------------------------------
# ERP / sentence task: Sessions 2, 3, 4 (training) + 6 (post-consolidation
# retention). Executive-function tasks: Sessions 1 (baseline) and 5 (post).
# Cognitive pre/post (Paper 2) uses S1 vs S5 (see plan / manuscript Methods).
# LES_NEURAL_PREPOST names the two sessions a resting-state pre/post would use if both
# recordings existed. Only Session 2 was recorded (see (2) above), so in practice it acts
# as a session filter in Paper 2's scripts 03, 04, 07 and 10, and the rs-EEG pre/post
# models exit at the two-session guard in 05_fit_brms_prepost.R.
LES_ERP_SESSIONS        <- c(2, 3, 4, 6)
LES_RETENTION_SESSIONS  <- c(4, 6)   # Paper 1 retention contrast. Records the design only:
                                     # 05_posterior_summaries_and_contrasts.R reads its
                                     # session codes off each cell's own data instead.
LES_COG_PREPOST         <- c(1, 5)   # Paper 2 cognitive pre/post
LES_NEURAL_PREPOST      <- c(2, 6)   # Paper 2 neural pre/post (S6 not recorded; see above)

# Grammatical properties and their sentence-marker codes in the file names.
# These S1/S2/S3 are markers inside the export file names, not sessions. A file is named
# <participant>_<property>_<grammaticality>, e.g. Session 2/Export/1_S1_S101.vhdr, where
# the folder gives the session, "S1" the grammatical property and "S101" the
# grammaticality marker (data/R_functions/import_trialbytrial_EEG_data.R). They are
# unrelated to the S1..S6 session labels used above.
LES_PROPERTY_CODES <- c(
  "gender_agreement"            = "S1",
  "differential_object_marking" = "S2",
  "verb_object_number_agreement" = "S3"
)

# --- Read-only guard ----------------------------------------------------------
les_assert_readonly_data <- function(output_paths) {
  data_root <- normalizePath(data_path(), winslash = "/", mustWork = FALSE)
  bad <- output_paths[startsWith(
    normalizePath(output_paths, winslash = "/", mustWork = FALSE), data_root
  )]
  if (length(bad)) {
    stop("Pipeline output must not be written inside read-only data/: \n  ",
         paste(bad, collapse = "\n  "))
  }
  invisible(TRUE)
}

cat("[manifest] logical data stores mapped; data/ is read-only.\n")
