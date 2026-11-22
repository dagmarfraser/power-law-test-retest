# varianceSupplementTable_N48.R
# Builds the supplementary variance-decomposition table for the paper from saved runs:
# lmer shares (mixedModel_N48.R) and brms shares with 90% intervals (bayesMixedModel_N48.R).
# Each shape's Bayesian shares are taken from the run named for it, and that run's
# convergence row must pass (fail loud otherwise).
# Usage (repo root):
#   Rscript src/R/varianceSupplementTable_N48.R <lmerRunDir> <shape>=<bayesRunDir> ...
#   e.g. ... reports/R/mixedModel_N48_20261122_090238 \
#            phi=0.4=reports/R/bayesMixedModel_N48_20261122_090425 ...

a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 2) stop("Need <lmerRunDir> and at least one <shape>=<bayesRunDir>")
lm <- read.csv(file.path(a[1], "varianceShares_N48.csv"), check.names = FALSE)
map <- regmatches(a[-1], regexpr("=(?=[^=]*$)", a[-1], perl = TRUE), invert = TRUE)
map <- setNames(vapply(map, `[`, "", 2), vapply(map, `[`, "", 1))
miss <- setdiff(lm$Shape, names(map))
if (length(miss)) stop("No Bayesian run given for: ", paste(miss, collapse = ", "))

comp <- c("person", "personVisit", "personSession", "trial")
rows <- lapply(lm$Shape, function(s) {
  bd <- map[[s]]
  dg <- read.csv(file.path(bd, "bayes_diagnostics_N48.csv"))
  dg <- dg[dg$Shape == s & dg$Model == "main", ]
  if (nrow(dg) != 1 || !dg$OK) stop(s, ": Bayesian main model missing or failed convergence in ", bd)
  bs <- read.csv(file.path(bd, "bayes_varianceShares_N48.csv"), check.names = FALSE)
  bs <- bs[bs$Shape == s, ]
  fmt <- function(k) { r <- bs[bs$Component == k, ]
    sprintf("%.2f [%.2f, %.2f]", r$`50%`, r$`5%`, r$`95%`) }
  l <- lm[lm$Shape == s, ]
  data.frame(Shape = s,
             Person = fmt("person"), PersonXVisit = fmt("personVisit"),
             PersonXSession = fmt("personSession"), Trial = fmt("trial"),
             lmer_Person = round(l$person, 3), lmer_PersonXVisit = round(l$personVisit, 3),
             lmer_PersonXSession = round(l$personSession, 3), lmer_Trial = round(l$trial, 3),
             RelVisitMean_lmer = round(l$RelVisitMean, 3),
             maxRhat = round(dg$maxRhat, 4), minBulkESS = round(dg$minBulkESS),
             BayesRun = basename(bd), check.names = FALSE)
})
tab <- do.call(rbind, rows)
od  <- file.path(dirname(a[1]), paste0("varianceSupplement_N48_", format(Sys.time(), "%Y%m%d_%H%M%S")))
if (!dir.create(od)) stop("Could not create ", od)
f <- file.path(od, "varianceSupplementTable_N48.csv")
write.csv(tab, f, row.names = FALSE)
if (!file.exists(f)) stop("Write failed: ", f)
md <- c("| Shape | Person | Person x visit | Person x session | Trial | Implied visit-mean reliability |",
        "|---|---|---|---|---|---|",
        sprintf("| %s | %s | %s | %s | %s | %.3f |", tab$Shape, tab$Person, tab$PersonXVisit,
                tab$PersonXSession, tab$Trial, tab$RelVisitMean_lmer))
writeLines(md, file.path(od, "varianceSupplementTable_N48.md"))
print(tab[, 1:10], row.names = FALSE)
message("Wrote ", od)
