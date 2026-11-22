# bayesMixedModel_N48.R
# Bayesian (brms) version of mixedModel_N48.R: per shape, main and Visit x CATI models,
# LOO comparison, variance shares with intervals, and Bayesian participant-level slopes.
# Adapted from Harvey Neal, "R_Code_Bayesian_Mixed_Model_N48.R" (17 Nov 2026).
# Changes: repo paths and merge step (loadHandoverWithScores.R); install.packages() call
# removed (it installed digest into a folder named "rstan"); backend chosen explicitly
# (cmdstanr if CmdStan is installed, else rstan, announced); 2000 iterations (1000 warmup)
# by default (env vars BRMS_ITER, BRMS_WARMUP, BRMS_TREEDEPTH override); variance shares with 90% intervals; fits cached in reports/R/brms_fits;
# tables saved to reports/R/<timestamp>/.
# Run from the repo root or src/:  Rscript src/R/bayesMixedModel_N48.R [shapes...]
#   e.g. Rscript src/R/bayesMixedModel_N48.R ellipse square   (default: the 4 templated shapes)

suppressPackageStartupMessages({ library(dplyr); library(brms) })
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
od   <- makeOutDir(root, "bayesMixedModel_N48")
fitDir <- file.path(root, "reports", "R", "brms_fits")
dir.create(fitDir, showWarnings = FALSE, recursive = TRUE)

# Sampler settings; override for hard shapes, e.g. BRMS_ITER=6000 BRMS_TREEDEPTH=12
envNum <- function(k, def) as.numeric(Sys.getenv(k, def))
ITER <- envNum("BRMS_ITER", 2000); WARMUP <- envNum("BRMS_WARMUP", 1000)
TREEDEPTH <- envNum("BRMS_TREEDEPTH", 10); CHAINS <- 4; SEED <- 2026
message(sprintf("iter %d, warmup %d, max_treedepth %d", ITER, WARMUP, TREEDEPTH))
# brms file_refit = "on_change" ignores sampler settings, so they go into the cache name
fitSfx <- sprintf("_i%d_w%d_td%d", ITER, WARMUP, TREEDEPTH)
args   <- commandArgs(trailingOnly = TRUE)
todo   <- if (length(args)) args else c("phi04", "phi08", "ellipse", "square")
badTag <- setdiff(todo, names(SHAPES))
if (length(badTag)) stop("Unknown shape tag(s): ", paste(badTag, collapse = ", "),
                         ". Use: ", paste(names(SHAPES), collapse = ", "))

###Stan backend###
useCmd <- requireNamespace("cmdstanr", quietly = TRUE) &&
  !is.null(cmdstanr::cmdstan_version(error_on_NA = FALSE))
options(brms.backend = if (useCmd) "cmdstanr" else "rstan", mc.cores = CHAINS)
message("Stan backend: ", getOption("brms.backend"),
        if (!useCmd) " (cmdstanr/CmdStan not found; rstan is slower to compile, same results)")

###Priors###
# Fixed effects: beta is about 0.19 with total SD about 0.08, so normal(0, 0.1) allows any
# plausible effect. Intercept and SD priors are brms defaults (scaled to the data).
priors_mlm <- prior(normal(0, 0.1), class = "b")
# Participant-level models: both variables standardised, so normal(0, 1) is weakly informative
priors_cor <- c(prior(normal(0, 1), class = "b"), prior(normal(0, 1), class = "Intercept"))

# Compiled once and reused with update(); tiny 1-chain run as chains = 0 is unreliable
cor_template <- brm(y ~ x, data = data.frame(y = rnorm(10), x = rnorm(10)),
                    prior = priors_cor, chains = 1, iter = 200, warmup = 100,
                    refresh = 0, silent = 2, seed = SEED)

# Posterior summary of fixed effects: mean, 95% CrI, P(effect > 0)
post_summary <- function(fit, shape, model) {
  dr <- as_draws_df(fit)
  bc <- setdiff(grep("^b_", names(dr), value = TRUE), "b_Intercept")
  bind_rows(lapply(bc, function(cn) { x <- dr[[cn]]
    data.frame(Shape = shape, Model = model, Term = sub("^b_", "", cn),
               Estimate = mean(x), CI_low = unname(quantile(x, .025)),
               CI_high = unname(quantile(x, .975)), P_positive = mean(x > 0)) }))
}

# Fit diagnostics: fail loud in the output if chains did not mix
diag_row <- function(fit, shape, model) {
  s <- summary(fit)
  rh <- c(s$fixed$Rhat, unlist(lapply(s$random, `[[`, "Rhat")), s$spec_pars$Rhat)
  es <- c(s$fixed$Bulk_ESS, unlist(lapply(s$random, `[[`, "Bulk_ESS")), s$spec_pars$Bulk_ESS)
  nDiv <- sum(subset(nuts_params(fit), Parameter == "divergent__")$Value)
  ok <- max(rh) < 1.01 && min(es) > 400 && nDiv == 0
  if (!ok) warning(shape, " ", model, ": max Rhat ", round(max(rh), 3), ", min bulk ESS ",
                   round(min(es)), ", divergences ", nDiv)
  data.frame(Shape = shape, Model = model, maxRhat = max(rh), minBulkESS = min(es),
             divergences = nDiv, OK = ok)
}

run_brms_shape <- function(tag) {
  shape <- SHAPES[[tag]]
  dd <- centreCATI(subset(d, ShapeName == shape & !is.na(Beta_SG6_IRLS)))
  f0 <- bf(Beta_SG6_IRLS ~ Visit + CATI_Total_c + (1 | ParticipantID) +
             (1 | ParticipantID:Visit) + (1 | ParticipantID:Session))
  fitArgs <- list(data = dd, family = gaussian(), prior = priors_mlm, chains = CHAINS,
                  iter = ITER, warmup = WARMUP, seed = SEED, refresh = 0,
                  control = list(adapt_delta = 0.95, max_treedepth = TREEDEPTH), file_refit = "on_change")
  m_main <- do.call(brm, c(list(formula = f0, file = file.path(fitDir, paste0(tag, "_main", fitSfx))), fitArgs))
  m_int  <- do.call(brm, c(list(formula = bf(Beta_SG6_IRLS ~ Visit * CATI_Total_c + (1 | ParticipantID) +
                                  (1 | ParticipantID:Visit) + (1 | ParticipantID:Session)),
                                file = file.path(fitDir, paste0(tag, "_interaction", fitSfx))), fitArgs))
  m_main <- add_criterion(m_main, "loo"); m_int <- add_criterion(m_int, "loo")
  lc <- loo_compare(m_main, m_int, criterion = "loo")

  # Variance shares (main model: CATI explains about none of the person variance)
  p <- as_draws_df(m_main)
  v <- cbind(person = p$sd_ParticipantID__Intercept^2,
             personVisit = p$`sd_ParticipantID:Visit__Intercept`^2,
             personSession = p$`sd_ParticipantID:Session__Intercept`^2,
             trial = p$sigma^2)
  sh <- v / rowSums(v)
  vs <- data.frame(Shape = shape, Component = colnames(sh),
                   t(apply(sh, 2, quantile, c(.05, .5, .95))), row.names = NULL, check.names = FALSE)

  # Participant level: standardised mean beta ~ standardised measure (slope about r)
  ps <- participantSummary(dd)
  bc <- bind_rows(lapply(PERSON_VARS, function(vn) {
    cd <- data.frame(y = as.numeric(scale(ps$mean_Beta)), x = as.numeric(scale(ps[[vn]])))
    b  <- as_draws_df(update(cor_template, newdata = cd, recompile = FALSE, chains = CHAINS,
                             iter = ITER, warmup = WARMUP, seed = SEED, refresh = 0))$b_x
    data.frame(Shape = shape, Measure = vn, n = nrow(cd), slope_std = mean(b),
               CI_low = unname(quantile(b, .025)), CI_high = unname(quantile(b, .975)),
               P_positive = mean(b > 0))
  }))

  list(effects = rbind(post_summary(m_main, shape, "main"), post_summary(m_int, shape, "interaction")),
       loo = data.frame(Shape = shape, Model = rownames(lc), lc[, c("elpd_diff", "se_diff")], row.names = NULL),
       diag = rbind(diag_row(m_main, shape, "main"), diag_row(m_int, shape, "interaction")),
       shares = vs, cor = bc)
}

res <- lapply(setNames(todo, todo), function(tg) { message("Fitting ", SHAPES[[tg]]); run_brms_shape(tg) })
pick <- function(k) bind_rows(lapply(res, `[[`, k))
writeChecked(pick("effects"), file.path(od, "bayes_fixedEffects_N48.csv"))
writeChecked(pick("loo"),     file.path(od, "bayes_looCompare_N48.csv"))
writeChecked(pick("diag"),    file.path(od, "bayes_diagnostics_N48.csv"))
writeChecked(pick("shares"),  file.path(od, "bayes_varianceShares_N48.csv"))
writeChecked(pick("cor"),     file.path(od, "bayes_participantSlopes_N48.csv"))
print(pick("diag"), row.names = FALSE)
print(pick("shares"), row.names = FALSE, digits = 3)
if (!all(pick("diag")$OK)) warning("Some fits failed the convergence checks; see bayes_diagnostics_N48.csv")
message("Done: ", od)
