#!/bin/bash
# =============================================================================
# submit_all.sh  --  submit the Paper 2 Bayesian pipeline with SLURM afterok chaining.
# -----------------------------------------------------------------------------
# Stage graph:
#   01 extract cognitive --\
#   02 extract trajectory --+--> 04 fit Part A (predictive) --\
#   03 extract rs-EEG [opt]/      01 ----------> 05 fit Part B -+--> 06 summaries
#
# 03 (resting-state EEG) is NOT a hard dependency of the core path: 04/05 fit the
# cognitive-only models when resting_state_eeg.rds is absent, and include the Session-2
# rs-EEG baseline predictors when it is present. To include rs-EEG, make sure 03 finishes
# before 04/05 (or just re-run 04/05 after 03). Part B's rs-EEG pre/post skips either
# way -- there is no Session-6 resting-state recording to pair with Session 2.
#
# Usage:
#   bash paper_2_plasticity/hpc/submit_all.sh                # assumes deps present
#   bash paper_2_plasticity/hpc/submit_all.sh with_restore   # restore the pinned
#                                                            # environment first
#   bash paper_2_plasticity/hpc/submit_all.sh with_install   # bootstrap an unpinned
#                                                            # library first
#
# `with_restore` chains the pipeline on _shared/hpc/00_restore_environment.slurm, which
# runs renv::restore() against renv.lock and installs the pinned CmdStan; it is the
# reproduction route. `with_install` chains on 00_install_dependencies.slurm, which
# bootstraps a library from CRAN where none exists and pins nothing.
# =============================================================================
set -o errexit
set -o nounset

HPC_DIR="paper_2_plasticity/hpc"
mkdir -p "${HPC_DIR}/logs"
submit() { sbatch --parsable "$@"; }

DEP_INSTALL=""
if [[ "${1:-}" == "with_restore" ]]; then
  JID_INSTALL=$(submit "_shared/hpc/00_restore_environment.slurm")
  echo "00 restore environment  : ${JID_INSTALL}"
  DEP_INSTALL="--dependency=afterok:${JID_INSTALL}"
elif [[ "${1:-}" == "with_install" ]]; then
  JID_INSTALL=$(submit "${HPC_DIR}/00_install_dependencies.slurm")
  echo "00 install dependencies : ${JID_INSTALL}"
  DEP_INSTALL="--dependency=afterok:${JID_INSTALL}"
fi

JID_COG=$(submit ${DEP_INSTALL} "${HPC_DIR}/01_extract_cognitive.slurm")
echo "01 extract cognitive    : ${JID_COG}"
# 02 reads 01's cognitive_indices.rds (baseline cognition), so it must wait for 01.
JID_TRAJ=$(submit --dependency=afterok:${JID_COG} "${HPC_DIR}/02_extract_trajectory.slurm")
echo "02 extract trajectory   : ${JID_TRAJ}"
JID_EEG=$(submit ${DEP_INSTALL} "${HPC_DIR}/03_extract_rseeg.slurm")
echo "03 extract rs-EEG       : ${JID_EEG}  (optional; local Session-2 recordings, base R)"

JID_FITA=$(submit --dependency=afterok:${JID_COG}:${JID_TRAJ} "${HPC_DIR}/04_fit_predictors.slurm")
echo "04 fit Part A           : ${JID_FITA}"
JID_FITB=$(submit --dependency=afterok:${JID_COG} "${HPC_DIR}/05_fit_prepost.slurm")
echo "05 fit Part B           : ${JID_FITB}"
JID_SUM=$(submit --dependency=afterok:${JID_FITA}:${JID_FITB} "${HPC_DIR}/06_summaries.slurm")
echo "06 summaries            : ${JID_SUM}"

echo
echo "All jobs queued. Track with:  squeue -u \$USER"
