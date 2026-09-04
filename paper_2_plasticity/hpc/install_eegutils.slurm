#!/bin/bash
# =============================================================================
# install_eegutils.slurm  --  install eegUtils from R-universe / GitHub (ARC)
# -----------------------------------------------------------------------------
# eegUtils is no longer on CRAN for current R ("not available for this version of
# R"), so install.packages() from CRAN cannot find it. It is installed instead
# from the maintainer's R-universe (prebuilt binary, pulls its CRAN Imports
# automatically), with a GitHub source build as fallback.
#
# STANDALONE FALLBACK, not a prerequisite. The shared 00 installer
# (_shared/install_bayesian_dependencies.R) already runs the same R-universe install, and
# neither pipeline loads eegUtils: the resting-state step (03) reads the BrainVision
# ASCII exports in base R because eegUtils::import_raw() cannot read ASCII. The only
# remaining consumers are the reconnaissance scripts under
# _shared/hpc/reconnaissance/ and an optional check in check_arc_env.R. Use this
# script when 00 has already run and only eegUtils is missing.
#   sbatch paper_2_plasticity/hpc/install_eegutils.slurm
# =============================================================================
#SBATCH --job-name=les_eegutils
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=4G
#SBATCH --time=01:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/install_eegutils.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

Rscript -e '
  ok <- tryCatch({
    install.packages("eegUtils",
      repos = c("https://craddm.r-universe.dev", "https://cloud.r-project.org"))
    requireNamespace("eegUtils", quietly = TRUE)
  }, error = function(e) { cat("r-universe route failed:", conditionMessage(e), "\n"); FALSE })
  if (!ok) {
    if (!requireNamespace("remotes", quietly = TRUE))
      install.packages("remotes", repos = "https://cloud.r-project.org")
    tryCatch(remotes::install_github("craddm/eegUtils", upgrade = "never"),
             error = function(e) cat("github route failed:", conditionMessage(e), "\n"))
  }
  cat("eegUtils:", if (requireNamespace("eegUtils", quietly = TRUE))
        as.character(packageVersion("eegUtils")) else "STILL MISSING", "\n")
'
echo "eegUtils install attempt finished $(date)"
