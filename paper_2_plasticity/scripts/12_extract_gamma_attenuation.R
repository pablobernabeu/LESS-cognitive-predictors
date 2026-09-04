# =============================================================================
# paper_2_plasticity/scripts/12_extract_gamma_attenuation.R
# How much genuine 30-45 Hz power survives the acquisition low-pass?
# =============================================================================
#
# WHY THIS EXISTS
# ---------------
# The offline preprocessing applied a zero-phase-shift fourth-order Butterworth
# low-pass at 30 Hz, and the nominal gamma band (30-45 Hz) lies entirely at or
# beyond that corner. The manuscript therefore declines to interpret the gamma
# predictor, and quantifies the point: the share of each participant's aperiodic
# (1/f) background power in 30-45 Hz that the filter would let through. Those
# retained-power quantiles were first computed ad hoc and typed into the prose;
# this script persists the computation so the manuscript injects them instead.
#
# WHAT IT COMPUTES
# ----------------
# For each participant, the aperiodic background is fitted to the shipped
# eyes-closed occipito-parietal power spectrum (results/_resting_state_psd.csv)
# over 2-40 Hz with the same robust outlier-trimmed fit as
# 07_extract_aperiodic.R (whose functions are sourced, not duplicated), then
# extrapolated across 30-45 Hz. The retained fraction is
#
#     integral_{30}^{45} T(f) * Phat(f) df  /  integral_{30}^{45} Phat(f) df ,
#
# with Phat(f) = 10^(offset - exponent * log10 f). The aperiodic offset cancels
# in the ratio, so the fraction depends on the exponent alone; it is retained in
# the output for traceability.
#
# THE TRANSFER-FUNCTION ASSUMPTION (stated because it moves the number ~3x)
# -------------------------------------------------------------------------
# "Fourth order, zero phase shift" is read literally: a fourth-order Butterworth
# magnitude applied once in each direction (filtfilt), so the net POWER response
# is T(f) = [1 + (f/30)^8]^-2. BrainVision Analyzer's internals are not fully
# documented, so the single-pass power response [1 + (f/30)^8]^-1 is written
# alongside as an upper bound on retention (`retained_fraction_singlepass`).
# Under either reading most of the band's genuine power is removed, which is the
# fact the manuscript needs.
#
# INPUT   results/_resting_state_psd.csv   (per participant x condition spectra)
# OUTPUT  results/_gamma_attenuation.csv   one row per participant:
#         participant_lab_ID, aperiodic_exponent, aperiodic_offset,
#         retained_fraction (two-pass), retained_fraction_singlepass
#
# USAGE   Rscript paper_2_plasticity/scripts/12_extract_gamma_attenuation.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

source(here::here("_shared", "R", "00_paths.R"))
source(here::here("_shared", "R", "03_data_manifest.R"))
# Defines .fit_aperiodic(), .ap_predict() and LES_AP_SETTINGS; its driver is
# guarded by `if (sys.nframe() == 0L)`, so sourcing runs nothing.
source(here::here("paper_2_plasticity", "scripts", "07_extract_aperiodic.R"))

LES_GAMMA_BAND   <- c(30, 45)   # Hz; the band the low-pass corner truncates
LES_LOWPASS_HZ   <- 30          # Butterworth corner frequency
LES_LOWPASS_ORD  <- 4           # design order (see header on the two-pass reading)

# Butterworth POWER responses at frequency f (Hz).
.bw_power_singlepass <- function(f) 1 / (1 + (f / LES_LOWPASS_HZ)^(2 * LES_LOWPASS_ORD))
.bw_power_twopass    <- function(f) .bw_power_singlepass(f)^2

.retained_fraction <- function(exponent, response) {
  f <- seq(LES_GAMMA_BAND[1], LES_GAMMA_BAND[2], by = 0.01)
  p <- f^(-exponent)                       # offset cancels in the ratio
  sum(response(f) * p) / sum(p)
}

extract_gamma_attenuation <- function() {
  psd <- readr::read_csv(paper2_results("_resting_state_psd.csv"),
                         show_col_types = FALSE, progress = FALSE) %>%
    filter(condition == "eyes_closed",
           freq_hz >= LES_AP_SETTINGS$fit_range[1], freq_hz <= LES_AP_SETTINGS$fit_range[2],
           is.finite(power), power > 0)

  # The full spectrum (not truncated at the fit range) is needed for the
  # empirical band ratio below, which runs to 45 Hz.
  psd_full <- readr::read_csv(paper2_results("_resting_state_psd.csv"),
                              show_col_types = FALSE, progress = FALSE) %>%
    filter(condition == "eyes_closed", is.finite(power), power > 0)

  rows <- psd %>%
    group_by(participant_lab_ID) %>%
    group_modify(~ {
      params <- .fit_aperiodic(.x$freq_hz, log10(.x$power),
                               mode = LES_AP_SETTINGS$aperiodic_mode,
                               max_iter = LES_AP_SETTINGS$max_iter)
      # Empirical companion quantity: OBSERVED 30-45 Hz power over the
      # EXTRAPOLATED aperiodic background. Values well above the transfer-function
      # retention mean the residual band is dominated by something the low-pass
      # did not remove in proportion (line-noise spill, EMG, the noise floor),
      # which is the manuscript's second reason for not interpreting gamma.
      band <- psd_full %>%
        filter(participant_lab_ID == .y$participant_lab_ID,
               freq_hz >= LES_GAMMA_BAND[1], freq_hz <= LES_GAMMA_BAND[2])
      obs_ratio <- sum(band$power) /
        sum(10^(params[1] - params[3] * log10(band$freq_hz)))
      tibble(
        aperiodic_offset   = params[1],
        aperiodic_exponent = params[3],
        retained_fraction  = .retained_fraction(params[3], .bw_power_twopass),
        retained_fraction_singlepass =
          .retained_fraction(params[3], .bw_power_singlepass),
        observed_over_extrapolated = obs_ratio
      )
    }) %>%
    ungroup()

  f <- paper2_results("_gamma_attenuation.csv")
  les_assert_readonly_data(f)
  readr::write_csv(rows, f)
  message(sprintf(
    "[gamma-att] wrote %d participants | two-pass retained: median %.3f (IQR %.3f-%.3f) | single-pass: median %.3f (IQR %.3f-%.3f)",
    nrow(rows),
    stats::median(rows$retained_fraction),
    stats::quantile(rows$retained_fraction, 0.25),
    stats::quantile(rows$retained_fraction, 0.75),
    stats::median(rows$retained_fraction_singlepass),
    stats::quantile(rows$retained_fraction_singlepass, 0.25),
    stats::quantile(rows$retained_fraction_singlepass, 0.75)))
  invisible(rows)
}

if (sys.nframe() == 0L) extract_gamma_attenuation()
