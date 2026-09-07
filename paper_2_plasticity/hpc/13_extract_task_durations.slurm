#!/bin/bash
# =============================================================================
# 13_extract_task_durations.slurm -- observed home-task and lab-phase durations
# -----------------------------------------------------------------------------
# Reads the raw Gorilla and OpenSesame exports on the project-space data mount and
# writes the two small manuscript-facing CSVs into both paper result stores.
# No model is fitted and no existing fit or derived dataset is changed.
#
#   sbatch --clusters=htc --account=educ-intract \
#       paper_2_plasticity/hpc/13_extract_task_durations.slurm
# =============================================================================
#SBATCH --job-name=p2_task_durations
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/13_extract_task_durations.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

Rscript "paper_2_plasticity/scripts/13_extract_task_durations.R" \
    > "paper_2_plasticity/hpc/logs/13_extract_task_durations.Rout" 2>&1

echo "13 task-duration extraction finished $(date)"
