#!/bin/bash
# =============================================================================
# 04_fit_predictors.slurm  --  Part A: joint trajectory model (pooled + gender-only, ARC)
# Fits the Bernoulli multilevel model relating the judgement-accuracy trajectory to the
# baseline cognitive (and, if 03 has run, rs-EEG) predictors. Runs BOTH the pooled and the
# gender-only sensitivity fits. 4 chains x 2 within-chain threads = 8 CPUs.
# Submit AFTER 01 + 02:  sbatch paper_2_plasticity/hpc/04_fit_predictors.slurm
# =============================================================================
#SBATCH --job-name=p2_fit_partA
#SBATCH --partition=long
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=12G
#SBATCH --time=3-00:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/04_fit_predictors.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

export LES_THREADS_PER_CHAIN=2   # 4 chains x 2 = 8 CPUs

# Variant fits write their own logs so a sensitivity run never overwrites the mainline
# fit log, and any arguments given to sbatch are passed through to the script, which is
# how a single stratum is selected (e.g. `sbatch ... 04_fit_predictors.slurm gender`).
# With no variant variable set and no arguments both are empty, so an unadorned
# submission behaves exactly as it did before.
TAG=""
[ "${LES_PRIOR_SET:-}" = "weak" ] && TAG="${TAG}_weak"
[ "${LES_P2_IAF_RESOLVED:-}" = "1" ] && TAG="${TAG}_iafres"

Rscript "paper_2_plasticity/scripts/04_fit_brms_predictors.R" "$@" \
    > "paper_2_plasticity/hpc/logs/04_fit_predictors${TAG}.Rout" 2>&1

echo "04 fit Part A finished $(date)"
