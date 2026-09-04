#!/bin/bash
# =============================================================================
# 10_compare_aperiodic.slurm -- PSIS-LOO comparison, raw-band vs. aperiodic (HTC)
# -----------------------------------------------------------------------------
# SUPERSEDED (2026-07-11) -- do NOT submit. Its 09_compare_aperiodic.R loo_compare
# is invalid (raw and aperiodic models are fit to different samples: 56 vs 50
# participants). Use 09b_compare_commonsample.slurm instead, which refits the raw
# model on the aperiodic common subsample and compares on identical observations.
# -----------------------------------------------------------------------------
# Runs 09_compare_aperiodic.R: reloads the (already-fitted, cached) raw-band and
# de-confounded/aperiodic Part A reference models, computes the loo criterion for
# each (no refitting -- a single fast PSIS-LOO pass over the existing draws), and
# compares them within each of the pooled and gender-only strata separately (never
# pooled-vs-gender-only, which are fit to different data and not loo-comparable).
# Cheap: no sampling, so short partition / modest resourcing suffices.
#
# Submit AFTER both 04 (raw + aperiodic fits) and, ideally, 08/09's projpred runs
# have produced their cached fits (only the brms fit .rds files are required here,
# not the projpred outputs):
#   sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/10_compare_aperiodic.slurm
# (Standard QoS only -- never --qos=priority. See paper_2_plasticity/hpc/README.md.)
# =============================================================================
#SBATCH --job-name=p2_compare_aperiodic
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=8G
#SBATCH --time=00:30:00
#SBATCH -o paper_2_plasticity/hpc/logs/10_compare_aperiodic.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

Rscript "paper_2_plasticity/scripts/09_compare_aperiodic.R" \
    > "paper_2_plasticity/hpc/logs/10_compare_aperiodic.Rout" 2>&1

echo "09_compare_aperiodic finished $(date)"
