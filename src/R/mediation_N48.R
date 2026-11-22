# mediation_N48.R
# Registered analysis 2 (pre-registration crosswalk, kept internally; Claims J14): autistic traits -> kinematics
# -> motor control, H1 = higher CATI predicts jerkier movement.
# Specification used (the registered draft is ambiguous: kinematics is called both covariate
# and mediator; coordinator + Dagmar fixed it on 2026-11-22):
#   X = CATI_Total, M = beta (Beta_SG6_IRLS), Y = jerk (MeanJerk_SG).
# One participant-level row per participant and shape (mean over both visits and all trials),
# so N = 48 per shape. All variables z-scored. Paths: a (X->M), b (M->Y | X), c' (X->Y | M),
# indirect a*b, total c. Indirect effect: percentile bootstrap, 5000 resamples (lavaan).
# Sensitivity: log(jerk), because trial jerk is right-skewed. Holm across the 5 shapes per path.
# Caveats: jerk and beta share kinematic information (duration, Claims/AnalysisPipeline
# "Jerk is duration-sensitive"); CATI subscale labels unverified (I2), only CATI_Total used;
# cross-sectional mediation does not establish a causal chain.
# The registration's H2 (t-test of questionnaire scores across time points) is NOT run: the data hold
# one CATI/M-EDL score per participant, so there is no T2 questionnaire to compare.
# Run from the repo root or src/:  Rscript src/R/mediation_N48.R

suppressPackageStartupMessages({ library(lavaan); library(dplyr) })
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
set.seed(20261122)
NBOOT <- 5000

root <- findRepoRoot(scriptDir)
d    <- loadHandoverWithScores(root)
od   <- makeOutDir(root, "mediation_N48")
if (!"MeanJerk_SG" %in% names(d)) stop("MeanJerk_SG missing from handover CSV")

model <- "
  M ~ a*X
  Y ~ b*M + cp*X
  ind   := a*b
  total := cp + a*b
"
z <- function(x) as.numeric(scale(x))
rows <- list(); fitInfo <- list()
for (spec in c("raw_jerk", "log_jerk")) {
  for (tag in names(SHAPES)) {
    shape <- SHAPES[[tag]]
    pp <- d |> filter(ShapeName == shape) |>
      group_by(ParticipantID) |>
      summarise(X = first(CATI_Total), M = mean(Beta_SG6_IRLS, na.rm = TRUE),
                Y = mean(MeanJerk_SG, na.rm = TRUE), .groups = "drop")
    if (nrow(pp) != 48 || anyNA(pp)) stop(sprintf("%s: %d participants, NA present: %s", shape, nrow(pp), anyNA(pp)))
    if (spec == "log_jerk") { if (any(pp$Y <= 0)) stop("jerk <= 0, cannot log"); pp$Y <- log(pp$Y) }
    pp[c("X", "M", "Y")] <- lapply(pp[c("X", "M", "Y")], z)
    fit <- sem(model, data = pp, se = "bootstrap", bootstrap = NBOOT)
    pe  <- parameterEstimates(fit, boot.ci.type = "perc", standardized = FALSE)
    pe  <- pe[pe$label %in% c("a", "b", "cp", "ind", "total"), c("label", "est", "se", "pvalue", "ci.lower", "ci.upper")]
    pe$shape <- shape; pe$spec <- spec; pe$n <- nrow(pp)
    pe$r_XM <- cor(pp$X, pp$M); pe$r_XY <- cor(pp$X, pp$Y); pe$r_MY <- cor(pp$M, pp$Y)
    rows[[length(rows) + 1]] <- pe
    fitInfo[[length(fitInfo) + 1]] <- data.frame(shape = shape, spec = spec, converged = lavInspect(fit, "converged"))
  }
}
out <- do.call(rbind, rows)
if (!all(do.call(rbind, fitInfo)$converged)) stop("A lavaan fit did not converge")
out$p_holm <- NA_real_
for (s in unique(out$spec)) for (l in unique(out$label)) {
  i <- out$spec == s & out$label == l
  out$p_holm[i] <- p.adjust(out$pvalue[i], "holm")
}
out$excludesZero <- out$ci.lower > 0 | out$ci.upper < 0
writeChecked(out, file.path(od, "mediation_paths.csv"))
cat("\n=== Raw jerk: paths per shape (z-scored; bootstrap perc CI) ===\n")
print(out[out$spec == "raw_jerk", c("shape", "label", "est", "ci.lower", "ci.upper", "pvalue", "p_holm")], digits = 3, row.names = FALSE)
cat("\n=== Log jerk (sensitivity) ===\n")
print(out[out$spec == "log_jerk", c("shape", "label", "est", "ci.lower", "ci.upper", "pvalue", "p_holm")], digits = 3, row.names = FALSE)
cat("\nOutput folder: ", od, "\n")
writeLines(capture.output(sessionInfo()), file.path(od, "sessionInfo.txt"))
