# =============================================================================
# 05_funnel.R  --  Shared participant-flow ("funnel") figure generator
# =============================================================================
#
# Both manuscripts report participant flow, but they draw on DIFFERENT stages of
# the same cohort: Paper 1 uses the four EEG sessions and its ERP/judgement samples,
# Paper 2 uses the Session-1 and Session-5 cognitive battery, the Session-2
# resting-state recording, and the learning trajectory. A single shared figure would
# therefore show each paper stages it does not use -- which is exactly the defect the
# methods audit found in Paper 1's original flow diagram, where four Paper 2 stages
# were rendered into Paper 1's chain. The generator is shared so the two figures are
# visually identical; the CONTENT is paper-specific.
#
# DESIGN
# Each stage spans the full width of the panel. The retained participants are drawn solid
# and centred, and the participants no longer present are drawn as a faint "ghost"
# completing the bar to full cohort width. The reasons for drawing it this way:
#   * cumulative attrition is legible as filled-versus-faint area, without the
#     reader having to compare bar lengths across the figure;
#   * every bar is the same width, so a stage label can never overflow its bar,
#     the failure mode of a plain width-proportional funnel;
#   * a tapering ribbon can be drawn between consecutive stages, which carries the
#     eye down the funnel and makes each drop a visible narrowing.
# Where a stage records the mini-language split, the retained portion is divided by
# language, so the reader can see whether attrition fell evenly on the two groups, which
# the counts alone do not show.
#
# WHY THE TIERS ARE SEPARATED
# The stages are NOT strictly nested, so the figure must not imply subsetting:
#   * attendance is not monotonic -- at least one participant missed a session and
#     returned for a later one, so "attended S6" is not a subset of "attended S5";
#   * the analysis samples are drawn from the whole cohort across sessions, not from
#     the final session, so they can exceed the last attendance bar.
# Stages are therefore grouped into tiers, and ribbons are drawn only WITHIN a tier,
# where the subset relation genuinely holds.
# =============================================================================

# INPUTS AND OUTPUT
# `d` needs: label (character), n (integer), tier (character/factor).
# Optional: n_a / n_b (group split of n), `note`.
# `base_size` is the ggplot base font size, and every text size in the figure is derived
# from it. `group_labs` names the two mini-language groups, in the legend and in the split
# fill. `cols` overrides the two group colours, which otherwise come from depictr.
# `ghost` and `ghost_edge` are the fill and outline of the faint remainder block.
# `tier_gap` is the vertical space left between tiers, in stage-row units, where one stage
# occupies one unit. `show_loss` toggles the "-n  x% kept" annotations to the right of
# each within-tier drop. `show_legend` can suppress the legend even where the split is
# recorded, and the legend is dropped automatically when no stage records one.
# Returns a ggplot object. Both manuscripts call it as les_funnel(d, base_size = 9), in
# paper_1_transfer/paper_1_morphosyntax.qmd and
# paper_2_plasticity/paper_2_neuroplasticity.qmd.
les_funnel <- function(d, base_size = 9,
                       group_labs = c("Mini-English", "Mini-Norwegian"),
                       cols = NULL, ghost = "grey93", ghost_edge = "grey85",
                       tier_gap = 1.05, show_loss = TRUE, show_legend = TRUE) {
  stopifnot(all(c("label", "n", "tier") %in% names(d)))
  d <- d[!is.na(d$n), , drop = FALSE]
  if (!nrow(d)) return(ggplot2::ggplot() + ggplot2::theme_void())

  if (is.null(cols)) {
    # The literal fallback is depictr's first two qualitative colours, so the figure comes
    # out the same whether or not the package is installed.
    cols <- if (requireNamespace("depictr", quietly = TRUE))
      depictr::depictr_palette(3, "qualitative")[1:2] else c("#005b96", "#e69f00")
  }
  has_split <- all(c("n_a", "n_b") %in% names(d)) && any(!is.na(d$n_a))

  d$tier <- factor(d$tier, levels = unique(d$tier))
  has_note <- if ("note" %in% names(d)) !is.na(d$note) & nzchar(d$note) else rep(FALSE, nrow(d))
  nlines <- function(s) if (is.na(s) || !nzchar(s)) 0 else
    lengths(regmatches(s, gregexpr("\n", s))) + 1

  # Row layout: one unit per stage, extra room under a stage that carries a note,
  # and a gap between tiers for the tier heading and its rule.
  d$row <- NA_real_
  y <- 0; tiers <- levels(d$tier)
  for (ti in seq_along(tiers)) {
    ix <- which(d$tier == tiers[ti])
    for (k in seq_along(ix)) {
      y <- y - 1
      d$row[ix[k]] <- y
      if (has_note[ix[k]]) y <- y - (0.18 + 0.15 * nlines(d$note[ix[k]]))
    }
    if (ti < length(tiers)) y <- y - tier_gap
  }

  W    <- 0.50                              # half-width of the full cohort
  wmax <- max(d$n, na.rm = TRUE)
  d$half   <- W * d$n / wmax
  d$bar_t  <- d$row - 0.06
  d$bar_b  <- d$row - 0.44
  d$lab_y  <- d$row + 0.17

  # Retained block, split by group where available.
  # A stage that does not record the split must NOT be drawn in a language colour:
  # filling it with the first group's colour would assert that every one of its
  # participants belonged to that group. Such stages get a neutral fill, kept out of
  # the legend, so the figure says only what the data say.
  UNSPLIT <- "(not recorded by language)"
  split_ok <- if (has_split) !is.na(d$n_a) & !is.na(d$n_b) else rep(FALSE, nrow(d))
  blocks <- NULL
  if (any(split_ok)) {
    s <- d[split_ok, , drop = FALSE]
    tot <- pmax(s$n_a + s$n_b, 1)
    mid <- -s$half + 2 * s$half * (s$n_a / tot)
    blocks <- rbind(
      data.frame(xmin = -s$half, xmax = mid,    ymin = s$bar_b, ymax = s$bar_t,
                 grp = group_labs[1], stringsAsFactors = FALSE),
      data.frame(xmin = mid,     xmax = s$half, ymin = s$bar_b, ymax = s$bar_t,
                 grp = group_labs[2], stringsAsFactors = FALSE))
  }
  if (any(!split_ok)) {
    u <- d[!split_ok, , drop = FALSE]
    blocks <- rbind(blocks,
      data.frame(xmin = -u$half, xmax = u$half, ymin = u$bar_b, ymax = u$bar_t,
                 grp = UNSPLIT, stringsAsFactors = FALSE))
  }
  blocks <- blocks[blocks$xmax > blocks$xmin, , drop = FALSE]

  # Ghost remainder: what the cohort would fill if nobody had been lost.
  gh <- rbind(
    data.frame(xmin = -W, xmax = -d$half, ymin = d$bar_b, ymax = d$bar_t),
    data.frame(xmin = d$half, xmax = W,   ymin = d$bar_b, ymax = d$bar_t))
  gh <- gh[gh$xmax - gh$xmin > 1e-9, , drop = FALSE]

  # Tapering ribbons between consecutive stages within a tier.
  rib <- NULL; seg <- NULL
  parts <- lapply(tiers, function(tg) {
    s <- d[d$tier == tg, , drop = FALSE]
    if (nrow(s) < 2) return(NULL)
    s <- s[order(-s$row), ]
    do.call(rbind, lapply(seq_len(nrow(s) - 1), function(i) {
      a <- s[i, ]; b <- s[i + 1, ]
      data.frame(
        id = paste(tg, i),
        x  = c(-a$half, a$half, b$half, -b$half),
        yv = c(a$bar_b, a$bar_b, b$bar_t, b$bar_t),
        stringsAsFactors = FALSE)
    }))
  })
  rib <- do.call(rbind, Filter(Negate(is.null), parts))

  if (show_loss) {
    lp <- lapply(tiers, function(tg) {
      s <- d[d$tier == tg, , drop = FALSE]
      if (nrow(s) < 2) return(NULL)
      s <- s[order(-s$row), ]
      data.frame(y = (utils::head(s$bar_b, -1) + utils::tail(s$bar_t, -1)) / 2,
                 lost = utils::head(s$n, -1) - utils::tail(s$n, -1),
                 kept = utils::tail(s$n, -1) / utils::head(s$n, -1))
    })
    seg <- do.call(rbind, Filter(Negate(is.null), lp))
    if (!is.null(seg)) seg <- seg[seg$lost > 0, , drop = FALSE]
  }

  lab <- function(i) {
    s <- sprintf("%s   n = %d", d$label[i], d$n[i])
    if (has_split && !is.na(d$n_a[i]) && !is.na(d$n_b[i]))
      s <- sprintf("%s  (%d / %d)", s, d$n_a[i], d$n_b[i])
    s
  }
  d$text <- vapply(seq_len(nrow(d)), lab, character(1))

  heads <- do.call(rbind, lapply(tiers, function(tg) {
    s <- d[d$tier == tg, , drop = FALSE]
    data.frame(tier = tg, y = max(s$row) + 0.60, stringsAsFactors = FALSE)
  }))

  p <- ggplot2::ggplot()
  # The connector is deliberately very light. At a heavier tone it merges with the
  # ghost blocks into one continuous grey field, and the funnel stops reading as a
  # sequence of stages.
  if (!is.null(rib) && nrow(rib))
    p <- p + ggplot2::geom_polygon(data = rib,
                                   ggplot2::aes(x = x, y = yv, group = id),
                                   fill = "grey96", colour = NA)
  if (nrow(gh))
    p <- p + ggplot2::geom_rect(data = gh,
                                ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
                                fill = ghost, colour = ghost_edge, linewidth = 0.2)
  p <- p +
    ggplot2::geom_rect(data = blocks,
                       ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = grp),
                       colour = "white", linewidth = 0.35) +
    # A label rather than plain text: the connector passes behind the caption, so the
    # white ground punches the text out of it and keeps each caption tied to the bar
    # beneath it rather than floating on the band above.
    ggplot2::geom_label(data = d, ggplot2::aes(x = 0, y = lab_y, label = text),
                        size = base_size / 3.05, colour = "grey12",
                        fill = "white", label.r = ggplot2::unit(0, "pt"),
                        label.padding = ggplot2::unit(1.1, "pt"), linewidth = 0)

  if (!is.null(seg) && nrow(seg))
    p <- p + ggplot2::geom_text(
      data = seg,
      ggplot2::aes(x = W + 0.055, y = y,
                   label = sprintf("−%d   %.0f%% kept", lost, 100 * kept)),
      size = base_size / 3.7, hjust = 0, colour = "grey45")

  if ("note" %in% names(d)) {
    nd <- d[has_note, , drop = FALSE]
    if (nrow(nd))
      p <- p + ggplot2::geom_text(data = nd,
                                  ggplot2::aes(x = 0, y = bar_b - 0.10, label = note),
                                  size = base_size / 4.05, vjust = 1, lineheight = 0.95,
                                  fontface = "italic", colour = "grey45")
  }

  p <- p +
    ggplot2::geom_segment(data = heads,
                          ggplot2::aes(x = -W - 0.30, xend = W + 0.30, y = y - 0.09, yend = y - 0.09),
                          colour = "grey88", linewidth = 0.25) +
    ggplot2::geom_text(data = heads,
                       ggplot2::aes(x = -W - 0.30, y = y + 0.06, label = toupper(tier)),
                       hjust = 0, size = base_size / 4.0, colour = "grey45", fontface = "bold") +
    ggplot2::scale_fill_manual(
      values = stats::setNames(c(cols[1:2], "grey62"), c(group_labs, UNSPLIT)),
      breaks = group_labs, name = NULL, drop = TRUE) +
    ggplot2::scale_x_continuous(limits = c(-W - 0.32, W + 0.34), expand = c(0, 0)) +
    ggplot2::coord_cartesian(clip = "off") +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_void(base_size = base_size) +
    ggplot2::theme(legend.position = if (has_split && show_legend) "top" else "none",
                   legend.key.size = ggplot2::unit(0.5, "lines"),
                   legend.text = ggplot2::element_text(size = base_size * 0.85),
                   plot.margin = ggplot2::margin(4, 4, 4, 4))
  p
}
