# Claims register

*Created 2026-11-22. One row per claim the paper may make, with its value, the output file it comes from, the date it was set, and its status. When a number changes, update the row here and move the old value to "Superseded claims" rather than deleting it.*

**Status:** **current** = holds for the final run and may be quoted; **open** = not yet settled, do not quote as fact; **superseded** = replaced by a later fix or run, kept so old drafts can be checked.

**Sources.** Every value comes from a script output in `data/processed/` (not in this repository; see README, "Data"). The methods and decision log are in `docs/AnalysisPipeline.md` and `docs/SensitivityPlan_N48.md`. The project's internal log and to-do list are kept outside the repository; this register summarises the claims in them that can be made public.

**Final run (all current values unless stated):** `trial_level_results_20261109_112129` and `icc_results_20261109_112131` (N=48, 5.209 points/mm, Pencil samples only), downstream refreshed by `refreshDownstream_2026`, headline numbers in `keyNumbers_20261109_120558.txt` (`summariseKeyNumbers_2026`). Primary measure: Beta_SG6_IRLS, between-visit ICC(A,1), class from the 95% CI lower bound (Koo & Li 2016).

Shape codes: 1 phi=0.4, 2 phi=0.8, 3 Ellipse, 4 Square, 5 Cursive.

## A. Sample and design

| ID | Claim | Value | Source | Date | Status |
|---|---|---|---|---|---|
| A1 | Participants recruited / complete | 51 took part, 48 complete (45 originals + replacements 401, 402, 403); 101, 102, 214 excluded as non-completers | `preflightN48_2026` inventory | 2026-11-09 | current |
| A2 | Stopping rule | Replace non-completers only; 48 final whatever the results; a replacement who drops out is not replaced; set before any replacement data existed | Sample rule, `docs/SensitivityPlan_N48.md` | 2026-10-12 | current |
| A3 | Trials in final run | 14,388 trials; Beta_SG6_IRLS 0.190 +/- 0.105; 0.26% NaN; 240 Hz throughout | `keyNumbers_20261109_120558.txt` | 2026-11-09 | current |
| A4 | Ellipse trials (reconciled) | **2,879 analysed** (2,873 with a finite SG6_IRLS beta). 2,880 scheduled (48 x 2 visits x 3 sessions x 10); 1 has no samples in the raw file (ID305, visit 1, trial 21), so 2,879 were recorded. The companion simulation paper's importer (`importDB_fraser_v002`) keeps 2,877: it also rejects 2 trials whose recorded clock drifts 12.3 and 12.5 ms from a uniform 240 Hz clock (ID202 and ID204, limit 10 ms); both are in this run with finite beta. Its older corpus of 2,829 is 45 complete participants x 60 - 1 plus 130 trials from non-completers 101, 102, 214 (before 401 to 403 existed). Every trial's status is in the `_trials.csv` | `ellipseCountReconciliation_20261122_082713_summary.csv` / `_trials.csv` (`reconcileEllipseCounts_2026`) | 2026-11-22 | current |
| A5 | Retest interval | Median 8.0 d (IQR 7.0 to 13.1, range 6.0 to 43.2); 11 of 48 over 14 d, 2 over 28 d (IDs 203, 204) | `retestInterval_N48_20261109_161028.csv` | 2026-11-09 | current |
| A6 | Framing of N | N=48 comes from a student a-priori ANCOVA power calculation (L10), not an ICC target, so ICCs are estimation and Zou N per shape is planning information. N=48 primary, N=45 (originals) supplementary | `src/R/powerCalcN48.R` | 2026-11-23 | current (supersedes the 2026-11-01 "preregistered Pearson design" wording, S13) |

## B. Data handling (fixes that changed earlier numbers)

| ID | Claim | Value | Source | Date | Status |
|---|---|---|---|---|---|
| B1 | Trajectory scale | Raw x,y are UIKit points, **5.209 points/mm** (M4 13" iPad Pro). Single source `ipadPointsPerMm.m` | `docs/AnalysisPipeline.md`, "Trajectory scale" | 2026-11-02 | current (supersedes 9.73 and 10.418, see S1, S2) |
| B2 | Scale fix effect | mm, mm/s, mm/s^2, mm/s^3 and PathLength_mm x1.868; VGF x1.868^(1-beta); SG6_IRLS beta max change 3.3e-4, ICC max change 0.0005, no class change | `trial_level_results_20261102_150632` | 2026-11-02 | current |
| B3 | Finger/palm touches | `touch_type` 0 in 926 trials (all shapes, 34 participants), sharing one `touch_index` counter with the Pencil. Fix: keep `touch_type == 2` and renumber (`pencilSamplesOnly.m`) | `docs/AnalysisPipeline.md`, "Finger and palm touches" | 2026-11-09 | current |
| B4 | Touch fix effect on beta | Beta ICCs unchanged (SG6_IRLS change <= 0.0005, no class change in any beta pipeline); 13,462 clean trials identical to the 3 Nov run | `touchFixRunCheck_ICC_20261109_113047.csv` | 2026-11-09 | current |
| B5 | Touch fix effect on peak kinematics | Peak velocity, acceleration and jerk ICCs rise on templated shapes and fall on Cursive; class changes: PeakVelocity_SG phi=0.8 moderate to good, Cursive poor to moderate | same | 2026-11-09 | current (supersedes all pre-fix peak-kinematic ICCs, S3) |
| B6 | Pen-lift timing | Cursive time base taken from `time_seconds` residual (`detectPenLifts.m`); templated shapes unchanged | `docs/AnalysisPipeline.md`, "Pen lifts in Cursive" | 2026-07-16 | current (any Cursive kinematics before this date are stale) |
| B7 | Two import rule sets exist for the same raw files | This run (`runAnalysis_2026`): Pencil samples only (`touch_type == 2`), 50-sample edge clip, uniform clock t = touch_index/240, pen lifts where the clock residual steps by more than 12.5 ms, each stroke differentiated separately and all strokes pooled in one regression, no clock-drift rejection, all five shapes. Companion importer (`importDB_fraser_v002`, Ellipse only): Pencil only, 50-sample edge clip, split at `time_seconds` gaps over 20 ms and keep the longest piece, reject clock drift over 10 ms, uniform 240 Hz clock. The paper must cite the rules that produced its numbers (this run's) | `runAnalysis_2026.m`, `detectPenLifts.m`, `calculatePowerLaw.m`; `importDB_fraser_v002.m` header | 2026-11-22 | current (which set the paper cites: J11) |

## C. Primary result: between-visit reliability of beta (N=48)

| ID | Shape | ICC(A,1) [95% CI] | Class (LB) | Zou N required (p0 0.75, power 0.80) | Source | Status |
|---|---|---|---|---|---|---|
| C1 | phi=0.8 | 0.878 [0.782, 0.932] | good | 41 (cleared at 48) | `icc_results_20261109_112131`, `icc_power_output.csv` | current |
| C2 | phi=0.4 | 0.850 [0.748, 0.913] | moderate (LB just under 0.75; do not round up) | 78 | same | current |
| C3 | Square | 0.862 [0.765, 0.920] | good | 59 | same | current |
| C4 | Ellipse | 0.791 [0.655, 0.877] | moderate | 620 | same | current |
| C5 | Cursive | 0.385 [0.117, 0.601] | poor | none (ICC below p0) | same | current |

- **C6** Only phi=0.8 clears its Zou N; phi=0.8 and Square have LB above 0.75. Report required N per shape, not one planned N. *current*
- **C7** Cursive is poor because the free-text content differs between visits, not because of N: within-visit ICC 0.82 / 0.81; without IDs 202 and 302 ICC 0.769 [0.618, 0.865] (post hoc, footnote only). Source `diagnoseShapeStability_2026(5)`, 2026-11-09. *current*
- **C8** Required N is very sensitive to where the LB sits near 0.75 (pilot N=61 gave 34 / 41 / 65 for phi=0.4 / phi=0.8 / Ellipse). *current*
- **C10** Model choice does not change the result: ICC(A,1) 0.850 / 0.878 / 0.791 / 0.862 / 0.385 and ICC(3,1) 0.849 / 0.889 / 0.788 / 0.866 / 0.384 (phi=0.4 / phi=0.8 / Ellipse / Square / Cursive), so the only gap above 0.005 is phi=0.8 (the visit-2 shift, F4). The registered ANCOVA and the Bayesian model give CATI slopes that agree to about 1e-5, and every CI spans 0 (I4, K4). Neither ICC form was registered; the pre-registrations named Pearson r (J14). Source `reliabilityModelCompare_20261124_221001.csv` from `src/functions/compareReliabilityModels_2026.m`, 2026-11-24. *current*
- **C9** Abstract line: beta from templated tracing shows moderate-to-good between-visit reliability (ICC 0.79 to 0.88, N=48) and outperforms jerk; free-text handwriting does not, because the stimulus differs between visits. *current*

## D. Beta versus jerk (N=48)

| ID | Claim | Value | Source | Date | Status |
|---|---|---|---|---|---|
| D1 | Mean jerk ICC(A,1), MeanJerk_SG | phi=0.4 0.656 [0.457, 0.791]; phi=0.8 0.657 [0.459, 0.792]; Ellipse 0.337 [0.060, 0.566]; Square 0.518 [0.275, 0.698]; Cursive 0.428 [0.170, 0.633]; all poor by the LB rule | `icc_results_20261109_112131` | 2026-11-09 | current |
| D2 | Beta beats jerk | On all four templated shapes | same | 2026-11-09 | current |
| D3 | Cursive | Jerk nominally above beta (0.428 vs 0.385), CIs overlap: write "neither is reliable", not "jerk is better" | same | 2026-11-03 | current (supersedes the N=31 flip, S6) |

## E. Absolute beta versus theory

| ID | Claim | Value | Source | Date | Status |
|---|---|---|---|---|---|
| E1 | Beta below Huh & Sejnowski theory, graded | SG6_IRLS 0.236 / 0.249 / 0.189 / 0.092 = 38 / 47 / 57 / 52% of theory (0.620 / 0.528 / 0.330 / 0.176) for phi=0.4 / phi=0.8 / Ellipse / Square | `beta_vs_theory_20261109_113603.csv` | 2026-11-09 | current |
| E2 | Not a regression artefact | BW_Linear within 0.008 to 0.018 of SG6_IRLS | same | 2026-11-09 | current |
| E3 | Claim is reliability under a fixed pipeline, not absolute beta | Beta is strongly filter-cutoff dependent (`sweepFilterCutoff_2026`, `iccVsCutoff_2026`) | `docs/AnalysisPipeline.md` | 2026-07 | current |
| E4 | H&S formula uses phi^2 in the denominator, not phi^2/2 | Correction logged | `reportNoteEvidence_2026` | 2026-07 | current |

## F. Stability and agreement (N=48)

| ID | Claim | Value | Source | Date | Status |
|---|---|---|---|---|---|
| F1 | MDC95 as % of mean beta | 29 to 54% (good for ranking, coarse for individual change) | `stability_agreement_N48_20261109_113547.csv` | 2026-11-09 | current |
| F2 | Individuals beyond MDC95 | 41 of 48 never; IDs 209 and 321 in 2+ shapes | `stability_individual_N48_20261109_113547.csv` | 2026-11-09 | current |
| F3 | Spearman flatters Cursive | Spearman 0.71 vs ICC 0.385 | same | 2026-11-09 | current |
| F4 | phi=0.8 visit-2 shift | +0.017 [0.003, 0.032] (visit 2 about 7% higher); CI excludes 0 | `tostShift_N48_20261109_115259.csv` | 2026-11-09 | current |
| F5 | Shift TOST, margin +/-0.03 | All five shapes equivalent (phi=0.8 narrowly, p = 0.042; fails at +/-0.02). Margin is an equivalence margin, not an MDC | same | 2026-11-09 | current |
| F6 | Corridor of stability +/-0.05 | nStable95 40 / 37 / 43 / 27 / 47 (phi=0.4, phi=0.8, Ellipse, Square, Cursive); Cursive not stable | `corridorSummary_N48_20261109_115303.csv` | 2026-11-09 | current (corridor permutes one sample, so overstates stability) |

## G. Measurement error and tempo (N=48)

From `semReliability_N48_20261115_205624.csv` (`reportSEMReliability_2026`, `extractTrialTempo_2026`); write-up in `docs/SEM_Tempo_Reliability_N48.md`. Adopted 2026-11-15 from the companion simulation project's recommendations, points 1 to 5 (point 6, beta_gen*, stays in that paper).

| ID | Claim | Value | Date | Status |
|---|---|---|---|---|
| G1 | SEM_A / MDC95 [CI] | phi=0.4 0.046 / 0.128 [0.098, 0.159]; phi=0.8 0.037 / 0.101 [0.070, 0.134]; Ellipse 0.034 / 0.093 [0.070, 0.117]; Square 0.010 / 0.027 [0.020, 0.035]; Cursive 0.025 / 0.070 [0.029, 0.105] | 2026-11-15 | current |
| G2 | A 0.03 group difference is not detectable in one person | MDC95 is 3 to 4x 0.03 for phi=0.4, phi=0.8, Ellipse (CI LBs above 2x); Square reaches it but 0.03 is a third of its mean | 2026-11-15 | current |
| G3 | Tempo is reliable | Tempo ICC(A,1) 0.77 to 0.86 (templated shapes) | 2026-11-15 | current |
| G4 | Ellipse spread is largely tempo | Tempo-adjusted Ellipse ICC 0.79 to 0.51 (between-person SD 0.065 to 0.026); phi=0.8 0.88 to 0.76; phi=0.4 and Square barely change | 2026-11-15 | current (descriptive, not pre-registered) |
| G5 | phi=0.8 shift is about a third tempo | +0.017 to +0.012 [-0.000, 0.024] after adjustment; r(delta beta, delta log tempo) 0.54 | 2026-11-15 | current |
| G6 | Tempo frequency of templated shapes | Median speed spectrum F50 0.94 Hz (check a possible ~1 Hz threshold) | `docs/AnalysisPipeline.md` | 2026-07 | open |
| G7 | MDC95 against 0.03 and against the 0.0108 SEM limit | 0.0108 = 0.03/2.77 is an SEM limit, so compare SEM with 0.0108 and MDC95 with 0.03; the two ratios are the same (MDC95 = 2.772 x SEM). SEM_A / 0.0108 [CI]: phi=0.4 4.3 [3.3, 5.3]; phi=0.8 3.4 [2.3, 4.5]; Ellipse 3.1 [2.3, 3.9]; Square 0.88 [0.65, 1.16]; Cursive 2.3 [0.97, 3.5]. No shape meets either limit on its CI upper bound; Square meets both on the point estimate only. MDC95 / 0.0108 (8.6x for Ellipse) mixes an MDC with an SEM limit and should not be reported. The companion limit is a within-occasion pipeline repeatability; this SEM is between visits days apart, so it also contains day-to-day change | `mdcThresholdComparison_20261122_082835.csv` (`compareMDCThresholds_2026`) | 2026-11-22 | current |

## H. Robustness and sensitivity

| ID | Claim | Value | Source | Date | Status |
|---|---|---|---|---|---|
| H1 | Pipeline robustness (2x3 grid) | Templated shapes move by at most 0.041 ICC; 1 of 25 paired-bootstrap delta-ICC CIs excludes 0 (Square SG6_LMLS +0.038, uncorrected); primary ranks 6th of 6 for Ellipse and Square | `pipelineRobustness_N48_20261109_113559.csv` | 2026-11-09 | current |
| H2 | Cursive pipeline spread | ICC 0.16 to 0.61 across pipelines, CIs wide | same | 2026-11-09 | current |
| H3 | Pipeline choice framed on validity, not reliability | Do not claim the vetted protocol is more reliable | Fraser et al. 2025 | 2026-10-08 | current |
| H4 | N=45 vs N=48 | ICC N=45 / N=48: phi=0.4 0.852 / 0.850; phi=0.8 0.882 / 0.878; Ellipse 0.792 / 0.791; Square 0.864 / 0.862; Cursive 0.351 / 0.385. Zou N in the same shape order 75 / 38 / 567 / 56 vs 78 / 41 / 620 / 59. Max templated |dICC| 0.0034, no class change, 20/20 leave-3-out flags ok, max replacement |z| 1.93, all 15 permutation Holm p = 1 | `cohort*_N45vsN48_20261109_160648.csv` | 2026-11-09 | current |
| H5 | Replacements' mean beta | Lower than originals on all four templated shapes by 0.012 to 0.048, not significant; cohort, experimenter and time confounded. Footnote | same | 2026-11-03 | current |
| H6 | Leave-3-out instability of borderline classes | Koo & Li class flips in 27% (phi=0.4) and 33% (Square) of 3-person removals, 0.4% phi=0.8, 0.2% Ellipse | `leaveKOut_N45_k3_20261101_222510.csv` (frozen N=45 baseline) | 2026-11-01 | current, but computed on the pre-fix baseline; re-run on the rebuilt baseline before quoting exact % |
| H7 | Non-completers resemble completers | 33 of 35 values ok; ID102 V2 phi=0.4 outside95, V1 Ellipse SUSPECT (consistently high-beta, 2 sessions) | `orphanRuns_20261109_120047.csv` | 2026-11-09 | current |
| H8 | Retest interval does not drive ICC | Dropping gaps > 28 d changes ICC by <= 0.016, no class change; <= 14 d subset within CIs; Square rho(gap, abs change) -0.44 is confounded with cohort | `retestInterval_N48_20261109_161028.csv` | 2026-11-09 | current |

## I. Exploratory trait correlations (N=48)

| ID | Claim | Value | Source | Date | Status |
|---|---|---|---|---|---|
| I1 | CATI_Total and M-EDL vs beta and jerk | 1 of 20 Spearman CIs excludes 0, only just (M-EDL vs Cursive beta -0.27 [-0.52, -0.00]); about 1 expected by chance. CATI about 0 throughout; M-EDL vs beta consistently negative (-0.10 to -0.28) | `exploratory_traitKinematics_N48_20261109_113543.csv` | 2026-11-09 | current, exploratory |
| I2 | CATI subscale labels | Assumed published English et al. 2021 order; `LABELS_VERIFIED = false`. 2026-11-22: Harvey Neal's sheet (`data/CATI and M-EDL scores anonymised_fullScores.xlsx`, values identical) labels the columns in the same order as Social Interactions, Communication, Social Camouflage, Self-Regulatory Behaviours, Cognitive Inflexibility, Sensory Sensitivity | `mergeQuestionnaires_2026` | 2026-10-08 | **open** (ask Harvey whether the headers came from the scoring sheet) |
| I3 | M-EDL zeros | 18 of 48 exact zeros (401 and 402 added two), meaning unknown | questionnaire sheet | 2026-11-03 | **open** |
| I4 | Registered mediation CATI_Total -> beta -> jerk (run 2026-11-22) | Indirect effect null in every shape (bootstrap CIs span 0, Holm p = 1); a-path 0.04 to 0.06 (phi=0.4, phi=0.8, Ellipse), Square 0.08, Cursive -0.09, all CIs spanning 0; the beta-jerk b-path is large on templated shapes (0.57 to 0.75) because both come from the same kinematics, not a trait effect. Agrees with I1 | `src/R/mediation_N48.R` | 2026-11-22 | current, registered (CATI subscale labels unverified, I2) |
| I5 | Registered repeated-measures ANCOVA on beta, Shape x Visit with CATI_Total as covariate (run 2026-11-22) | No CATI effect (CATI p = .74, CATI x Shape p = .94, CATI x Visit p = .52). Shape x Visit p = .059 with 5 shapes, .087 with the 4 templated shapes as registered; only phi=0.8 shifts between visits (+0.017, Holm p = .049, as F4). Normality imperfect (Shapiro-Wilk p < .05 in 7 of 10 cells, residual excess kurtosis 2.2), but the registered skew-based transformation rule did not trigger | `src/R/regAncova_N48.R` | 2026-11-22 | current, registered |
| I6 | ANCOVA sensitivity (registered exploratory plan and skew rule, run 2026-11-23) | M-EDL as covariate instead of CATI: main effect p = .18 (5 shapes) / .23 (4 templated), all M-EDL interactions p > .5, slopes negative on every shape with CIs spanning 0 (M-EDL has 18 exact zeros, I3). Log and square-root beta: CATI main effect p = .68 to .73, CATI interactions p > .5, Shape x Visit p = .058 to .064 (5 shapes) / .12 to .20 (4 templated). phi=0.8 visit shift Holm p = .049 raw, .051 with M-EDL, .057 log: borderline, do not call it significant. Cohen's f: CATI main effect 0.05, Shape x Visit 0.22, both far below the f = 0.5 used to plan N (L10) | `src/R/regAncova_N48.R` | 2026-11-23 | current, exploratory |

## K. Variance decomposition of trial-level beta (N=48, supplementary)

Model per shape: `Beta_SG6_IRLS ~ Visit + (1|ParticipantID) + (1|ParticipantID:Visit) + (1|ParticipantID:Session)` on all trials (Harvey Neal's model, adapted in `src/R`). Decided 2026-11-22: supplementary table, ICC(A,1) (section C) stays primary.

| ID | Claim | Value | Source | Date | Status |
|---|---|---|---|---|---|
| K1 | Variance shares, brms median [90% CrI]: person / person x visit / person x session / trial | phi=0.4 0.70 [0.61, 0.79] / 0.10 / 0.05 / 0.14; phi=0.8 0.75 [0.67, 0.82] / 0.07 / 0.05 / 0.13; Ellipse 0.62 [0.51, 0.72] / 0.13 / 0.07 / 0.17; Square 0.58 [0.49, 0.68] / 0.06 / 0.06 / 0.30; Cursive 0.20 [0.07, 0.33] / 0.30 [0.21, 0.44] / 0.06 / 0.42. All fits max Rhat <= 1.005, min bulk ESS >= 1,054, 0 divergences (Square and Cursive needed iter 6000, max_treedepth 12). Shares are for a single trial; a visit mean averages about 30 trials, so trial noise shrinks (Square's 58% person share still gives visit-mean reliability 0.87, K2) | `varianceSupplement_N48_20261122_114442/varianceSupplementTable_N48.csv` (from `mixedModel_N48_20261122_090238`, `bayesMixedModel_N48_20261122_090425` and `_095529`) | 2026-11-22 | current |
| K2 | Decomposition reproduces the ICCs | Implied reliability of a visit mean (lmer, REML; person / (person + PxV + PxS/3 + trial/n)) 0.849 / 0.889 / 0.788 / 0.867 / 0.384 equals the between-visit consistency ICC(3,1) from `runICC_2026` (0.849 / 0.889 / 0.788 / 0.866 / 0.384, max difference 0.0005); also reproduced in MATLAB `fitlme`. Like ICC(3,1) it ignores the mean visit shift, so it sits 0.011 above ICC(A,1) for phi=0.8 (F4) and within 0.005 elsewhere. `runICC_2026` averages trials to session means, then session means to visit means, then computes ICC on the 48 x 2 visit-mean matrix | same; `varianceDecompHarvey_2026.m`; `icc_results_20261109_112131` | 2026-11-22 | current |
| K3 | Why Cursive is poor and Square is not | Cursive: 30% person x visit (content differs between visits, supports C7). Square: lowest person share of the templated shapes but 30% is trial noise, which averaging over about 30 trials removes | same | 2026-11-22 | current |
| K4 | CATI as person-level predictor | No CATI main effect or Visit x CATI interaction in any shape (lmer all p > 0.26; brms all 95% CrIs include 0); LOO prefers the main-effects model throughout (Cursive LOO has 1 to 2 Pareto k > 0.7). No participant-level questionnaire correlation reaches p < .05 uncorrected (Pearson or Spearman, mean beta over both visits). Agrees with I1 | `mixedModel_N48_20261122_090238`, `bayesMixedModel_N48_*` | 2026-11-22 | current, exploratory |

## M. Literature context (cross-domain, not group-delta evidence)

Uppal et al. 2026, bioRxiv, doi 10.64898/2026.11.23.768645: fMRI test-retest. Context for the discussion only.

| ID | Claim | Value | Relevance here | Date | Status |
|---|---|---|---|---|---|
| M1 | Design | N=25 healthy adults, 2 sessions 7 to 14 d apart, 4 tasks; ICC(3,1) only, plus group Dice and Spearman | Comparable interval to ours (A5); they report consistency only, we report ICC(A,1) and ICC(3,1) (C10) | 2026-11-28 | current |
| M2 | Individual ROI reliability | ICC N-back 0.42 to 0.49, OASIS 0.21 to 0.27, MID and Go/No-Go < 0.15 | Templated-shape beta (0.79 to 0.88, C1 to C4) sits well above typical task-fMRI reliability | 2026-11-28 | current |
| M3 | Task dominates pipeline | Across 12 denoising pipelines, task drove reliability more than pipeline; pipeline mattered most for the weakest tasks | Parallels H1 and H2: templated shapes move by at most 0.041, Cursive spans 0.16 to 0.61 | 2026-11-28 | current |
| M4 | Group exceeds individual reliability | Group Dice about 0.8, Spearman > 0.95 (N-back), above individual ICC | Same pattern as F3 (rank agreement flatters individual agreement) | 2026-11-28 | current |
| M5 | CI method not comparable | Their ICC CIs are mean +/- 1.96 SD/sqrt(N voxels), not subject-level; ours are subject-level | Do not compare CI widths directly | 2026-11-28 | current |

## L. Sample-size planning: the pilot power calculation (N=61)

Zou (2012) via `ICC.Sample.Size::calculateIccSampleSize(p, p0 = 0.75, k = 2, alpha = 0.05, tails = 1, power = 0.80)`, with p the between-visit ICC(A,1) of SG+IRLS beta from the analysis_2025 pilot (N=61). The same settings are used for the final run (`icc_power_analysis.R`). The calculation was set as the MSc students' exercise (January 2026). Inputs: `analysis_2025/results/IRLS_ICC_PilotData.csv`; output: `analysis_2025/results/icc_power_output.csv` (both 2026-03-15, not in this repository).

| ID | Shape | Pilot ICC(A,1) [95% CI], N=61 | Required N (pilot) | N=61 enough? | Required N (final run, N=48; C1 to C5) |
|---|---|---|---|---|---|
| L1 | phi=0.4 | 0.888 [0.750, 0.943] | 34 | yes | 78 |
| L2 | phi=0.8 | 0.878 [0.584, 0.949] | 41 | yes | 41 |
| L3 | Ellipse | 0.858 [0.623, 0.934] | 65 | no (just) | 620 |
| L4 | Square | 0.785 [0.663, 0.866] | 827 | no | 59 |
| L5 | Cursive | 0.814 [0.708, 0.884] | 227 | no | none (ICC below p0) |

- **L6** In the pilot, Square and Cursive needed very large N. The final study reverses this for Square (59) and makes Ellipse the hard templated shape (620). Cursive goes from 0.81 to 0.39, consistent with free text differing between visits (C7). Required N moves a lot with small changes in ICC near p0 = 0.75 (C8), so a pilot estimate is a weak guide to the final N. *current*
- **L7** No pilot-based N was adopted as the study's target: the original aim was N=80, and N=48 came from a student a-priori ANCOVA calculation (L10, A6), so the final ICCs are estimation and required N is planning information. Cite this Zou analysis for ICC precision, not the students' formative preregistration. *current*
- **L8** Pilot ICC(3,1) (consistency) for comparison: 0.911 / 0.921 / 0.897 / 0.794 / 0.811 (`IRLS_ICC31_PilotData.csv`). *current, not used for N*
- **L9** The pilot's hard-coded values in `powerAnalysisICC_2025.m` (e.g. phi=0.8 0.880) differ from its CSV in the third decimal; the Zou N above came from the CSV. *current (minor)*
- **L10** N=48 reproduces from a fixed-effects ANCOVA power calculation (G*Power settings): f = 0.5, alpha .05, power .80, 3 numerator df, 4 groups, 1 covariate, denominator df 43, lambda 12 (actual power 0.802; G*Power 3.1.9.7, confirmed against the original G*Power output); with 20% dropout the recruitment target was 58. f = 0.5 is above Cohen's large effect (0.40); the same design needs N=73 at f = 0.40 and N=179 at f = 0.25. The pilot Zou N in L1 to L5 reproduces exactly; a pilot ICC of about 0.871 would have given N=48. Source `src/R/powerCalcN48.R`, 2026-11-23. *current*

## J. Release and repository items (open)

| ID | Item | Status |
|---|---|---|
| J1 | Data release staged (current run only, session times as day offsets, MD5 manifest) but NOT published; blocked on consent wording, CATI subscale order (I2) and M-EDL zeros (I3) | open |
| J2 | Data DOI (Zenodo or OSF) and README link | open |
| J3 | `CITATION.cff` authors: Fraser (first), Azizi, Neal (middle two alphabetical for now), Cook (last), set 2026-11-22, all four with ORCID | current |
| J4 | Trim `docs/AnalysisPipeline.md` for a public audience (it refers to internal notes) | open |
| J5 | Square spatial jump: 649 points (124.57 mm at 5.209) with no time gap, noted 2026-07-16. It is a finger sample (ID302, session 2026-06-03 145850, trial 25; `touch_type` 0 then 2), removed by the Pencil filter (B3); afterwards that trial's largest step is 0.77 mm. Over all 14,388 trials of the 48 included participants, every step > 10 mm without a clock gap involved a finger sample before the filter, and none remain after it, so every remaining jump is a real pen lift handled by `detectPenLifts`. Square after the filter: 16 of 2,879 trials contain a pen lift (the July "0% gapped" figure covered 6 participants only). Source `src/functions/diagnoseSpatialJumps_2026.m`, 2026-11-26 | resolved 2026-11-26 |
| J6 | Scripts not yet in this repository: `exportDataRelease_2026.m`, and the SEM/tempo set (`estimateTempoF0.m`, `extractTrialTempo_2026.m`, `semFromVisitMatrix_2026.m`, `reportSEMReliability_2026.m`, `test_semFromVisitMatrix_2026.m`, `docs/SEM_Tempo_Reliability_N48.md`) | open |
| J7 | Trial count off by one: the touch-fix diagnostic counts 14,389 trials and 13,463 clean, the final run 14,388 and 13,462 | open (minor) |
| J8 | Whether the iPad app logs `location(in:)` or `preciseLocation(in:)` (all x,y on whole or half points) | open |
| J9 | Pre-specification wording: "designated primary from the pilot and the 2025 protocol paper", not "preregistered", unless a timestamped registration is found | open |
| J10 | The companion repository's `data/fraser/README.md` still says "48 recruited, 45 usable (3 excluded for missing sessions), ~2,830 ellipse trials". Current: 51 took part, 48 complete, 2,879 Ellipse trials analysed here (A1, A4) | open (fix in that repository) |
| J11 | Which import rules the paper cites (B7): this run's rules (`runAnalysis_2026`); the companion importer's 2,877 is reported as a stricter Ellipse-only variant | decided 2026-11-22 (Dagmar) |
| J12 | B6 says templated shapes are single strokes, but the companion importer audit (3 Nov) found 51 Ellipse trials with `time_seconds` gaps over 20 ms. Count Ellipse trials with more than one stroke in this run | open |
| J13 | R scripts `src/R/*.R` (mixed and Bayesian models, supplementary table) and the `.gitignore` entry for `HarveyR/` added to this repository 2026-11-22. They need R with lme4, brms and readxl, the handover CSV and the full-scores sheet, none of which are in the repository | current |
| J14 | Student pre-registrations: a crosswalk of registered hypotheses against what was run is kept internally (registration content is not quoted here until dates, embargo status and permission are settled). The registered ANCOVA, mediation and normality checks were run 2026-11-22 (I4, I5). Open: protocol deviations to declare: retest registered within 7 days vs median 8 d (range 6 to 43, A5), registered stimuli and trial counts differ from those run (5 shapes, about 150 trials per visit), registered recruitment target 58 vs 48 + 3 replacements (A1, L10); the registrations named Pearson r for test-retest, not ICC, so both ICC(A,1) and ICC(3,1) are unregistered (C10); questionnaires were registered and collected at visit 1 only, so no visit-2 questionnaire test is possible; whether any registration was made live (the source of N=48 is now resolved, L10) | open |

## Superseded claims

| ID | Old claim | Replaced by | Why |
|---|---|---|---|
| S1 | Scale 9.73 px/mm (analysis_2025, Analysis_2026 before 2026-11-02, student handover of 2026-08-04) | B1, 5.209 points/mm | x,y are UIKit points; every mm quantity was 1.868x too small |
| S2 | Scale 10.418 (Fraser importer) | B1 | 2.00x too large in the other direction |
| S3 | Peak velocity, acceleration and jerk ICCs before 2026-11-09 (including the "Ellipse and Square peak-jerk ICCs 0.15 / 0.26" note) | B5 | Finger/palm samples inflated peaks; beta ICCs were not affected |
| S4 | N=45 interim (2026-08-04 frozen baseline): ICC 0.882 / 0.852 / 0.863 / 0.792 / 0.350; Zou N 38 / 74 / 57 / 577 | C1 to C5 at N=48; H4 for N=45 on the current pipeline | Final N=48; frozen baseline was pre-scale-fix and pre-touch-fix (archived) |
| S5 | 2026-11-03 N=48 run: Zou N 41 / 77 / 60 / 632; Cursive without 202/302 0.773; M-EDL vs Cursive beta -0.28 [-0.53, -0.01]; TOST phi=0.8 p 0.041 | C1 to C5, C7, I1, F5 | Touch-fix re-run |
| S6 | N=31 (2026-07-16): beta 0.941 / 0.898 / 0.875 / 0.868 / 0.323; Cursive "flip" (jerk 0.638 vs beta 0.323); jerk LB 0.41 to 0.42 labelled moderate | C, D3 | More participants; jerk is poor by the LB rule |
| S7 | N=45 stability: Spearman 0.70 vs ICC 0.35 (Cursive); grid range 0.045; 2 of 25 robustness CIs; Cursive pipeline range 0.143 to 0.558; 202/302 removal 0.350 to 0.753; 0 of 20 trait CIs | F3, H1, H2, C7, I1 | N=48 |
| S8 | "48 recruited, 45 complete" flow | A1 | 51 took part including 3 replacements |
| S9 | `cohort*_N45vsN48_20261109_120548` and comparisons against the frozen baseline (`*_20261103_151028`, `*_20261109_112137`) | H4 (`_160648`) | Same numbers without local paths; frozen-baseline comparisons mixed cohort with fixes |
| S10 | "runAnalysis_2026 and runICC_2026 call writetable unguarded" | `writeTableVerified.m` (PR #2) | Fixed 2026-11-09 |
| S11 | Ellipse trial count "2,829" (companion corpus) and "2,877" (companion draft) quoted as the study's count | A4 | Different cohort (2,829) and a stricter importer (2,877); the study's count is 2,879 |
| S12 | Ellipse Bayesian pilot (10 Nov): variance shares 61% person [90% interval 50, 71] / 14% person x visit / 7% person x session / 18% trial; default priors, Stan sampling warnings, labelled a demonstration | K1 | Final brms run converged (0.62 / 0.13 / 0.07 / 0.17); same shares |
| S13 | "N=48 was set by the students' preregistered Pearson design" (A6, 2026-11-01) | A6, L10 | No registration draft states 48; it reproduces from a student a-priori ANCOVA calculation (f = 0.5) |

## Conflicts found when this register was built

**Canonical docs disagree with themselves in a few places** (the internal to-do list still carries some N=45 numbers inside open items):

- phi=0.8 quoted as "ICC 0.882, CI lower bound 0.789": that is N=45 (S4). Use C1, 0.878 [0.782].
- phi=0.8 shift "about 6% higher": the N=48 value is about 7% (F4).
- "Templated shapes move by at most 0.045", "Spearman 0.70 vs ICC 0.35", "Cursive 0.143 to 0.558", "202 and 302 take ICC from 0.350 to 0.753": all N=45 (S7).
- "16 M-EDL zeros": now 18 of 48 (I3).
- The writetable guard and GitHub staging are listed as to-do but are done (S10).

**Stale copies of the docs and code in the project's shared folder** (not in this repository) differ from the canonical ones:

| Copy | State | Conflicts |
|---|---|---|
| `scale-fix/` (docs, `claude.md`, 4 code files) | 2026-11-01 to 02, superseded (has its own SUPERSEDED note) | N=45 interim table (S4), N=31 beta-vs-theory and Cursive flip (S6), "48 recruited, 45 complete" (S8); `runAnalysis_2026` and test predate the touch fix |
| `touch-fix/docs/` | 2026-11-09 midday | Cites `cohort*_20261109_120548` (S9); missing the GitHub, retest-interval and SEM entries |
| `touch-fix/docs-final/` | 2026-11-09 morning | Zou N 77 / 60 / 632 (S5), frozen-baseline N=45 column (S4), "45 complete" (S8), writetable guard still to do (S10) |
| `touch-fix/src`, root `.m` files | 2026-11-09 | `compareCohortsN45N48_2026`, `rebuildBaselineN45_2026`, `runAnalysis_2026`, `exportHandoverDataset_2026`, `zouCohort_M5.sh` differ from the repository versions (pre-guard, pre-path fix) |
| `github-release/pc-sync2/` | 2026-11-09 evening | `claude.md` cites `_120548` (S9); code identical to the repository |
| `github-release/pc-sync3/` | 2026-11-09 evening | Identical to canonical except the 2026-11-15 SEM line in the to-do list |
| `github-release/pc-sync/` | 2026-11-09 | Identical to the repository |
| `sem-recs/` | 2026-11-15 | Current; the only container copy of the SEM/tempo code (J6) |
