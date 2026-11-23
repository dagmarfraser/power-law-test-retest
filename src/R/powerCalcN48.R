# powerCalcN48.R
# Where does N = 48 come from, and what does the ICC planning calculation say?
#
# A. A-priori sample size as specified before data collection: G*Power 3.1 "F tests: ANCOVA,
#    fixed effects, main effects and interactions", effect size f = 0.5, alpha .05, power .80,
#    numerator df = 3, groups = 2, covariates = 1  ->  N = 48; +20% dropout -> 58 recruited.
#    G*Power's formula is reproduced here in base R (lambda = f^2 N, df2 = N - groups - covariates).
#    Note: f = 0.5 is larger than Cohen's conventional "large" (f = 0.40), and "d = 0.5" is a
#    different quantity (f = d/2 for two groups); the sample size rests on the f = 0.5 input.
# B. The same design at conventional effect sizes (sensitivity of N to the effect-size input).
# C. ICC planning N per shape from the pilot (N = 61 pilot): Zou (2012) via
#    ICC.Sample.Size::calculateIccSampleSize, p0 = 0.75, k = 2, alpha .05, one tail, power .80.
#    Pilot ICC(A,1) values are copied from the pilot results file icc_power_output.csv
#    (analysis_2025/results/, 2026-03-15), which is not in this repository.
# Writes CSVs to reports/R/powerCalcN48_<timestamp>/ . Run from the repo root or src/:
#   Rscript src/R/powerCalcN48.R

scriptDir <- local({
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a)) dirname(normalizePath(sub("^--file=", "", a))) else {
    d <- getwd()
    while (!file.exists(file.path(d, "src", "R"))) {
      if (dirname(d) == d) stop("Cannot find src/R; setwd() to the repo or src/ first"); d <- dirname(d)
    }
    file.path(d, "src", "R")
  }
})
root <- normalizePath(file.path(scriptDir, "..", ".."))
od <- file.path(root, "reports", "R", paste0("powerCalcN48_", format(Sys.time(), "%Y%m%d_%H%M%S")))
if (!dir.create(od, recursive = TRUE)) stop("Could not create ", od)
writeChecked <- function(x, f) {
  write.csv(x, f, row.names = FALSE)
  if (!file.exists(f) || file.size(f) == 0) stop("Write failed: ", f)
  message("Wrote ", f)
}

alpha <- .05; power <- .80

# ---- A and B: G*Power-equivalent ANCOVA (fixed effects) ---------------------------------------
ancovaPower <- function(N, f, df1, groups, cov) {
  df2 <- N - groups - cov
  1 - pf(qf(1 - alpha, df1, df2), df1, df2, f^2 * N)
}
ancovaN <- function(f, df1, groups, cov) {
  for (N in (groups + cov + 2):5000) if (ancovaPower(N, f, df1, groups, cov) >= power) return(N)
  stop("No N below 5000 reaches power for f = ", f)
}
A <- data.frame(f = .5, df1 = 3, groups = 2, covariates = 1)
A$N <- ancovaN(A$f, A$df1, A$groups, A$covariates)
A$actualPower <- ancovaPower(A$N, A$f, A$df1, A$groups, A$covariates)
A$recruit_plus20pct <- round(A$N * 1.2)
A$recruit_N_over_0.8 <- ceiling(A$N / 0.8)
if (A$N != 48) stop("Expected N = 48 for the specified inputs, got ", A$N, ": formula or inputs changed")
writeChecked(A, file.path(od, "A_ancova_f0.5_N48.csv"))
print(A, row.names = FALSE)

B <- do.call(rbind, lapply(c(0.10, 0.25, 0.40, 0.50), function(f)
  data.frame(f = f, d_equiv_two_groups = 2 * f, N = ancovaN(f, 3, 2, 1))))
writeChecked(B, file.path(od, "B_ancova_N_by_effectSize.csv"))
cat("\nSame design, other effect sizes:\n"); print(B, row.names = FALSE)

# ---- C: ICC planning N from the pilot ----------------------------------------------------------
if (!requireNamespace("ICC.Sample.Size", quietly = TRUE))
  stop("Package ICC.Sample.Size is required for part C (install.packages('ICC.Sample.Size'))")
suppressPackageStartupMessages(library(ICC.Sample.Size))
pilot <- data.frame(
  ShapeName = c("phi=0.4", "phi=0.8", "Ellipse", "Square", "Cursive"),
  ICC_pilot = c(0.887751773429555, 0.878418400655554, 0.858108458803676, 0.785467011963291, 0.813912795871049))
zouN <- function(p, p0 = .75, k = 2)
  calculateIccSampleSize(p = p, p0 = p0, k = k, alpha = alpha, power = power, tails = 1)[[1]]$N
pilot$N_required <- vapply(pilot$ICC_pilot, zouN, numeric(1))
pilot$expected_N <- c(34, 41, 65, 827, 227)       # from the saved pilot results file
if (!identical(as.numeric(pilot$N_required), pilot$expected_N))
  stop("Zou N does not match the saved pilot output: ", paste(pilot$N_required, collapse = ", "))
writeChecked(pilot, file.path(od, "C_zou_pilot_N.csv"))
cat("\nPilot Zou N (p0 .75, k 2, one tail, power .80), reproduces the saved pilot output:\n")
print(pilot, row.names = FALSE)

# Pilot ICC at which Zou N would equal 48 (same settings): scan
ps <- seq(0.80, 0.95, by = 0.001)
nn <- vapply(ps, zouN, numeric(1))
inv <- data.frame(ICC = ps[nn == 48], N = 48)
if (!nrow(inv)) inv <- data.frame(ICC = NA_real_, N = 48)
writeChecked(inv, file.path(od, "C_pilotICC_giving_N48.csv"))
cat("\nPilot ICC giving Zou N = 48:", paste(inv$ICC, collapse = ", "), "\n")
writeLines(capture.output(sessionInfo()), file.path(od, "sessionInfo.txt"))
