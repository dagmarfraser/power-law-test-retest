# mixedModel_N48.R
# Frequentist mixed models of trial-level beta per shape, with CATI as a person-level
# predictor, plus participant-level correlations and histograms.
# Adapted from Harvey Neal, "R_Code_Mixed_Model_N48_All_Shapes+Histograms.R" (17 Nov 2026).
# Changes: repo paths and merge step (loadHandoverWithScores.R); all 5 shapes in one loop
# (Cursive included, flagged in output); variance shares and implied visit-mean
# reliability added; Spearman beside Pearson; Holm also across all shapes; figures and
# tables saved to reports/R/<timestamp>/.
# Run from the repo root or src/:  Rscript src/R/mixedModel_N48.R

suppressPackageStartupMessages({
  library(lme4); library(lmerTest); library(dplyr); library(ggplot2); library(tidyr)
})
# Folder of this script: from Rscript --file=, else search up from getwd() for src/R
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

root <- findRepoRoot(scriptDir)
d    <- loadHandoverWithScores(root)
od   <- makeOutDir(root, "mixedModel_N48")

varRows <- list(); fixRows <- list(); cmpRows <- list(); corRows <- list()

for (tag in names(SHAPES)) {
  shape <- SHAPES[[tag]]
  dd <- centreCATI(subset(d, ShapeName == shape & !is.na(Beta_SG6_IRLS)))
  if (!nrow(dd)) stop("No rows for ShapeName == '", shape, "'")

  # Main effects, and Visit x CATI (does the visit change differ by CATI score?)
  # Random structure: person, person x visit, person x session
  f0 <- Beta_SG6_IRLS ~ Visit + CATI_Total_c + (1 | ParticipantID) +
    (1 | ParticipantID:Visit) + (1 | ParticipantID:Session)
  m_main <- lmer(f0, data = dd)
  m_int  <- lmer(update(f0, . ~ . + Visit:CATI_Total_c), data = dd)
  # Record fit problems in the output rather than only in the console
  fitNote <- function(m) paste(c(if (isSingular(m)) "singular fit",
                                 m@optinfo$conv$lme4$messages), collapse = "; ")

  # Variance shares from the model without CATI (pure decomposition)
  m_vc <- lmer(Beta_SG6_IRLS ~ Visit + (1 | ParticipantID) + (1 | ParticipantID:Visit) +
                 (1 | ParticipantID:Session), data = dd)
  vc <- as.data.frame(VarCorr(m_vc))
  v  <- setNames(vc$vcov, vc$grp)
  v  <- c(person = v[["ParticipantID"]], personVisit = v[["ParticipantID:Visit"]],
          personSession = v[["ParticipantID:Session"]], trial = v[["Residual"]])
  nT <- nrow(dd) / (nlevels(dd$ParticipantID) * nlevels(dd$Visit))   # trials per visit
  varRows[[tag]] <- data.frame(Shape = shape, nTrials = nrow(dd), t(round(v / sum(v), 4)),
    RelVisitMean = round(v[["person"]] / (v[["person"]] + v[["personVisit"]] +
                         v[["personSession"]] / 3 + v[["trial"]] / nT), 4),
    Note = ifelse(shape == "Cursive", "free text differs between visits (Claims C7)", ""))

  for (nm in c("main", "interaction")) {
    cf <- as.data.frame(coef(summary(if (nm == "main") m_main else m_int)))
    fixRows[[paste(tag, nm)]] <- data.frame(Shape = shape, Model = nm, Term = rownames(cf),
                                            cf, row.names = NULL, check.names = FALSE)
  }
  a <- anova(m_main, m_int)   # refits with ML
  cmpRows[[tag]] <- data.frame(Shape = shape, Model = c("main", "interaction"),
                               AIC = a$AIC, BIC = a$BIC, Chisq = a$Chisq, p = a$`Pr(>Chisq)`,
                               FitWarning = c(fitNote(m_main), fitNote(m_int)))

  # Participant level: mean beta vs each questionnaire measure
  ps <- participantSummary(dd)
  corRows[[tag]] <- bind_rows(lapply(PERSON_VARS, function(vn) {
    pr <- cor.test(ps$mean_Beta, ps[[vn]])
    sp <- suppressWarnings(cor.test(ps$mean_Beta, ps[[vn]], method = "spearman"))
    data.frame(Shape = shape, Measure = vn, n = nrow(ps),
               r = unname(pr$estimate), r_lo = pr$conf.int[1], r_hi = pr$conf.int[2],
               p = pr$p.value, rho = unname(sp$estimate), p_rho = sp$p.value)
  })) |> mutate(p_holm_shape = p.adjust(p, "holm"))

  # Figures
  ggsave(file.path(od, paste0("hist_meanBeta_", tag, ".png")),
         ggplot(ps, aes(mean_Beta)) + geom_histogram(bins = 15, fill = "steelblue", colour = "white") +
           labs(title = paste("Mean beta per participant:", shape)) + theme_minimal(),
         width = 6, height = 4, dpi = 150)
  pl <- pivot_longer(ps, all_of(PERSON_VARS), names_to = "Measure", values_to = "Score")
  ggsave(file.path(od, paste0("scatter_meanBeta_vs_scores_", tag, ".png")),
         ggplot(pl, aes(Score, mean_Beta)) + geom_point(colour = "steelblue", size = 1.8) +
           geom_smooth(method = "lm", formula = y ~ x, se = TRUE, colour = "black") +
           facet_wrap(~ Measure, scales = "free_x", ncol = 4) +
           labs(y = "Mean Beta_SG6_IRLS (per participant)",
                title = paste("Participant mean beta vs questionnaire measures:", shape)) +
           theme_minimal(), width = 11, height = 6, dpi = 150)
}

cors <- bind_rows(corRows) |> mutate(p_holm_all = p.adjust(p, "holm"))
writeChecked(bind_rows(varRows), file.path(od, "varianceShares_N48.csv"))
writeChecked(bind_rows(fixRows), file.path(od, "fixedEffects_N48.csv"))
writeChecked(bind_rows(cmpRows), file.path(od, "modelComparison_N48.csv"))
writeChecked(cors,               file.path(od, "correlations_N48.csv"))

# Questionnaire histograms (one value per participant)
ps1 <- d[!duplicated(d$ParticipantID), PERSON_VARS]
ggsave(file.path(od, "hist_questionnaires.png"),
       ggplot(pivot_longer(ps1, everything(), names_to = "Measure", values_to = "Score"), aes(Score)) +
         geom_histogram(bins = 15, fill = "darkorange", colour = "white") +
         facet_wrap(~ Measure, scales = "free", ncol = 4) +
         labs(title = "Questionnaire scores across participants (N=48)") + theme_minimal(),
       width = 11, height = 6, dpi = 150)

print(bind_rows(varRows), row.names = FALSE)
message("Done: ", od)
