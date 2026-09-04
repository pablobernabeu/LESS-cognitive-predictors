# =============================================================================
# _shared/hpc/reconnaissance/probe_rseeg4_osf.R  --  OSF rs- resting-state coverage + file format
# -----------------------------------------------------------------------------
# Walks OSF node tq7vy, counts the .vhdr files whose names begin "rs-" or "rs_" by
# top-level (session) folder, and downloads the first such header to print its
# DataFormat / BinaryFormat / SamplingInterval / NumberOfChannels lines.
#   Rscript _shared/hpc/reconnaissance/probe_rseeg4_osf.R   (needs network; prints to stdout only)
#
# STATUS: superseded reconnaissance, not a pipeline step, and nothing in either paper
# calls it. No step downloads from OSF: the resting-state recordings are local, in the
# task-EEG tree, and are named <lab_ID>_RS_eyes_{closed,open}.vhdr, which the "rs-"
# prefix used here would not match. See
# paper_2_plasticity/scripts/03_extract_resting_state_eeg.R for the live implementation.
# =============================================================================
suppressMessages(library(osfr))
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
nms <- vapply(files, `[[`, "", "name"); paths <- vapply(files, `[[`, "", "path")
topdir <- ifelse(grepl("/", paths), sub("/.*", "", paths), "(root)")
isrs <- grepl("^rs[-_]", nms, ignore.case = TRUE) & grepl("\\.vhdr$", nms, ignore.case = TRUE)
cat("OSF rs- .vhdr total:", sum(isrs), "\n")
cat("-- rs- .vhdr by session folder --\n"); print(table(topdir[isrs]))
cat("-- all .vhdr by session folder (for context) --\n"); print(table(topdir[grepl("\\.vhdr$", nms, ignore.case = TRUE)]))
cat("-- sample rs- names --\n"); print(utils::head(nms[isrs], 10))
if (any(isrs)) {
  obj <- files[[which(isrs)[1]]]
  td <- file.path(tempdir(), "rs4"); dir.create(td, showWarnings = FALSE)
  osf_download(obj$obj, path = td, conflicts = "overwrite", progress = FALSE)
  cat("\n=== format of OSF", obj$name, "===\n")
  cat(grep("DataFormat|BinaryFormat|DataFile|MarkerFile|SamplingInterval|NumberOfChannels",
           readLines(file.path(td, obj$name), warn = FALSE), value = TRUE, ignore.case = TRUE), sep = "\n")
}
cat("\n[probe4 osf] done.\n")
