# =============================================================================
# _shared/hpc/check_arc_env.R  --  one-shot sanity check of the ARC environment
# -----------------------------------------------------------------------------
# Prints, after `source _shared/hpc/arc_env.sh`, where the project paths resolve, which
# library R is using, and whether the (relocated) CmdStan toolchain really does compile
# and sample a trivial model.
#
# Read the lines, not only the verdict. The closing PASS/FAIL covers the Stan compile
# alone. The path and package lines above it are printed for the reader and do not feed
# into it, so a run with a missing data tree can still end in PASS.
#
# Run it by hand, or through _shared/hpc/rebuild_cmdstan.slurm, which calls it after
# rebuilding CmdStan. Prefer a compute node: the Stan compile is memory-hungry and
# login nodes cap `ulimit -v` (paper_1_transfer/hpc/99_diagnose_ice.slurm records the
# 2 GB cap).
#   Rscript _shared/hpc/check_arc_env.R
# =============================================================================
suppressMessages({
  .codeRoot <- Sys.getenv("LES_CODE_ROOT", unset = getwd())
  source(file.path(.codeRoot, "_shared", "R", "00_paths.R"))
  source(file.path(.codeRoot, "_shared", "R", "03_data_manifest.R"))  # participant_key_csv(), etc.
})
ok <- TRUE
say <- function(label, val) cat(sprintf("  %-28s %s\n", label, val))

cat("== env ==\n")
say("LES_DATA_ROOT", Sys.getenv("LES_DATA_ROOT"))
say("LES_STORE",     Sys.getenv("LES_STORE"))
say(".libPaths()[1]", .libPaths()[1])

cat("== data (read-only inputs resolve under new_LESS/data) ==\n")
say("raw data/EEG",               dir.exists(data_path("raw data", "EEG")))
say("raw data/executive functions", dir.exists(data_path("raw data", "executive functions")))
say("participant key",            file.exists(participant_key_csv()))

# The path helpers create their directory on demand (.ensure_dir in _shared/R/00_paths.R),
# so the two lines below establish that the store resolves and can be created. They are
# not a permissions test: nothing is written and no file is removed.
cat("== output store writable ==\n")
say("paper1_results()", { d <- paper1_results(); dir.exists(d) })
say("paper2_derived()", { d <- paper2_derived(); dir.exists(d) })

cat("== packages ==\n")
suppressMessages(library(brms));     say("brms", as.character(packageVersion("brms")))
suppressMessages(library(cmdstanr))
say("cmdstan_path",    tryCatch(cmdstanr::cmdstan_path(),                       error = function(e) paste("ERR", conditionMessage(e))))
say("cmdstan_version", tryCatch(as.character(cmdstanr::cmdstan_version()),      error = function(e) "ERR"))
say("eegUtils (opt.)", if (requireNamespace("eegUtils", quietly = TRUE)) as.character(packageVersion("eegUtils")) else "MISSING")

cat("== compile + sample a trivial Stan model (proves the relocated toolchain) ==\n")
res <- tryCatch({
  f <- cmdstanr::write_stan_file("parameters { real y; } model { y ~ normal(0, 1); }")
  m <- cmdstanr::cmdstan_model(f)
  s <- m$sample(chains = 1, iter_warmup = 100, iter_sampling = 100, refresh = 0, show_messages = FALSE)
  sprintf("OK (mean y = %.3f)", mean(s$draws("y")))
}, error = function(e) { ok <<- FALSE; paste("FAILED:", conditionMessage(e)) })
say("tiny cmdstan fit", res)

cat(if (ok) "\n[check_arc_env] PASS\n" else "\n[check_arc_env] FAIL\n")
