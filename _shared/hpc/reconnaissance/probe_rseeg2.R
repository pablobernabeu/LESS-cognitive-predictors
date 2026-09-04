# =============================================================================
# _shared/hpc/reconnaissance/probe_rseeg2.R  --  is OSF tq7vy resting-state or task EEG?
# Reads the session logbook + a marker census (markers, duration) for one recording
# per session folder. Task EEG = thousands of stimulus markers; resting = a handful.
#   Rscript _shared/hpc/reconnaissance/probe_rseeg2.R   (needs network; prints to stdout only)
#
# STATUS: superseded reconnaissance, not a pipeline step, and nothing in either paper
# calls it. The question it asks was settled by locating the resting-state recordings in
# the local task-EEG tree, which removed the OSF route altogether; see
# paper_2_plasticity/scripts/03_extract_resting_state_eeg.R. Retained only as a record.
# =============================================================================
suppressMessages({ library(osfr) })
node <- osf_retrieve_node("tq7vy")

collect <- function(tbl, path = "", acc = list(), depth = 0) {
  for (i in seq_len(nrow(tbl))) {
    kind <- tryCatch(tbl$meta[[i]]$attributes$kind, error = function(e) NA)
    nm <- tbl$name[i]; full <- if (nzchar(path)) file.path(path, nm) else nm
    if (identical(kind, "folder") && depth < 4) {
      sub <- tryCatch(osf_ls_files(tbl[i, ], n_max = 500), error = function(e) NULL)
      if (!is.null(sub) && nrow(sub)) acc <- collect(sub, full, acc, depth + 1)
    } else acc[[length(acc) + 1]] <- list(name = nm, path = full, obj = tbl[i, ])
  }
  acc
}
files <- collect(osf_ls_files(node, n_max = 500))
paths <- vapply(files, `[[`, "", "path"); nms <- vapply(files, `[[`, "", "name")
topdir <- ifelse(grepl("/", paths), sub("/.*", "", paths), "(root)")

cat("=== .vhdr recordings per top-level folder ===\n")
print(table(topdir[grepl("\\.vhdr$", nms, ignore.case = TRUE)]))

# Session logbook
lb <- Filter(function(f) grepl("logbook", f$name, ignore.case = TRUE), files)
if (length(lb)) {
  td <- file.path(tempdir(), "rs2"); dir.create(td, showWarnings = FALSE)
  osf_download(lb[[1]]$obj, path = td, conflicts = "overwrite", progress = FALSE)
  cat("\n=== session logbook:", lb[[1]]$name, "===\n")
  d <- tryCatch(read.csv(file.path(td, lb[[1]]$name), stringsAsFactors = FALSE, check.names = FALSE),
                error = function(e) NULL)
  if (!is.null(d)) { cat("dims", nrow(d), "x", ncol(d), "\ncolumns:\n"); print(names(d)); cat("\nhead:\n"); print(utils::head(d, 12)) }
  else cat(utils::head(readLines(file.path(td, lb[[1]]$name)), 25), sep = "\n")
}

# Marker census: one .vmrk per session folder. The duration below divides the last
# marker position by an assumed 500 Hz rather than reading SamplingInterval from the
# matching .vhdr, which is adequate for telling a task run from a resting run but would
# have to be read properly before this code were reused for anything quantitative.
vmrks <- Filter(function(f) grepl("\\.vmrk$", f$name, ignore.case = TRUE), files)
byfolder <- split(vmrks, vapply(vmrks, function(f) sub("/.*", "", f$path), ""))
td2 <- file.path(tempdir(), "rs2mk"); dir.create(td2, showWarnings = FALSE)
cat("\n=== marker census (first recording in each session folder; 500 Hz) ===\n")
for (fld in names(byfolder)) {
  f <- byfolder[[fld]][[1]]
  osf_download(f$obj, path = td2, conflicts = "overwrite", progress = FALSE)
  mk <- readLines(file.path(td2, f$name), warn = FALSE)
  stim <- grep("^Mk[0-9]+=Stimulus", mk, value = TRUE)
  allmk <- grep("^Mk[0-9]+=", mk, value = TRUE)
  pos <- suppressWarnings(as.numeric(sub("^Mk[0-9]+=[^,]*,[^,]*,([0-9]+),.*", "\\1", allmk)))
  cat(sprintf("  %-14s %-10s : %4d stimulus markers, %4d total, ~%.1f min\n",
              fld, f$name, length(stim), length(allmk), max(pos, na.rm = TRUE) / 500 / 60))
}
cat("\n[probe_rseeg2] done.\n")
