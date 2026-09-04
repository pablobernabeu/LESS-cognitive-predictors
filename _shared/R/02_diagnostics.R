# =============================================================================
# 02_diagnostics.R  --  Shared convergence checks & posterior reporting helpers
# =============================================================================
#
# These helpers implement a single, citable standard for (a) verifying that each
# model has converged and (b) summarising posteriors for the manuscripts, so that
# Paper 1 and Paper 2 report results identically.
# =============================================================================

suppressPackageStartupMessages({
  library(brms)
  if (requireNamespace("posterior", quietly = TRUE))  library(posterior)
  if (requireNamespace("bayesplot", quietly = TRUE))  library(bayesplot)
})

# -----------------------------------------------------------------------------
# les_check_convergence()  --  hard pass/fail gate on the standard diagnostics
# -----------------------------------------------------------------------------
# A model is accepted only if ALL of the following hold (thresholds from
# Vehtari, Gelman, Simpson, Carpenter & Bürkner, 2021, Bayesian Analysis,
# https://doi.org/10.1214/20-BA1221):
#   * rank-normalised split-Rhat < 1.01 for every parameter,
#   * bulk-ESS and tail-ESS > 400 for every parameter (>= 100 per chain),
#   * zero divergent transitions after warmup (HMC/NUTS validity;
#     Betancourt, 2017, arXiv:1701.02434).
# The count of iterations saturating max_treedepth is reported in the table but is NOT
# part of the pass/fail flag. It is also unavailable in practice: the max_treedepth
# ceiling is looked up in an rstan-shaped slot of the fit object and comes back empty
# under the cmdstanr backend, so n_treedepth is NA in every row of the shipped
# results/_pooled_convergence.csv files for both papers.
# The function returns a one-row data frame and (optionally) saves it, so the
# whole grid of models can be screened programmatically before reporting.
les_check_convergence <- function(fit, label = NULL, save_to = NULL,
                                  rhat_max = 1.01, ess_min = 400) {

  draws <- posterior::as_draws_array(fit)
  sumy  <- posterior::summarise_draws(
    draws,
    rhat      = posterior::rhat,
    ess_bulk  = posterior::ess_bulk,
    ess_tail  = posterior::ess_tail
  )

  np <- brms::nuts_params(fit)
  n_divergent <- sum(np$Value[np$Parameter == "divergent__"], na.rm = TRUE)
  max_td      <- attr(fit$fit@sim$samples[[1]], "args")$control$max_treedepth
  td_hits     <- if ("treedepth__" %in% np$Parameter && !is.null(max_td)) {
    sum(np$Value[np$Parameter == "treedepth__"] >= max_td, na.rm = TRUE)
  } else NA_integer_

  out <- data.frame(
    model          = label %||% "unnamed",
    max_rhat       = max(sumy$rhat, na.rm = TRUE),
    min_ess_bulk   = min(sumy$ess_bulk, na.rm = TRUE),
    min_ess_tail   = min(sumy$ess_tail, na.rm = TRUE),
    n_divergent    = n_divergent,
    n_treedepth    = td_hits,
    passed         = NA,
    stringsAsFactors = FALSE
  )
  out$passed <- (out$max_rhat < rhat_max) &
                (out$min_ess_bulk > ess_min) &
                (out$min_ess_tail > ess_min) &
                (out$n_divergent == 0)

  if (!is.null(save_to)) saveRDS(out, save_to)
  out
}

# -----------------------------------------------------------------------------
# les_posterior_summary()  --  the table reported in the manuscripts
# -----------------------------------------------------------------------------
# For each population-level effect we report the posterior MEDIAN, the 95%
# credible interval (equal-tailed), and the PROBABILITY OF DIRECTION pd (the
# share of the posterior on the sign of the median). These Bayesian indices
# replace p-values and communicate both the magnitude and the certainty of an
# effect (Makowski, Ben-Shachar, Chen & Lüdecke, 2019, Front. Psychol.,
# https://doi.org/10.3389/fpsyg.2019.02767; Kruschke & Liddell, 2018,
# Psychon. Bull. Rev., https://doi.org/10.3758/s13423-016-1221-4).
les_posterior_summary <- function(fit, save_to = NULL, ci = 0.95) {

  draws <- posterior::as_draws_df(fit)
  b_cols <- grep("^b_", names(draws), value = TRUE)
  lo <- (1 - ci) / 2; hi <- 1 - lo

  tab <- do.call(rbind, lapply(b_cols, function(p) {
    x  <- draws[[p]]
    pd <- max(mean(x > 0), mean(x < 0))
    data.frame(
      parameter = sub("^b_", "", p),
      median    = stats::median(x),
      ci_low    = stats::quantile(x, lo, names = FALSE),
      ci_high   = stats::quantile(x, hi, names = FALSE),
      pd        = pd,
      stringsAsFactors = FALSE
    )
  }))
  rownames(tab) <- NULL
  if (!is.null(save_to)) saveRDS(tab, save_to)
  tab
}

# -----------------------------------------------------------------------------
# les_save_ppc()  --  posterior predictive check figure
# -----------------------------------------------------------------------------
# A density overlay of observed vs. replicated data is the standard graphical
# check that the model can reproduce the data it was fit to (Gabry, Simpson,
# Vehtari, Betancourt & Gelman, 2019, J. R. Stat. Soc. A,
# https://doi.org/10.1111/rssa.12378).
les_save_ppc <- function(fit, save_to, ndraws = 100, type = "dens_overlay") {
  # The default bayesplot scheme draws the y-rep draws in a pale blue that loses
  # contrast in print and greyscale; darken the scheme before drawing.
  old_scheme <- bayesplot::color_scheme_get()
  on.exit(bayesplot::color_scheme_set(old_scheme), add = TRUE)
  bayesplot::color_scheme_set("darkgray")
  p <- brms::pp_check(fit, ndraws = ndraws, type = type) +
    ggplot2::theme_minimal(base_size = 12)
  ggplot2::ggsave(save_to, p, width = 6, height = 4, dpi = 300)
  invisible(save_to)
}

# -----------------------------------------------------------------------------
# les_prior_predictive_check()  --  PRIOR predictive check figure
# -----------------------------------------------------------------------------
# Before trusting an informative prior we confirm it generates PLAUSIBLE data:
# refit the model with `sample_prior = "only"` (likelihood switched off) and
# overlay prior-predicted draws on the observed response. A prior implying, e.g.,
# impossible amplitudes or near-deterministic accuracies would reveal itself here.
# This is the prior-side analogue of les_save_ppc and a core step of a principled
# Bayesian workflow (Schad, Betancourt & Vasishth, 2021,
# https://doi.org/10.1037/met0000275; Gabry et al., 2019,
# https://doi.org/10.1111/rssa.12378).
# `x_lab` and `xlim` are arguments rather than hardcoded because this function serves two
# different model families: the ERP models (Gaussian, response in within-participant SD
# units) and the accuracy models (Bernoulli, called with type = "bars"). An amplitude axis
# label or a fixed amplitude range baked in here would mislabel the accuracy figure.
#
# `xlim` also does real work for the ERP case. The priors are deliberately wide relative to
# a standardised response, so unconstrained prior draws span roughly +/-30 SD. On that
# range the observed data collapse to a spike at zero and the panel becomes unreadable.
# Clipping the view to a stated range shows the comparison that matters. The figure then
# shows only that the priors generate data of a plausible order of magnitude. It is not a
# calibration check against the observed distribution.
#
# No in-image title: Quarto supplies the figure number and caption, so a title inside the
# panel duplicates it.
les_prior_predictive_check <- function(formula, data, family, prior, save_to,
                                       ndraws = 100, type = "dens_overlay",
                                       x_lab = NULL, xlim = NULL, base_size = 12) {
  backend <- if (exists(".les_backend")) .les_backend else "rstan"
  seed    <- if (exists("LES_SEED")) LES_SEED else 1L
  fit_prior <- brms::brm(
    formula = formula, data = data, family = family, prior = prior,
    sample_prior = "only",
    # A short run is enough here. The panel is read as an order-of-magnitude check (see
    # above) rather than as inference, so it does not need the shared LES_CHAINS and
    # LES_ITER_* configuration used for the reported fits.
    chains = 2L, iter = 1000L, warmup = 500L, refresh = 0,
    seed = seed, backend = backend
  )
  # As in les_save_ppc: the pale default y-rep colour has too little contrast in
  # print, so the scheme is darkened before the plot is built.
  old_scheme <- bayesplot::color_scheme_get()
  on.exit(bayesplot::color_scheme_set(old_scheme), add = TRUE)
  bayesplot::color_scheme_set("darkgray")
  p <- brms::pp_check(fit_prior, ndraws = ndraws, type = type) +
       ggplot2::labs(x = x_lab, y = "Density", title = NULL) +
       ggplot2::theme_minimal(base_size = base_size)
  if (!is.null(xlim)) p <- p + ggplot2::coord_cartesian(xlim = xlim)
  ggplot2::ggsave(save_to, p, width = 6, height = 3.6, dpi = 600)
  invisible(save_to)
}

# -----------------------------------------------------------------------------
# les_prior_sensitivity()  --  informative vs weakly-informative posterior shift
# -----------------------------------------------------------------------------
# Quantifies how far the informative priors move the posterior relative to the
# weakly-informative baseline, per population-level effect: the median shift and
# the two CI widths. Small shifts on the TESTED effects demonstrate the
# conclusions are not prior-driven (Depaoli & van de Schoot, 2017,
# https://doi.org/10.1037/met0000065). Requires the pipeline to have been run once
# normally and once with LES_PRIOR_SET=weak (which writes the `*_weakprior_*` files).
# `weak_id` defaults to the informative id with "_weakprior" appended, which is the
# naming the pipeline produces for the base structure. It is an explicit argument
# because the tags COMPOSE: the maximal by-item variant is cached as
# "<cell>_weakprior_itemslope", not "<cell>_itemslope_weakprior", so a caller comparing
# that structure must pass the weak id rather than let it be derived.
les_prior_sensitivity <- function(results_dir, model_id,
                                  weak_id = paste0(model_id, "_weakprior")) {
  inf_path  <- file.path(results_dir, paste0(model_id, "_summary.rds"))
  weak_path <- file.path(results_dir, paste0(weak_id,  "_summary.rds"))
  if (!file.exists(inf_path) || !file.exists(weak_path)) {
    stop("Need both '", basename(inf_path), "' and '", basename(weak_path),
         "'. Run the pipeline once normally and once with LES_PRIOR_SET=weak.")
  }
  inf  <- readRDS(inf_path)
  weak <- readRDS(weak_path)
  m <- merge(inf, weak, by = "parameter", suffixes = c("_inf", "_weak"))
  m$median_shift  <- m$median_inf  - m$median_weak
  m$ci_width_inf  <- m$ci_high_inf  - m$ci_low_inf
  m$ci_width_weak <- m$ci_high_weak - m$ci_low_weak
  m[order(-abs(m$median_shift)), , drop = FALSE]
}

# small null-coalescing helper
`%||%` <- function(a, b) if (is.null(a)) b else a
