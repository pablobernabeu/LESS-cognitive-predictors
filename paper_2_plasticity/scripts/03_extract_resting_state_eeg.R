# =============================================================================
# paper_2_plasticity/scripts/03_extract_resting_state_eeg.R
# Phase 3a -- Resting-state EEG band power + IAF for Paper 2  [HPC]
# =============================================================================
#
# DATA (established 2026-06-13 by direct reconnaissance of the actual recordings)
# ---------------------------------------------------------------------------
# Resting-state EEG was recorded at SESSION 2 ONLY (there is no Session-6 resting
# recording on ARC or OSF), so it serves as a BASELINE neural predictor of learning
# in Part A; the S2-vs-S6 neural pre/post is not possible and is not attempted.
# The recordings already live in the task-EEG tree, exported per condition:
#   data/raw data/EEG/Session 2/Export/<lab_ID>_RS_eyes_{closed,open}.vhdr (+ .txt)
# These are BrainVision Analyzer ASCII exports (DataFormat=ASCII, DecimalSymbol=",",
# DataOrientation=VECTORIZED, SkipColumns=1 -> a leading per-row channel-label column),
# 32 EEG + 3 accelerometer + FCz channels at 500 Hz. eegUtils' import_raw does NOT
# read ASCII, so we parse them directly in base R (fast via data.table::fread) and
# compute the PSD with a self-contained Welch estimator (validated against the Berger
# effect: posterior alpha is higher eyes-closed than eyes-open). IAF is the peak of the
# posterior PSD over a 7-13 Hz search window, which reaches below the 8 Hz lower edge of
# the alpha band in _config.R; see the note above les_iaf() for the boundary cases and
# the cross-check against the specparam peak frequency.
#
# OUTPUT
#   data_derived/resting_state_eeg.rds: one row per participant x condition with
#   posterior (occipito-parietal) band power (delta/theta/alpha/beta/gamma; bands from
#   _config.R) and the individual alpha frequency (IAF). Consumed by 04 (Part A) as a
#   baseline (S2) predictor -- eyes-closed by convention, alpha being suppressed
#   eyes-open. (Part B rs-EEG pre/post auto-skips: only one neural session exists.)
#
# USAGE (HPC):  Rscript 03_extract_resting_state_eeg.R
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "03_data_manifest.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  library(dplyr)
})

# Posterior / occipito-parietal channels: where the resting alpha rhythm and IAF are
# maximal (Klimesch, 1999) -- the ROI for band power + IAF here.
LES_RS_POSTERIOR <- c("O1", "Oz", "O2", "P3", "Pz", "P4", "P7", "P8")

# -----------------------------------------------------------------------------
# BrainVision header + ASCII data readers (base R; no eegUtils -- ASCII unsupported there)
# -----------------------------------------------------------------------------
.parse_vhdr <- function(vhdr) {
  L <- readLines(vhdr, warn = FALSE)
  g <- function(key) { v <- grep(paste0("^", key, "="), L, value = TRUE); if (length(v)) sub(paste0("^", key, "="), "", v[1]) else NA_character_ }
  ch <- grep("^Ch[0-9]+=", L, value = TRUE)                          # [Channel Infos] + [Coordinates] both match;
  ch <- ch[!grepl("^Ch[0-9]+=[0-9-]", ch)]                           # drop coordinate lines (Ch1=1,-90,-72)
  list(srate       = 1e6 / as.numeric(g("SamplingInterval")),
       channels    = sub("^Ch[0-9]+=([^,]*),.*", "\\1", ch),
       orientation = g("DataOrientation"),
       datafile    = g("DataFile"),
       skiplines   = suppressWarnings(as.integer(g("SkipLines"))),
       skipcols    = suppressWarnings(as.integer(g("SkipColumns"))),
       decimal     = g("DecimalSymbol"))
}

# Returns a time x channel numeric matrix with channel names as column names.
# Uses data.table::fread when available (fast); otherwise falls back to a base-R
# reader so the pipeline runs on a minimal install (e.g. a dev box without
# data.table). Both branches yield the identical time x channel matrix.
.read_bv_ascii <- function(vhdr, h = .parse_vhdr(vhdr)) {
  txt <- file.path(dirname(vhdr), h$datafile)
  if (!file.exists(txt)) stop("data file not found: ", txt)
  skipc <- ifelse(is.na(h$skipcols), 0L, h$skipcols)                 # leading column(s) = per-row channel labels
  skipl <- ifelse(is.na(h$skiplines), 0L, h$skiplines)
  dec   <- ifelse(is.na(h$decimal), ".", h$decimal)

  if (requireNamespace("data.table", quietly = TRUE)) {
    dt <- data.table::fread(txt, header = FALSE, showProgress = FALSE,
                            skip = skipl, dec = dec)
    labels <- if (skipc >= 1) as.character(dt[[1]]) else h$channels
    mat <- as.matrix(dt[, (skipc + 1L):ncol(dt), with = FALSE]); storage.mode(mat) <- "numeric"
  } else {                                                           # base-R fallback (no data.table)
    lines <- readLines(txt, warn = FALSE)
    if (skipl > 0) lines <- lines[-seq_len(skipl)]
    lines <- lines[nzchar(trimws(lines))]
    parts <- strsplit(trimws(lines), "[[:space:]]+")
    labels <- if (skipc >= 1) vapply(parts, `[`, character(1), 1L) else h$channels
    nums   <- if (skipc >= 1) lapply(parts, `[`, -seq_len(skipc)) else parts
    if (identical(dec, ",")) nums <- lapply(nums, function(v) gsub(",", ".", v, fixed = TRUE))
    ncols <- max(lengths(nums))
    mat <- matrix(NA_real_, nrow = length(nums), ncol = ncols)
    for (i in seq_along(nums)) { v <- suppressWarnings(as.numeric(nums[[i]])); mat[i, seq_along(v)] <- v }
  }
  if (grepl("VECTORIZED", h$orientation, ignore.case = TRUE)) {      # rows = channels -> time x channel
    rownames(mat) <- labels[seq_len(nrow(mat))]; mat <- t(mat)
  } else {                                                           # MULTIPLEXED: rows already = time
    colnames(mat) <- labels[seq_len(ncol(mat))]
  }
  mat
}

# -----------------------------------------------------------------------------
# Welch PSD (Hann window, 50% overlap, per-segment mean removal) + reductions
# -----------------------------------------------------------------------------
welch_psd <- function(x, fs, seconds = 2) {
  x <- x[is.finite(x)]; if (length(x) < fs) return(NULL)
  nper <- min(round(seconds * fs), length(x)); nover <- floor(nper / 2)
  win  <- 0.5 - 0.5 * cos(2 * pi * (0:(nper - 1)) / (nper - 1)); U <- mean(win^2)
  starts <- seq(1, length(x) - nper + 1, by = nper - nover)
  nf <- floor(nper / 2) + 1; acc <- numeric(nf)
  for (s in starts) {
    seg <- x[s:(s + nper - 1)]; seg <- (seg - mean(seg)) * win
    P <- (Mod(fft(seg))^2)[1:nf] / (fs * nper * U); P[2:(nf - 1)] <- 2 * P[2:(nf - 1)]
    acc <- acc + P
  }
  list(freqs = (0:(nf - 1)) * fs / nper, power = acc / length(starts))
}

# Absolute band power = trapezoidal integral of the PSD over each band's [lo, hi).
les_band_power <- function(freqs, power, bands = LES_P2_EEG_BANDS)
  vapply(bands, function(b) { sel <- which(freqs >= b[[1]] & freqs < b[[2]]); if (length(sel) < 2) NA_real_ else
    sum(diff(freqs[sel]) * (utils::head(power[sel], -1) + utils::tail(power[sel], -1)) / 2) }, numeric(1))

# Individual alpha frequency = frequency of peak power within the alpha search range.
#
# WHY THE PLAIN ARGMAX IS KEPT. A concern was raised that this returns the lowest bin
# (7 Hz) for any spectrum that merely decays across the range, floor-pinning participants
# with no resolvable alpha peak at the extreme of the predictor range as high-leverage
# points. Three eyes-closed recordings (participants 12, 23 and 41) do sit at exactly
# 7 Hz, so the concern is not hypothetical. An alternative estimator requiring an interior
# local maximum was implemented and tested against the specparam peak frequency from
# script 07, which locates the alpha peak AFTER removing the aperiodic 1/f background and
# is therefore the appropriate external reference. It performed worse:
#
#   agreement with specparam_iaf (eyes-closed, n = 54 with a fitted alpha peak)
#     plain argmax            r = +0.83, mean |diff| = 0.44 Hz, max |diff| = 2.82 Hz
#     interior-local-maximum  r = +0.66, mean |diff| = 0.48 Hz, max |diff| = 4.30 Hz
#
# Decisively, participant 23 -- one of the three pinned at 7 Hz -- has a specparam peak at
# 7.21 Hz. Their alpha peak really is that low; the argmax was right, and the interior-peak
# rule wrongly relocated them to 11.5 Hz. The rule skips genuine peaks lying at or near the
# lower boundary in favour of a smaller high-frequency bump.
#
# The residual issue is narrower than first supposed and is one of MISSINGNESS, not of the
# estimator: specparam finds no alpha peak at all for participants 12 and 41, so for those
# two any value in this range is spurious (7 Hz and 11.5/12.5 Hz alike). They are reported
# as lacking a resolvable peak in the resting-state descriptives, and IAF-based claims
# should be checked for sensitivity to their exclusion rather than silently resting on an
# imputed boundary value. specparam_iaf is retained as the independent cross-check; it is
# deliberately NOT substituted here, because the raw-band and aperiodic parameterisations
# are pre-specified as separate arms (04_fit_brms_predictors.R).
les_iaf <- function(freqs, power, rng = c(7, 13)) { sel <- which(freqs >= rng[1] & freqs <= rng[2]); if (!length(sel)) NA_real_ else freqs[sel][which.max(power[sel])] }

# Posterior-averaged PSD -> band power + IAF for one recording.
.summarise_recording <- function(vhdr) {
  h   <- .parse_vhdr(vhdr)
  sig <- .read_bv_ascii(vhdr, h)
  post <- intersect(LES_RS_POSTERIOR, colnames(sig))
  if (!length(post)) { warning("no posterior channels in ", basename(vhdr)); return(NULL) }
  psds <- Filter(Negate(is.null), lapply(post, function(ch) welch_psd(sig[, ch], h$srate)))
  if (!length(psds)) return(NULL)
  freqs <- psds[[1]]$freqs
  pw <- rowMeans(matrix(unlist(lapply(psds, `[[`, "power")), ncol = length(psds)))
  bp <- les_band_power(freqs, pw)
  c(as.list(bp), iaf = les_iaf(freqs, pw))
}

# -----------------------------------------------------------------------------
# Driver: every Session-2 resting recording -> band power + IAF table.
# -----------------------------------------------------------------------------
extract_resting_state_eeg <- function() {
  root  <- data_path("raw data", "EEG")
  vhdrs <- list.files(root, pattern = "_RS_eyes_(open|closed)\\.vhdr$",
                      recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  if (!length(vhdrs)) { message("[rs-eeg] no resting-state .vhdr under ", root); return(invisible(NULL)) }
  message(sprintf("[rs-eeg] %d resting-state recordings found", length(vhdrs)))

  rows <- list()
  for (vhdr in vhdrs) {
    sess <- suppressWarnings(as.integer(sub(".*/Session[ _]?([0-9]+)/.*", "\\1", vhdr)))
    if (is.na(sess) || !(sess %in% LES_P2_NEURAL_SESSIONS)) next       # S2 (and S6 if it ever exists)
    pid  <- suppressWarnings(as.integer(sub("^([0-9]+)_RS.*", "\\1", basename(vhdr))))
    cond <- if (grepl("eyes_open", vhdr, ignore.case = TRUE)) "eyes_open" else "eyes_closed"
    s <- tryCatch(.summarise_recording(vhdr), error = function(e) { message("  skip ", basename(vhdr), ": ", conditionMessage(e)); NULL })
    if (is.null(s)) next
    rows[[length(rows) + 1]] <- tibble::tibble(
      participant_lab_ID = pid, session = sess, condition = cond,
      delta = s$delta, theta = s$theta, alpha = s$alpha,
      beta = s$beta, gamma = s$gamma, iaf = s$iaf)
  }
  out_tbl <- dplyr::bind_rows(rows)
  out <- paper2_derived("resting_state_eeg.rds")
  les_assert_readonly_data(out)
  saveRDS(out_tbl, out)
  message(sprintf("[rs-eeg] wrote %s (%d recordings x %d participants x conditions %s)",
                  out, nrow(out_tbl), dplyr::n_distinct(out_tbl$participant_lab_ID),
                  paste(sort(unique(out_tbl$condition)), collapse = "/")))
  invisible(out_tbl)
}

# =============================================================================
# Entry point
# =============================================================================
.run <- function() { extract_resting_state_eeg(); message("[rs-eeg] done.") }
if (sys.nframe() == 0L) .run()
