# =============================================================================
# 00_paths.R  --  Portable, project-anchored paths for the two-paper workspace
# =============================================================================
#
# PURPOSE
# -------
# This helper makes every script in `paper_1_transfer/` and `paper_2_plasticity/`
# runnable on any machine, regardless of the directory the user starts R in. It
# is the single mechanism that replaces the hard-coded container paths
# (e.g. "/mnt/less_data/analyses/results/...") and the inconsistent relative
# paths ("Raw data/" vs. "data/raw data/") found in the legacy scripts, both of
# which break a clean-machine, cross-platform run.
#
# WHY ANCHOR TO THE PROJECT ROOT WITH `here`?
# -------------------------------------------
# `here::here()` locates the project root by searching upwards for a sentinel
# file (here, "LESS Project.Rproj") and builds every path relative to it. This is
# the recommended pattern for reproducible, portable research compendia
# (Marwick, Boettiger & Mullen, 2018, The American Statistician,
#  https://doi.org/10.1080/00031305.2017.1375986; project-oriented workflow,
#  Bryan, 2017, https://www.tidyverse.org/blog/2017/12/workflow-vs-script/).
#
# WHY ALSO `setwd(here::here())`?
# -------------------------------
# The established data-loading functions under `data/R_functions/` and
# `data/importation and preprocessing/` address files with paths relative to the
# PROJECT ROOT (e.g. read.csv("data/Participant IDs and session progress.csv")).
# To reuse that validated code *without modifying it* (a non-destructive
# requirement of this project), we anchor the session's working directory at the
# root exactly once. After this call, both (a) the legacy root-relative paths and
# (b) our own `here::here()` calls resolve correctly from any starting location.
# =============================================================================

# --- Require `here` ---------------------------------------------------------------
# `here` is pinned in renv.lock and listed in _shared/install_bayesian_dependencies.R, so
# on a correctly restored environment this check never fires. A missing package stops the
# run with the instruction to restore the environment, so the recorded environment is the
# one the lockfile describes. Installing it on the spot would take whatever CRAN shipped
# that day, unpinned and over the network from inside a batch job, and would silently
# change the environment the run then recorded.
if (!requireNamespace("here", quietly = TRUE)) {
  stop("Package 'here' is not installed. Restore the pinned environment first ",
       "(renv::restore() from the project root, or on the cluster ",
       "_shared/hpc/00_restore_environment.slurm), so that the run uses the recorded ",
       "package versions.", call. = FALSE)
}

# --- Anchor the project root ----------------------------------------------------
# `here::here()` locates the root by searching upwards for the "LESS Project.Rproj"
# sentinel. The tryCatch is a last-resort fallback to the working directory, so that
# sourcing this file can never itself abort a run on a machine where the sentinel is
# missing. The announcement at the foot of this file makes the resolved root visible in
# the log either way.
.les_root <- tryCatch(
  here::here(),
  error = function(e) normalizePath(getwd(), winslash = "/", mustWork = FALSE)
)

# Bridge for the legacy root-relative loaders (see header for rationale).
setwd(.les_root)

# --- Heavy-store / data-root resolution (ARC cluster vs. dev box) --------------
# Core scripts live on the user's PERSONAL DISK (the code root anchored above),
# but the HEAVY material -- the read-only input data and ALL model outputs -- can
# be redirected to a separate, larger filesystem (the ARC project /data space)
# via two environment variables. On the dev box neither is set, so everything
# stays in a single self-contained tree (behaviour unchanged). On the cluster the
# job scripts (see _shared/hpc/arc_env.sh, which defines LES_BASE) export:
#     LES_DATA_ROOT = $LES_BASE/data    (read-only inputs)
#     LES_STORE     = $LES_BASE/store   (derived data, results, figures)
# so the personal disk only ever holds code -- never gigabytes of data or fits.
.les_data_root <- Sys.getenv("LES_DATA_ROOT", unset = here::here("data"))
.les_store     <- Sys.getenv("LES_STORE",     unset = .les_root)

# =============================================================================
# Path helpers
# =============================================================================
# Paths are anchored at the project root, or at LES_DATA_ROOT / LES_STORE when those are
# set. The six output helpers (paper{1,2}_figures, _results and _derived) create their
# directory on demand, so no script needs to pre-create folders. The read-only data helper
# and the source-tree helpers only build a path.

# Shared, read-only data root (never written to by the paper pipelines).
# Root is LES_DATA_ROOT when set (ARC project space), else <project>/data.
data_path <- function(...) file.path(.les_data_root, ...)

# Paper 1 (morphosyntactic transfer) sub-trees -----------------------------------
paper1_path        <- function(...) here::here("paper_1_transfer", ...)
paper1_scripts     <- function(...) here::here("paper_1_transfer", "scripts", ...)
paper1_figures     <- function(...) {
  .ensure_dir(file.path(.les_store, "paper_1_transfer", "figures", ...))
}
paper1_results     <- function(...) {
  .ensure_dir(file.path(.les_store, "paper_1_transfer", "results", ...))
}
paper1_derived     <- function(...) {
  .ensure_dir(file.path(.les_store, "paper_1_transfer", "data_derived", ...))
}

# Paper 2 (neuroplasticity) sub-trees -------------------------------------------
paper2_path        <- function(...) here::here("paper_2_plasticity", ...)
paper2_scripts     <- function(...) here::here("paper_2_plasticity", "scripts", ...)
paper2_figures     <- function(...) {
  .ensure_dir(file.path(.les_store, "paper_2_plasticity", "figures", ...))
}
paper2_results     <- function(...) {
  .ensure_dir(file.path(.les_store, "paper_2_plasticity", "results", ...))
}
paper2_derived     <- function(...) {
  .ensure_dir(file.path(.les_store, "paper_2_plasticity", "data_derived", ...))
}

# Shared helpers -----------------------------------------------------------------
shared_path        <- function(...) here::here("_shared", ...)

# --- internal: create a directory (recursively) for a path and return it --------
# When the path looks like a file (has an extension) we create its PARENT folder;
# otherwise we treat the path itself as a directory to create.
.ensure_dir <- function(p) {
  if (length(p) == 0) return(p)
  looks_like_file <- grepl("\\.[A-Za-z0-9]+$", basename(p))
  target_dir <- if (looks_like_file) dirname(p) else p
  if (!dir.exists(target_dir)) dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
  p
}

# --- Announce the anchor so logs/.Rout files are self-documenting ---------------
cat("[paths] Project root anchored at:", .les_root, "\n")
cat("[paths] data root:", .les_data_root, "| output store:", .les_store, "\n")
