#!/bin/bash
# =============================================================================
# 09b_compare_commonsample.slurm -- raw-vs-aperiodic PSIS-LOO on a COMMON sample
# -----------------------------------------------------------------------------
# Runs 09b_compare_aperiodic_commonsample.R: refits the raw-band Part A model on the
# aperiodic model's (smaller, 50-participant) common sample, then loo_compare on
# identical observations -- the valid replacement for 09_compare_aperiodic.R, whose
# naive loo_compare errored because raw (56 ppts / 29,565 obs) and aperiodic (50 /
# 26,454) are fit to different data.
#
# Cost: two brms refits (pooled + gender, the raw model on the common sample) plus
# PSIS-LOO on ~26k/12k-row trial-level Bernoulli models. Fitting is modest; the LOO
# pointwise log-lik matrices are memory-heavy (the naive job OOM'd at 16G), hence the
# larger --mem here. 4 chains x 2 threads = 8 CPUs.
#
#   sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/09b_compare_commonsample.slurm
# (Standard QoS only -- never --qos=priority.)
# =============================================================================
#SBATCH --job-name=p2_compare_commonsample
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=16G
#SBATCH --time=08:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/09b_compare_commonsample.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

export LES_THREADS_PER_CHAIN="2"    # 4 chains x 2 threads = 8 CPUs (matches cpus-per-task)

Rscript "paper_2_plasticity/scripts/09b_compare_aperiodic_commonsample.R" \
    > "paper_2_plasticity/hpc/logs/09b_compare_commonsample.Rout" 2>&1

echo "09b compare (common sample) finished $(date)"
