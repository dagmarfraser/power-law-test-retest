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
| A4 | Ellipse trials | 2,879 | `trial_level_results_20261109_112129` | 2026-11-15 | current (companion simulation paper should reconcile its 2,829 / 2,877 against this) |
| A5 | Retest interval | Median 8.0 d (IQR 7.0 to 13.1, range 6.0 to 43.2); 11 of 48 over 14 d, 2 over 28 d (IDs 203, 204) | `retestInterval_N48_20261109_161028.csv` | 2026-11-09 | current |
| A6 | Framing of N | N=48 was set by the students' preregistered Pearson design, not an ICC target, so ICCs are estimation and Zou N is planning information. N=48 primary, N=45 (originals) supplementary | Decision | 2026-11-01 | current |

## B. Data handling (fixes that changed earlier numbers)

| ID | Claim | Value | Source | Date | Status |
|---|---|---|---|---|---|
| B1 | Trajectory scale | Raw x,y are UIKit points, **5.209 points/mm** (M4 13" iPad Pro). Single source `ipadPointsPerMm.m` | `docs/AnalysisPipeline.md`, "Trajectory scale" | 2026-11-02 | current (supersedes 9.73 and 10.418, see S1, S2) |
| B2 | Scale fix effect | mm, mm/s, mm/s^2, mm/s^3 and PathLength_mm x1.868; VGF x1.868^(1-beta); SG6_IRLS beta max change 3.3e-4, ICC max change 0.0005, no class change | `trial_level_results_20261102_150632` | 2026-11-02 | current |
| B3 | Finger/palm touches | `touch_type` 0 in 926 trials (all shapes, 34 participants), sharing one `touch_index` counter with the Pencil. Fix: keep `touch_type == 2` and renumber (`pencilSamplesOnly.m`) | `docs/AnalysisPipeline.md`, "Finger and palm touches" | 2026-11-09 | current |
| B4 | Touch fix effect on beta | Beta ICCs unchanged (SG6_IRLS change <= 0.0005, no class change in any beta pipeline); 13,462 clean trials identical to the 3 Nov run | `touchFixRunCheck_ICC_20261109_113047.csv` | 2026-11-09 | current |
| B5 | Touch fix effect on peak kinematics | Peak velocity, acceleration and jerk ICCs rise on templated shapes and fall on Cursive; class changes: PeakVelocity_SG phi=0.8 moderate to good, Cursive poor to moderate | same | 2026-11-09 | current (supersedes all pre-fix peak-kinematic ICCs, S3) |
| B6 | Pen-lift timing | Cursive time base taken from `time_seconds` residual (`detectPenLifts.m`); templated shapes unchanged | `docs/AnalysisPipeline.md`, "Pen lifts in Cursive" | 2026-07-16 | current (any Cursive kinematics before this date are stale) |

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
| I2 | CATI subscale labels | Assumed published English et al. 2021 order; `LABELS_VERIFIED = false` | `mergeQuestionnaires_2026` | 2026-10-08 | **open** (needs the students' confirmation) |
| I3 | M-EDL zeros | 18 of 48 exact zeros (401 and 402 added two), meaning unknown | questionnaire sheet | 2026-11-03 | **open** |
| I4 | CATI to beta to jerk mediation | Not pursued: a-path about 0 | same | 2026-10-08 | current |

## J. Release and repository items (open)

| ID | Item | Status |
|---|---|---|
| J1 | Data release staged (current run only, session times as day offsets, MD5 manifest) but NOT published; blocked on consent wording, CATI subscale order (I2) and M-EDL zeros (I3) | open |
| J2 | Data DOI (Zenodo or OSF) and README link | open |
| J3 | `CITATION.cff` author list to confirm | open |
| J4 | Trim `docs/AnalysisPipeline.md` for a public audience (it refers to internal notes) | open |
| J5 | Square spatial jump: 649 points (125 mm at 5.209) with no time gap, noted 2026-07-16, never investigated. The finger/palm fix (B3) removed 50 to 120 mm jumps of the same kind, so it may already be explained; check on the current run | open |
| J6 | Scripts not yet in this repository: `exportDataRelease_2026.m`, and the SEM/tempo set (`estimateTempoF0.m`, `extractTrialTempo_2026.m`, `semFromVisitMatrix_2026.m`, `reportSEMReliability_2026.m`, `test_semFromVisitMatrix_2026.m`, `docs/SEM_Tempo_Reliability_N48.md`) | open |
| J7 | Trial count off by one: the touch-fix diagnostic counts 14,389 trials and 13,463 clean, the final run 14,388 and 13,462 | open (minor) |
| J8 | Whether the iPad app logs `location(in:)` or `preciseLocation(in:)` (all x,y on whole or half points) | open |
| J9 | Pre-specification wording: "designated primary from the pilot and the 2025 protocol paper", not "preregistered", unless a timestamped registration is found | open |

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
