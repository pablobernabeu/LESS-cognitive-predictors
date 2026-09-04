# =============================================================================
# _shared/hpc/reconnaissance/dbg_rseeg.R  --  one-file check of the rs-EEG channel labelling
# -----------------------------------------------------------------------------
# Diagnostic, not a pipeline step. Opens ONE hard-coded recording (participant 1,
# Session 2, eyes closed) to check two things the ASCII export makes awkward: whether
# the Ch= lines of the .vhdr yield the expected channel names, and whether the leading
# column of the .txt holds the per-row channel labels rather than data. Each is printed
# with its intersection against the posterior montage.
#   Rscript _shared/hpc/reconnaissance/dbg_rseeg.R   (reads two files, writes none, prints to stdout)
#
# LIMITATIONS: the participant, session and condition are fixed in the path below, and
# the decimal separator is fixed at "," instead of being read from DecimalSymbol in the
# header. Both are fine for a single-file look and wrong for anything general.
#
# STATUS: superseded. paper_2_plasticity/scripts/03_extract_resting_state_eeg.R now
# does all of this properly in .parse_vhdr() and .read_bv_ascii(), including dropping
# the [Coordinates] Ch= lines this file does not. Nothing in either paper calls it.
# =============================================================================
v   <- file.path(Sys.getenv("LES_DATA_ROOT", "data"), "raw data", "EEG", "Session 2", "Export", "1_RS_eyes_closed.vhdr")
txt <- sub("\\.vhdr$", ".txt", v)
L <- readLines(v, warn = FALSE)
chs <- grep("^Ch[0-9]+=", L, value = TRUE)
nms <- sub("^Ch[0-9]+=([^,]*),.*", "\\1", chs)
cat("n Ch= lines:", length(chs), "\n")
cat("parsed .vhdr names [1:36]:\n"); print(utils::head(nms, 36))
POST <- c("O1", "Oz", "O2", "P3", "Pz", "P4", "P7", "P8")
cat("intersect(.vhdr names, posterior):\n"); print(intersect(POST, nms))

dt <- data.table::fread(txt, header = FALSE, dec = ",", showProgress = FALSE)
cat("\nfread dims:", paste(dim(dt), collapse = " x "), "\n")
cat("col1 class:", class(dt[[1]])[1], "| col2 class:", class(dt[[2]])[1], "\n")
cat("col1 head (channel labels?):\n"); print(utils::head(dt[[1]], 8))
cat("intersect(.txt col1, posterior):\n"); print(intersect(POST, as.character(dt[[1]])))
cat("col2 head (first channel's first samples):\n"); print(utils::head(dt[[2]], 5))
cat("\n[dbg] done.\n")
