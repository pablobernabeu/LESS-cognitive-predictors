#!/bin/bash
# =============================================================================
# 07_aperiodic.slurm  --  aperiodic (1/f) spectral parameterisation of rs-EEG (HTC)
# -----------------------------------------------------------------------------
# Reuses 03's validated BrainVision readers + Welch PSD to reconstruct the SAME
# posterior-ROI-averaged eyes-closed Session-2 PSD, then runs a specparam / FOOOF-style
# decomposition ENTIRELY IN R (no Python) to extract, per participant, the aperiodic
# exponent/offset (+knee in the sensitivity pass), oscillation-ADJUSTED theta/alpha/beta
# power, and a specparam IAF. Writes:
#   $LES_STORE/paper_2_plasticity/results/07_aperiodic_features.csv   (+ _peaks.rds)
#   $LES_STORE/paper_2_plasticity/figures/07_aperiodic_fit_<ppt>.png  (QC)
# Pure base R (data.table read + self-contained PSD + lm/optim/nls) -- no OSF download,
# no eegUtils, no network. Independent step; run any time after the data are staged.
# The features are LATER added as baseline (S2) predictors to the Part A brms model (04).
#
# Submit (HTC):  sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/07_aperiodic.slurm
#   sensitivity (knee model):
#                sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/07_aperiodic.slurm knee
# =============================================================================
#SBATCH --job-name=p2_aperiodic
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/07_aperiodic.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

MODE="${1:-fixed}"   # "fixed" (default) or "knee" (sensitivity pass)

Rscript "paper_2_plasticity/scripts/07_extract_aperiodic.R" "${MODE}" \
    > "paper_2_plasticity/hpc/logs/07_aperiodic_${MODE}.Rout" 2>&1

echo "07 extract aperiodic (${MODE}) finished $(date)"
