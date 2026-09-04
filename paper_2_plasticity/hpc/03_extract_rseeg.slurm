#!/bin/bash
# =============================================================================
# 03_extract_rseeg.slurm  --  resting-state EEG band power + IAF (ARC)
# -----------------------------------------------------------------------------
# Reduces the Session-2 resting-state recordings (already local, in the task-EEG tree:
# data/raw data/EEG/Session 2/Export/<ppt>_RS_eyes_{closed,open}.{vhdr,txt}) to posterior
# band power + IAF -> $LES_STORE/paper_2_plasticity/data_derived/resting_state_eeg.rds.
# Pure base-R (data.table read + a self-contained Welch PSD) -- no OSF download, no
# eegUtils, no network. Provides the BASELINE (S2) neural predictors for Part A (04);
# there is no Session-6 resting-state, so the rs-EEG pre/post (Part B) does not apply.
# Submit AFTER nothing (independent), before re-fitting 04.
# =============================================================================
#SBATCH --job-name=p2_extract_rseeg
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/03_extract_rseeg.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

Rscript "paper_2_plasticity/scripts/03_extract_resting_state_eeg.R" \
    > "paper_2_plasticity/hpc/logs/03_extract_rseeg.Rout" 2>&1

echo "03 extract rs-EEG finished $(date)"
