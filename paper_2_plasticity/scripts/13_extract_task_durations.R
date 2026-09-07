# paper_2_plasticity/scripts/13_extract_task_durations.R
# Observed participant-level durations for the home tasks and lab-session phases.
# The artefacts are shared with Paper 1 because the two manuscripts describe the same
# study cohort and session protocol.

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "03_data_manifest.R"))
  source(here::here("_shared", "R", "07_task_durations.R"))
  library(dplyr)
  library(readr)
})

les_write_task_duration_artifacts()
