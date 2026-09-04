# =============================================================================
# _shared/hpc/reconnaissance/probe_rseeg.R  --  reconnaissance for finalising the rs-EEG import
# -----------------------------------------------------------------------------
# Read-only discovery (run on an ARC login node, after sourcing arc_env.sh):
#   (A) dump the installed eegUtils API (exact 0.8.0 function names + signatures);
#   (B) map the OSF node tq7vy structure + file naming;
#   (C) download ONLY the tiny .vhdr/.vmrk text headers of one recording and print
#       them, to reveal the channel montage, sampling rate and event markers
#       (eyes-open / eyes-closed triggers) -- WITHOUT pulling the multi-GB .eeg.
#   Rscript _shared/hpc/reconnaissance/probe_rseeg.R
#
# STATUS: superseded reconnaissance, not a pipeline step, and nothing in either paper
# calls it. Both premises it was written to test were dropped. The recordings turned out
# to be local in the task-EEG tree, so no step fetches anything from OSF, and eegUtils
# cannot read the BrainVision ASCII exports they are stored as. The live implementation
# is paper_2_plasticity/scripts/03_extract_resting_state_eeg.R. Retained only as a
# record of how the data were located.
# =============================================================================

cat("################## (A) eegUtils API ##################\n")
ok <- requireNamespace("eegUtils", quietly = TRUE)
cat("eegUtils installed:", ok, if (ok) as.character(packageVersion("eegUtils")) else "", "\n")
if (ok) {
  ex <- sort(getNamespaceExports("eegUtils"))
  key <- grep("import|read|load|filt|epoch|segment|psd|spectr|freq|welch|electrode|chan|event|select|reref|montage|times",
              ex, ignore.case = TRUE, value = TRUE)
  cat("\n-- candidate functions --\n"); print(key)
  for (fn in intersect(c("import_raw", "import_set", "read_vhdr", "eeg_filter", "iir_filt",
                         "epoch_data", "compute_psd", "select_elecs", "select_times",
                         "eeg_reference", "events", "channels", "channel_names"), ex)) {
    cat("\n### ", fn, "\n"); print(args(getExportedValue("eegUtils", fn)))
  }
}

cat("\n\n################## (B/C) OSF node tq7vy ##################\n")
tryCatch({
  suppressMessages(library(osfr))
  node <- osf_retrieve_node("tq7vy")
  cat("NODE:", node$name, "(", node$id, ")\n")

  # Recursively collect files (bounded), keeping each file's osf object + path.
  collect <- function(tbl, path = "", acc = list(), depth = 0) {
    for (i in seq_len(nrow(tbl))) {
      kind <- tryCatch(tbl$meta[[i]]$attributes$kind, error = function(e) NA)
      nm   <- tbl$name[i]
      full <- if (nzchar(path)) file.path(path, nm) else nm
      if (identical(kind, "folder") && depth < 4) {
        sub <- tryCatch(osf_ls_files(tbl[i, ], n_max = 500), error = function(e) NULL)
        if (!is.null(sub) && nrow(sub)) acc <- collect(sub, full, acc, depth + 1)
      } else {
        acc[[length(acc) + 1]] <- list(
          name = nm, path = full,
          size = tryCatch(tbl$meta[[i]]$attributes$size, error = function(e) NA),
          obj  = tbl[i, ])
      }
    }
    acc
  }
  files <- collect(osf_ls_files(node, n_max = 500))
  cat("total files:", length(files), "\n")
  nms <- vapply(files, `[[`, "", "name")
  cat("\n-- counts by extension --\n"); print(table(tolower(tools::file_ext(nms))))
  paths <- vapply(files, `[[`, "", "path")
  cat("\n-- sample paths (up to 25) --\n"); print(utils::head(paths, 25))
  vhdrs <- Filter(function(f) grepl("\\.vhdr$", f$name, ignore.case = TRUE), files)
  cat("\n.vhdr count:", length(vhdrs), "\n")
  if (length(vhdrs)) {
    cat("-- sample .vhdr names --\n"); print(utils::head(vapply(vhdrs, `[[`, "", "name"), 15))
    v <- vhdrs[[1]]
    base <- sub("\\.vhdr$", "", v$name, ignore.case = TRUE)
    mate <- Filter(function(f) grepl(paste0("^", base, "\\.vmrk$"), f$name, ignore.case = TRUE), files)
    td <- file.path(tempdir(), "rseeg_probe"); dir.create(td, showWarnings = FALSE)
    osf_download(v$obj, path = td, conflicts = "overwrite", progress = FALSE)
    cat("\n===== .vhdr (", v$name, ") =====\n")
    cat(readLines(file.path(td, v$name), warn = FALSE), sep = "\n")
    if (length(mate)) {
      osf_download(mate[[1]]$obj, path = td, conflicts = "overwrite", progress = FALSE)
      mk <- readLines(file.path(td, mate[[1]]$name), warn = FALSE)
      cat("\n\n===== .vmrk markers (", mate[[1]]$name, "; up to 80 lines) =====\n")
      cat(utils::head(mk, 80), sep = "\n")
      cat("\n-- unique marker descriptions --\n")
      mrk <- grep("^Mk[0-9]+=", mk, value = TRUE)
      desc <- sub("^Mk[0-9]+=([^,]*,[^,]*).*", "\\1", mrk)
      print(table(sub("^([^,]*),.*", "\\1", sub("^Mk[0-9]+=", "", mrk))))
    }
  }
}, error = function(e) cat("OSF probe error:", conditionMessage(e), "\n"))

cat("\n[probe_rseeg] done.\n")
