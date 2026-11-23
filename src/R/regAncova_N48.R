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
# Added 2026-11-23 from the registration's own plan: (a) exploratory re-run with M-EDL total in
# place of CATI as the covariate ("see if M-EDL score is a covariate"; M-EDL has 18 exact zeros,
# meaning unknown, Claims I3); (b) log and square-root sensitivity runs, because that plan says
# "if data is skewed, log or square root" and several cell means are skewed; (c) Cohen's f
# beside partial eta^2 (the registration states f = 0.5 as its effect-size criterion).
# These are in addition to, not instead of, the pre-declared primary run above.
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
            CATI_Total = first(CATI_Total), M_EDL_Total = first(M_EDL_Total), .groups = "drop")
if (nrow(cells) != 48 * 5 * 2 || anyNA(cells$Beta) || any(cells$nTrials == 0))
  stop(sprintf("Incomplete design: %d cells (expect 480), %d NA means", nrow(cells), sum(is.na(cells$Beta))))
cells$ShapeName <- factor(cells$ShapeName, levels = unname(SHAPES))
pc <- cells[!duplicated(cells$ParticipantID), "CATI_Total"][[1]]
cells$CATI_c <- cells$CATI_Total - mean(pc)
cells$MEDL_c <- cells$M_EDL_Total - mean(cells[!duplicated(cells$ParticipantID), "M_EDL_Total"][[1]])
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
runAncova <- function(dat, yvar, label, covar = "CATI_c") {
  dat$y <- dat[[yvar]]
  dat$Cov <- dat[[covar]]
  dat$ShapeName <- droplevels(dat$ShapeName)
  f <- y ~ ShapeName * Visit * Cov + (1 | ParticipantID) + (1 | ParticipantID:ShapeName) +
         (1 | ParticipantID:Visit)
  m  <- lmer(f, data = dat)
  sing <- isSingular(m)
  at <- anova(m, type = 3, ddf = "Satterthwaite")
  tab <- data.frame(analysis = label, covariate = covar, term = gsub("Cov", covar, rownames(at)), at,
                    row.names = NULL, check.names = FALSE)
  tab$partialEta2 <- with(tab, (`F value` * NumDF) / (`F value` * NumDF + DenDF))
  tab$cohen_f <- sqrt(tab$partialEta2 / (1 - tab$partialEta2))
  tab$singular <- sing
  # visit shift within each shape; CATI slope within each shape (Holm across shapes)
  vs <- as.data.frame(pairs(emmeans(m, ~ Visit | ShapeName), adjust = "none"))
  vs$p_holm <- p.adjust(vs$p.value, "holm"); vs$analysis <- label
  cs <- as.data.frame(emtrends(m, ~ ShapeName, var = "Cov"))
  names(cs)[names(cs) == "Cov.trend"] <- "slope"
  cs$analysis <- label; cs$covariate <- covar
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
# Registration's own rule: skewed data -> log or square root (run both as sensitivity analyses)
tmpl <- function(d) subset(d, ShapeName != "Cursive")
cells$BetaLog  <- log(cells$Beta)
cells$BetaSqrt <- sqrt(cells$Beta)
if (any(!is.finite(cells$BetaLog)) || any(!is.finite(cells$BetaSqrt))) stop("log/sqrt of beta not finite (beta <= 0?)")
res$log5   <- runAncova(cells, "BetaLog",  "sensitivity_5shapes_log")
res$log4   <- runAncova(tmpl(cells), "BetaLog",  "sensitivity_4templated_log")
res$sqrt5  <- runAncova(cells, "BetaSqrt", "sensitivity_5shapes_sqrt")
res$sqrt4  <- runAncova(tmpl(cells), "BetaSqrt", "sensitivity_4templated_sqrt")
# Exploratory (registration's plan): M-EDL in place of CATI as the covariate
res$medl5  <- runAncova(cells, "Beta", "exploratory_5shapes_rawBeta_MEDL", covar = "MEDL_c")
res$medl4  <- runAncova(tmpl(cells), "Beta", "exploratory_4templated_rawBeta_MEDL", covar = "MEDL_c")
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
cat("\n=== Covariate terms in every run (CATI_c or MEDL_c) ===\n")
allTab <- do.call(rbind, lapply(res, `[[`, "tab"))
print(allTab[grepl("CATI_c|MEDL_c|Visit$|ShapeName:Visit$", allTab$term),
             c("analysis", "term", "NumDF", "DenDF", "F value", "Pr(>F)", "partialEta2", "cohen_f")], digits = 3, row.names = FALSE)
cat("\nResidual normality:\n"); print(do.call(rbind, lapply(res, `[[`, "rn")), digits = 3)
cat("\nOutput folder: ", od, "\n")
writeLines(capture.output(sessionInfo()), file.path(od, "sessionInfo.txt"))
