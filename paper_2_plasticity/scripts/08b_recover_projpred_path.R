# =============================================================================
# 08b_recover_projpred_path.R
# -----------------------------------------------------------------------------
# Recover the projpred solution-path CSV + summary rds from an ALREADY-COMPUTED
# `<model>_projpred_varsel.rds`, WITHOUT re-running the (multi-day) cv_varsel.
#
# Why this exists: the 2026-07-08 sequential projpred runs completed cv_varsel and
# saved the varsel object, then crashed one step later in .les_projpred_path() --
# projpred 2.10 stores the per-size performance path in summary(vs)$perf_sub, but the
# extractor was reading the (now-absent) $perf_stats / $selection slots, so `perf`
# was a 0-row frame and the data.frame() build failed. The extractor fix lives in
# 08_projpred_selection.R; this driver simply re-applies the fixed helper to the
# cached varsel objects so the ~2 days of CV compute is not repeated.
#
# Inputs  (in the Paper 2 results store):  <model>_projpred_varsel.rds
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
# Unlike the numbered scripts, this driver has no `if (sys.nframe() == 0L)` guard and
# executes at top level, so sourcing it starts the recovery.
# =============================================================================

# Sourcing 08 defines the helpers (.les_projpred_path [fixed], .les_solution_terms,
# paper2_results, config, ...). Its .run() is guarded by `if (sys.nframe() == 0L)`,
# so sourcing does NOT trigger any cv_varsel work.
source("paper_2_plasticity/scripts/08_projpred_selection.R")

# Models whose per-size path we recover. n_participants is taken from each run's log
# ([projpred] ... | N rows | M participants). The fold count is not stored in the varsel
# object, so the 10 asserted below is transcribed, not read back, and it should be checked
# against each run's log before the n_folds column is trusted: the two submission scripts
# disagree, hpc/08_projpred.slurm defaulting LES_PROJPRED_NFOLDS to 10 (the raw-band run)
# and hpc/09_aperiodic_model.slurm to 5, and the aperiodic projpred step runs from the
# latter.
.recover_models <- list(
  list(id = "p2_predictive_trajectory",          n = 56L),  # pooled raw-band
  list(id = "p2_predictive_trajectory_aperiodic", n = 50L)  # aperiodic (specparam)
)

for (m in .recover_models) {
  vpath <- paper2_results(paste0(m$id, "_projpred_varsel.rds"))
  if (!file.exists(vpath)) {
    message("[recover] SKIP -- no varsel object for ", m$id, " (", vpath, ")")
    next
  }
  message("[recover] loading ", vpath, " ...")
  vs <- readRDS(vpath)

  fold_info <- list(k = 10L, n_participants = m$n)
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
    n_participants    = m$n,
    n_folds           = 10L,
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
