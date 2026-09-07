# =============================================================================
# paper_2_plasticity/scripts/09_compare_aperiodic.R
# Phase 3e -- LOO model comparison: raw band power vs. de-confounded (aperiodic)
#             Part A reference models  [HPC or local -- cheap, no refit needed]
# =============================================================================
#
# SUPERSEDED by 09b_compare_aperiodic_commonsample.R. This script's loo_compare() is
# INVALID here because the raw-band model is fit to 56 participants (29,565 trials) and
# the aperiodic model to only 50 (26,454) -- the specparam decomposition yields usable
# aperiodic features for fewer participants -- and loo::loo_compare() requires IDENTICAL
# observations (it errors "models have inconsistent observation counts"). 09b refits the
# raw model on the aperiodic model's common subsample and compares on identical
# observations. Kept for reference; do NOT submit 10_compare_aperiodic.slurm.
#
# Two guards keep it from touching the reported artefact. The script stops at once unless
# LES_ALLOW_SUPERSEDED=1 is set, and when it does run it writes to
# results/_aperiodic_loo_compare_naive.csv, a path of its own, so the manuscript-facing
# results/_aperiodic_loo_compare.csv, which 09b writes, is never overwritten.
#
# WHY THIS SCRIPT EXISTS
# ----------------------
# 04_fit_brms_predictors.R fits TWO Part A reference models within each stratum: the
# original raw-band-power model (p2_predictive_trajectory) and a de-confounded variant
# that replaces raw band power with the specparam/aperiodic decomposition
# (p2_predictive_trajectory_aperiodic; Donoghue et al. 2020's periodic/aperiodic
# argument). They are fit to OVERLAPPING BUT DIFFERENT rows, 56 participants against 50,
# which is exactly why the comparison attempted here is invalid and why 09b refits on the
# common sample. Both are independently projection-predictive-selected in
# 08_projpred_selection.R. Without a formal comparison, reporting both models'
# results side by side risks reading as two independent "chances" to find an
# interesting predictor story, a researcher-degrees-of-freedom concern flagged
# by an internal audit (2026-07-02) even though no single p-value or test needs a
# frequentist correction here. This script was written to close that gap with PSIS-LOO
# cross-validation (Vehtari, Gelman & Gabry, 2017, doi:10.1007/s11222-016-9696-4)
# compared via `loo::loo_compare()`, so the manuscript can state which neural
# characterisation the data actually prefer rather than leaving the choice implicit.
#
# SCOPE: pooled-vs-pooled and gender-vs-gender ONLY
# --------------------------------------------------
# Raw vs. aperiodic is compared WITHIN each stratum (pooled Part A model, and
# separately the gender-only sensitivity model). As the notice above records, the two
# members of a pair are NOT fit to the same rows, so loo_compare()'s precondition of
# identical observations fails and this script's elpd_diff is not meaningful. 09b
# restores that precondition by refitting the raw model on the aperiodic model's sample.
# Pooled-vs-gender-only is NOT compared at all. Those two are fit to different data (all
# 3 properties vs. one), so their LOO elpd values are not on a comparable scale or
# support and loo_compare() between them would be statistically meaningless rather than
# merely superfluous. The pooled/gender-only pair is instead a pre-specified robustness
# check on disjoint data, reported side by side by design (see README.md and
# 04_fit_brms_predictors.R's own comments), never chosen between.
#
# OUTPUT
#   results/_aperiodic_loo_compare_naive.csv -- one row per stratum (pooled, gender),
#     with elpd_diff, se_diff (aperiodic relative to raw; negative elpd_diff means
#     the second-listed model in loo_compare's ranking predicts worse) and a
#     preferred_model column using the conventional |diff| > 2*se rule of thumb.
#
# USAGE -- retained for reference only; run 09b_compare_aperiodic_commonsample.R instead.
# The invocations below are recorded so the superseded procedure stays readable; each
# needs LES_ALLOW_SUPERSEDED=1 in the environment:
#   Rscript 09_compare_aperiodic.R              # both strata, whichever pairs exist
#   Rscript 09_compare_aperiodic.R pooled        # pooled pair only
#   Rscript 09_compare_aperiodic.R gender        # gender-only pair only
# =============================================================================

if (!identical(Sys.getenv("LES_ALLOW_SUPERSEDED"), "1")) {
  stop("09_compare_aperiodic.R is superseded by 09b; set LES_ALLOW_SUPERSEDED=1 to run it ",
       "for reference.", call. = FALSE)
}

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  library(brms)
})

# --- Reload a cached fit and attach the LOO criterion (cached in the same .rds) -
# add_criterion(..., file = ...) both computes loo (once) and re-saves it onto the
# fit's file so a re-run of this script does not recompute it.
.les_loo_for <- function(model_id) {
  cache <- paper2_results(model_id)
  rds   <- paste0(cache, ".rds")
  if (!file.exists(rds)) {
    message("[loo-compare] cached fit '", model_id, ".rds' not found -- skipping.")
    return(NULL)
  }
  fit <- brms::brm(file = cache)
  fit <- brms::add_criterion(fit, "loo", file = cache, moment_match = FALSE)
  fit
}

# --- Compare one raw-vs-aperiodic pair and return a tidy one-row summary --------
.les_compare_pair <- function(stratum, raw_id, aperiodic_id) {
  fit_raw <- .les_loo_for(raw_id)
  fit_ap  <- .les_loo_for(aperiodic_id)
  if (is.null(fit_raw) || is.null(fit_ap)) {
    message("[loo-compare] ", stratum, ": one or both fits missing -- skipping comparison.")
    return(NULL)
  }
  # Pass a NAMED list so loo_compare()'s row names are "raw"/"aperiodic" directly,
  # rather than relying on its positional "model1"/"model2" fallback naming.
  cmp <- loo::loo_compare(list(raw = fit_raw$criteria$loo, aperiodic = fit_ap$criteria$loo))
  rn <- rownames(cmp)
  raw_row <- cmp[rn == "raw", , drop = FALSE]
  ap_row  <- cmp[rn == "aperiodic", , drop = FALSE]
  # Both rows' elpd_diff/se_diff are relative to whichever of the two ranked first
  # (that row is exactly zero); with only two models, the non-reference row's own
  # elpd_diff/se_diff (sign-flipped if "raw" is the non-reference row) IS the
  # raw-vs-aperiodic contrast, so this difference-of-differences is exact, not
  # an approximation, and reduces to the non-reference row's own value up to sign.
  elpd_diff_ap_minus_raw <- ap_row[, "elpd_diff"] - raw_row[, "elpd_diff"]
  se_diff <- max(raw_row[, "se_diff"], ap_row[, "se_diff"])
  preferred <- if (abs(elpd_diff_ap_minus_raw) > 2 * se_diff) {
    if (elpd_diff_ap_minus_raw > 0) "aperiodic" else "raw"
  } else {
    "neither clearly preferred (|elpd_diff| <= 2*SE)"
  }
  message(sprintf("[loo-compare] %s: elpd_diff(aperiodic-raw) = %.2f (SE %.2f) -> %s",
                  stratum, elpd_diff_ap_minus_raw, se_diff, preferred))
  data.frame(
    stratum = stratum, raw_model = raw_id, aperiodic_model = aperiodic_id,
    elpd_diff_aperiodic_minus_raw = elpd_diff_ap_minus_raw,
    se_diff = se_diff, preferred_model = preferred,
    stringsAsFactors = FALSE
  )
}

# =============================================================================
.run <- function() {
  which <- commandArgs(trailingOnly = TRUE)
  do_pooled <- length(which) == 0 || "pooled" %in% which
  do_gender <- length(which) == 0 || "gender" %in% which

  rows <- list()
  if (do_pooled) rows[["pooled"]] <- .les_compare_pair(
    "pooled", LES_P2_MODELS[["predictive"]], LES_P2_MODELS[["predictive_aperiodic"]])
  if (do_gender) rows[["gender"]] <- .les_compare_pair(
    "gender", LES_P2_MODELS[["predictive_gender"]], LES_P2_MODELS[["predictive_aperiodic_gender"]])

  rows <- Filter(Negate(is.null), rows)
  if (length(rows)) {
    res <- do.call(rbind, rows)
    out <- paper2_results("_aperiodic_loo_compare_naive.csv")
    les_assert_readonly_data(out)
    utils::write.csv(res, out, row.names = FALSE)
    message("[loo-compare] wrote ", basename(out), " (", nrow(res), " row(s))")
  } else {
    message("[loo-compare] no comparable pairs available yet.")
  }
  message("[loo-compare] done.")
}

if (sys.nframe() == 0L) .run()
