# =============================================================================
# _shared/hpc/reconnaissance/probe_rseeg3.R  --  characterise the LOCAL resting-state EEG on ARC
# The RS recordings are already in the task-EEG tree, pre-split by condition:
#   data/raw data/EEG/Session {N}/**/<ppt>_RS_eyes_{open,closed}.vhdr
# Census them (sessions, conditions, participant coverage) and TEST import_raw +
# compute_psd on one file to learn the PSD output shape for the extractor rewrite.
#   Rscript _shared/hpc/reconnaissance/probe_rseeg3.R   (prints to stdout only)
#
# STATUS: superseded reconnaissance, not a pipeline step, and nothing in either paper
# calls it. The import_raw + compute_psd route it tests was rejected: the exports are
# BrainVision ASCII, which eegUtils cannot read, so
# paper_2_plasticity/scripts/03_extract_resting_state_eeg.R parses them in base R and
# computes its own Welch PSD. Its driver enumerates the same files with the same
# pattern, so the census below is duplicated there. This is the only remaining caller
# of eegUtils in the project.
# =============================================================================
suppressMessages(library(eegUtils))
root <- file.path(Sys.getenv("LES_DATA_ROOT", unset = "data"), "raw data", "EEG")
cat("EEG root:", root, "\n")

rs <- list.files(root, pattern = "_RS_eyes_(open|closed)\\.vhdr$",
                 recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
cat("resting-state .vhdr files:", length(rs), "\n\n")
sess <- sub(".*/Session[ _]?([0-9]+)/.*", "\\1", rs)
cond <- ifelse(grepl("eyes_open", rs, ignore.case = TRUE), "open", "closed")
ppt  <- sub("^([0-9]+)_RS.*", "\\1", basename(rs))
cat("-- files by session x condition --\n"); print(table(session = sess, condition = cond))
cat("\n-- distinct participants per session --\n")
for (s in sort(unique(sess))) cat("  Session", s, ":", length(unique(ppt[sess == s])), "participants\n")
cat("\n-- sample filenames --\n"); print(basename(utils::head(rs, 6)))
cat("-- parsed participant ids (sample) --\n"); print(utils::head(ppt, 12))

# --- test import + PSD on one file -------------------------------------------
f <- rs[grepl("eyes_closed", rs, ignore.case = TRUE)][1]
cat("\n=== import_raw + compute_psd test:", basename(f), "===\n")
dat <- tryCatch(import_raw(f), error = function(e) { cat("IMPORT ERROR:", conditionMessage(e), "\n"); NULL })
if (!is.null(dat)) {
  cat("object class :", paste(class(dat), collapse = "/"), "\n")
  cat("srate        :", tryCatch(dat$srate, error = function(e) NA), "\n")
  cat("n channels   :", tryCatch(length(channel_names(dat)), error = function(e) NA), "\n")
  cat("channels     :", tryCatch(paste(channel_names(dat), collapse = ","), error = function(e) ""), "\n")
  cat("signal dim   :", tryCatch(paste(dim(dat$signals), collapse = " x "), error = function(e) ""), "\n")
  psd <- tryCatch(compute_psd(dat), error = function(e) { cat("PSD ERROR (continuous):", conditionMessage(e), "\n"); NULL })
  if (is.null(psd)) {
    cat("retry: epoching continuous data into fixed segments then compute_psd ...\n")
    psd <- tryCatch(compute_psd(epoch_data(dat, 1)), error = function(e) { cat("PSD ERROR (epoched):", conditionMessage(e), "\n"); NULL })
  }
  if (!is.null(psd)) {
    cat("\nPSD class :", paste(class(psd), collapse = "/"), "\n")
    cat("PSD names :", paste(names(psd), collapse = ", "), "\n")
    df <- tryCatch(as.data.frame(psd), error = function(e) psd)
    cat("PSD colnames (as.df):", paste(names(df), collapse = ", "), "\n")
    cat("freq range:", tryCatch(paste(range(df$frequency, na.rm = TRUE), collapse = " - "), error = function(e) "?"), "Hz\n")
    print(utils::head(df))
  }
}
cat("\n[probe_rseeg3] done.\n")
