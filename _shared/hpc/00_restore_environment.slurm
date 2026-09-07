#!/bin/bash
# =============================================================================
# _shared/hpc/00_restore_environment.slurm  --  rebuild the recorded environment
# -----------------------------------------------------------------------------
# The reproduction route. Restores the project R library from the repository's
# renv.lock at the recorded versions and builds CmdStan 2.39.0, the release every
# reported fit was compiled by. The two Rscript lines are the ones HPC_RUNBOOK.md gives
# in section 0. The 00_install_dependencies.slurm job in either paper's hpc/ is the
# bootstrap for a library where none exists yet; it pins nothing and is not this route.
#
# Before submitting, put renv.lock beside the code root, from the dev box:
#   scp renv.lock arc:new_LESS/
# The code scp carries neither renv.lock nor .Rprofile nor renv/, so renv is never
# activated on the cluster and both the lockfile and the target library are named
# explicitly. The library argument is the whole search path, .libPaths(), because the
# snapshot was taken across the R module's own library as well as R_LIBS_USER; a restore
# confined to R_LIBS_USER would reinstall every package the lockfile pinned from the
# module.
#
# LES_CMDSTAN_VERSION is exported after arc_env.sh has been sourced. With the variable
# set, arc_env.sh stops when the named tree is absent, which on a fresh environment it
# still is at that point. Export it in the fitting jobs
# (--export=ALL,LES_CMDSTAN_VERSION=2.39.0) to pin them to the tree built here. The
# CXXFLAGS_OPTIM = -O1 pin is written to the new tree's make/local by the first job that
# sources arc_env.sh after this one.
#
# Needs outbound network and the gfbf/2025a compiler that the R module supplies.
#   sbatch _shared/hpc/00_restore_environment.slurm
#
# LOG: paper_1_transfer/hpc/logs/00_restore_environment.out, as rebuild_cmdstan.slurm
# does. Slurm opens that file when the job starts, so on a fresh checkout create the
# directory before submitting:  mkdir -p paper_1_transfer/hpc/logs
# =============================================================================
#SBATCH --job-name=les_restore_env
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=4G
#SBATCH --time=08:00:00
#SBATCH -o paper_1_transfer/hpc/logs/00_restore_environment.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_1_transfer/hpc/logs

if [ ! -f renv.lock ]; then
  echo "[restore] FATAL: no renv.lock beside the code root (${LES_CODE_ROOT}); scp it from the dev box first" >&2
  exit 1
fi

# renv has to be present before it can restore anything. The restore then replaces it
# with the pinned version along with everything else in the lockfile.
Rscript --vanilla -e 'if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv", repos = "https://cloud.r-project.org")'

echo "[restore] restoring renv.lock into R_LIBS_USER=${R_LIBS_USER} on $(hostname)"
Rscript --vanilla -e 'renv::restore(lockfile = "renv.lock", library = .libPaths(), prompt = FALSE)'
Rscript --vanilla -e 'cmdstanr::install_cmdstan(version = "2.39.0", dir = Sys.getenv("CMDSTAN_INSTALL_DIR"))'

export LES_CMDSTAN_VERSION=2.39.0
if [ ! -d "${LES_BASE}/cmdstan/cmdstan-${LES_CMDSTAN_VERSION}" ]; then
  echo "[restore] FATAL: ${LES_BASE}/cmdstan/cmdstan-${LES_CMDSTAN_VERSION} was not built" >&2
  exit 1
fi
echo "[restore] library restored from renv.lock and CmdStan ${LES_CMDSTAN_VERSION} built, $(date)"
