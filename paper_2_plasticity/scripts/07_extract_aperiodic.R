# =============================================================================
# paper_2_plasticity/scripts/07_extract_aperiodic.R
# Phase 3a -- Aperiodic (1/f) spectral parameterisation of resting-state EEG  [HPC]
# =============================================================================
#
# WHAT THIS DOES
# --------------
# A specparam / FOOOF-style decomposition of the Session-2 (baseline) resting-state
# power spectrum, implemented ENTIRELY IN R (no Python / no `fooof`). For each
# participant it separates the power spectral density (PSD) into
#   (i)  an APERIODIC ("1/f", scale-free) background, parameterised by an OFFSET and
#        an EXPONENT (and, optionally, a KNEE), and
#   (ii) a small number of periodic OSCILLATORY peaks (Gaussians) sitting above it,
# following the iterative algorithm of Donoghue et al. (2020, Nat. Neurosci.,
# 10.1038/s41593-020-00744-x). The aperiodic exponent indexes the excitation/
# inhibition balance and cortical "state" (Gao et al. 2017, NeuroImage,
# 10.1016/j.neuroimage.2017.06.078; Voytek et al. 2015, J. Neurosci.,
# 10.1523/JNEUROSCI.2332-14.2015), and flattens/steepens with development, arousal
# and task (Ouyang et al. 2020, NeuroImage, 10.1016/j.neuroimage.2019.116304).
#
# WHY THIS MATTERS FOR PAPER 2
# ----------------------------
# Script 03 already reduces each recording to ABSOLUTE band power, which conflates
# genuine oscillatory power with the 1/f background: a steeper 1/f alone inflates
# "theta/delta" and deflates "beta/gamma" with no oscillation present. Parameterising
# the spectrum yields (a) the aperiodic exponent/offset as neural predictors in their
# own right and (b) oscillation-ADJUSTED band power (peak height ABOVE the fitted 1/f),
# which is the quantity the band-power literature intends. These features are written
# to a tidy CSV and are LATER added, standardised, as baseline (S2) predictors to the
# existing Part A brms model (04); this script itself is only feature extraction.
#
# REUSE / NO DOUBLE PARSING
# -------------------------
# We SOURCE 03_extract_resting_state_eeg.R purely for its validated readers and PSD
# estimator (.parse_vhdr / .read_bv_ascii / welch_psd) -- sourcing does not trigger its
# driver (it is guarded by `if (sys.nframe() == 0L)`). We reconstruct the SAME
# posterior-ROI-averaged PSD (Welch, Hann, 2 s, 50% overlap; ROI LES_RS_POSTERIOR)
# that 03 computes, then fit the aperiodic model on it. Eyes-CLOSED by convention
# (alpha maximal, matching the predictor 03 hands to 04).
#
# FIT-RANGE / ALGORITHM CHOICES (all cited)
# -----------------------------------------
#   * Fit range 2-40 Hz: avoids the sub-2 Hz drift and the >40 Hz line-noise/EMG
#     region, per Gerster et al. (2022, Neuroinformatics,
#     10.1007/s12021-022-09581-8), who benchmark specparam settings and recommend
#     restricting the fit and using a "fixed" (knee-free) aperiodic model unless the
#     spectrum is plainly bent on a log-log plot. We fit "fixed" by default and expose
#     a "knee" mode for a sensitivity pass.
#     KNOWN LIMITATION OF THIS RANGE. The offline preprocessing low-passed these
#     recordings at 30 Hz (fourth-order Butterworth, zero phase shift; see
#     12_extract_gamma_attenuation.R), so the top quarter of the fitted bins sits in
#     the filter's roll-off, where power is attenuated increasingly with frequency.
#     The robust fit below trims only points ABOVE the fit, so those bins are always
#     retained and pull the high-frequency end of the log-log line down: the fitted
#     exponent is steeper, and the offset correspondingly shifted, relative to a fit
#     confined to the passband. The effect is not quantified here, and it carries into
#     12_extract_gamma_attenuation.R, whose retained fraction is a function of this
#     exponent. Narrowing the range to end at or below the 30 Hz corner would change
#     every exponent and offset, and with them the Part A aperiodic variant, so the
#     setting is left as it stands and the limitation is recorded instead. Because the
#     filter's attenuation in decibels is the same function of frequency for every
#     recording, and the aperiodic fit is linear in log power, the bias it adds to the
#     exponent is close to a constant shared across participants, which the z-scoring
#     applied before modelling removes. The robust trimming step is data-dependent, so
#     the cancellation is approximate and not exact.
#     OPT-IN SENSITIVITY. Setting LES_AP_FIT_MAX_HZ (e.g. 30) replaces the upper bound
#     of the fit range and tags every output file with "_fit<max>hz", so a passband-only
#     decomposition can be produced beside the reported one without touching it. With
#     the variable unset the range, the file names and every value are exactly as before.
#   * max_n_peaks, peak_width_limits, min_peak_height, peak_threshold: the standard
#     specparam guards, so noise ripples are not fit as oscillations. The values used
#     here are this project's own settings rather than any published default; see
#     LES_AP_SETTINGS below.
#   * Robust aperiodic regression: Donoghue's outlier-trimmed least squares (fit,
#     drop points far ABOVE the fit -- i.e. peaks -- refit) so peaks do not bias the
#     1/f estimate.
#
# GUARDING AGAINST DOUBLE-DIPPING / OPTIMISTIC ESTIMATES
# ------------------------------------------------------
# This is an unsupervised, per-participant DESCRIPTIVE decomposition -- there is no
# classifier and no cross-validation here, so the decoding-style leakage the project
# warns about (class balancing, CV optimism, item codes reused across languages)
# cannot arise at THIS step. The one relevant hazard is circularity when these
# features later feed the brms model: the adjusted band power and the exponent are
# partly redundant (both derive from the same PSD), so 04/06 must not treat them as
# independent evidence. We therefore (a) emit BOTH raw and adjusted band power plus a
# fit-quality flag (R^2, error) so the modelling step can pick a non-redundant subset,
# and (b) never select features by their association with the outcome here.
#
# OUTPUT
#   paper2_results("07_aperiodic_features.csv"): one row per participant with
#     aperiodic_exponent, aperiodic_offset, aperiodic_knee (NA in fixed mode),
#     r_squared, fit_error, adjusted alpha/theta/beta power (peak height above 1/f),
#     specparam IAF (centre freq of the fitted alpha peak), n_peaks, and the raw
#     band power for reference. Also a per-participant peak table (long) as .rds and a
#     couple of example fit plots (observed PSD + aperiodic fit) under paper2_figures().
#
# USAGE (HPC)
#   Rscript 07_extract_aperiodic.R                # fixed (knee-free) aperiodic model
#   Rscript 07_extract_aperiodic.R knee           # sensitivity: knee model
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "03_data_manifest.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  # Reuse 03's validated BrainVision readers + Welch PSD. Sourcing does NOT run its
  # driver (guarded by `if (sys.nframe() == 0L)`), so no re-parse / no side effects.
  source(here::here("paper_2_plasticity", "scripts", "03_extract_resting_state_eeg.R"))
  library(dplyr)
})

# --- Which resting-state condition feeds the aperiodic features --------------
# Eyes-CLOSED Session 2, matching the baseline predictor 03 supplies to Part A.
LES_AP_CONDITION <- "eyes_closed"

# --- Aperiodic fit settings (Donoghue 2020; Gerster 2022) --------------------
# Upper bound of the fit range. The reported decomposition uses 40 Hz (see the header).
# LES_AP_FIT_MAX_HZ overrides it for the opt-in passband-only sensitivity pass and, when
# set, tags every output file so the reported artefacts are never overwritten.
.les_ap_fit_max_hz <- local({
  v <- suppressWarnings(as.numeric(Sys.getenv("LES_AP_FIT_MAX_HZ", unset = "")))
  if (is.finite(v) && v > 2) v else 40
})
les_ap_range_tag <- function() {
  if (identical(.les_ap_fit_max_hz, 40)) "" else sprintf("_fit%ghz", .les_ap_fit_max_hz)
}

LES_AP_SETTINGS <- list(
  # Hz; Gerster 2022: avoid the <2 Hz drift and the >40 Hz line-noise/EMG region
  fit_range        = c(2, .les_ap_fit_max_hz),
  max_n_peaks      = 6,           # caps the peak model far below the number of ripples in
                                  #   a noisy spectrum, so noise is not fit as oscillation
  peak_width_limits = c(1, 12),   # Hz; reject implausibly narrow/broad "peaks"
  min_peak_height  = 0.05,        # log10 power above the flattened spectrum
  peak_threshold   = 2,           # in SD of the flattened spectrum (relative guard)
  aperiodic_mode   = "fixed",     # "fixed" (offset - exp*log10 f) or "knee"
  max_iter         = 25           # max outlier-trim/refit iterations for the aperiodic fit
)

# Canonical bands for oscillation-adjusted power (reuse the project's definitions).
LES_AP_BANDS <- LES_P2_EEG_BANDS[c("theta", "alpha", "beta")]
# Alpha search window for the specparam IAF, the same window les_iaf() in 03 searches, so
# the two IAF estimates are taken over the same range. It reaches below the 8 Hz lower
# edge of the alpha band; the note above les_iaf() records the low-peak cases this covers.
LES_AP_IAF_RANGE <- LES_P2_IAF_SEARCH_HZ

# =============================================================================
# Aperiodic model in log10-log10 space
# =============================================================================
# FIXED : L(f) = offset - exponent * log10(f)
# KNEE  : L(f) = offset - log10(knee + f^exponent)   (Donoghue 2020, eq. for knee)
#   fit on log10(power). Returned parameters are on the natural (Hz / log10-power)
#   scale used throughout specparam.

.ap_predict <- function(params, f, mode) {
  lf <- log10(f)
  if (mode == "knee") {
    # params = c(offset, knee, exponent); the knee is floored at 0 with pmax() rather
    # than reparameterised, so the optimiser searches the natural scale.
    params[1] - log10(pmax(params[2], 0) + f^params[3])
  } else {
    params[1] - params[3] * lf          # params[2] (knee) ignored in fixed mode
  }
}

# Robust aperiodic fit: initial OLS on log10 power, then iteratively DROP points that
# sit ABOVE the fit (oscillatory peaks) and refit, so the 1/f is estimated from the
# spectral "floor" only (Donoghue 2020). Returns c(offset, knee, exponent).
.fit_aperiodic <- function(f, logp, mode = "fixed", max_iter = 25) {
  lf <- log10(f)
  # initial guess: simple line through the endpoints
  b1 <- (logp[length(logp)] - logp[1]) / (lf[length(lf)] - lf[1])
  init_exp <- max(-b1, 0.1)
  init_off <- logp[1] + init_exp * lf[1]
  fit_line <- function(keep) {
    if (mode == "knee") {
      obj <- function(p) sum((logp[keep] - (p[1] - log10(pmax(p[2], 0) + f[keep]^p[3])))^2)
      start <- c(init_off, 0, init_exp)
      opt <- tryCatch(stats::optim(start, obj, method = "Nelder-Mead",
                                   control = list(maxit = 2000)),
                      error = function(e) NULL)
      if (is.null(opt)) c(init_off, 0, init_exp) else c(opt$par[1], max(opt$par[2], 0), opt$par[3])
    } else {
      d <- data.frame(y = logp[keep], x = lf[keep])
      cf <- stats::lm(y ~ x, data = d)$coefficients
      c(cf[[1]], 0, -cf[[2]])            # offset, knee=0, exponent
    }
  }
  keep <- rep(TRUE, length(f))
  params <- fit_line(keep)
  for (i in seq_len(max_iter)) {
    resid <- logp - .ap_predict(params, f, mode)
    # keep the spectral floor: drop points > 1 SD ABOVE the current fit (the peaks).
    thr <- stats::sd(resid)
    new_keep <- resid <= thr
    if (sum(new_keep) < max(5, 0.25 * length(f))) break   # never over-trim
    if (identical(new_keep, keep)) break
    keep <- new_keep
    params <- fit_line(keep)
  }
  params
}

# =============================================================================
# Peak fitting on the flattened (aperiodic-removed) spectrum
# =============================================================================
# Donoghue 2020: iteratively find the tallest residual peak, fit a Gaussian, subtract,
# repeat until the tallest remaining peak falls below threshold or max_n_peaks reached.
# Guards (peak_width_limits, min_peak_height, peak_threshold) reject noise ripples.

.gaussian <- function(f, ctr, hgt, wid) hgt * exp(-(f - ctr)^2 / (2 * wid^2))

.fit_peaks <- function(f, flat, s) {
  peaks <- list()
  resid <- flat
  noise_sd <- stats::sd(flat)
  for (k in seq_len(s$max_n_peaks)) {
    i <- which.max(resid)
    hgt <- resid[i]
    if (hgt < s$min_peak_height || hgt < s$peak_threshold * noise_sd) break
    ctr <- f[i]
    # initial width from the half-max crossing, clamped to the allowed limits
    half <- hgt / 2
    lo <- i; while (lo > 1 && resid[lo] > half) lo <- lo - 1
    hi <- i; while (hi < length(resid) && resid[hi] > half) hi <- hi + 1
    fwhm <- max(f[hi] - f[lo], s$peak_width_limits[1])
    wid0 <- fwhm / 2.355
    wid0 <- min(max(wid0, s$peak_width_limits[1] / 2.355), s$peak_width_limits[2] / 2.355)
    # refine the Gaussian by least squares in a local window
    win <- which(abs(f - ctr) <= 3 * fwhm)
    fit <- tryCatch(stats::nls(
      resid ~ .gaussian(f, ctr, hgt, wid),
      data = data.frame(resid = resid[win], f = f[win]),
      start = list(ctr = ctr, hgt = hgt, wid = wid0),
      control = stats::nls.control(maxiter = 200, warnOnly = TRUE)),
      error = function(e) NULL)
    if (!is.null(fit)) {
      co <- as.list(stats::coef(fit))
      if (is.finite(co$hgt) && co$hgt >= s$min_peak_height &&
          co$wid * 2.355 >= s$peak_width_limits[1] &&
          co$wid * 2.355 <= s$peak_width_limits[2] &&
          co$ctr >= min(f) && co$ctr <= max(f)) {
        ctr <- co$ctr; hgt <- co$hgt; wid0 <- abs(co$wid)
      }
    }
    peaks[[length(peaks) + 1]] <- c(center = ctr, height = hgt, width = wid0)
    resid <- resid - .gaussian(f, ctr, hgt, wid0)   # subtract before next search
  }
  if (!length(peaks)) return(NULL)
  do.call(rbind, peaks)
}

# =============================================================================
# Full specparam decomposition for one posterior-averaged PSD
# =============================================================================
# Returns a one-row list of features + the peak table. `power` is linear PSD, `freqs`
# in Hz. Follows Donoghue 2020: fit aperiodic, flatten, fit peaks, then REFIT the
# aperiodic on the peak-removed spectrum for the final exponent/offset.

specparam_decompose <- function(freqs, power, s = LES_AP_SETTINGS) {
  sel <- which(freqs >= s$fit_range[1] & freqs <= s$fit_range[2] & power > 0 & is.finite(power))
  if (length(sel) < 10) return(NULL)
  f <- freqs[sel]; logp <- log10(power[sel])

  # (1) initial aperiodic fit on the full (restricted) spectrum
  ap <- .fit_aperiodic(f, logp, s$aperiodic_mode, s$max_iter)
  # (2) flatten and fit oscillatory peaks
  flat <- logp - .ap_predict(ap, f, s$aperiodic_mode)
  pk <- .fit_peaks(f, flat, s)
  # (3) remove all peaks and REFIT the aperiodic (final exponent/offset)
  logp_noosc <- logp
  if (!is.null(pk)) for (r in seq_len(nrow(pk)))
    logp_noosc <- logp_noosc - .gaussian(f, pk[r, "center"], pk[r, "height"], pk[r, "width"])
  ap <- .fit_aperiodic(f, logp_noosc, s$aperiodic_mode, s$max_iter)

  # (4) goodness of fit: full model = aperiodic + peaks vs. observed log10 power
  model_fit <- .ap_predict(ap, f, s$aperiodic_mode)
  if (!is.null(pk)) for (r in seq_len(nrow(pk)))
    model_fit <- model_fit + .gaussian(f, pk[r, "center"], pk[r, "height"], pk[r, "width"])
  ss_res <- sum((logp - model_fit)^2)
  ss_tot <- sum((logp - mean(logp))^2)
  r2 <- if (ss_tot > 0) 1 - ss_res / ss_tot else NA_real_
  fit_err <- sqrt(mean((logp - model_fit)^2))     # RMSE in log10 power

  # (5) oscillation-ADJUSTED band power = summed peak height (above 1/f) in each band.
  #     This is the peak-model contribution only; the aperiodic background is excluded.
  band_adj <- vapply(LES_AP_BANDS, function(b) {
    if (is.null(pk)) return(0)
    inb <- pk[, "center"] >= b[[1]] & pk[, "center"] < b[[2]]
    if (!any(inb)) 0 else sum(pk[inb, "height"])
  }, numeric(1))

  # (6) specparam IAF = centre frequency of the tallest peak in the alpha window.
  iaf <- NA_real_
  if (!is.null(pk)) {
    ina <- pk[, "center"] >= LES_AP_IAF_RANGE[1] & pk[, "center"] <= LES_AP_IAF_RANGE[2]
    if (any(ina)) { a <- pk[ina, , drop = FALSE]; iaf <- a[which.max(a[, "height"]), "center"] }
  }

  list(
    features = list(
      aperiodic_offset   = ap[1],
      aperiodic_knee     = if (s$aperiodic_mode == "knee") ap[2] else NA_real_,
      aperiodic_exponent = ap[3],
      r_squared          = r2,
      fit_error          = fit_err,
      n_peaks            = if (is.null(pk)) 0L else nrow(pk),
      theta_adj          = band_adj[["theta"]],
      alpha_adj          = band_adj[["alpha"]],
      beta_adj           = band_adj[["beta"]],
      specparam_iaf      = iaf
    ),
    peaks = pk,
    fit   = list(f = f, logp = logp, model = model_fit,
                 aperiodic = .ap_predict(ap, f, s$aperiodic_mode))
  )
}

# =============================================================================
# Posterior-ROI-averaged eyes-closed PSD for one recording (reusing 03's readers)
# =============================================================================
# Mirrors 03's `.summarise_recording` up to the posterior-averaged PSD, but RETURNS
# that PSD (freqs + linear power) instead of collapsing it to band power, so we can
# parameterise it. LES_RS_POSTERIOR / welch_psd come from the sourced script 03.

.posterior_psd <- function(vhdr) {
  h   <- .parse_vhdr(vhdr)
  sig <- .read_bv_ascii(vhdr, h)
  post <- intersect(LES_RS_POSTERIOR, colnames(sig))
  if (!length(post)) { warning("no posterior channels in ", basename(vhdr)); return(NULL) }
  psds <- Filter(Negate(is.null), lapply(post, function(ch) welch_psd(sig[, ch], h$srate)))
  if (!length(psds)) return(NULL)
  freqs <- psds[[1]]$freqs
  power <- rowMeans(matrix(unlist(lapply(psds, `[[`, "power")), ncol = length(psds)))
  # raw absolute band power for reference (same reduction 03 reports).
  list(freqs = freqs, power = power, raw_band = les_band_power(freqs, power))
}

# =============================================================================
# QC: example fit plots (observed PSD + aperiodic fit + full model), log-log
# =============================================================================
.plot_example_fit <- function(dec, raw_freqs, raw_power, pid, out_png) {
  # HPC compute nodes are headless: the default png() device needs X11 and writes a
  # 0-byte file. Use cairo (renders without a display); skip cleanly if unavailable.
  if (!isTRUE(grDevices::capabilities("cairo"))) {
    message("  [qc] cairo device unavailable; skipping example fit plot for ppt ", pid)
    return(invisible(NULL))
  }
  grDevices::png(out_png, width = 1100, height = 700, res = 130, type = "cairo")
  on.exit(grDevices::dev.off(), add = TRUE)
  f <- dec$fit$f
  op <- graphics::par(mfrow = c(1, 2)); on.exit(graphics::par(op), add = TRUE)
  # left: full spectrum (log-log) with fit range shaded
  in_rng <- raw_freqs >= LES_AP_SETTINGS$fit_range[1] &
    raw_freqs <= LES_AP_SETTINGS$fit_range[2] & raw_power > 0
  plot(log10(raw_freqs[in_rng]), log10(raw_power[in_rng]), type = "l", col = "grey40",
       xlab = "log10 frequency (Hz)", ylab = "log10 power",
       main = sprintf("ppt %s: PSD + aperiodic fit", pid))
  graphics::lines(log10(f), dec$fit$aperiodic, col = "firebrick", lwd = 2, lty = 2)
  graphics::lines(log10(f), dec$fit$model,     col = "steelblue", lwd = 2)
  graphics::legend("topright", bty = "n", lwd = 2, lty = c(2, 1),
                   col = c("firebrick", "steelblue"), legend = c("aperiodic", "aperiodic + peaks"))
  # right: flattened spectrum (peaks above the 1/f background)
  plot(f, dec$fit$logp - dec$fit$aperiodic, type = "l", col = "grey40",
       xlab = "frequency (Hz)", ylab = "log10 power above 1/f",
       main = sprintf("flattened (exp=%.2f, R2=%.2f)",
                      dec$features$aperiodic_exponent, dec$features$r_squared))
  graphics::abline(h = 0, col = "grey70", lty = 3)
  if (!is.null(dec$peaks)) graphics::abline(v = dec$peaks[, "center"], col = "firebrick", lty = 3)
  invisible(out_png)
}

# =============================================================================
# Driver: every eligible eyes-closed Session-2 recording -> specparam features CSV
# =============================================================================
extract_aperiodic <- function(mode = LES_AP_SETTINGS$aperiodic_mode) {
  s <- LES_AP_SETTINGS; s$aperiodic_mode <- mode
  # The knee tag and the fit-range tag compose, so a knee-mode passband-only run is
  # distinguishable from either sensitivity pass on its own.
  tag <- paste0(if (mode == "knee") "_knee" else "", les_ap_range_tag())

  root  <- resting_state_eeg_path()
  vhdrs <- list.files(root, pattern = "_RS_eyes_(open|closed)\\.vhdr$",
                      recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  if (!length(vhdrs)) {
    message("[aperiodic] no resting-state .vhdr under ", root)
    return(invisible(NULL))
  }

  rows <- list(); peak_rows <- list(); n_plotted <- 0L
  for (vhdr in vhdrs) {
    # eyes-CLOSED only, Session-2 (baseline) only.
    if (!grepl(LES_AP_CONDITION, vhdr, ignore.case = TRUE)) next
    sess <- suppressWarnings(as.integer(sub(".*/Session[ _]?([0-9]+)/.*", "\\1", vhdr)))
    if (is.na(sess) || !(sess %in% LES_P2_NEURAL_SESSIONS)) next
    pid  <- suppressWarnings(as.integer(sub("^([0-9]+)_RS.*", "\\1", basename(vhdr))))

    psd <- tryCatch(.posterior_psd(vhdr), error = function(e) {
      message("  skip ", basename(vhdr), ": ", conditionMessage(e)); NULL
    })
    if (is.null(psd)) next
    dec <- tryCatch(specparam_decompose(psd$freqs, psd$power, s), error = function(e) {
      message("  fit fail ", basename(vhdr), ": ", conditionMessage(e)); NULL
    })
    if (is.null(dec)) next

    ft <- dec$features
    rows[[length(rows) + 1]] <- tibble::tibble(
      participant_lab_ID = pid, session = sess, condition = LES_AP_CONDITION,
      aperiodic_offset   = ft$aperiodic_offset,
      aperiodic_exponent = ft$aperiodic_exponent,
      aperiodic_knee     = ft$aperiodic_knee,
      r_squared          = ft$r_squared,
      fit_error          = ft$fit_error,
      n_peaks            = ft$n_peaks,
      theta_adj          = ft$theta_adj,
      alpha_adj          = ft$alpha_adj,
      beta_adj           = ft$beta_adj,
      specparam_iaf      = ft$specparam_iaf,
      # raw absolute band power for reference / redundancy checks downstream
      theta_raw = psd$raw_band[["theta"]], alpha_raw = psd$raw_band[["alpha"]],
      beta_raw  = psd$raw_band[["beta"]])

    if (!is.null(dec$peaks)) peak_rows[[length(peak_rows) + 1]] <- tibble::tibble(
      participant_lab_ID = pid,
      center = dec$peaks[, "center"], height = dec$peaks[, "height"], width = dec$peaks[, "width"])

    # QC: emit a couple of example fit plots (first two participants that fit cleanly).
    if (n_plotted < 2 && is.finite(ft$r_squared) && ft$r_squared > 0.9) {
      png <- paper2_figures(sprintf("07_aperiodic_fit_%s%s.png", pid, tag))
      tryCatch(.plot_example_fit(dec, psd$freqs, psd$power, pid, png),
               error = function(e) message("  plot fail ", pid, ": ", conditionMessage(e)))
      n_plotted <- n_plotted + 1L
    }
  }

  if (!length(rows)) { message("[aperiodic] no recordings decomposed."); return(invisible(NULL)) }
  out_tbl <- dplyr::bind_rows(rows) |> dplyr::arrange(participant_lab_ID)

  out_csv <- paper2_results(sprintf("07_aperiodic_features%s.csv", tag))
  les_assert_readonly_data(out_csv)
  utils::write.csv(out_tbl, out_csv, row.names = FALSE)

  peak_tbl <- if (length(peak_rows)) dplyr::bind_rows(peak_rows) else tibble::tibble()
  out_rds <- paper2_results(sprintf("07_aperiodic_peaks%s.rds", tag))
  les_assert_readonly_data(out_rds)
  saveRDS(peak_tbl, out_rds)

  message(sprintf("[aperiodic] wrote %s (%d participants; median exp=%.2f, median R2=%.2f)",
                  out_csv, nrow(out_tbl),
                  stats::median(out_tbl$aperiodic_exponent, na.rm = TRUE),
                  stats::median(out_tbl$r_squared, na.rm = TRUE)))
  message(sprintf("[aperiodic] wrote %s (%d peaks) + %d example fit plots",
                  out_rds, nrow(peak_tbl), n_plotted))
  invisible(out_tbl)
}

# =============================================================================
# Entry point
# =============================================================================
.run <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  mode <- if (length(args) && args[1] %in% c("fixed", "knee")) {
    args[1]
  } else {
    LES_AP_SETTINGS$aperiodic_mode
  }
  message(sprintf("[aperiodic] aperiodic_mode = %s", mode))
  extract_aperiodic(mode)
  message("[aperiodic] done.")
}
if (sys.nframe() == 0L) .run()
