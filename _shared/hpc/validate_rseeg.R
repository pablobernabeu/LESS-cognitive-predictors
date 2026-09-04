# =============================================================================
# _shared/hpc/validate_rseeg.R  --  sanity-check the resting-state EEG extraction
# -----------------------------------------------------------------------------
# INPUT   paper2_derived("resting_state_eeg.rds"), written by
#         paper_2_plasticity/scripts/03_extract_resting_state_eeg.R: one row per
#         participant x condition with posterior band power (delta/theta/alpha/beta/
#         gamma, absolute power in the units of the exported signal) and the individual
#         alpha frequency (IAF, in Hz).
#
# USAGE   Rscript _shared/hpc/validate_rseeg.R
#         Run after script 03. It is not wired into
#         paper_2_plasticity/hpc/03_extract_rseeg.slurm, so it has to be invoked
#         separately. Exits with status 1 if the .rds is absent, otherwise 0.
#
# PRINTS  the table dimensions and coverage, mean band power and IAF by condition, the
#         eyes-closed IAF distribution, and the eyes-open/eyes-closed alpha comparison.
#
# WHAT A PASS LOOKS LIKE. Two physiological expectations. The script asserts neither of
# them, so read the printed numbers and judge.
#   * Berger effect: mean posterior alpha should be higher eyes-closed than eyes-open.
#     If it is not, suspect the channel labels or the eyes-open/closed file naming
#     before suspecting the PSD.
#   * Eyes-closed IAF should fall in 8-13 Hz for most participants. Three recordings sit
#     at the 7 Hz edge of the search window, which is expected and is discussed at
#     les_iaf() in script 03. A majority sitting there would need investigating.
# =============================================================================
suppressPackageStartupMessages(source(here::here("_shared", "R", "00_paths.R")))
p <- paper2_derived("resting_state_eeg.rds")
if (!file.exists(p)) { cat("FAIL: resting_state_eeg.rds not written\n"); quit(status = 1) }
d <- readRDS(p)
cat("rows:", nrow(d), "| participants:", length(unique(d$participant_lab_ID)),
    "| sessions:", paste(sort(unique(d$session)), collapse = ","),
    "| conditions:", paste(sort(unique(d$condition)), collapse = ","), "\n")
agg <- aggregate(cbind(delta, theta, alpha, beta, gamma, iaf) ~ condition, d,
                 function(x) round(mean(x, na.rm = TRUE), 3))
cat("-- mean band power + IAF by condition --\n"); print(agg)
ec <- d[d$condition == "eyes_closed", ]
cat(sprintf("IAF eyes-closed: median %.2f Hz, range %.2f-%.2f, in 8-13 Hz: %d/%d\n",
            median(ec$iaf, na.rm = TRUE), min(ec$iaf, na.rm = TRUE), max(ec$iaf, na.rm = TRUE),
            sum(ec$iaf >= 8 & ec$iaf <= 13, na.rm = TRUE), sum(!is.na(ec$iaf))))
cat(sprintf("Berger check  : posterior alpha closed=%.3f vs open=%.3f  (closed should be higher)\n",
            mean(ec$alpha, na.rm = TRUE), mean(d$alpha[d$condition == "eyes_open"], na.rm = TRUE)))
cat("rows with any NA band power:", sum(!stats::complete.cases(d[, c("delta", "theta", "alpha", "beta", "gamma")])), "\n")
