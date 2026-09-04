#!/bin/bash
# =============================================================================
# 01_extract_cognitive.slurm  --  executive-function / statistical-learning indices (ARC)
# Reads the Session 1 & 5 Gorilla exports and writes
# $LES_STORE/paper_2_plasticity/data_derived/cognitive_indices.rds. Light (CSV parsing).
# Submit: sbatch paper_2_plasticity/hpc/01_extract_cognitive.slurm
# =============================================================================
#SBATCH --job-name=p2_extract_cog
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=4G
#SBATCH --time=01:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/01_extract_cognitive.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

Rscript "paper_2_plasticity/scripts/01_extract_cognitive_indices.R" \
    > "paper_2_plasticity/hpc/logs/01_extract_cognitive.Rout" 2>&1

echo "01 extract cognitive finished $(date)"
