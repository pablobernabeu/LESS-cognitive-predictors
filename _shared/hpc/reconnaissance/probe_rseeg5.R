# =============================================================================
# _shared/hpc/reconnaissance/probe_rseeg5.R  --  prototype the base-R rs-EEG read + Welch PSD
# Reads ONE participant's eyes-closed & eyes-open BrainVision ASCII export, computes
# a Welch PSD on posterior channels, and reports band power + IAF. Validation: alpha
# should be HIGHER eyes-closed than eyes-open, and IAF should land ~8-12 Hz.
#   Rscript _shared/hpc/reconnaissance/probe_rseeg5.R   (participant 1, Session 2; stdout only)
#
# STATUS: superseded prototype, not a pipeline step, and nothing in either paper calls
# it. Its code was promoted into
# paper_2_plasticity/scripts/03_extract_resting_state_eeg.R, where welch_psd(),
# les_band_power() and les_iaf() now live in a documented form, the IAF estimator in
# particular carrying the justification for the plain argmax that this file lacks.
#
# HAZARD while it is kept: those three functions are defined here in the global
# environment under the same names as the production copies, so sourcing this file and
# script 03 in one session leaves whichever was sourced last in place.
# =============================================================================
suppressPackageStartupMessages({
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))  # LES_P2_EEG_BANDS
})
EXP <- file.path(Sys.getenv("LES_DATA_ROOT", "data"), "raw data", "EEG", "Session 2", "Export")

# --- parse a BrainVision .vhdr: channels, sampling rate, ASCII layout ---------
parse_vhdr <- function(vhdr) {
  L <- readLines(vhdr, warn = FALSE)
  get1 <- function(key) { v <- grep(paste0("^", key, "="), L, value = TRUE); if (length(v)) sub(paste0("^", key, "="), "", v[1]) else NA }
  si   <- as.numeric(get1("SamplingInterval"))             # microseconds/sample
  srate <- 1e6 / si
  chs  <- grep("^Ch[0-9]+=", L, value = TRUE)
  chnames <- sub("^Ch[0-9]+=([^,]*),.*", "\\1", chs)
  list(srate = srate, channels = chnames,
       orientation = get1("DataOrientation"),
       datafile = get1("DataFile"),
       skiplines = suppressWarnings(as.integer(get1("SkipLines"))),
       skipcols  = suppressWarnings(as.integer(get1("SkipColumns"))),
       decimal   = get1("DecimalSymbol"))
}

# --- Welch PSD (Hann window, 50% overlap, per-segment mean removal) -----------
welch_psd <- function(x, fs, seconds = 2) {
  x <- x[is.finite(x)]; if (length(x) < fs) return(NULL)
  nper <- min(round(seconds * fs), length(x)); nover <- floor(nper / 2)
  win <- 0.5 - 0.5 * cos(2 * pi * (0:(nper - 1)) / (nper - 1)); U <- mean(win^2)
  starts <- seq(1, length(x) - nper + 1, by = nper - nover)
  nf <- floor(nper / 2) + 1; acc <- numeric(nf)
  for (s in starts) {
    seg <- x[s:(s + nper - 1)]; seg <- (seg - mean(seg)) * win
    P <- (Mod(fft(seg))^2)[1:nf] / (fs * nper * U)
    P[2:(nf - 1)] <- 2 * P[2:(nf - 1)]
    acc <- acc + P
  }
  list(freqs = (0:(nf - 1)) * fs / nper, power = acc / length(starts))
}
les_band_power <- function(freqs, power, bands = LES_P2_EEG_BANDS)
  vapply(bands, function(b) { sel <- which(freqs >= b[[1]] & freqs < b[[2]]); if (length(sel) < 2) NA_real_ else
    sum(diff(freqs[sel]) * (utils::head(power[sel], -1) + utils::tail(power[sel], -1)) / 2) }, numeric(1))
les_iaf <- function(freqs, power, rng = c(7, 13)) { sel <- which(freqs >= rng[1] & freqs <= rng[2]); if (!length(sel)) NA_real_ else freqs[sel][which.max(power[sel])] }

POSTERIOR <- c("O1", "Oz", "O2", "P3", "Pz", "P4", "P7", "P8")

analyse_one <- function(vhdr) {
  h <- parse_vhdr(vhdr)
  txt <- file.path(dirname(vhdr), h$datafile)
  if (!file.exists(txt)) { cat("  missing data file:", h$datafile, "\n"); return(NULL) }
  dt <- data.table::fread(txt, header = FALSE, showProgress = FALSE,
                          skip = ifelse(is.na(h$skiplines), 0L, h$skiplines),
                          dec = ifelse(is.na(h$decimal), ".", h$decimal))
  skipc  <- ifelse(is.na(h$skipcols), 0L, h$skipcols)             # leading column(s) = channel labels
  labels <- if (skipc >= 1) as.character(dt[[1]]) else h$channels
  mat <- as.matrix(dt[, (skipc + 1L):ncol(dt), with = FALSE]); storage.mode(mat) <- "numeric"
  if (grepl("VECTORIZED", h$orientation, ignore.case = TRUE)) {   # rows = channels -> transpose to time x ch
    rownames(mat) <- labels[seq_len(nrow(mat))]; raw <- t(mat)
  } else {                                                         # MULTIPLEXED: rows already = time
    raw <- mat; colnames(raw) <- labels[seq_len(ncol(raw))]
  }
  cat(sprintf("  %s: srate=%g, dims(time x ch)=%d x %d, orient=%s\n",
              basename(vhdr), h$srate, nrow(raw), ncol(raw), h$orientation))
  post <- intersect(POSTERIOR, colnames(raw))
  psds <- Filter(Negate(is.null), lapply(post, function(ch) welch_psd(raw[, ch], h$srate)))
  if (!length(psds)) { cat("    no PSD computed (no posterior channels found)\n"); return(NULL) }
  freqs <- psds[[1]]$freqs
  pp <- rowMeans(matrix(unlist(lapply(psds, `[[`, "power")), ncol = length(psds)))
  bp <- les_band_power(freqs, pp); iaf <- les_iaf(freqs, pp)
  cat("    posterior channels (", length(post), "):", paste(post, collapse = ","), "\n")
  cat("    band power:", paste(sprintf("%s=%.3g", names(bp), bp), collapse = "  "), "\n")
  cat("    IAF:", round(iaf, 2), "Hz\n")
  invisible(list(bp = bp, iaf = iaf))
}

for (cond in c("eyes_closed", "eyes_open")) {
  vhdr <- file.path(EXP, paste0("1_RS_", cond, ".vhdr"))
  cat("===", cond, "===\n")
  if (file.exists(vhdr)) analyse_one(vhdr) else cat("  not found:", vhdr, "\n")
}
cat("\n[probe_rseeg5] done. (expect alpha higher for eyes_closed; IAF ~8-12 Hz)\n")
