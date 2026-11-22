# loadHandoverWithScores.R
# Shared loader for the R mixed-model scripts in src/R (adapted from Harvey Neal's
# HarveyR scripts, 17 Nov 2026). Finds the repo root, reads the N=48 handover CSV
# and the CATI/M-EDL full-scores sheet, merges them by participant, and fails
# loudly on any mismatch.

HANDOVER_CSV <- "StudentDataset_2026_SG6IRLS_20261109_113130.csv"
SCORES_XLSX  <- file.path("data", "CATI and M-EDL scores anonymised_fullScores.xlsx")
PERSON_VARS  <- c("CATI_Total", "M_EDL_Total", "Social_Interactions", "Communication",
                  "Social_Camouflage", "Self_Regulatory_Behaviours",
                  "Cognitive_Inflexibility", "Sensory_Sensitivity")
SHAPES       <- c(phi04 = "phi=0.4", phi08 = "phi=0.8", ellipse = "Ellipse",
                  square = "Square", cursive = "Cursive")

# Repo root = first folder at or above the working directory holding src/ and data/
findRepoRoot <- function(start = getwd()) {
  d <- normalizePath(start)
  repeat {
    if (dir.exists(file.path(d, "src")) && dir.exists(file.path(d, "data"))) return(d)
    up <- dirname(d)
    if (up == d) stop("Repo root not found above ", start,
                      " (need a folder holding src/ and data/). Run from the repo or src/.")
    d <- up
  }
}

# Handover CSV lives in <root>/handover (PC layout) or <root>/../handover (M5 Dropbox layout)
findHandover <- function(root) {
  cand <- file.path(c(root, dirname(root)), "handover", HANDOVER_CSV)
  hit  <- cand[file.exists(cand)]
  if (!length(hit)) stop("Handover CSV not found. Looked in:\n  ", paste(cand, collapse = "\n  "))
  hit[1]
}

loadHandoverWithScores <- function(root = findRepoRoot()) {
  d <- read.csv(findHandover(root))
  xl <- file.path(root, SCORES_XLSX)
  if (!file.exists(xl)) stop("Scores sheet not found: ", xl)
  # Row 1 holds group labels ("CATI Scores", "M-EDL Scores"); row 2 the column names
  s <- as.data.frame(readxl::read_excel(xl, skip = 1))
  names(s)[names(s) == "Particpant Number"] <- "ParticipantID"   # typo in the sheet
  miss <- setdiff(c("ParticipantID", PERSON_VARS), names(s))
  if (length(miss)) stop("Scores sheet lacks columns: ", paste(miss, collapse = ", "))
  s <- s[, c("ParticipantID", PERSON_VARS)]
  s[] <- lapply(s, as.numeric)
  if (anyNA(s)) stop("Scores sheet has empty or non-numeric cells")
  if (anyDuplicated(s$ParticipantID)) stop("Duplicate participant numbers in scores sheet")
  sub <- c("Social_Interactions", "Communication", "Social_Camouflage",
           "Self_Regulatory_Behaviours", "Cognitive_Inflexibility", "Sensory_Sensitivity")
  bad <- s$ParticipantID[rowSums(s[, sub]) != s$CATI_Total]
  if (length(bad)) stop("CATI subscales do not sum to CATI_Total for: ", paste(bad, collapse = ", "))

  idD <- sort(unique(d$ParticipantID)); idS <- sort(s$ParticipantID)
  if (!identical(as.numeric(idD), as.numeric(idS)))
    stop("Participant sets differ. Only in trials: ", paste(setdiff(idD, idS), collapse = ","),
         "; only in scores: ", paste(setdiff(idS, idD), collapse = ","))
  d <- merge(d, s, by = "ParticipantID", all.x = TRUE, sort = FALSE)

  d$ParticipantID <- factor(d$ParticipantID)
  d$Visit         <- factor(d$Visit)
  d$Session       <- factor(d$Session)   # 1-6 overall, so PID:Session is nested in visit
  message(sprintf("Loaded %d trials, %d participants, scores from %s",
                  nrow(d), nlevels(d$ParticipantID), basename(xl)))
  d
}

# Timestamped output folder under reports/R (reports/ is git-ignored)
makeOutDir <- function(root, tag) {
  od <- file.path(root, "reports", "R", paste0(tag, "_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  if (!dir.create(od, recursive = TRUE)) stop("Could not create ", od)
  od
}

# Write a CSV and confirm it landed (fail loud)
writeChecked <- function(x, f) {
  write.csv(x, f, row.names = FALSE)
  if (!file.exists(f) || file.size(f) == 0) stop("Write failed: ", f)
  message("Wrote ", f)
}

# One row per participant: mean beta plus the person-level scores
participantSummary <- function(dd) {
  dd |>
    dplyr::group_by(ParticipantID) |>
    dplyr::summarise(mean_Beta = mean(Beta_SG6_IRLS, na.rm = TRUE),
                     dplyr::across(dplyr::all_of(PERSON_VARS), dplyr::first),
                     .groups = "drop")
}

# Grand-mean-centre CATI on one value per person (not per trial)
centreCATI <- function(dd) {
  pc <- dd[!duplicated(dd$ParticipantID), "CATI_Total"]
  dd$CATI_Total_c <- dd$CATI_Total - mean(pc)
  dd
}
