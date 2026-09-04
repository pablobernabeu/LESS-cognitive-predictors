# =============================================================================
# 04_provenance.R  --  Capture the computational environment at fit time
# =============================================================================
#
# WHY THIS EXISTS
# Reporting guidelines require the software and versions used for the MCMC, and a
# Stan model's results are version-sensitive: brms formula translation, default
# priors and NUTS adaptation have all changed across releases, and projpred's search
# and suggest_size behaviour changed between major versions. The manuscripts
# previously said only "a versioned R environment", which is not reproducible
# information.
#
# WHY NOT renv.lock ALONE
# renv.lock does record the fitting library, brms, cmdstanr, rstan, projpred and loo
# among them, at the versions these models were fitted under, and it is how a
# reproducer rebuilds the R side of the environment. It still cannot stand in for this
# file. A lockfile records what a library held when it was snapshotted, not what a given
# run loaded, and it carries no seeds. Nor can it record CmdStan, the GCC toolchain or
# the CXXFLAGS_OPTIM = -O1 pin, none of which is an R package; those are set by
# _shared/hpc/arc_env.sh. Versions and seeds are therefore recorded by the process that
# actually fits the models, at the moment it fits them, with renv.lock restoring the
# library those versions name.
#
# HOW IT IS USED
# Paper 1's ERP fitting script (03_fit_brms_erp.R) and Paper 2's predictor fitting script
# (04_fit_brms_predictors.R) each call les_write_provenance() once per run. The other
# scripts that fit or refit models do not: Paper 1's 04_fit_brms_accuracy.R, and Paper
# 2's 05_fit_brms_prepost.R, 08_projpred_selection.R, 09b_compare_aperiodic_commonsample.R
# and 09c_compare_aperiodic_grouped.R. A run confined to those therefore leaves the file
# as the last full run left it, which is a gap wherever the manuscript describes the
# recorded versions as those of the run that produced the results. Each call writes
# results/_provenance.csv, which each manuscript reads and injects inline, so the
# reported versions are those of the run that produced the results being reported,
# not of whatever machine happens to render the document. Where no provenance file
# exists yet the manuscripts print a marked placeholder, consistent with the
# render-anytime design.
# =============================================================================

# Packages whose version materially affects the results and must be reported.
LES_PROVENANCE_PKGS <- c("brms", "cmdstanr", "rstan", "StanHeaders", "posterior",
                         "loo", "projpred", "bayesplot", "mgcv", "MASS", "dplyr")

# -----------------------------------------------------------------------------
# les_write_provenance()  --  record R, package and Stan versions plus the seeds
# -----------------------------------------------------------------------------
# `results_dir` is the paper's results directory. `seeds` is a named list of the
# seed constants in force for this run, so the exact reproducibility claim in the
# manuscript is backed by a recorded value rather than by a constant in a script
# that may later change. `extra` is a named list of any further key/value pairs to
# record, written as further component/version rows.
#
# The file written is <results_dir>/_provenance.csv, with columns component, version and
# recorded_utc (the UTC time of the write, the same for every row). The same table is
# returned invisibly.
les_write_provenance <- function(results_dir, seeds = list(), extra = list()) {
  rows <- list(
    data.frame(component = "R", version = paste0(R.version$major, ".", R.version$minor),
               stringsAsFactors = FALSE),
    data.frame(component = "platform", version = R.version$platform, stringsAsFactors = FALSE)
  )

  for (p in LES_PROVENANCE_PKGS) {
    v <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
    if (!is.na(v)) rows[[length(rows) + 1]] <-
      data.frame(component = p, version = v, stringsAsFactors = FALSE)
  }

  # CmdStan itself is versioned separately from the cmdstanr interface.
  csv <- tryCatch(cmdstanr::cmdstan_version(), error = function(e) NULL)
  if (!is.null(csv)) rows[[length(rows) + 1]] <-
    data.frame(component = "CmdStan", version = as.character(csv), stringsAsFactors = FALSE)

  for (nm in names(seeds)) rows[[length(rows) + 1]] <-
    data.frame(component = paste0("seed:", nm), version = as.character(seeds[[nm]]),
               stringsAsFactors = FALSE)
  for (nm in names(extra)) rows[[length(rows) + 1]] <-
    data.frame(component = nm, version = as.character(extra[[nm]]), stringsAsFactors = FALSE)

  out <- do.call(rbind, rows)
  out$recorded_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)

  f <- file.path(results_dir, "_provenance.csv")
  if (exists("les_assert_readonly_data")) les_assert_readonly_data(f)
  utils::write.csv(out, f, row.names = FALSE)
  message("[provenance] wrote ", nrow(out), " rows to ", f)
  invisible(out)
}
