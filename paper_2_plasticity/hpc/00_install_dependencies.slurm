#!/bin/bash
# =============================================================================
# 00_install_dependencies.slurm  --  provision the Bayesian + rs-EEG toolchain (ARC)
# -----------------------------------------------------------------------------
# SHARED with Paper 1 -- installs the SAME project-space R library
# (/data/educ-intract/educ1242/new_LESS/Rlib/R-4.5) + CmdStan build, and guarantees the
# resting-state-EEG stack (eegUtils, osfr) is present. Run EITHER this OR
# paper_1_transfer/hpc/00_install_dependencies.slurm a single time, NOT both.
# Needs outbound network + the gfbf/2025a (GCC 14.2.0) compiler from the R module.
#
# Submit:  sbatch paper_2_plasticity/hpc/00_install_dependencies.slurm
# =============================================================================
#SBATCH --job-name=p2_install_bayes
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=4G
#SBATCH --time=08:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/00_install_dependencies.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

export LES_INSTALL_CORES="${SLURM_CPUS_PER_TASK:-8}"

Rscript "_shared/install_bayesian_dependencies.R" \
    > "paper_2_plasticity/hpc/logs/00_install_dependencies.log" 2>&1

echo "Dependency provisioning finished at $(date)"
