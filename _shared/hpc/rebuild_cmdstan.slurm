#!/bin/bash
# =============================================================================
# _shared/hpc/rebuild_cmdstan.slurm  --  rebuild CmdStan's precompiled headers
# -----------------------------------------------------------------------------
# Run ONCE on a compute node after CmdStan is installed or RELOCATED (the PCH
# files bake in the install path, so a moved CmdStan must be rebuilt; the rebuild
# is memory-hungry and is killed on the login node). Recompiles the CmdStan core
# + PCH at $CMDSTAN, then runs the environment check (which compiles a trivial
# model) to confirm the toolchain works.
#   sbatch _shared/hpc/rebuild_cmdstan.slurm
#
# LOG: paper_1_transfer/hpc/logs/rebuild_cmdstan.out, so this shared script writes into
# Paper 1's log tree. Slurm opens that file when the job starts, before the `mkdir -p`
# below runs, so on a fresh checkout create the directory before submitting:
#   mkdir -p paper_1_transfer/hpc/logs
# =============================================================================
#SBATCH --job-name=les_rebuild_cmdstan
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=4G
#SBATCH --time=00:40:00
#SBATCH -o paper_1_transfer/hpc/logs/rebuild_cmdstan.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_1_transfer/hpc/logs

echo "Rebuilding CmdStan at ${CMDSTAN} on $(hostname) with ${SLURM_CPUS_PER_TASK} cores..."
Rscript -e 'cmdstanr::set_cmdstan_path(Sys.getenv("CMDSTAN")); cmdstanr::rebuild_cmdstan(cores = as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "4")))'

echo "=== re-running the environment check (compiles a trivial model) ==="
Rscript _shared/hpc/check_arc_env.R
echo "rebuild + check finished $(date)"
