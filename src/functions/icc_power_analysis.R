# icc_power_analysis.R
#
# Calculate required sample size for ICC reliability confirmatory study.
# Implements Zou (2012) via the ICC.Sample.Size package.
#
# Called from MATLAB: powerAnalysisICC_R.m
# Reads:  <input_csv>   (written by MATLAB, one row per shape)
# Writes: <output_csv>  (read back by MATLAB)
#
# Usage (standalone):
#   Rscript icc_power_analysis.R <input_csv> <output_csv>
#
# Input CSV columns required:
#   ShapeName, ICC_BetweenVisit
#
# Fixed analysis parameters (pre-specified):
#   p0     = 0.75  (minimum "good" threshold, Koo & Li 2016)
#   k      = 2     (number of visits -- update if k=3 design adopted, see docs/DesignNotes.md)
#   alpha  = 0.05  (one-sided)
#   power  = 0.80
#
# Unchanged from analysis_2025/icc_power_analysis.R -- this script never
# referenced project-specific paths, so no adaptation was needed beyond
# this header note.

# ---- package check -------------------------------------------------------
if (!requireNamespace("ICC.Sample.Size", quietly = TRUE)) {
  install.packages("ICC.Sample.Size", repos = "https://cran.r-project.org",
                   quiet = TRUE)
}
library(ICC.Sample.Size)

# ---- arguments -----------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript icc_power_analysis.R <input_csv> <output_csv>")
}
input_csv  <- args[1]
output_csv <- args[2]

# ---- fixed parameters ----------------------------------------------------
p0    <- 0.75
k     <- 2
alpha <- 0.05
power <- 0.80

# ---- read input ----------------------------------------------------------
dat <- read.csv(input_csv, stringsAsFactors = FALSE)
if (!all(c("ShapeName", "ICC_BetweenVisit") %in% names(dat))) {
  stop("Input CSV must contain columns: ShapeName, ICC_BetweenVisit")
}

# ---- compute -------------------------------------------------------------
results <- data.frame(
  ShapeName    = character(),
  ICC_observed = numeric(),
  p0           = numeric(),
  k            = integer(),
  alpha        = numeric(),
  power        = numeric(),
  N_required   = integer(),
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(dat))) {
  shape <- dat$ShapeName[i]
  p     <- dat$ICC_BetweenVisit[i]

  if (p <= p0) {
    # ICC not above null -- N is intractable
    n_req <- NA
    cat(sprintf("%-10s  ICC=%.3f <= p0=%.2f  [intractable]\n", shape, p, p0))
  } else {
    r     <- calculateIccSampleSize(p     = p,
                                    p0    = p0,
                                    k     = k,
                                    alpha = alpha,
                                    tails = 1,
                                    power = power)
    # calculateIccSampleSize returns a list of length 1 wrapping a data frame
    n_req <- as.integer(r[[1]]$N)
    cat(sprintf("%-10s  ICC=%.3f  N_required=%d\n", shape, p, n_req))
  }

  results <- rbind(results, data.frame(
    ShapeName    = shape,
    ICC_observed = p,
    p0           = p0,
    k            = k,
    alpha        = alpha,
    power        = power,
    N_required   = n_req,
    stringsAsFactors = FALSE
  ))
}

# ---- write output --------------------------------------------------------
write.csv(results, output_csv, row.names = FALSE)
cat(sprintf("\nWritten: %s\n", output_csv))
