#!/bin/bash
# =============================================================================
# 11_predictor_reliability.slurm  --  split-half reliability of the three baseline
# cognitive predictors (ARC). Reads the Session 1 Gorilla exports and
# $LES_STORE/paper_2_plasticity/data_derived/cognitive_indices.rds, and writes
# $LES_STORE/paper_2_plasticity/results/_predictor_reliability.csv, the table behind
# the manuscript's predictor-reliability appendix. Light (CSV parsing and resampling).
# Submit AFTER 01, whose indices the script self-validates against.
# Submit: sbatch paper_2_plasticity/hpc/11_predictor_reliability.slurm
# =============================================================================
#SBATCH --job-name=p2_predrel
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/11_predictor_reliability.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

# The two env knobs of the script itself (LES_REL_SPLITS, LES_REL_SEED) carry defaults
# that reproduce the reported table, so neither is exported here.
#
# The Stroop variant runs through the same job. With LES_P2_STROOP_TEST_ONLY=1 the
# practice rows are dropped and the output is tagged, so the reported artefact is left
# alone; it needs the matching tagged indices file, which means running 01 under the same
# switch first:
#   JID=$(sbatch --parsable --export=ALL,LES_P2_STROOP_TEST_ONLY=1 \
#                paper_2_plasticity/hpc/01_extract_cognitive.slurm)
#   sbatch --dependency=afterok:$JID --export=ALL,LES_P2_STROOP_TEST_ONLY=1 \
#          paper_2_plasticity/hpc/11_predictor_reliability.slurm

Rscript "paper_2_plasticity/scripts/11_extract_predictor_reliability.R" \
    > "paper_2_plasticity/hpc/logs/11_predictor_reliability.Rout" 2>&1

echo "11 predictor reliability finished $(date)"
