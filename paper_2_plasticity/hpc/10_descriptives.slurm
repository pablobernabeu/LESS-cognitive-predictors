#!/bin/bash
# =============================================================================
# 10_descriptives.slurm  --  the descriptive tables the manuscript injects (ARC)
# -----------------------------------------------------------------------------
# Runs the two light scripts that read only data/ and the derived files already in
# the store, and write the descriptive tables the manuscript and the supplement read:
#   10_extract_descriptives.R   _cognitive_descriptives.csv, _predictor_descriptives.csv,
#                               _predictor_values.csv, _predictor_correlations.csv,
#                               _rseeg_descriptives.csv, _resting_state_psd.csv,
#                               _accuracy_trajectory_descriptives.csv, _task_specs.csv
#   12_extract_gamma_attenuation.R  _gamma_attenuation.csv
# Script 12 runs second because it reads the spectra script 10 writes. No model is
# fitted and no fit is invalidated. The counterpart on the Paper 1 side is
# paper_1_transfer/hpc/00_descriptives.slurm.
#
#   sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/10_descriptives.slurm
# (Standard QoS only -- never --qos=priority.)
# =============================================================================
#SBATCH --job-name=p2_descriptives
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/10_descriptives.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

# The variant switches must be unset: this job regenerates the reported artefacts.
unset LES_P2_STROOP_TEST_ONLY

Rscript "paper_2_plasticity/scripts/10_extract_descriptives.R" \
    > "paper_2_plasticity/hpc/logs/10_extract_descriptives.Rout" 2>&1
Rscript "paper_2_plasticity/scripts/12_extract_gamma_attenuation.R" \
    > "paper_2_plasticity/hpc/logs/12_extract_gamma_attenuation.Rout" 2>&1

echo "10 descriptives finished $(date)"
