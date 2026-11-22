# regAncova_N48.R
# Registered analysis 1 (pre-registration crosswalk, kept internally; Claims J14): repeated-measures
# ANCOVA on beta, Shape x Time (Visit) within participants, CATI total as a continuous covariate.
#   H1 = CATI main effect, CATI x Shape, CATI x Visit.   H2 = Shape x Visit.
# Implemented as the mixed-model equivalent on participant x shape x visit CELL MEANS
# (one value per cell, 48 x 5 x 2 = 480), with participant, participant:shape and
# participant:visit random intercepts (the repeated-measures error strata), Type III
# F tests with Satterthwaite df (lmerTest). No sphericity correction is needed because
# the covariance is modelled, not assumed.
# Primary: all 5 shapes. Sensitivity: 4 templated shapes (Cursive dropped; the registration
# says "four levels", and Cursive is the free-text condition, Claims C7).
# Normality (her plan): histograms, Kolmogorov-Smirnov, Shapiro-Wilk, skew and kurtosis.
# Transformation rule, fixed in this script before any run: analyse RAW beta as primary
# (ICC work is on raw beta). If skew of the primary model residuals is > +0.5 repeat with
# log(beta); if < -0.5 repeat with log(max+1-beta) (reflected); otherwise no transformed run.
# CATI subscale labels are unverified (Claims I2): only CATI_Total is used here.
# Run from the repo root or src/:  Rscript src/R/regAncova_N48.R

suppressPackageStartupMessages({
  library(lme4); library(lmerTest); library(emmeans); library(dplyr); library(ggplot2)
})
scriptDir <- local({
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a)) dirname(normalizePath(sub("^--file=", "", a))) else {
    d <- getwd()
    while (!file.exists(file.path(d, "src", "R", "loadHandoverWithScores.R"))) {
      if (dirname(d) == d) stop("Cannot find src/R; setwd() to the repo or src/ first"); d <- dirname(d)
    }
    file.path(d, "src", "R")
  }
})
source(file.path(scriptDir, "loadHandoverWithScores.R"))
options(contrasts = c("contr.sum", "contr.poly"))
set.seed(20261122)

root <- findRepoRoot(scriptDir)
d    <- loadHandoverWithScores(root)
od   <- makeOutDir(root, "regAncova_N48")

# ---- 1. Cell means, complete-design check (fail loud) -------------------------------------
cells <- d |>
  group_by(ParticipantID, ShapeName, Visit) |>
  summarise(Beta = mean(Beta_SG6_IRLS, na.rm = TRUE), nTrials = sum(!is.na(Beta_SG6_IRLS)),
            CATI_Total = first(CATI_Total), .groups = "drop")
if (nrow(cells) != 48 * 5 * 2 || anyNA(cells$Beta) || any(cells$nTrials == 0))
  stop(sprintf("Incomplete design: %d cells (expect 480), %d NA means", nrow(cells), sum(is.na(cells$Beta))))
cells$ShapeName <- factor(cells$ShapeName, levels = unname(SHAPES))
pc <- cells[!duplicated(cells$ParticipantID), "CATI_Total"][[1]]
cells$CATI_c <- cells$CATI_Total - mean(pc)
message(sprintf("Cell means: %d cells, trials per cell median %d (min %d, max %d); min beta %.3f",
                nrow(cells), median(cells$nTrials), min(cells$nTrials), max(cells$nTrials), min(cells$Beta)))

# ---- 2. Normality on the cell means ---------------------------------------------------------
skew <- function(x) { x <- x[is.finite(x)]; mean((x - mean(x))^3) / sd(x)^3 }
kurt <- function(x) { x <- x[is.finite(x)]; mean((x - mean(x))^4) / sd(x)^4 - 3 }
normRows <- cells |>
  group_by(ShapeName, Visit) |>
  summarise(n = n(), mean = mean(Beta), sd = sd(Beta), skew = skew(Beta), exKurt = kurt(Beta),
            SW_p = shapiro.test(Beta)$p.value,
            KS_p = suppressWarnings(ks.test(Beta, "pnorm", mean(Beta), sd(Beta))$p.value),
            .groups = "drop")
normRows$note <- "KS uses estimated mean/sd (no Lilliefors correction): conservative, read with Shapiro-Wilk"
writeChecked(normRows, file.path(od, "normality_cellMeans.csv"))
p <- ggplot(cells, aes(Beta)) + geom_histogram(bins = 15) + facet_grid(Visit ~ ShapeName, scales = "free_x") +
  labs(title = "Beta cell means by shape and visit (N=48)", x = "Beta_SG6_IRLS")
ggsave(file.path(od, "hist_cellMeans.png"), p, width = 11, height = 4.5, dpi = 150)

# ---- 3. The ANCOVA, run for a given data set / outcome -------------------------------------
runAncova <- function(dat, yvar, label) {
  dat$y <- dat[[yvar]]
  dat$ShapeName <- droplevels(dat$ShapeName)
  f <- y ~ ShapeName * Visit * CATI_c + (1 | ParticipantID) + (1 | ParticipantID:ShapeName) +
         (1 | ParticipantID:Visit)
  m  <- lmer(f, data = dat)
  sing <- isSingular(m)
  at <- anova(m, type = 3, ddf = "Satterthwaite")
  tab <- data.frame(analysis = label, term = rownames(at), at, row.names = NULL, check.names = FALSE)
  tab$partialEta2 <- with(tab, (`F value` * NumDF) / (`F value` * NumDF + DenDF))
  tab$singular <- sing
  # visit shift within each shape; CATI slope within each shape (Holm across shapes)
  vs <- as.data.frame(pairs(emmeans(m, ~ Visit | ShapeName), adjust = "none"))
  vs$p_holm <- p.adjust(vs$p.value, "holm"); vs$analysis <- label
  cs <- as.data.frame(emtrends(m, ~ ShapeName, var = "CATI_c"))
  cs$analysis <- label
  rs <- residuals(m)
  rn <- data.frame(analysis = label, skew = skew(rs), exKurt = kurt(rs),
                   SW_p = shapiro.test(rs)$p.value, singular = sing)
  list(tab = tab, vs = vs, cs = cs, rn = rn, model = m)
}

res <- list()
res$primary5 <- runAncova(cells, "Beta", "primary_5shapes_rawBeta")
res$sens4    <- runAncova(subset(cells, ShapeName != "Cursive"), "Beta", "sensitivity_4templated_rawBeta")

# Pre-declared transformation rule, applied to the primary residuals
sk <- res$primary5$rn$skew
if (sk > 0.5) {
  cells$BetaT <- log(cells$Beta); tlab <- "log(beta)"
} else if (sk < -0.5) {
  cells$BetaT <- log(max(cells$Beta) + 1 - cells$Beta); tlab <- "reflected log(max+1-beta)"
} else tlab <- NA
if (!is.na(tlab)) {
  if (any(!is.finite(cells$BetaT))) stop("Transformation produced non-finite values (beta <= 0?)")
  res$transf5 <- runAncova(cells, "BetaT", paste0("transformed_5shapes_", tlab))
  res$transf4 <- runAncova(subset(cells, ShapeName != "Cursive"), "BetaT", paste0("transformed_4templated_", tlab))
}
message("Primary residual skew = ", round(sk, 3), "; transformation: ", ifelse(is.na(tlab), "none triggered", tlab))

# ---- 4. Save ---------------------------------------------------------------------------------
writeChecked(do.call(rbind, lapply(res, `[[`, "tab")), file.path(od, "ancova_typeIII.csv"))
writeChecked(do.call(rbind, lapply(res, `[[`, "vs")),  file.path(od, "visitShift_byShape.csv"))
writeChecked(do.call(rbind, lapply(res, `[[`, "cs")),  file.path(od, "CATIslope_byShape.csv"))
writeChecked(do.call(rbind, lapply(res, `[[`, "rn")),  file.path(od, "residualNormality.csv"))
cat("\n=== Primary (5 shapes, raw beta) Type III F tests ===\n")
print(res$primary5$tab[, c("term", "NumDF", "DenDF", "F value", "Pr(>F)", "partialEta2")], digits = 4)
cat("\n=== Sensitivity (4 templated shapes) ===\n")
print(res$sens4$tab[, c("term", "NumDF", "DenDF", "F value", "Pr(>F)", "partialEta2")], digits = 4)
cat("\nResidual normality:\n"); print(do.call(rbind, lapply(res, `[[`, "rn")), digits = 3)
cat("\nOutput folder: ", od, "\n")
writeLines(capture.output(sessionInfo()), file.path(od, "sessionInfo.txt"))
