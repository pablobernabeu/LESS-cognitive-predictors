#!/bin/bash
# =============================================================================
# 05_fit_prepost.slurm  --  Part B: pre/post change models (ARC)
# Cognition S1 vs S5, one small Gaussian multilevel model per index; 4 chains x 2
# within-chain threads = 8 CPUs. The rs-EEG S2 vs S6 models are attempted whenever 03
# has produced resting_state_eeg.rds, but they always skip: resting-state EEG was
# recorded at Session 2 only, so no band has two sessions to contrast (05_fit_brms_prepost.R
# requires at least two distinct sessions before it fits).
# Submit AFTER 01:  sbatch paper_2_plasticity/hpc/05_fit_prepost.slurm
# =============================================================================
#SBATCH --job-name=p2_fit_partB
#SBATCH --partition=medium
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=4G
#SBATCH --time=1-00:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/05_fit_prepost.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

export LES_THREADS_PER_CHAIN=2

# Variant fits (LES_P2_SIGN_ALIGNED=1) write their own logs so the mainline log is
# never overwritten by a resubmission. Extra sbatch arguments are passed through to
# the R script (e.g. "joint" to fit only the joint model).
TAG=""
[ "${LES_P2_SIGN_ALIGNED:-0}" = "1" ] && TAG="${TAG}_signaligned"

Rscript "paper_2_plasticity/scripts/05_fit_brms_prepost.R" "$@" \
    > "paper_2_plasticity/hpc/logs/05_fit_prepost${TAG}.Rout" 2>&1

echo "05 fit Part B finished $(date)"
