# =============================================================================
# install_bayesian_dependencies.R
# -----------------------------------------------------------------------------
# Extends HPC scripts/check_and_install_packages.R with everything the two
# Bayesian manuscripts need (brms + Stan toolchain, posterior tooling, the
# resting-state EEG stack for Paper 2, papaja and Quarto).
# Run ONCE on the cluster to BOOTSTRAP a library where none exists. It is not the way to
# reproduce the environment the reported fits ran in: it pins nothing, resolving against
# whatever CRAN ships on the day, and install_if_missing() keeps whatever version is
# already installed. renv.lock takes precedence over the list below. It records R 4.5.1
# and the fitting library, so the way to rebuild the environment is the batch job
# _shared/hpc/00_restore_environment.slurm, which runs
#
#   scp renv.lock arc:new_LESS/       # from the dev box; the code scp does not carry it
#   source _shared/hpc/arc_env.sh
#   Rscript --vanilla -e 'renv::restore(lockfile = "renv.lock", library = .libPaths(),
#                                       prompt = FALSE)'        # R packages, exact versions
#   Rscript --vanilla -e 'cmdstanr::install_cmdstan(version = "2.39.0",
#                                                   dir = Sys.getenv("CMDSTAN_INSTALL_DIR"))'
#
# The lockfile and the library are named explicitly because the cluster code root carries
# neither renv.lock nor a .Rprofile (HPC_RUNBOOK.md, section 0), so renv is never activated
# there. The last line is deliberately not the 00_install_dependencies.slurm job: that job
# runs this script, whose install_cmdstan() call carries no version= and would take whatever
# release is current. What renv cannot restore at all is CmdStan, the GCC toolchain and the
# CXXFLAGS_OPTIM = -O1 pin, none of which is an R package. Those are set by
# _shared/hpc/arc_env.sh, and the CmdStan version a run used is recorded in
# results/_provenance.csv. Take any fresh snapshot with
# the R module loaded and `library = .libPaths()`, so the module's own bundled library is
# captured alongside R_LIBS_USER; a snapshot of R_LIBS_USER alone omits about a fifth of
# the environment. The status table this script prints at the end is a convenience log,
# not the record.
#
# Usage (on the cluster, under environment modules rather than a container):
#   source _shared/hpc/arc_env.sh && Rscript _shared/install_bayesian_dependencies.R
# normally reached through paper_1_transfer/hpc/00_install_dependencies.slurm or its
# Paper 2 twin, of which only one should ever be run.
#
# ENVIRONMENT
#   LES_INSTALL_CORES   cores for the CmdStan build (default: detectCores() - 1; the
#                       slurm wrappers set it from SLURM_CPUS_PER_TASK)
#   CMDSTAN_INSTALL_DIR where CmdStan is built (exported by _shared/hpc/arc_env.sh; off
#                       the cluster it falls back to cmdstanr's ~/.cmdstan default)
#
# OUTPUTS: packages into .libPaths()[1] (R_LIBS_USER on the cluster) and a CmdStan
# tree under CMDSTAN_INSTALL_DIR, plus a status table on stdout.
# =============================================================================

cat("R version:", R.version.string, "\n\n")

repos <- "https://cloud.r-project.org/"

# --- CRAN packages -----------------------------------------------------------
required_packages <- c(
  # --- reproducibility / paths ---
  "here",            # project-anchored paths (Marwick et al., 2018)
  "renv",            # environment lockfile
  # --- Bayesian modelling ---
  "brms",            # Bayesian multilevel models (Bürkner, 2017, JSS 80:1)
  "posterior",       # rank-normalised Rhat / ESS (Vehtari et al., 2021)
  "bayesplot",       # posterior predictive checks (Gabry et al., 2019)
  "loo",             # PSIS-LOO model checking (Vehtari, Gelman & Gabry, 2017)
  # --- data wrangling / plotting (used by legacy + new code) ---
  "dplyr", "tidyr", "stringr", "readr", "readxl", "data.table", "purrr",
  "ggplot2", "ggtext", "scales", "patchwork",
  # --- resting-state EEG (Paper 2) ---
  # (eegUtils is NOT on CRAN for current R; installed from R-universe below. No OSF
  # client is needed: the recordings are local and no pipeline step downloads anything,
  # see paper_2_plasticity/scripts/03_extract_resting_state_eeg.R.)
  # --- manuscripts ---
  "papaja",          # the apa_num/apa_p number formatters used by the .qmd files
                     #   (Aust & Barth). The manuscripts themselves are built with
                     #   apaquarto, and the .qmd carry base-R fallbacks for these two
                     #   helpers, so papaja is optional
  "quarto"           # render the .qmd documents
)

# --- Optional tooling, not installed by this script ---------------------------
# Neither pipeline loads any of these. The scripts read draws with
# posterior::as_draws_df and reduce them themselves, pd and the CI are computed from the
# draws in _shared/R/02_diagnostics.R, and the retention contrasts are formed from the
# draws in step 05 of Paper 1. They are listed so that a reader knows what was considered;
# add a name to required_packages above to provision it.
#   "tidybayes"        tidy posterior extraction
#   "bayestestR"       pd, ROPE, CI (Makowski et al., 2019)
#   "marginaleffects"  model-agnostic marginal and conditional effects and contrasts
#   "emmeans"          estimated marginal means, used by the legacy lmerTest analyses
#                      under analyses/

# --- install one CRAN package if it is not already there ---------------------
# Reports the version when the package is present, so the log doubles as a record of
# what the run found. A failed install is reported and does not abort the rest.
install_if_missing <- function(pkg) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("OK   %-16s %s\n", pkg, as.character(packageVersion(pkg))))
    return(invisible(TRUE))
  }
  cat(sprintf("..   installing %s\n", pkg))
  tryCatch(
    install.packages(pkg, repos = repos, dependencies = TRUE),
    error = function(e) cat(sprintf("FAIL %-16s %s\n", pkg, conditionMessage(e)))
  )
}

invisible(lapply(required_packages, install_if_missing))

# =============================================================================
# From here on, the packages that are not on CRAN. cmdstanr lives on the Stan
# R-universe and eegUtils on the maintainer's; papaja is on CRAN but is built from
# GitHub if the CRAN install failed. All three are optional and the run continues
# without them: brms falls back to the rstan backend, and the manuscripts use their
# own base-R number formatters when papaja is missing.
# =============================================================================

# --- cmdstanr + CmdStan (preferred Stan backend) -----------------------------
if (!requireNamespace("cmdstanr", quietly = TRUE)) {
  cat("\nInstalling cmdstanr from the Stan R-universe...\n")
  tryCatch(
    install.packages("cmdstanr",
                     repos = c("https://stan-dev.r-universe.dev", repos)),
    error = function(e) cat("FAIL cmdstanr:", conditionMessage(e), "\n")
  )
}
if (requireNamespace("cmdstanr", quietly = TRUE)) {
  # Build the CmdStan toolchain once if it is not already present.
  ok <- tryCatch(!is.null(cmdstanr::cmdstan_version(error_on_NA = FALSE)),
                 error = function(e) FALSE)
  if (!isTRUE(ok)) {
    # Honour CMDSTAN_INSTALL_DIR so the (large) toolchain is built in the project
    # /data space on the cluster rather than on the personal disk. That is the
    # new_LESS/cmdstan directory which _shared/hpc/arc_env.sh exports. Off-cluster the
    # variable is unset and cmdstanr's default (~/.cmdstan) applies.
    .install_cores <- as.integer(Sys.getenv("LES_INSTALL_CORES",
                                             unset = as.character(max(1, parallel::detectCores() - 1))))
    .cmdstan_dir <- Sys.getenv("CMDSTAN_INSTALL_DIR", unset = "")
    cat(sprintf("Installing CmdStan (one-off C++ toolchain build; cores=%d, dir=%s)...\n",
                .install_cores, if (nzchar(.cmdstan_dir)) .cmdstan_dir else "<default>"))
    tryCatch(
      if (nzchar(.cmdstan_dir)) {
        dir.create(.cmdstan_dir, recursive = TRUE, showWarnings = FALSE)
        cmdstanr::install_cmdstan(dir = .cmdstan_dir, cores = .install_cores, overwrite = FALSE)
      } else {
        cmdstanr::install_cmdstan(cores = .install_cores)
      },
      error = function(e) cat("FAIL CmdStan:", conditionMessage(e), "\n"))
  }
}

# --- papaja GitHub fallback --------------------------------------------------
if (!requireNamespace("papaja", quietly = TRUE)) {
  if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes", repos = repos)
  tryCatch(remotes::install_github("crsh/papaja"),
           error = function(e) cat("FAIL papaja (GitHub):", conditionMessage(e), "\n"))
}

# --- eegUtils (Paper 2 resting-state) ----------------------------------------
# Not on CRAN for current R, so install from the maintainer's R-universe (prebuilt
# binary that pulls its CRAN Imports automatically; the default Imports tree avoids
# the gganimate -> sf -> units Suggests chain that needs absent system libraries).
# Optional, and currently called by no pipeline step. The resting-state extractor
# (Paper 2, script 03) parses the BrainVision ASCII exports in base R because
# eegUtils::import_raw() cannot read that format. It is still provisioned so that the
# eegUtils route, and the reconnaissance scripts in _shared/hpc/reconnaissance/ that use
# it, stay runnable.
if (!requireNamespace("eegUtils", quietly = TRUE)) {
  cat("\nInstalling eegUtils from the maintainer's R-universe...\n")
  tryCatch(
    install.packages("eegUtils", repos = c("https://craddm.r-universe.dev", repos)),
    error = function(e) cat("FAIL eegUtils:", conditionMessage(e), "\n"))
}

# --- Final report ------------------------------------------------------------
cat("\n=== FINAL STATUS ===\n")
for (pkg in c(required_packages, "cmdstanr", "eegUtils")) {
  status <- if (requireNamespace(pkg, quietly = TRUE)) {
    sprintf("OK   (%s)", as.character(packageVersion(pkg)))
  } else "MISSING"
  cat(sprintf("%-16s %s\n", pkg, status))
}
cat("\nNext: on the CLUSTER, and only there, run\n",
    "  Rscript --vanilla -e 'renv::snapshot(library = .libPaths(), type = \"all\", prompt = FALSE)'\n",
    "That writes renv.lock into the cluster code root, not into the repository, so copy it\n",
    "back to the working copy (from the dev box: scp arc:new_LESS/renv.lock renv.lock) and\n",
    "commit it. Without that step the lockfile in the repository stays stale. Never snapshot\n",
    "from the render box: it has no projpred or eegUtils and would replace the lockfile with\n",
    "a partial one.\n", sep = "")
