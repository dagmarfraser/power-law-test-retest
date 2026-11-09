# Sensitivity plan: N=45 (interim) vs N=48 (final)

*Written 2026-11-01, BEFORE any replacement data exist. Do not edit the decisions below after the data arrive; add a dated amendment instead.*

## Context

- 45 complete participants (IDs 1XX to 3XX) were analysed on 2026-08-04 (frozen in `data/processed/baseline_N45/`).
- Three replacements for the non-completers (101, 102, 214) are being collected as 4XX IDs, after that analysis. Rule of 2026-10-12 (`docs/PublicationTodo.md`): 48 is final; a replacement who drops out is not replaced; analyse whoever completes (46 to 48).
- Both results are reported: N=45 (interim) and the final N (45 + completing replacements). The final N is primary. N=48 was set by the MSc students' preregistered design for their Pearson comparison, not for the ICC, so the ICC results are estimation (point estimate, 95% CI, class), not a powered test; the Zou required N is planning information (Dagmar, 2026-11-01).

## Files (all in `src/functions/` except the test)

| File | Role |
|---|---|
| `preflightN48_2026.m` | Read-only readiness check: baseline intact against its manifest (bytes + MD5), originals still complete, 101/102/214 still excluded, replacements complete (2 visits x 3 sessions) |
| `runN48_2026.m` | Entry point. `'preflight'` (default), `'pipeline'`, `'compare'`, `'all'`. Refuses to run unless preflight is ready; errors if processed N differs from expected |
| `compareCohortsN45N48_2026.m` | The N=45 vs final-N comparison and sensitivity analysis (below) |
| `leaveKOutReference_2026.m`, `computeTOST.m`, `reportShiftTOST_2026.m`, `plotCorridorOfStability_2026.m`, `analyseOrphanRuns_2026.m` | Leave-3-out reference, TOST engine and shift report, corridor of stability, non-completer check (sections below) |
| `tests/test_compareCohortsN45N48_2026.m` | Runs the comparison on SYNTHETIC replacements built from the frozen baseline; R not needed |

Order when data arrive: ingest `.eml` (checklist in `docs/PublicationTodo.md`), `runN48_2026('stage','preflight')`, then `runN48_2026('stage','all')` run by Dagmar in the console (long run, not via MCP).

## Pre-specified analyses (confirmatory parameter Beta_SG6_IRLS, ICC(A,1), visit means)

1. **Original N=45 vs all N**: ICC, 95% CI, Koo & Li class from the CI lower bound, Zou required N, for both, per shape. "Original N=45" is recomputed from the new run restricted to original IDs, so the comparison is like-for-like; the drift columns state whether it reproduces the frozen baseline (it should, to 1e-9; if not, a banner warning fires and `strictDrift` can make it an error).
2. **Exact exchangeability reference** (delete-d jackknife, Shao & Wu 1989; descriptive): the change in ICC, in its CI lower bound, in mean beta and in the V2 minus V1 shift when 3 (or however many) participants are added to the originals, over every possible choice of that many originals (14,190 for 3 of 45; `leaveKOutReference_2026` gives the same distributions for the frozen 45 alone). The observed change from the real replacements is located in each distribution. **Rule fixed 2026-11-01, before the data:** a change inside the 2.5 to 97.5% range is `ok`; beyond it, `outside95` (noted); beyond the minimum or maximum of every possible draw, `SUSPECT` (a warning, and a reason to check protocol, device, labelling and the .eml mapping before interpreting anything). For the frozen 45 the 95% range of the mean-beta change is within about +/-0.01 for every shape (worst single draw 0.018); the exchangeability assumption is that the replacements behave like more of the same cohort, so a SUSPECT flag means they do not, whatever the cause. With 5 shapes x 4 statistics some `outside95` flags are expected by chance; SUSPECT should essentially never occur by chance.
3. **Exact permutation tests** that the replacements are a random draw from the pooled cohort, for mean beta, V2 minus V1 shift and absolute V2 minus V1 difference, per shape, Holm-adjusted over all 15 tests.
4. **Per-replacement z-scores** against the originals; |z| > 3 is flagged.
5. **Data-quality and protocol checks**: replacement sessions post-date the 2026-08-04 lock, sampling frequency, session counts, NaN rate.

## What this can and cannot show

- With 3 replacements, the permutation tests have almost no power to detect a real cohort difference. A non-significant result is **not** evidence of no difference. Say "no evidence of a difference; the design cannot rule out a small one".
- Showing equivalence needs TOST or a Bayesian equivalence check with a justified SESOI. That is still an open prerequisite (see `claude.md`, On the horizon) and is not run here.
- Any shape whose Koo & Li class or whether its CI lower bound clears 0.75 changes between N=45 and the final N is reported as changed, whatever the p-values say.
- 4XX is a single block run after the interim look; cohort, experimenter and time are confounded. N=48 itself was preregistered by the students, so no separate registration of the sample size is needed; this replacement sensitivity analysis is labelled **sensitivity, not pre-registered**.

## Fail-loud behaviour

Errors: no new run, no replacements, more than 3, IDs outside 400 to 499, a baseline participant missing, a participant x visit x shape cell missing, baseline manifest mismatch, 101/102/214 now complete. Visible warnings (kept in the output, not suppressed): drift from baseline, replacements pre-dating the lock, sampling frequency out of range, unusual session count, outlier replacement, Zou N failure (left NaN, never estimated).

## Edit made outside the new files

`powerAnalysisICC_R.m` gained optional `inputCSV` and `outputCSV` arguments (defaults unchanged) so the Zou step can run on the N=45 and final-N ICCs without overwriting `icc_power_output.csv`.

## Amendment 2026-11-01 (still before any replacement data): TOST and corridor of stability

- **Equivalence margin**: +/-0.03 in Beta_SG6_IRLS, the same absolute value for every shape, fixed by Dagmar for consistency with the other pre-print (after Fourie's ellipses). Call it an equivalence margin (SESOI), not an MDC: this dataset's own MDC95 is 0.027 to 0.13 per shape (29 to 54% of mean beta). It is lenient relative to the Cook et al. 2026 group gradient differences (about 0.04). A +/-0.02 run is the stated sensitivity check.
- **Rule**: equivalent iff the 90% CI lies inside the margin (Schuirmann 1987); Welch/Satterthwaite for independent groups. `computeTOST.m`.
- **Shift TOST** (`reportShiftTOST_2026.m`): paired V2 minus V1 per shape, for N=45 and for final N. Real N=45 result (tostShift_N45_20261101_225154.csv): all five shapes equivalent within +/-0.03; phi=0.8 only narrowly (shift 0.016, 90% CI [0.0037, 0.0289], p=0.037) and it would fail at +/-0.02.
- **Replacement vs original**: three contrasts per shape in the comparison output (Shift_original, Shift_all, MeanBeta_replacement_minus_original). With 3 vs 45 the last cannot pass; underpowered by design, report as inconclusive, not as a difference.
- **Corridor of stability** (`plotCorridorOfStability_2026.m`; Schonbrodt and Perugini 2013): 2000 random orderings, ICC vs n, corridors +/-0.05 and +/-0.10 around the final ICC; summary reports nStable95 and the percentage of orderings inside the corridor at n=N-3. Real N=45: at +/-0.05, nStable95 = 38, 35, 41, 25.5, 44 (phi=0.4, 0.8, Ellipse, Square, Cursive); Cursive is not stable (87% inside at n=42).

## Orphan runs (non-completers 101, 102, 214), added 2026-11-01

`analyseOrphanRuns_2026.m` places their visit means and V2-V1 shifts in the frozen N=45 distribution, matched for session count (an orphan visit with m sessions is compared with the originals' first m sessions). Flags: SUSPECT outside the originals' min..max, outside95 outside the empirical 2.5-97.5 percentiles. Result (orphanRuns_20261101_230611.csv): 33 of 35 values ok; ID102 is a consistently high-beta participant (V2 phi=0.4 outside95; V1 Ellipse above all 45 with only 2 sessions). ID101 and ID214 within range throughout. Descriptive; reasons for dropout unknown. Footnote-level evidence that attrition was not selective on beta, with n=3 and no inference.

## Not yet done

Static check, test run (10/10 pass) and entries in `claude.md` and `docs/ProjectLog.md`: DONE 2026-11-01. Judged footnote-level and not pursued: with-replacement corridor arm, per-cohort SEM/LoA and heteroscedasticity check (Schonbrodt and Perugini 2013; Atkinson and Nevill 1998; the corridor permutes the same sample so it overstates stability, and ICC depends on between-subject spread). Outstanding: the rest of the re-run checklist (questionnaires, stability, robustness, figures, handover, refreshing literal N=45 numbers).

## Amendment 2026-11-09: baseline rebuilt on the current pipeline (Dagmar: "n = 45 is obsolete")

- The frozen 2026-10-12 baseline (from the 2026-08-04 run) predates the 2026-11-02 scale fix and the 2026-11-09 finger-touch fix, so comparing it with a current run mixed pipeline changes into the N=45 vs N=48 contrast. `rebuildBaselineN45_2026` archived it to `data/processed/archive/baseline_N45_frozen20261012/` and wrote a new `baseline_N45/` from the 45 originals of `trial_level_results_20261109_112129` (plus `icc_results_20261109_115236` and `MANIFEST_20261109.md`). The pre-specified analyses above are unchanged; only their reference data moved to the current pipeline.
- `compareCohortsN45N48_2026` gained `lockDate` (the interim-look date, previously parsed from the baseline file name) and `zouDir` (the PC has no R: it writes `data/processed/zou/zouInput_N45/N48.csv`, `src/functions/zouCohort_M5.sh` runs `icc_power_analysis.R` on the M5, and the comparison accepts the outputs only if they were made from the same ICCs). `runN48_2026('stage','compare')` uses `zouDir` on Windows.
- Result (`cohort*_N45vsN48_20261109_120548.csv`; 51 took part, 48 complete): N=45 vs N=48 ICC(A,1) phi=0.4 0.852 vs 0.850, phi=0.8 0.882 vs 0.878, Ellipse 0.792 vs 0.791, Square 0.864 vs 0.862, Cursive 0.351 vs 0.385; Zou N 75/38/567/56 vs 78/41/620/59 (Cursive intractable); no class change; all 20 leave-3-out flags ok; max replacement |z| 1.93; all 15 permutation tests Holm p = 1; all V2-V1 shifts equivalent within +/-0.03 (phi=0.8 N=45 shift 0.016, 90% CI [0.003, 0.029], p = 0.036). Drift vs the rebuilt baseline < 1e-14. Orphans (`orphanRuns_20261109_120047.csv`): 33 of 35 ok, same two ID102 flags. Preflight passes against the new manifest; `test_compareCohortsN45N48_2026` 10/10.
- The N=45 corridor and shift-TOST figures in the 2026-11-01 amendment above are from the obsolete baseline and are kept as the dated record.
