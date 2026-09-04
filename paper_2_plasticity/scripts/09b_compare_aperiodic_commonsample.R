# =============================================================================
# 09b_compare_aperiodic_commonsample.R
# -----------------------------------------------------------------------------
# Valid raw-band vs. aperiodic PSIS-LOO comparison on a COMMON sample.
#
# Why this supersedes the naive comparison (09_compare_aperiodic.R): the raw-band
# Part A model is fit to 56 participants (29,565 trials) but the aperiodic model to
# only 50 (26,454) -- the specparam decomposition yields usable aperiodic features
# for fewer participants -- and loo::loo_compare() requires IDENTICAL observations.
# Comparing the two fits directly errored ("models have inconsistent observation
# counts"), and even a sum-only elpd difference across different samples would be
# meaningless.
#
# Fix: refit the raw-band model on the aperiodic model's (smaller) common sample --
# the SAME rows in the SAME order -- so both models are evaluated on identical
# observations and elpd_diff and its SE are valid and pointwise-aligned. The
# aperiodic model replaced the raw resting-state bands with specparam-derived
# quantities, so its stored data lacks the raw bands; we rebuild a common frame =
# the aperiodic fit's rows (defining the sample and row order) + the raw neural
# predictors joined in by participant, then refit the raw model on it with the
# pipeline's standard sampler and priors (les_brm, so formula/family/priors are the
# original raw model's, only the data are restricted).
#
# Outputs:
#   results/_aperiodic_loo_compare.csv     one row per stratum (pooled, gender):
#     elpd_diff_aperiodic_minus_raw, se_diff, preferred_model, n_obs, n_participants.
#   results/<raw_id>_commonsample.rds      the cached common-sample raw refits.
#
# Submit AFTER the four Part A reference fits exist (all cached):
#   sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/09b_compare_commonsample.slurm
# (Standard QoS only -- never --qos=priority.)
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "01_bayesian_settings.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  library(brms)
  library(dplyr)
})

# Raw resting-state predictors the raw-band model carries but the aperiodic fit drops
# (replaced by specparam exponent/offset + 1/f-adjusted bands + specparam IAF).
RAW_NEURAL <- c("z_alpha", "z_theta", "z_beta", "z_delta", "z_gamma", "z_iaf")

.les_loo <- function(fit, cache) brms::add_criterion(fit, "loo", file = cache)$criteria$loo

compare_common <- function(stratum, raw_id, aper_id) {
  raw_cache  <- paper2_results(raw_id)
  aper_cache <- paper2_results(aper_id)
  if (!file.exists(paste0(raw_cache, ".rds")) || !file.exists(paste0(aper_cache, ".rds"))) {
    message("[common-loo] ", stratum, ": one or both fits missing -- skipping.")
    return(NULL)
  }
  fit_raw  <- brms::brm(file = raw_cache)
  fit_aper <- brms::brm(file = aper_cache)

  # participant-level raw neural predictors (one row per participant)
  have <- intersect(RAW_NEURAL, names(fit_raw$data))
  raw_pred <- fit_raw$data |>
    dplyr::select(participant_lab_ID, dplyr::all_of(have)) |>
    dplyr::distinct(participant_lab_ID, .keep_all = TRUE)

  # common sample = the aperiodic fit's rows (define the row set AND order) with the
  # raw neural predictors joined on by participant. left_join preserves fit_aper$data's
  # row order, so the resulting loo is pointwise-aligned with the aperiodic fit's loo.
  common <- dplyr::left_join(fit_aper$data, raw_pred, by = "participant_lab_ID")
  stopifnot(nrow(common) == nrow(fit_aper$data),
            !anyNA(common[, have, drop = FALSE]))

  # refit the raw-band model on the common sample: identical formula/family/priors,
  # only the data restricted to the aperiodic model's participants.
  raw_common_cache <- paper2_results(paste0(raw_id, "_commonsample"))
  message("[common-loo] ", stratum, ": refitting raw model on common sample (",
          nrow(common), " rows, ", length(unique(common$participant_lab_ID)), " participants)...")
  fit_raw_c <- les_brm(formula = fit_raw$formula, data = common,
                       family = fit_raw$family, prior = fit_raw$prior,
                       file = raw_common_cache)

  loo_raw  <- .les_loo(fit_raw_c, raw_common_cache)
  loo_aper <- .les_loo(fit_aper,  aper_cache)

  cmp <- loo::loo_compare(list(raw = loo_raw, aperiodic = loo_aper))
  rn <- rownames(cmp)
  raw_row <- cmp[rn == "raw", , drop = FALSE]
  ap_row  <- cmp[rn == "aperiodic", , drop = FALSE]
  # With two models loo_compare zeroes the better row; the non-reference row's own
  # elpd_diff/se_diff (up to sign) IS the contrast, so this difference is exact.
  elpd_diff <- ap_row[, "elpd_diff"] - raw_row[, "elpd_diff"]
  se_diff   <- max(raw_row[, "se_diff"], ap_row[, "se_diff"])
  preferred <- if (abs(elpd_diff) > 2 * se_diff) {
    if (elpd_diff > 0) "aperiodic" else "raw"
  } else {
    "neither clearly preferred (|elpd_diff| <= 2*SE)"
  }

  message(sprintf("[common-loo] %s: elpd_diff(aperiodic-raw) = %.2f (SE %.2f) -> %s",
                  stratum, elpd_diff, se_diff, preferred))
  data.frame(
    stratum = stratum, raw_model = raw_id, aperiodic_model = aper_id,
    n_obs = nrow(common), n_participants = length(unique(common$participant_lab_ID)),
    elpd_diff_aperiodic_minus_raw = elpd_diff, se_diff = se_diff,
    preferred_model = preferred, stringsAsFactors = FALSE
  )
}

res <- dplyr::bind_rows(
  compare_common("pooled", "p2_predictive_trajectory",        "p2_predictive_trajectory_aperiodic"),
  compare_common("gender", "p2_predictive_trajectory_gender", "p2_predictive_trajectory_aperiodic_gender")
)

if (!is.null(res) && nrow(res)) {
  utils::write.csv(res, paper2_results("_aperiodic_loo_compare.csv"), row.names = FALSE)
  print(res)
  message("[common-loo] wrote _aperiodic_loo_compare.csv (", nrow(res), " row(s))")
} else {
  message("[common-loo] nothing to write -- no strata compared.")
}
