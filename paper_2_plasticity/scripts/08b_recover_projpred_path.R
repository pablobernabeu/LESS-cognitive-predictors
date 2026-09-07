# =============================================================================
# 08b_recover_projpred_path.R
# -----------------------------------------------------------------------------
# Recover the projpred solution-path CSV + summary rds from an ALREADY-COMPUTED
# `<model>_projpred_varsel.rds`, WITHOUT re-running the (multi-day) cv_varsel.
#
# Why this exists: the sequential projpred runs behind the shipped path CSVs completed
# cv_varsel and saved the varsel object, then crashed one step later in
# .les_projpred_path() -- projpred 2.10 stores the per-size performance path in
# summary(vs)$perf_sub, but the extractor was reading the (now-absent) $perf_stats /
# $selection slots, so `perf` was a 0-row frame and the data.frame() build failed. The
# extractor fix lives in 08_projpred_selection.R; this driver simply re-applies the fixed
# helper to the cached varsel objects so the ~2 days of CV compute is not repeated.
#
# Inputs  (in the Paper 2 results store):  <model>_projpred_varsel.rds
#                                          <model>_projpred_summary.rds (optional; see
#                                          .recover_fold_count below)
# Outputs (same dir):                      <model>_projpred_path.csv
#                                          <model>_projpred_summary.rds
#
# Run via paper_2_plasticity/hpc/08b_recover.slurm (needs enough RAM to load the
# varsel object -- the aperiodic one is ~8 GB on disk).
#
# STATUS: already run. The two <model>_projpred_path.csv files and their summaries in
# results/ are its output, so it is kept as the provenance record of how they were
# produced rather than as a step to repeat. A re-run today would not reproduce them
# byte-for-byte: 08's extractor has since gained a cv_prop_diag column that the two
# shipped CSVs do not carry.
#
# Like the numbered scripts, the driver runs only under `if (sys.nframe() == 0L)`, so
# sourcing this file defines .recover_projpred_paths() and starts nothing.
# =============================================================================

# Sourcing 08 defines the helpers (.les_projpred_path [fixed], .les_solution_terms,
# paper2_results, config, ...). Its .run() is guarded by `if (sys.nframe() == 0L)`,
# so sourcing does NOT trigger any cv_varsel work.
source(here::here("paper_2_plasticity", "scripts", "08_projpred_selection.R"))

# Models whose per-size path we recover. n_participants is taken from each run's log
# ([projpred] ... | N rows | M participants) and is used only where no summary written
# by 08 is on disk to read it from.
.recover_models <- list(
  list(id = "p2_predictive_trajectory",          n = 56L),  # pooled raw-band
  list(id = "p2_predictive_trajectory_aperiodic", n = 50L)  # aperiodic (specparam)
)

# The fold count is not stored in the varsel object. 08 records it, from the fold builder,
# as n_folds in <model>_projpred_summary.rds, so that field is read back when a summary
# written by 08 is present. Otherwise the value falls back to ten, the default in both
# submission scripts (hpc/08_projpred.slurm and hpc/09_aperiodic_model.slurm), which is
# then transcribed, not read back, and should be checked against the run's log line
# "[projpred] grouped <k>-fold CV over <n> participants" before the n_folds column is
# trusted. The shipped path CSVs were checked this way: hpc/logs/09_projpred_aperiodic.Rout
# prints "[projpred] grouped 10-fold CV over 50 participants" for the aperiodic model,
# hpc/logs/08_projpred.Rout prints "grouped 10-fold CV over 56 participants" for the pooled
# model, and the cached <model>_cvfits.rds objects carry ten distinct fold ids. Because 08
# caches those cvfits by model id alone, a resubmission must pass LES_PROJPRED_NFOLDS=10 or
# delete the cache first. A summary this script wrote carries a transcribed value and is
# never mistaken for 08's record: it is marked n_folds_source = "transcribed", and it
# leaves base_rate unset, whereas 08 always computes base_rate from the data.
.recover_fold_count <- function(m) {
  spath <- paper2_results(paste0(m$id, "_projpred_summary.rds"))
  if (file.exists(spath)) {
    prev <- tryCatch(readRDS(spath), error = function(e) NULL)
    k    <- suppressWarnings(as.integer(prev$n_folds))
    from_08 <- is.list(prev) && length(k) == 1L && !is.na(k) &&
      isTRUE(is.finite(prev$base_rate)) &&
      !identical(prev$n_folds_source, "transcribed")
    if (from_08) {
      n_p <- suppressWarnings(as.integer(prev$n_participants))
      if (length(n_p) != 1L || is.na(n_p)) n_p <- m$n
      message("[recover] ", m$id, ": n_folds = ", k, " read from the summary 08 wrote")
      return(list(k = k, n_participants = n_p, source = "08 summary"))
    }
  }
  message("[recover] ", m$id, ": n_folds = 10 transcribed from the submission default; ",
          "check the run's log line before trusting the n_folds column")
  list(k = 10L, n_participants = m$n, source = "transcribed")
}

.recover_projpred_paths <- function() {
  for (m in .recover_models) {
    vpath <- paper2_results(paste0(m$id, "_projpred_varsel.rds"))
    if (!file.exists(vpath)) {
      message("[recover] SKIP -- no varsel object for ", m$id, " (", vpath, ")")
      next
    }
    fold_info <- .recover_fold_count(m)
    message("[recover] loading ", vpath, " ...")
    vs <- readRDS(vpath)

    sug <- tryCatch(projpred::suggest_size(vs, stat = "elpd"),
                    error = function(e) NA_integer_)

    path_df <- .les_projpred_path(vs, m$id, sug, fold_info)
    utils::write.csv(path_df, paper2_results(paste0(m$id, "_projpred_path.csv")),
                     row.names = FALSE)

    ranking <- .les_solution_terms(vs)
    summ <- list(
      model             = m$id,
      suggested_size    = sug,
      solution_path     = ranking,
      n_candidate_terms = length(ranking),
      n_participants    = fold_info$n_participants,
      n_folds           = fold_info$k,
      n_folds_source    = fold_info$source,
      base_rate         = NA_real_,   # descriptive only; recovered runs leave it unset
      validate_search   = TRUE,
      cv_method         = "participant-grouped kfold"
    )
    saveRDS(summ, paper2_results(paste0(m$id, "_projpred_summary.rds")))

    message(sprintf("[recover] %s | suggested size = %s | path rows = %d | ranking: %s",
                    m$id, ifelse(is.na(sug), "NA", sug), nrow(path_df),
                    paste(ranking, collapse = " > ")))
    cat("---- head of", m$id, "path ----\n")
    print(utils::head(path_df, 4))
    cat("---- column names ----\n"); print(names(path_df))

    rm(vs); gc()
  }
  message("[recover] done.")
}

if (sys.nframe() == 0L) .recover_projpred_paths()
