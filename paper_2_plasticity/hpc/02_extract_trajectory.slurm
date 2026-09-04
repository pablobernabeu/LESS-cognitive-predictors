#!/bin/bash
# =============================================================================
# 02_extract_trajectory.slurm  --  longitudinal learning-outcome dataset (ARC)
# Reads the lab-session behavioural logs (reusing Paper 1's validated extractor) and
# writes $LES_STORE/paper_2_plasticity/data_derived/learning_trajectory.rds
# (judgement accuracy + baseline cognition).
# Submit: sbatch paper_2_plasticity/hpc/02_extract_trajectory.slurm
# =============================================================================
#SBATCH --job-name=p2_extract_traj
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/02_extract_trajectory.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

Rscript "paper_2_plasticity/scripts/02_extract_learning_trajectory.R" \
    > "paper_2_plasticity/hpc/logs/02_extract_trajectory.Rout" 2>&1

echo "02 extract trajectory finished $(date)"
