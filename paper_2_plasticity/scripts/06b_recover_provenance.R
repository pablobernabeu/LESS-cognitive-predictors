# =============================================================================
# 06b_recover_provenance.R  --  Recover the fit-time environment record for Paper 2
# =============================================================================
#
# WHAT THIS IS FOR
# ----------------
# results/_provenance.csv is written by 04_fit_brms_predictors.R at fit time, through
# les_write_provenance() in _shared/R/04_provenance.R, and the manuscript injects its
# version fields inline. The Part A fits reported in the manuscript were produced before
# that mechanism existed, and no later run of script 04 has completed against them, so
# the file is absent and the manuscript prints "pending" in place of every version. This
# script recovers the record from what the fitted objects themselves carry, so that the
# manuscript can report the environment that actually produced them.
#
# WHERE EACH VERSION COMES FROM
# -----------------------------
#   * brms stamps every brmsfit with the versions of brms, rstan, StanHeaders, cmdstanr
#     and CmdStan in force when the object was created (the $version element). Those are
#     fit-time values by construction and are taken from the fits.
#   * The R version is read from the serialisation header of each fitted object's .rds
#     file, which records the R version that wrote it.
#   * projpred, loo, posterior and bayesplot leave no stamp in a brmsfit. Their versions
#     are read from the project library the job runs under, which is the pinned library
#     the fits were produced from (renv.lock), and each such row is marked as read from
#     the library.
# Every row carries a `source` column saying which of the three it is, and a
# `record_source` row says the file was recovered. The manuscript reads that row and
# describes the record accordingly. The next completed run of script 04 overwrites this
# file with a record written at fit time, which is the intended end state.
#
# The script reads the fitted objects and writes one CSV. It refits nothing and changes
# no other artefact. Opt-in: nothing in the pipeline calls it.
#
# USAGE (HPC)
#   sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/06b_recover_provenance.slurm
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "04_provenance.R"))   # LES_PROVENANCE_PKGS
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
})

# The fits whose environment the manuscript reports: the Part A reference models and
# their gender-only and aperiodic variants, in LES_P2_MODELS.
.les_prov_models <- unname(LES_P2_MODELS[c("predictive", "predictive_gender",
                                           "predictive_aperiodic",
                                           "predictive_aperiodic_gender")])

# R version stamped in an .rds serialisation header. The header is "X\n" followed by
# three big-endian integers: the serialisation format, the writing R version and the
# minimal reading R version, each packed as major * 65536 + minor * 256 + patch.
.les_rds_r_version <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  magic <- readBin(con, "raw", n = 2L)
  if (!identical(rawToChar(magic), "X\n")) return(NA_character_)
  ints <- readBin(con, "integer", n = 3L, size = 4L, endian = "big")
  v <- ints[2]
  sprintf("%d.%d.%d", v %/% 65536L, (v %/% 256L) %% 256L, v %% 256L)
}

# brms's own version stamp, as component/version rows. The element names differ across
# brms releases (stanHeaders/StanHeaders, cmdstan/CmdStan), so they are normalised here to
# the component names les_write_provenance() uses.
.les_fit_version_rows <- function(fit) {
  v <- fit$version
  if (is.null(v)) return(NULL)
  nm_map <- c(brms = "brms", rstan = "rstan", stanheaders = "StanHeaders",
              cmdstanr = "cmdstanr", cmdstan = "CmdStan")
  rows <- lapply(names(v), function(n) {
    comp <- nm_map[tolower(n)]
    if (is.na(comp)) return(NULL)
    data.frame(component = unname(comp), version = as.character(v[[n]]),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, Filter(Negate(is.null), rows))
}

les_recover_provenance <- function(models = .les_prov_models) {
  # One call per model: the path helper creates directories on demand and takes a
  # single path, so it is not vectorised.
  paths <- vapply(models, function(m) paper2_results(paste0(m, ".rds")), character(1))
  have  <- file.exists(paths)
  if (!any(have)) stop("[provenance] none of the fitted objects is present: ",
                       paste(basename(paths), collapse = ", "))
  paths <- paths[have]; models <- models[have]

  stamps <- list(); r_vers <- character(0); mtimes <- character(0)
  for (i in seq_along(paths)) {
    message("[provenance] reading ", basename(paths[i]))
    r_vers[i] <- .les_rds_r_version(paths[i])
    mtimes[i] <- format(file.info(paths[i])$mtime, tz = "UTC", usetz = TRUE)
    fit <- readRDS(paths[i])
    stamps[[models[i]]] <- .les_fit_version_rows(fit)
    rm(fit); invisible(gc())
  }

  # The fits must agree with one another on every stamped version, or the record would
  # describe an environment none of them came from. Disagreement stops the run so it can
  # be looked at, which is preferable to a silently averaged record.
  st <- do.call(rbind, Map(function(m, d) { d$model <- m; d }, names(stamps), stamps))
  agg <- aggregate(version ~ component, data = st,
                   FUN = function(x) paste(sort(unique(x)), collapse = " | "))
  bad <- agg[grepl(" | ", agg$version, fixed = TRUE), , drop = FALSE]
  if (nrow(bad)) stop("[provenance] the fitted objects disagree on: ",
                      paste(sprintf("%s = %s", bad$component, bad$version), collapse = "; "))
  r_agree <- unique(r_vers[!is.na(r_vers)])
  if (length(r_agree) > 1) stop("[provenance] the fitted objects were written by ",
                                "different R versions: ", paste(r_agree, collapse = ", "))

  from_fits <- data.frame(component = c("R", agg$component),
                          version   = c(if (length(r_agree)) r_agree else NA_character_,
                                        agg$version),
                          source    = "fitted object", stringsAsFactors = FALSE)
  from_fits <- from_fits[!is.na(from_fits$version), , drop = FALSE]

  # Packages that leave no stamp: read from the pinned project library the job runs under.
  unstamped <- setdiff(LES_PROVENANCE_PKGS, from_fits$component)
  from_lib <- do.call(rbind, lapply(unstamped, function(p) {
    v <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
    if (is.na(v)) NULL else data.frame(component = p, version = v,
                                       source = "project library", stringsAsFactors = FALSE)
  }))

  meta <- data.frame(
    component = c("platform", "seed:LES_SEED", "record_source", "fits_written_utc",
                  "fits_recorded"),
    version   = c(R.version$platform, as.character(LES_SEED),
                  "recovered from the fitted objects; see 06b_recover_provenance.R",
                  paste(range(mtimes), collapse = " to "),
                  paste(models, collapse = "; ")),
    source    = c("job environment", "shared settings", "this script", "file system",
                  "this script"),
    stringsAsFactors = FALSE)

  out <- rbind(from_fits, from_lib, meta)
  out$recorded_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  f <- paper2_results("_provenance.csv")
  if (exists("les_assert_readonly_data")) les_assert_readonly_data(f)
  utils::write.csv(out, f, row.names = FALSE)
  message("[provenance] wrote ", nrow(out), " rows to ", f)
  invisible(out)
}

if (sys.nframe() == 0L) {
  suppressPackageStartupMessages(source(here::here("_shared", "R", "01_bayesian_settings.R")))  # LES_SEED
  les_recover_provenance()
}
