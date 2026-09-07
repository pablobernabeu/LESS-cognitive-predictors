# =============================================================================
# paper_2_plasticity/scripts/01_extract_cognitive_indices.R
# Phase 3a -- Extract the executive-function / statistical-learning indices
#             (Stroop interference, digit span, ASRT learning) for Paper 2.
# =============================================================================
#
# WHAT THIS PRODUCES
# ------------------
# One tidy row per (participant x session) with the three cognitive indices, for
# the cognitive pre/post sessions (S1 baseline, S5 post), written to
# paper_2_plasticity/data_derived/cognitive_indices.rds. Linked to participant_lab_ID
# and language (Mini-English / Mini-Norwegian) via the participant key.
#
# RELATION TO THE LEGACY SCRIPTS
# ------------------------------
# The index formulas are taken VERBATIM from the validated legacy scripts
#   data/importation and preprocessing/preprocess {Stroop, digit span,
#   alternating serial reaction time} task.R
# but those scripts are top-level, run-on-source, and hard-coded to Session 1.
# Paper 2 needs the SAME indices for BOTH S1 and S5, so the logic is refactored
# here into session-parameterised functions (the Paper-1 pattern: a fresh,
# unit-runnable extraction rather than sourcing fragile legacy code). Index
# definitions are unchanged:
#   * stroop_interference = mean RT(incongruent) - mean RT(congruent)
#   * digit_span          = sum(Correct) over digit-span response trials
#   * asrt_learning       = mean RT(low-prob) - mean RT(high-prob)
# Trimming (RT 50-5000 ms; >=50 obs Stroop / >=100 obs ASRT; 3 SD within cells) is
# also carried over verbatim (see _config.R).
#
# ONE DELIBERATE ROBUSTNESS FIX over the legacy scripts
# -----------------------------------------------------
# The Session-1 export folder mixes per-participant files ("wbij5 Stroop.csv") with
# batch files ("Stroop 1.csv") AND a duplicate "Mini English/" subfolder; at least
# one participant (wbij5) appears in BOTH a named and a numbered export. Reading all
# files would double-count that participant -- harmless for a mean (Stroop, ASRT) but
# WRONG for a sum (digit span). We therefore (a) list files NON-recursively, ignoring
# the "Mini English/" subfolder, and (b) apply a BATCH-PRIORITY rule: take every row of
# the numbered batch exports, then add rows from the named exports only for participants
# the batch does not cover, and finally `distinct()` to collapse identical re-exports.
# `distinct()` on its own is not enough, because the two export kinds differ in trailing
# metadata columns; see .les_read_bind() below. The .run() validation reports
# per-participant trial counts so any residual duplication is visible.
#
# USAGE
#   Rscript --vanilla paper_2_plasticity/scripts/01_extract_cognitive_indices.R
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "03_data_manifest.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  library(dplyr)
  library(tidyr)
  library(readr)
})

# --- File listing: non-recursive, so the duplicate "Mini English/" subfolder is
#     ignored; matches the legacy non-recursive list.files() ---------------------
# A missing session folder is a warning by default, and the indices file is then written
# without that session's rows, so a staging error in the data tree would surface only as
# pending markers in the manuscript. With LES_STRICT_INPUTS=1, an opt-in the cluster job
# documents, a missing folder for a session the design requires stops the run instead.
.les_p2_files <- function(session, pattern) {
  dir <- cognitive_ef_path(paste0("Session ", session))
  if (!dir.exists(dir)) {
    msg <- paste0("Missing EF session folder: ", dir)
    if (session %in% LES_P2_COG_SESSIONS &&
        identical(Sys.getenv("LES_STRICT_INPUTS"), "1")) stop(msg, call. = FALSE)
    warning(msg)
    return(character(0))
  }
  list.files(dir, pattern = pattern, full.names = TRUE, recursive = FALSE)
}

# Read a task's exports with BATCH-PRIORITY participant de-duplication. The numbered
# "batch" exports (e.g. "Stroop 1.csv") are the systematic export; the per-participant
# "named" exports (e.g. "wbij5 Stroop.csv") are early individual extracts. A few
# participants (e.g. wbij5) appear in BOTH, so reading all files double-counts them --
# harmless for a mean but WRONG for the digit-span sum, and `distinct()` alone fails to
# collapse them because the two exports differ in trailing metadata columns. We therefore
# take all batch rows and add named-file rows ONLY for participants absent from the batch,
# then distinct() to collapse any identical re-exports.
.les_read_bind <- function(files, task_pattern, response_as_char = FALSE) {
  if (length(files) == 0) return(NULL)
  id_col   <- "Participant Public ID"
  is_batch <- grepl(paste0("^", task_pattern, " [0-9]+\\.csv$"), basename(files),
                    ignore.case = TRUE)
  read1 <- function(f) {
    d <- suppressWarnings(readr::read_csv(f, show_col_types = FALSE, progress = FALSE))
    if (response_as_char && "Response" %in% names(d)) d$Response <- as.character(d$Response)
    d
  }
  batch <- if (any(is_batch))  dplyr::bind_rows(lapply(files[is_batch],  read1)) else NULL
  named <- if (any(!is_batch)) dplyr::bind_rows(lapply(files[!is_batch], read1)) else NULL
  if (!is.null(batch) && !is.null(named) &&
      id_col %in% names(batch) && id_col %in% names(named)) {
    named <- named[!(named[[id_col]] %in% unique(batch[[id_col]])), , drop = FALSE]
  }
  dplyr::distinct(dplyr::bind_rows(batch, named))
}

# --- Opt-in test-only Stroop index (LES_P2_STROOP_TEST_ONLY=1) ------------------
# The Gorilla export records the practice block in the same response zone as the test
# block, and no practice filter is applied by default, so the practice responses enter
# the reported Stroop index and its reliability estimate (11_extract_predictor_reliability.R
# mirrors this reader). With the switch set, rows the export marks as practice are dropped
# and the indices file is written under a "_stroop_testonly" tag, so the reported artefact
# is never overwritten. The manuscript discloses the default and does not report the
# test-only variant.
les_p2_stroop_test_only <- function() identical(Sys.getenv("LES_P2_STROOP_TEST_ONLY"), "1")
les_p2_stroop_tag       <- function() if (les_p2_stroop_test_only()) "_stroop_testonly" else ""
.les_drop_practice <- function(raw) {
  keep <- rep(TRUE, nrow(raw))
  if ("Practice" %in% names(raw)) keep <- keep & !(raw$Practice %in% c(1, "1", TRUE, "TRUE"))
  if ("display" %in% names(raw))  keep <- keep & !grepl("practice", raw$display, ignore.case = TRUE)
  message("[cog] Stroop test-only index: dropping ", sum(!keep), " practice rows")
  raw[keep, , drop = FALSE]
}

# =============================================================================
# Index 1: Stroop interference  =  mean RT(incongruent) - mean RT(congruent)
# =============================================================================
les_p2_stroop <- function(files) {
  raw <- .les_read_bind(files, LES_P2_COG_TASKS$stroop$pattern)
  if (is.null(raw)) {
    return(tibble(participant_home_ID = character(), stroop_interference = double()))
  }
  raw <- raw %>%
    rename(participant_home_ID = `Participant Public ID`,
           rt = `Reaction Time`, trial_number = `Trial Number`) %>%
    mutate(across(c(rt, trial_number), as.numeric)) %>%
    filter(`Zone Type` == "response_keyboard") %>%
    distinct()                                   # de-dup named-vs-numbered re-exports
  names(raw) <- make.names(names(raw), unique = TRUE)
  if (les_p2_stroop_test_only()) raw <- .les_drop_practice(raw)

  trimmed <- raw %>%
    filter(rt >= LES_P2_RT_MIN, rt <= LES_P2_RT_MAX) %>%
    group_by(participant_home_ID) %>% filter(n() >= LES_P2_MIN_OBS_STROOP) %>% ungroup() %>%
    group_by(participant_home_ID, Correct) %>%
    group_modify(~ {
      m <- mean(.x$rt, na.rm = TRUE); s <- sd(.x$rt, na.rm = TRUE)
      .x %>% filter(rt > (m - LES_P2_SD_CUTOFF * s), rt < (m + LES_P2_SD_CUTOFF * s))
    }) %>% ungroup()

  trimmed %>%
    select(rt, participant_home_ID, Congruency) %>%
    drop_na(rt, Congruency) %>%
    mutate(Congruency = factor(Congruency, levels = c(0, 1),
                               labels = c("incongruent", "congruent"))) %>%
    group_by(participant_home_ID, Congruency) %>%
    summarise(mean_rt = mean(rt, na.rm = TRUE), .groups = "drop") %>%
    pivot_wider(names_from = Congruency, values_from = mean_rt) %>%
    mutate(stroop_interference = incongruent - congruent) %>%
    filter(!is.na(participant_home_ID), participant_home_ID != "") %>%
    select(participant_home_ID, stroop_interference)
}

# =============================================================================
# Index 2: Digit span  =  sum of correct forward+backward response trials
# =============================================================================
les_p2_digit_span <- function(files) {
  raw <- .les_read_bind(files, LES_P2_COG_TASKS$digit_span$pattern, response_as_char = TRUE)
  if (is.null(raw)) {
    return(tibble(participant_home_ID = character(), digit_span = double(),
                  .n_trials = integer()))
  }
  raw <- raw %>%
    rename(participant_home_ID = `Participant Public ID`, Zone.Type = `Zone Type`) %>%
    filter(Zone.Type == "response_text_entry") %>%
    distinct()                                   # CRITICAL for a sum: collapse re-exports
  names(raw) <- make.names(names(raw), unique = TRUE)
  raw %>%
    group_by(participant_home_ID) %>%
    summarise(digit_span = sum(Correct, na.rm = TRUE), .n_trials = n(), .groups = "drop") %>%
    filter(!is.na(participant_home_ID), participant_home_ID != "")
}

# =============================================================================
# Index 3: ASRT statistical learning  =  mean RT(low-prob) - mean RT(high-prob)
# =============================================================================
les_p2_asrt <- function(files) {
  raw <- .les_read_bind(files, LES_P2_COG_TASKS$asrt$pattern)
  if (is.null(raw)) return(tibble(participant_home_ID = character(), asrt_learning = double()))
  raw <- raw %>%
    rename(participant_home_ID = `Participant Public ID`, pattern_or_random = p_or_r) %>%
    mutate(pattern_or_random = case_when(pattern_or_random == "P" ~ "pattern_ASRT",
                                         pattern_or_random == "R" ~ "random_ASRT",
                                         TRUE ~ NA_character_),
           across(c(cumulative_RT, trial_number), as.numeric)) %>%
    filter(triplet_type %in% c("H", "L")) %>%
    drop_na(participant_home_ID, pattern_or_random, block, triplet_type, cumulative_RT) %>%
    distinct()

  trimmed <- raw %>%
    filter(cumulative_RT >= LES_P2_RT_MIN, cumulative_RT <= LES_P2_RT_MAX) %>%
    group_by(participant_home_ID) %>% filter(n() >= LES_P2_MIN_OBS_ASRT) %>% ungroup() %>%
    group_by(participant_home_ID, pattern_or_random, block, triplet_type) %>%
    group_modify(~ {
      m <- mean(.x$cumulative_RT, na.rm = TRUE); s <- sd(.x$cumulative_RT, na.rm = TRUE)
      .x %>% filter(cumulative_RT > (m - LES_P2_SD_CUTOFF * s),
                    cumulative_RT < (m + LES_P2_SD_CUTOFF * s))
    }) %>% ungroup()

  trimmed %>%
    group_by(participant_home_ID, triplet_type) %>%
    summarise(mean_RT = mean(cumulative_RT, na.rm = TRUE), .groups = "drop") %>%
    pivot_wider(names_from = triplet_type, values_from = mean_RT) %>%
    mutate(asrt_learning = L - H) %>%
    filter(!is.na(participant_home_ID), participant_home_ID != "") %>%
    select(participant_home_ID, asrt_learning)
}

# =============================================================================
# Driver: indices for every cognitive session, linked to the participant key
# =============================================================================
extract_cognitive_indices <- function() {
  key <- suppressWarnings(readr::read_csv(participant_key_csv(), show_col_types = FALSE,
                                          progress = FALSE))
  key_slim <- key %>%
    select(any_of(c("participant_home_ID", "participant_lab_ID", "language"))) %>%
    distinct()

  per_session <- lapply(LES_P2_COG_SESSIONS, function(sess) {
    st <- les_p2_stroop(.les_p2_files(sess, LES_P2_COG_TASKS$stroop$pattern))
    ds <- les_p2_digit_span(.les_p2_files(sess, LES_P2_COG_TASKS$digit_span$pattern))
    asr <- les_p2_asrt(.les_p2_files(sess, LES_P2_COG_TASKS$asrt$pattern))

    message(sprintf("[cog] Session %d: Stroop n=%d | digit span n=%d | ASRT n=%d",
                    sess, nrow(st), nrow(ds), nrow(asr)))
    # surface any participant whose digit-span trial count is a >1.5x-median outlier
    if (nrow(ds)) {
      med <- stats::median(ds$.n_trials)
      odd <- ds %>% filter(.n_trials > 1.5 * med)
      if (nrow(odd)) message("[cog]   digit-span trial-count outliers (possible residual dup): ",
                             paste(odd$participant_home_ID, collapse = ", "))
    }

    st %>%
      full_join(ds %>% select(-.n_trials), by = "participant_home_ID") %>%
      full_join(asr, by = "participant_home_ID") %>%
      mutate(session = sess)
  })

  indices <- bind_rows(per_session) %>%
    left_join(key_slim, by = "participant_home_ID") %>%
    relocate(participant_home_ID, participant_lab_ID, language, session)

  # Records whose Gorilla public ID has no entry in the participant key are dropped
  # at the source: they cannot be tied to an enrolled, consented participant, so they
  # must not enter any analysis (descriptives, reliability, or the Part B models,
  # whose z-scoring would otherwise absorb them). The raw exports contain three such
  # Session-1-only IDs; their nearest enrolled IDs sit at edit distance >= 3 of 5
  # characters, so they are not plausible typos of enrolled participants.
  unlinked <- indices %>% filter(is.na(participant_lab_ID))
  if (nrow(unlinked) > 0) {
    message("[cog] dropping ", nrow(unlinked),
            " row(s) with no enrolled-participant mapping (home IDs: ",
            paste(unique(unlinked$participant_home_ID), collapse = ", "), ")")
    indices <- indices %>% filter(!is.na(participant_lab_ID))
  }

  out <- paper2_derived(paste0("cognitive_indices", les_p2_stroop_tag(), ".rds"))
  les_assert_readonly_data(out)
  saveRDS(indices, out)
  message("[cog] wrote ", out, " (", nrow(indices), " participant x session rows)")
  invisible(indices)
}

# =============================================================================
# Entry point + validation
# =============================================================================
.run <- function() {
  ind <- extract_cognitive_indices()
  cat("\n--- cognitive_indices.rds summary ---\n")
  print(ind %>% count(session, name = "n_participants"))
  cat("\nNon-missing per index x session:\n")
  print(ind %>% group_by(session) %>%
          summarise(stroop = sum(!is.na(stroop_interference)),
                    digit_span = sum(!is.na(digit_span)),
                    asrt = sum(!is.na(asrt_learning)),
                    unlinked_lab_ID = sum(is.na(participant_lab_ID)), .groups = "drop"))
  cat("\nIndex ranges (all sessions):\n")
  print(ind %>% summarise(
    stroop = sprintf("%.0f..%.0f ms", min(stroop_interference, na.rm = TRUE),
                     max(stroop_interference, na.rm = TRUE)),
    digit_span = sprintf("%.0f..%.0f", min(digit_span, na.rm = TRUE),
                         max(digit_span, na.rm = TRUE)),
    asrt = sprintf("%.0f..%.0f ms", min(asrt_learning, na.rm = TRUE),
                   max(asrt_learning, na.rm = TRUE))))
  message("[cog] done.")
}

if (sys.nframe() == 0L) .run()
