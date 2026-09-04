# =============================================================================
# 11_extract_predictor_reliability.R
# -----------------------------------------------------------------------------
# PURPOSE
# Estimate the internal-consistency reliability of the three baseline cognitive
# predictors, and write results/_predictor_reliability.csv.
#
# WHY
# The manuscript reports the reliability of its OUTCOME (the by-participant
# attainment and learning rate) but not of its PREDICTORS, while simultaneously
# citing Hedge, Powell and Sumner (2018, https://doi.org/10.3758/s13428-017-0935-1)
# on the low reliability of difference scores. Two of the three predictors --
# Stroop interference and ASRT learning -- ARE difference scores. An
# individual-differences claim is bounded by the reliability of both sides of the
# association, so reporting one and not the other is an asymmetry a reviewer will
# notice, and it leaves the reader unable to judge how much attenuation a null
# predictor effect might reflect.
#
# METHOD
# Permutation-based split-half: repeatedly split each participant's trials into two
# halves, recompute the index on each half, correlate the halves across
# participants, and apply the Spearman-Brown prophecy formula to project the
# correlation back to full test length. Averaging over many random splits avoids
# the arbitrariness of a single odd/even split (Parsons, Kruijt & Fox, 2019,
# https://doi.org/10.1177/2515245919879695).
#
# The preprocessing here MIRRORS 01_extract_cognitive_indices.R exactly: the same
# file de-duplication, the same reaction-time bounds, the same minimum-observation
# rules and the same within-cell 3-SD trim. Mirroring is a risk, because the two
# could silently drift apart, so the script SELF-VALIDATES: it first recomputes each
# index on the FULL trial set and checks that it reproduces the shipped values in
# data_derived/cognitive_indices.rds. If the reproduction fails, the split-half
# numbers would be computed on a different trial set from the modelled indices, so
# the script stops rather than emitting a misleading reliability.
#
# SCOPE
# Reliability is estimated at Session 1, the baseline session whose values enter the
# predictor models. Digit span is a sum of correct responses, so its split-half is a
# conventional internal consistency; the two difference scores are the cases the
# Hedge et al. argument is about.
#
# OUTPUT
#   paper_2_plasticity/results/_predictor_reliability.csv: one row per predictor, with
#   the session, n_participants, the split-half correlation averaged over the random
#   splits (r_half), its Spearman-Brown corrected value (reliability_sb) and the number
#   of splits averaged (n_splits).
#
# USAGE
#   Rscript --vanilla paper_2_plasticity/scripts/11_extract_predictor_reliability.R
#
# Env knobs
#   LES_REL_SPLITS   number of random split-halves averaged (default 500)
#   LES_REL_SEED     fixed so the reported reliabilities are reproducible
#                    (default 20260724)
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "03_data_manifest.R"))
  source(here::here("paper_2_plasticity", "scripts", "01_extract_cognitive_indices.R"))
  library(dplyr); library(tidyr)
})

LES_REL_SPLITS <- as.integer(Sys.getenv("LES_REL_SPLITS", unset = "500"))
LES_REL_SEED   <- as.integer(Sys.getenv("LES_REL_SEED",   unset = "20260724"))

# Spearman-Brown correction for a half-length test.
.sb <- function(r) (2 * r) / (1 + r)

# --- Index recomputation on an arbitrary subset of trials ---------------------
# Each takes the ALREADY-TRIMMED trial frame produced below and a logical vector
# selecting the trials to use, and returns one value per participant.
.idx_digit_span <- function(d, keep) {
  d[keep, ] |> group_by(participant_home_ID) |>
    summarise(v = sum(Correct, na.rm = TRUE), .groups = "drop")
}
.idx_stroop <- function(d, keep) {
  d[keep, ] |> group_by(participant_home_ID, Congruency) |>
    summarise(m = mean(rt, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(names_from = Congruency, values_from = m) |>
    mutate(v = incongruent - congruent) |> select(participant_home_ID, v)
}
.idx_asrt <- function(d, keep) {
  d[keep, ] |> group_by(participant_home_ID, triplet_type) |>
    summarise(m = mean(cumulative_RT, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(names_from = triplet_type, values_from = m) |>
    mutate(v = L - H) |> select(participant_home_ID, v)
}

# --- Trimmed trial frames, mirroring 01_extract_cognitive_indices.R ------------
.trials_digit_span <- function(session) {
  raw <- .les_read_bind(.les_p2_files(session, LES_P2_COG_TASKS$digit_span$pattern),
                        LES_P2_COG_TASKS$digit_span$pattern, response_as_char = TRUE)
  if (is.null(raw)) return(NULL)
  raw <- raw |> rename(participant_home_ID = `Participant Public ID`,
                       Zone.Type = `Zone Type`) |>
    filter(Zone.Type == "response_text_entry") |> distinct()
  names(raw) <- make.names(names(raw), unique = TRUE)
  raw |> filter(!is.na(participant_home_ID), participant_home_ID != "") |>
    select(participant_home_ID, Correct)
}

.trials_stroop <- function(session) {
  raw <- .les_read_bind(.les_p2_files(session, LES_P2_COG_TASKS$stroop$pattern),
                        LES_P2_COG_TASKS$stroop$pattern)
  if (is.null(raw)) return(NULL)
  raw <- raw |>
    rename(participant_home_ID = `Participant Public ID`,
           rt = `Reaction Time`, trial_number = `Trial Number`) |>
    mutate(across(c(rt, trial_number), as.numeric)) |>
    filter(`Zone Type` == "response_keyboard") |> distinct()
  names(raw) <- make.names(names(raw), unique = TRUE)
  raw |>
    filter(rt >= LES_P2_RT_MIN, rt <= LES_P2_RT_MAX) |>
    group_by(participant_home_ID) |> filter(n() >= LES_P2_MIN_OBS_STROOP) |> ungroup() |>
    group_by(participant_home_ID, Correct) |>
    group_modify(~ { m <- mean(.x$rt, na.rm = TRUE); s <- sd(.x$rt, na.rm = TRUE)
                     .x |> filter(rt > (m - LES_P2_SD_CUTOFF * s),
                                  rt < (m + LES_P2_SD_CUTOFF * s)) }) |> ungroup() |>
    drop_na(rt, Congruency) |>
    mutate(Congruency = factor(Congruency, levels = c(0, 1),
                               labels = c("incongruent", "congruent"))) |>
    filter(!is.na(participant_home_ID), participant_home_ID != "") |>
    select(participant_home_ID, rt, Congruency)
}

.trials_asrt <- function(session) {
  raw <- .les_read_bind(.les_p2_files(session, LES_P2_COG_TASKS$asrt$pattern),
                        LES_P2_COG_TASKS$asrt$pattern)
  if (is.null(raw)) return(NULL)
  raw <- raw |>
    rename(participant_home_ID = `Participant Public ID`, pattern_or_random = p_or_r) |>
    mutate(pattern_or_random = case_when(pattern_or_random == "P" ~ "pattern_ASRT",
                                         pattern_or_random == "R" ~ "random_ASRT",
                                         TRUE ~ NA_character_),
           across(c(cumulative_RT, trial_number), as.numeric)) |>
    filter(triplet_type %in% c("H", "L")) |>
    drop_na(participant_home_ID, pattern_or_random, block, triplet_type, cumulative_RT) |>
    distinct()
  raw |>
    filter(cumulative_RT >= LES_P2_RT_MIN, cumulative_RT <= LES_P2_RT_MAX) |>
    group_by(participant_home_ID) |> filter(n() >= LES_P2_MIN_OBS_ASRT) |> ungroup() |>
    group_by(participant_home_ID, pattern_or_random, block, triplet_type) |>
    group_modify(~ { m <- mean(.x$cumulative_RT, na.rm = TRUE); s <- sd(.x$cumulative_RT, na.rm = TRUE)
                     .x |> filter(cumulative_RT > (m - LES_P2_SD_CUTOFF * s),
                                  cumulative_RT < (m + LES_P2_SD_CUTOFF * s)) }) |> ungroup() |>
    filter(!is.na(participant_home_ID), participant_home_ID != "") |>
    select(participant_home_ID, cumulative_RT, triplet_type)
}

# --- Permutation split-half ---------------------------------------------------
# Splits are stratified within participant (and, for the difference scores, within
# the condition being contrasted), so each half contains both conditions and the
# half-indices are computable.
.split_half <- function(d, idx_fun, strata_cols, n_splits = LES_REL_SPLITS) {
  set.seed(LES_REL_SEED)
  strata <- interaction(d[, c("participant_home_ID", strata_cols), drop = FALSE], drop = TRUE)
  rs <- vapply(seq_len(n_splits), function(i) {
    keep <- unsplit(lapply(split(seq_len(nrow(d)), strata), function(ix) {
      n <- length(ix); s <- rep(FALSE, n); s[sample.int(n, floor(n / 2))] <- TRUE; s
    }), strata)
    a <- idx_fun(d,  keep); b <- idx_fun(d, !keep)
    m <- merge(a, b, by = "participant_home_ID")
    m <- m[is.finite(m$v.x) & is.finite(m$v.y), ]
    if (nrow(m) < 10) return(NA_real_)
    suppressWarnings(stats::cor(m$v.x, m$v.y))
  }, numeric(1))
  rs <- rs[is.finite(rs)]
  if (!length(rs)) return(c(r_half = NA_real_, r_sb = NA_real_, n = NA_real_))
  a <- idx_fun(d, rep(TRUE, nrow(d)))
  c(r_half = mean(rs), r_sb = .sb(mean(rs)), n = nrow(a))
}

les_predictor_reliability <- function(session = 1) {
  shipped <- readRDS(paper2_derived("cognitive_indices.rds")) |>
    filter(session == !!session)

  # Only enrolled participants enter the reliability estimates. The raw Gorilla
  # exports include records from individuals who completed the online battery but
  # never enrolled (no participant-key entry, hence no consent linkage);
  # 01_extract drops them from the shipped indices, and the trial-level mirror
  # must drop them here for the same reason, or n would exceed the enrolled sample.
  key <- suppressWarnings(readr::read_csv(participant_key_csv(), show_col_types = FALSE,
                                          progress = FALSE))
  key_ids <- unique(key$participant_home_ID)
  key_ids <- key_ids[!is.na(key_ids)]

  specs <- list(
    list(name = "digit_span",          trials = .trials_digit_span, idx = .idx_digit_span,
         strata = character(0)),
    list(name = "stroop_interference", trials = .trials_stroop,     idx = .idx_stroop,
         strata = "Congruency"),
    list(name = "asrt_learning",       trials = .trials_asrt,       idx = .idx_asrt,
         strata = "triplet_type"))

  out <- lapply(specs, function(s) {
    d <- s$trials(session)
    if (!is.null(d)) d <- d[d$participant_home_ID %in% key_ids, , drop = FALSE]
    if (is.null(d) || !nrow(d)) {
      warning("No trials recovered for ", s$name); return(NULL)
    }
    # SELF-VALIDATION: the full-set recomputation must reproduce the shipped index,
    # or the split-half would describe a different trial set from the modelled one.
    full <- s$idx(d, rep(TRUE, nrow(d)))
    cmp  <- merge(full, shipped[, c("participant_home_ID", s$name)],
                  by = "participant_home_ID")
    names(cmp)[names(cmp) == s$name] <- "shipped"
    cmp <- cmp[is.finite(cmp$v) & is.finite(cmp$shipped), ]
    max_dev <- if (nrow(cmp)) max(abs(cmp$v - cmp$shipped)) else Inf
    if (!nrow(cmp) || max_dev > 1e-6)
      stop(sprintf(paste0("[reliability] mirror of %s does not reproduce the shipped index ",
                          "(n compared = %d, max deviation = %s). Refusing to report a ",
                          "split-half computed on a different trial set."),
                   s$name, nrow(cmp), format(max_dev)))
    message(sprintf("[reliability] %-20s mirror reproduces shipped index for %d participants",
                    s$name, nrow(cmp)))

    r <- .split_half(d, s$idx, s$strata)
    data.frame(predictor = s$name, session = session,
               n_participants = unname(r["n"]),
               r_half = unname(r["r_half"]), reliability_sb = unname(r["r_sb"]),
               n_splits = LES_REL_SPLITS, stringsAsFactors = FALSE)
  })

  res <- do.call(rbind, Filter(Negate(is.null), out))
  f <- paper2_results("_predictor_reliability.csv")
  les_assert_readonly_data(f)
  utils::write.csv(res, f, row.names = FALSE)
  message("[reliability] wrote ", nrow(res), " row(s) to ", f)
  invisible(res)
}

if (sys.nframe() == 0L) les_predictor_reliability()
