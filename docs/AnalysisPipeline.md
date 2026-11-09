# Analysis Pipeline: Power Law + ICC (carried forward from analysis_2025, extended to 6 pipelines)

Companion to `docs/EmailIngestionPipeline.md` (data in) and
`docs/DesignNotes.md` (k=2 vs k=3). This covers what happens after
ingestion: trial-level power law calculation, then test-retest ICC.

## What changed from analysis_2025

analysis_2025 computed 3 of the 6 possible {filter x regression}
combinations (BW+Linear, SG6+LMLS, SG6+IRLS) and pre-specified SG6+IRLS as
the confirmatory method. That pre-specification stands -- nothing here
argues for changing the champion -- but Analysis_2026 computes **all 6**
combinations every time, so the champion's advantage stays auditable
against the full grid rather than the 2 comparators analysis_2025 chose
to also compute.

analysis_2025 also had ICC(3,1) (`runICC_2025.m`) and ICC(A,1)
(`runICC_2025_AbsAgree.m`) as two separate scripts with an identical
aggregation block copy-pasted between them -- flagged in
`analysis_2025/README_TestRetest.md` as technical debt ("update both
files if aggregation logic changes"). That duplication is fixed here:
one aggregation pass, one `computeICC.m` core function parameterised by
type, one results table with an `ICCType` column.

## Pipeline

```
data/raw/automatic/ID*/  ->  runAnalysis_2026  ->  data/processed/trial_level_results_*.mat/csv
                                                 -> data/processed/participant_summary_*.csv
data/processed/trial_level_results_*.mat  ->  runICC_2026  ->  data/processed/icc_results_*.mat/csv
data/processed/icc_results_*.mat  ->  exportICCForPowerAnalysis  ->  data/processed/ICC_PilotData_for_R.csv
data/processed/ICC_PilotData_for_R.csv  ->  powerAnalysisICC_R  ->  data/processed/icc_power_output.csv
```

## The 6 pipelines

`calculatePowerLaw.m` computes, for every trial, all combinations of:

| Filter | Regression | Column suffix | Status |
|--------|-----------|----------------|--------|
| BW (Butterworth, 2nd order, 10 Hz) | Linear (OLS, log-log, +intercept) | `_BW_Linear` | comparator |
| BW | LMLS (Levenberg-Marquardt) | `_BW_LMLS` | comparator (new in 2026) |
| BW | IRLS (robust, bisquare) | `_BW_IRLS` | comparator (new in 2026) |
| SG6 (Savitzky-Golay, fs-scaled) | Linear (OLS) | `_SG6_Linear` | comparator (new in 2026) |
| SG6 | LMLS | `_SG6_LMLS` | comparator |
| SG6 | **IRLS** | `_SG6_IRLS` | **pre-specified confirmatory method** |

Each combination produces `Beta_{suffix}`, `VGF_{suffix}`, `FitCorr_{suffix}`.
Regression type codes (`regressDataEBR.m`): 3=Linear, 4=LMLS, 5=IRLS.

Smoke-tested on a synthetic ellipse trajectory (240 Hz, ~3s, small
Gaussian noise): all 6 pipelines returned beta in [0.30, 0.32], consistent
with the Huh & Sejnowski (2015) prediction for an ellipse (nu=2, expected
beta=0.330) and with each other -- no pipeline diverging or erroring.

Also fixed here: analysis_2025's `NumPoints_Regress` only tracked the
BW-path point count ("SG runs its own count for the >=50 guard but this
is not stored" -- its own code comment). Analysis_2026 stores both
(`NumPoints_Regress_BW`, `NumPoints_Regress_SG6`).

## runAnalysis_2026.m: visit-grouping fix, exactSessionsOnly, parfor

**Visit-grouping bug fix (found against real data, not anticipated).**
The original logic sorted a participant's sessions chronologically, then
chunked the flat list into fixed blocks of 3 (`ceil(idx/3)`) and
truncated the whole participant to the first `minSessions` overall. This
silently misassigns visits whenever one visit has an extra session: for
ID103 (4 same-day sessions in visit 1, see `docs/EmailIngestionPipeline.md`),
blind chunking put 4 sessions in visit 1's slot, spilling the genuine 4th
session into visit 2's slot and losing visit 2's real third session
entirely. Fixed by grouping into visits by same-visit proximity first
(mirrors `analyzeTimings.py`'s 90-min `PROXIMITY_THRESHOLD_MINUTES`),
THEN truncating any oversized visit to its own first 3 sessions --
contained to the visit that actually has the problem. Fires a `warning()`
per oversized visit (e.g. `ID103 visit 1 has 4 sessions -- using first 3
(by timestamp within this visit)`) rather than truncating silently.

**`exactSessionsOnly` option** excludes participants whose raw session
count doesn't exactly match `minSessions`, rather than truncating and
processing them. Used for the first confirmatory run to exclude ID103
(7 sessions, genuinely ambiguous which is extra -- see
`docs/EmailIngestionPipeline.md`) and ID212 (9 sessions, not yet
investigated) entirely, rather than including them with a truncation
guess baked in:

```matlab
runAnalysis_2026('exactSessionsOnly', true, 'useParfor', true)
```

**`useParfor`/`nWorkers` options** parallelise the per-participant loop
(each participant's trial extraction is fully independent). Required
refactoring the main loop's body into a local function,
`processParticipant()` (same file, below `runAnalysis_2026`'s own `end`),
since parfor disallows the previous pattern of growing `allResults`/
`participantSummary` by repeated concatenation inside the loop --
`processParticipant` now returns its own results/summary table per
participant into a pre-allocated cell array, concatenated once after the
loop with `vertcat`. `nWorkers` defaults to `max(numcores-1, 1)` (one
fewer than all cores, so the machine stays usable during a run).

**Measured, not estimated, timing** (first real confirmatory run, N=31,
M5 Mac, 9 workers): 255.8 seconds wall-clock. A pre-parfor profiling
estimate (median 0.18s/trial x ~12,000 trials, plus ~13 min file I/O)
put the serial equivalent at ~49 minutes -- an ~11.5x speedup, better
than the naive 9x from worker count alone, consistent with
per-participant work having little shared-resource contention (each
worker reads only its own participant's files).

## Absolute beta magnitude vs theoretical predictions (real 2026 cohort data)

**Reproducible via `reportNoteEvidence_2026.m`** -- run it to regenerate
both tables below (and the ICC-type comparison in the next section)
rather than trusting hand-copied console numbers. It also writes
timestamped `beta_vs_theory_*.csv` / `icc_type_symmetry_*.csv` to
`data/processed/`.

**Correction, logged rather than silently fixed (same convention as the
R cross-validation section below):** the first version of this section
used a Huh & Sejnowski (2015) formula with `phi^2/2` in the denominator
(`beta(phi) = 2/3 * (1+phi^2/2) / (1+phi^2/2+phi^4/15)`), copied in
error from the numerator term. That formula systematically overstated
every theoretical anchor except phi near zero -- e.g. it gave 0.653 for
phi=0.8 and 0.230 for the square, both wrong. The correct denominator
uses `phi^2`, not `phi^2/2`:

```
beta(phi) = (2/3) * (1 + phi^2/2) / (1 + phi^2 + phi^4/15)
```

Caught by cross-checking this formula's output against Cook et al.
(2026)'s explicitly stated theoretical values across their full shape
range (phi = 2/33 .. 4) before trusting it -- the corrected formula
matches Cook's stated values to within ~0.02-0.09 everywhere; the
original did not match at all above phi~0.1. See
`reportNoteEvidence_2026.m`'s `hsTheoreticalBeta` for the fixed version
and this same account in its header comment.

The smoke test earlier in this document (synthetic ellipse, no real
noise) landed inside [0.30, 0.32] for all 6 pipelines, matching the
ellipse-specific theoretical value (0.330) that was never in question.
Real cohort data (final N=48, refreshed 2026-11-09 after the finger-touch fix from
`beta_vs_theory_20261109_113603.csv`, trial-level means; tables in this file regenerated by `makeDocTables_2026`) sits well below
theory at every shape:

| Shape | phi | Beta_SG6_IRLS | Beta_BW_Linear | H&S theoretical | %-of-theory (SG6_IRLS) | %-of-theory (BW_Linear) |
|---|---|---|---|---|---|---|
| phi=0.4 | 0.4 | 0.236 | 0.254 | 0.620 | 38% | 41% |
| phi=0.8 | 0.8 | 0.249 | 0.263 | 0.528 | 47% | 50% |
| Ellipse | 2 | 0.189 | 0.197 | 0.330 | 57% | 60% |
| Square | 4 | 0.092 | 0.102 | 0.176 | 52% | 58% |

The first scoped run (N=31, 2026-07) gave 40 / 48 / 59 / 54% of theory
for SG6_IRLS (0.246 / 0.254 / 0.195 / 0.095): the same graded pattern,
each shape 1 to 2 points lower at N=48.

With the corrected theoretical values, the deflation is graded rather
than flat: low-phi shapes retain a smaller fraction of their (higher)
theoretical value than the higher-phi shapes do of their (lower)
theoretical value. Worth keeping in mind for later write-up, since this
is a more specific and more checkable claim than "everything is roughly
half of theory."

This deflation is not a regression-method artefact: BW+Linear (the
"legacy" pipeline closest to what older published methods used) shows
essentially the same degree of deflation as SG6+IRLS at every shape
(within 0.01-0.02 of each other everywhere; N=48: 0.008 to 0.018), so it is not specific to
choosing IRLS/SG over OLS/BW.

Cross-checked against the two most relevant published datasets:

- **Huh & Sejnowski (2015)'s own measured values** (e.g. ellipse
  beta_m=0.330) sit close to theory, but only because their pipeline
  applies a narrow bandpass filter centred on each shape's target
  frequency nu0 (`e^(-5*nu0*log2(nu/nu0)^2)`) before estimating beta.
  That filter suppresses energy away from the pure target frequency --
  exactly where real individual/clinical differences in speed
  modulation would show up (c.f. Cook et al. 2026's FFT finding that
  autistic participants show broader, less target-locked speed
  spectra). Analysis_2026 deliberately does not apply an equivalent
  filter, so some deflation relative to H&S's filtered numbers is
  expected by design, not a pipeline bug.
- **Cook et al. (2026)**, which also does not appear to apply a
  target-frequency bandpass, shows a different, non-monotonic deviation
  pattern rather than a uniform deflation: their non-autistic group's
  estimated means are inflated for spiral (+30%) and square (+26%),
  match theory almost exactly for ellipse and triangle (~0%), and are
  deflated for the three middle shapes (double-nested -31%,
  single-nested -16%, petalled -24%). This is a different shape of
  deviation to ours, so "Cook shows the same pattern" is not quite
  right -- but it does independently confirm that unfiltered,
  real-world pipelines regularly produce substantial departures from
  the H&S theoretical curve, in both directions, not only downward.

**Bottom line:** absolute beta magnitude diverging from the H&S/Cook
textbook numbers is expected here, given no target-frequency filtering
is applied, and is consistent with the wider literature Fraser et al.
(2025) reviews on this point. It should not be treated as a pipeline
bug without further evidence. The ordinal structure (lower phi
outperforming higher phi, square lowest) is the more informative signal
from this pipeline than absolute magnitude, and broadly tracks the
predicted direction even where the exact value does not.

**Also noted:** Cursive (freehand) shows a much larger spread across the
6 pipelines (N=48: beta 0.15-0.28, 0.135 span; N=31: 0.18-0.31) than any
other shape (N=48: 0.023 to 0.073 span across pipelines). Unlike the other
four shapes, Cursive has no template -- phi=0.4/0.8/Ellipse/Square are
the same fixed curve every session, but the handwriting task is free
text, so "session 1" and "session 2" are not the same stimulus the way
they are for the other shapes. This matters beyond the pipeline-spread
observation -- see the between-visit ICC discussion below, where it
turns out to be the likely explanation for Cursive's specifically poor
reliability.

## Between-visit ICC: beta vs jerk, and where Cursive falls down

**Take-home at N=48 (2026-11-03, unchanged by the 2026-11-09 finger-touch fix):** see `claude.md` section 2, "Take-home", for the agreed one-paragraph framing (templated-shape beta moderate-to-good and better than jerk; free-text Cursive poor because the stimulus differs between visits). Numbers below.

**Final N=48 (refreshed 2026-11-09 from `icc_results_20261109_112131.csv`,
`runN48_2026`, after the finger-touch fix; 2026-11-03 values differed by at most 0.009).** Classified by 95% CI lower bound (Koo & Li 2016),
absolute agreement, between-visit:

| Shape | Beta_SG6_IRLS ICC [95% CI] | Class | MeanJerk_SG ICC [95% CI] | Class |
|---|---|---|---|---|
| phi=0.8 | 0.878 [0.782, 0.932] | good | 0.657 [0.459, 0.792] | poor (LB < 0.5) |
| phi=0.4 | 0.850 [0.748, 0.913] | moderate (LB just under 0.75) | 0.656 [0.457, 0.791] | poor (LB < 0.5) |
| Square | 0.862 [0.765, 0.920] | good | 0.518 [0.275, 0.698] | poor |
| Ellipse | 0.791 [0.655, 0.877] | moderate | 0.337 [0.060, 0.566] | poor |
| Cursive | 0.385 [0.117, 0.601] | **poor** | 0.428 [0.170, 0.633] | poor |

Beta beats jerk clearly on the four templated shapes. **The Cursive "flip"
has largely gone at N=48:** jerk is still nominally above beta (0.428 vs
0.385) but both are poor and the CIs overlap almost entirely. Do not write
that jerk is the more reliable Cursive measure; write that neither is
reliable for free-text Cursive. The N=31 history below explains how the
flip shrank (pen-lift fix, then more participants).

**History: first real-data ICC run (N=31, 2026-07-16)**, from
`icc_results_20260716_131101.csv`:

| Shape | Beta_SG6_IRLS ICC (LB) | Class | MeanJerk_SG ICC (LB) | Class |
|---|---|---|---|---|
| phi=0.8 | 0.941 (0.882) | excellent | 0.672 (0.420) | moderate |
| phi=0.4 | 0.898 (0.801) | good | 0.666 (0.411) | moderate |
| Square | 0.875 (0.756) | good | 0.497 (0.175) | poor |
| Ellipse | 0.868 (0.746) | borderline moderate/good | 0.310 (-0.046) | poor |
| Cursive | 0.323 (-0.033) | **poor** | 0.638 (0.378) | moderate |

Those numbers were taken after the pen-lift correction documented below. The four templated shapes
are unchanged to three decimals (they are single continuous strokes, so
the correction cannot touch them); both Cursive figures moved, in
opposite directions.

At N=31 this replicated the analysis_2025 pilot's headline finding:
beta clearly outperforms jerk for the low-phi shapes, and the
relationship **flipped for Cursive** (jerk 0.638 vs beta 0.323). At N=48
the first half holds; the flip is down to 0.428 vs 0.385 (see above).

The flip survives the pen-lift correction but is weaker than first
reported. Cursive jerk was 0.805 ("good") before the fix and is 0.638
("moderate", LB 0.378) after: a substantial part of what made Cursive
jerk look reliable was the pen-lift artifact rather than motor control.
Do not quote the pre-2026-07-16 Cursive jerk figure.

**Why Cursive-beta collapses specifically (not just "poor reliability"):**
variance decomposition (`BetweenSD`/`WithinSD` columns from `runICC_2026`)
shows Cursive's between-person spread (N=48: 0.0266; N=31: 0.0294) is
essentially identical to Square's (0.0248; N=31: 0.0276) -- so it is not
that everyone's cursive beta converges to a similar value. What differs is
WithinSD: Cursive's is nearly double Square's (N=48: 0.0131 vs 0.0073;
N=31: 0.0147 vs 0.0074). That within-person
visit-to-visit wobble is the likely fingerprint of the no-template
issue above: phi=0.4/0.8/Ellipse/Square are the identical curve on both
visits, so any visit-to-visit beta difference is genuine motor drift;
Cursive is different free-written content each time, so its
visit-to-visit beta difference conflates genuine motor drift with
content-driven compositional variance (different letterforms -> different
effective frequency mix feeding the same regression). ICC cannot
separate those two sources when the "same" measurement is never really
the same stimulus twice. Consistent with this: within-visit ICC for
Cursive-beta is still good (N=48: 0.80-0.82; N=31: 0.88-0.91) -- the 3 trials inside one
visit are presumably closer in content (same short sitting) than trials
a week apart, so the confound bites specifically at the between-visit
level, exactly where it shows up.

**ICC(absolute) vs ICC(consistency) does not recover the Cursive
problem, and this generalises across the whole table, not just
Cursive:**

N=48 (`icc_type_symmetry_20261109_113603` from `reportNoteEvidence_2026`, 2026-11-09):

| Parameter | Shape | Absolute | Consistency | Diff |
|---|---|---|---|---|
| Beta_SG6_IRLS | phi=0.4 | 0.850 | 0.849 | 0.002 |
| Beta_SG6_IRLS | phi=0.8 | 0.878 | 0.889 | -0.010 |
| Beta_SG6_IRLS | Ellipse | 0.791 | 0.788 | 0.003 |
| Beta_SG6_IRLS | Square | 0.862 | 0.866 | -0.005 |
| Beta_SG6_IRLS | Cursive | 0.385 | 0.384 | 0.001 |
| MeanJerk_SG | phi=0.4 | 0.656 | 0.651 | 0.005 |
| MeanJerk_SG | phi=0.8 | 0.657 | 0.652 | 0.005 |
| MeanJerk_SG | Ellipse | 0.337 | 0.335 | 0.003 |
| MeanJerk_SG | Square | 0.518 | 0.513 | 0.005 |
| MeanJerk_SG | Cursive | 0.428 | 0.430 | -0.002 |

Max |diff| at N=48 is 0.010, and it is phi=0.8 beta: consistent with the
small positive visit-2 shift there (about 7%, CI excludes 0; equivalent
within +/-0.03 by TOST). Everywhere else |diff| <= 0.005.

N=31 (history; the Cursive jerk row is the pre-pen-lift-fix value):

| Parameter | Shape | Absolute | Consistency | Diff |
|---|---|---|---|---|
| Beta_SG6_IRLS | phi=0.4 | 0.898 | 0.896 | 0.002 |
| Beta_SG6_IRLS | phi=0.8 | 0.941 | 0.941 | 0.000 |
| Beta_SG6_IRLS | Ellipse | 0.868 | 0.872 | -0.003 |
| Beta_SG6_IRLS | Square | 0.876 | 0.882 | -0.007 |
| Beta_SG6_IRLS | Cursive | 0.246 | 0.245 | 0.001 |
| MeanJerk_SG | phi=0.4 | 0.665 | 0.659 | 0.006 |
| MeanJerk_SG | phi=0.8 | 0.671 | 0.665 | 0.006 |
| MeanJerk_SG | Ellipse | 0.310 | 0.306 | 0.003 |
| MeanJerk_SG | Square | 0.491 | 0.484 | 0.007 |
| MeanJerk_SG | Cursive | 0.805 | 0.805 | ~0.000 |

Max |diff| across all 10 N=31 rows was 0.007 -- negligible everywhere. The two
ICC types only diverge when there is a shared, population-level
systematic between-visit shift (e.g. everyone speeding up on visit 2);
absolute agreement penalises that, consistency ignores it. The flat
diff table here means there isn't much of a shared systematic shift for
either parameter, in any shape, in this cohort -- which also rules out
"population-level practice effect" as the explanation for Cursive's
poor beta reliability specifically. The content-variability account
above is the one left standing: it predicts exactly this signature
(idiosyncratic, not shared, noise), since a shared drift would show up
in the absolute-vs-consistency gap and it does not.

**Methods implication for anyone extending this protocol:** if
beta-as-trait-marker for handwriting specifically is wanted later, a
fixed repeated phrase (not free text) would let content-driven and
motor-driven variance be told apart, which the current free-text design
cannot do.

## Pen lifts in Cursive: what the touch_index clock was hiding (2026-07-16)

Found by asking a simple question of the day-1/day-2 figures: why is
Cursive peak velocity ~1039 mm/s when Ellipse is ~161 (old 9.73 scale; about 1941 and 301 mm/s at
the correct 5.209 pt/mm, see "Trajectory scale"), given the two
should be broadly comparable freehand movements?

**The symptom.** Cursive's *median* velocity (93.9) was essentially
identical to Ellipse's (94.1), exactly as expected. Only the peaks
diverged: peak/median ratio 11.1 for Cursive against ~1.7 for every
templated shape. Central tendency undisturbed, transients enormous: the
signature of isolated spikes, not of faster writing.

**The cause.** `runAnalysis_2026` built its time vector as
`t = trialTraj.touch_index / fs`. The digitiser samples uniformly at
240 Hz *while the pen is down* and records nothing while it is up, and
`touch_index` simply counts recorded samples: it steps by exactly 1
across a pen lift, no matter how long the lift lasted. Cursive is free
handwriting, so the pen leaves the glass between letters. Result: a real
0.704 s pen-up interval was represented as 1/240 s, turning the 653 px
(67 mm at the old 9.73 scale; 125 mm at 5.209 pt/mm) hop between letters into a step discontinuity. Differentiated,
that is a 16,097 mm/s finite-difference spike (67.1 mm x 240 Hz; 30,090 mm/s at 5.209 pt/mm), which
the SG window then smeared down into the ~1000 mm/s "peak" (~1870 mm/s at 5.209 pt/mm).

**Prevalence (6 participants, all sessions, 1800 trials).** Pen lifts are
essentially exclusive to Cursive:

| Shape | trials | with gaps | % | max jump |
|---|---|---|---|---|
| phi=0.4 | 360 | 6 | 1.7% | 183 px |
| phi=0.8 | 360 | 1 | 0.3% | 367 px |
| Ellipse | 360 | 2 | 0.6% | 671 px |
| Square | 360 | 0 | 0.0% | 649 px |
| Cursive | 360 | 360 | **100.0%** | 1357 px |

("px" in this table is the raw CSV unit, which is UIKit points: divide by 5.209 for mm, e.g. Cursive 1357 pt = 261 mm.)

**Why the existing guard did not catch it.** `calculatePowerLaw` had a
Fail Loud check for exactly this: compare `1/mean(diff(t))` against `fs`
and warn "dropped samples?". It could never fire. Because `t` was
synthesised from the sample index, `diff(t)` is *always* exactly `1/fs`
and the estimate *always* exactly 240 -- including on trials where 0.79 s
of pen-up time really had been dropped. The guard was correct and
completely blinded by its input. It is now replaced by a per-stroke
uniformity assertion, which tests the assumption the filters actually
depend on rather than an assumption the input guarantees.

### Why not just use time_seconds

The obvious fix, and it is wrong. `time_seconds` is quantised to 3 d.p.
and 1/240 = 0.0041667 s does not fit that grid, so consecutive stamps
step by 0.004/0.005 and sometimes 0.000. Measured across ~608k samples:
648 duplicate stamps (dt = 0, i.e. division by zero) and occasional
**negative** steps to -0.006 s. It is not monotonic. As a per-sample
clock it is unusable; `touch_index` is the correct clock.

### The fix: use time_seconds only as a gap detector, via the residual

The two clocks disagree only where it matters. Take

```
r = time_seconds - touch_index/fs
```

Within a stroke both advance at the same rate, so the 1/fs increment
cancels and `r` is **piecewise-constant**: the quantisation noise does
not accumulate. A pen lift steps `r` by the lift duration. Measured:

| | residual noise SD | max step in r | lifts found |
|---|---|---|---|
| Ellipse | 0.0004 s | 0.0018 s | 0 |
| Cursive | 0.0005 s | 0.6998 s | 6 |

Noise ceiling ~0.002 s against a gap floor of 0.029 s: **~16x**
separation, against only ~4x for raw `diff(time_seconds)`. So
`time_seconds` is asked only "did roughly a quarter of a second elapse?",
a question its 1 ms quantisation answers perfectly well, and is never
divided by. `detectPenLifts()` in `runAnalysis_2026.m` does this;
`liftThreshold` defaults to 0.0125 s (3 sample periods), ~6x above the
observed noise and ~2.3x below the smallest real gap, so it is
defensible from both sides rather than tuned against one.

Reconstruction validates: ID104 trial 3 infers `[59 27 46 91 33 168]`
missing samples, so 985 pen-down + 424 missing = 5.871 s against 5.841 s
of recorded elapsed time (0.5%), from a clock that is junk per-sample.

`calculatePowerLaw` now takes an optional `strokeId` and differentiates
**each pen-down stroke independently**, masking each stroke's own sgPad
boundary samples. Nothing is ever differentiated across a lift. Per-stroke
segmentation rather than simply masking +/-sgPad around each gap because,
while the two are equivalent for SG (the window half-width *is* sgPad),
Butterworth is `filtfilt` IIR whose contamination spreads well beyond 20
samples; segmenting fixes both paths.

### Regression test: the templated shapes must not move

`strokeId` defaults to a single stroke, which reproduces the old
single-pass behaviour exactly. Verified on ID104 against
`trial_level_results_20260715_125134.csv`:

| Shape | trials | changed | with lifts | mean strokes |
|---|---|---|---|---|
| phi=0.4 | 60 | 0 | 2 | 1.03 |
| phi=0.8 | 60 | 0 | 0 | 1.00 |
| Ellipse | 60 | 0 | 0 | 1.00 |
| Square | 60 | 0 | 0 | 1.00 |
| Cursive | 60 | 60 | 60 | 4.58 |

phi=0.8/Ellipse/Square agree to floating-point noise (5e-16). phi=0.4
moves on two trials, correctly: those trials contain genuine lifts
(lift-and-replace, tiny spatial hop, so peak velocity is untouched and
only NumPoints/means shift by the extra stroke boundary). NaN count
unchanged (2 before, 2 after).

### What it changed

Between-visit ICC(A,1), N=31, before -> after:

| Parameter | Shape | before | after | delta |
|---|---|---|---|---|
| Beta_SG6_IRLS | phi=0.4 / 0.8 / Ellipse / Square | 0.898 / 0.941 / 0.868 / 0.876 | unchanged | +-0.000 |
| Beta_SG6_IRLS | Cursive | 0.246 | 0.323 | **+0.077** |
| MeanVelocity_SG | Cursive | 0.775 | 0.626 | **-0.150** |
| PeakVelocity_SG | Cursive | 0.858 | 0.739 | **-0.119** |
| MeanAcceleration_SG | Cursive | 0.807 | 0.639 | **-0.168** |
| MeanJerk_SG | Cursive | 0.805 | 0.638 | **-0.166** |

Mean Cursive peak velocity fell from ~1039 to 221.5 mm/s, against
Ellipse's 160.8 (old 9.73 scale; 1941, 413.7 and 300.4 mm/s at 5.209 pt/mm): roughly aligned, as it should have been all along.

**The confirmatory result is untouched.** phi=0.4 stays 0.898 and phi=0.8
stays 0.941, so confirmatory readiness does not change.

**Every Cursive kinematic ICC fell by 0.12-0.17.** This is the
counter-intuitive part and worth stating plainly: the pipeline had been
*reliably measuring an artifact*. How far a given person hops between
letters is a stable personal habit (hand size, letter spacing), so it
reproduced well across visits and inflated the ICC. A high ICC does not
make a measure valid.

**The Cursive-beta diagnosis survives.** Beta rose only 0.246 -> 0.323 and
its CI still straddles zero. `filterForRegression` drops near-zero
curvature and IRLS downweights outliers, so the regression was largely
protected even where the peaks were not. The content-variability account
above stands, and is now cleaner: it is not lift-driven, so more
participants still will not fix it.

### Collateral corrections

- `Duration` counted pen-down time only, and was described as trial
  duration. ID104 trial 3 reported 4.10 s for a 6.25 s trial. Kept with
  its original meaning, now named honestly by `DurationElapsed` beside
  it. Equal for the templated shapes.
- `PathLength_mm` counted the hop between letters as drawn distance. Now
  summed within strokes only.
- New per-trial provenance columns: `NumStrokes`, `NumLifts`,
  `NumSamplesDropped`.
- Cost, disclosed: per-stroke edge NaNs remove ~40 samples per stroke,
  and strokes shorter than the 41-sample SG window are dropped entirely
  (55,598 samples across 1,677 trials in the full run, almost all
  Cursive). Warned per trial and recorded in `NumSamplesDropped`.
- Kinematic units are **mm/s, mm/s^2, mm/s^3**, not px/s: the trajectory
  is divided by `pxPerMm` before differentiation. An early draft of
  `generateDayFigures_2026` mislabelled the axes px/s; corrected.

### Still open

Square shows a 649 px max spatial jump with **no** accompanying time gap
(0% gapped trials). That is a discontinuity without a clock gap, so a
different failure mode from pen lifts -- possibly touch re-registration.
Not investigated. Worth a look given Ellipse and Square have the worst
peak-jerk ICCs (0.15 / 0.26).

## Cursive is genuinely broadband, and the 10 Hz filter does not fit it

Raised by a good question: if the pen-lift fix brought Cursive's velocity
into line with Ellipse, is Cursive still a kinematic outlier? Yes, and
selectively. Post-fix, as a multiple of Ellipse:

| Cursive / Ellipse | medVel | pkVel | medAcc | pkAcc | medJrk | pkJrk |
|---|---|---|---|---|---|---|
| ratio | 0.93 | 1.38 | **4.14** | 3.37 | **8.72** | 4.44 |

Median velocity is now aligned (0.93x, marginally slower than Ellipse) but
median acceleration is 4.1x and median jerk 8.7x. These are MEDIANS, robust
to spikes, so this is not pen-lift residue or a few contaminated stroke
boundaries: it is pervasive, sample by sample.

The spectra say why (ID104, pen-down strokes, PSD of the raw trajectory):

| Shape | F50 | F95 | % power >10 Hz |
|---|---|---|---|
| phi=0.4 / phi=0.8 / Ellipse / Square | 0.94 Hz | 1.88 Hz | 0.028% |
| Cursive | 3.75 Hz | 6.56 Hz | 0.382% |

The four templated shapes are spectrally identical and narrowband, which is
reassuring in itself (they are the same curve traced at the same pace).
Cursive's F50 is 3.99x higher. For matched velocity, acceleration scales as
omega, so a 4x frequency ratio predicts a 4x acceleration ratio: observed
4.14. The prediction lands. **Cursive is genuinely about 4x wigglier at the
same speed** -- cusps, reversals and letter transitions -- and that is a
real property of handwriting, not an artifact.

### Consequence: beta's cutoff dependence flips sign for Cursive

Beta_BW_Linear as a function of the Butterworth cutoff (ID104, 10 trials):

| shape | 5 Hz | 10 Hz | 20 Hz | 40 Hz | 60 Hz | SG6_IRLS |
|---|---|---|---|---|---|---|
| phi=0.4 | 0.316 | 0.232 | 0.201 | 0.172 | 0.150 | 0.216 |
| Ellipse | 0.241 | 0.172 | 0.158 | 0.139 | 0.126 | 0.156 |
| Square | 0.138 | 0.124 | 0.121 | 0.110 | 0.106 | 0.093 |
| Cursive | 0.262 | 0.265 | 0.297 | 0.323 | 0.322 | 0.190 |

Every templated shape DECREASES monotonically with bandwidth; Cursive
INCREASES. The spectra explain it: the templated signal ends at ~1.9 Hz, so
raising the cutoff past that admits only noise, which corrupts curvature and
drags beta toward zero. Cursive's signal extends to ~6.6 Hz, so raising the
cutoff admits real signal.

This matters methodologically: **the pre-specified 10 Hz Butterworth is ~5x
the templated signal band but only ~1.5x Cursive's.** The same filter is
doing materially different jobs across shapes. It is also why Cursive is the
only shape where the BW and SG pipelines disagree substantially (0.283 vs
0.183; every templated shape agrees within ~0.02).

(The "0.382% of power above 10 Hz" looks negligible but is not: jerk PSD
goes as omega^6 times position PSD, so that sliver dominates the third
derivative. That is how a spectrum 95% below 6.6 Hz produces a median jerk
8.7x Ellipse's.)

### What NOT to conclude from this

Cursive's BW beta reaches 0.323 at a 40 Hz cutoff, temptingly close to the
canonical 1/3. That is a filter choice, not a finding: at the pre-specified
confirmatory method (SG6+IRLS) Cursive is 0.190, and beta's absolute value
is strongly filter-dependent for EVERY shape (Ellipse spans 0.241 to 0.126
across the same sweep, nearly 2x). Cursive beta is also unreliable between
visits (ICC 0.323, CI straddles zero), so there is no stable per-person
quantity there to stand on regardless.

The reverse observation is the interesting one and remains open: Ellipse is
where 1/3 is supposed to be canonical (Huh & Sejnowski predict 0.330 for
it), and we observe 0.195, i.e. 59% of theory. That deflation is systematic
across all four templated shapes (39.6 / 48.1 / 59.3 / 53.7 % of theory) and
non-monotonic in phi. See the beta-vs-theory section above; do not overstate
it as a uniform deflation.

This whole table is also a caution against reading absolute beta at all: the
confirmatory claim is about RELIABILITY under a fixed, pre-specified
pipeline, not about beta's magnitude. Comparing our absolute betas to Huh &
Sejnowski requires their filtering to match ours, which has not been checked.

## Filter cutoff sweep: exploiting the fc dependence (sweepFilterCutoff_2026)

`src/functions/sweepFilterCutoff_2026.m` recomputes beta across a range of
Butterworth corner frequencies, per shape, on real cohort data. Standalone:
it does not touch the confirmatory pipeline and writes only its own
timestamped `data/processed/filterCutoffSweep_*.csv` and
`figures/filterCutoffSweep_*.png`.

```matlab
[sw, sg] = sweepFilterCutoff_2026();                                  % ID104, 0.07-40 Hz
sweepFilterCutoff_2026('participantIDs', "all", 'zeroLag', true);     % whole cohort, filtfilt
sweepFilterCutoff_2026('cutoffs', [2 2.5 3], 'regressType', 5);       % IRLS instead of Linear
```

It reuses `detectPenLifts` (promoted out of `runAnalysis_2026` for this
purpose), `differentiateKinematicsEBR`, `curvatureKinematicEBR` and
`regressDataEBR`, calls `calculatePowerLaw` itself for the SG6+IRLS
reference rather than re-implementing it, and reads the theoretical betas
from the newest `beta_vs_theory_*.csv` rather than duplicating the Huh &
Sejnowski formula (which has been wrong once already). Nothing is
differentiated across a pen lift; each stroke's boundary samples are masked
as `calculatePowerLaw` does.

### What it shows (ID104, 300 trials, 4th order single pass, Linear)

| shape | theory | 0.07 | 0.5 | 1 | 1.5 | 2.5 | 4 | 10 | 40 | SG6_IRLS |
|---|---|---|---|---|---|---|---|---|---|---|
| phi=0.4 | 0.620 | 0.647 | 0.250 | 0.282 | 0.455 | 0.371 | 0.339 | 0.212 | 0.167 | 0.231 |
| phi=0.8 | 0.528 | 0.615 | 0.116 | 0.178 | 0.429 | 0.382 | 0.336 | 0.216 | 0.166 | 0.229 |
| Ellipse | 0.330 | 0.583 | 0.330 | 0.269 | 0.294 | 0.273 | 0.230 | 0.156 | 0.136 | 0.157 |
| Square | 0.176 | 0.570 | 0.153 | 0.135 | 0.178 | 0.202 | 0.194 | 0.163 | 0.158 | 0.122 |
| Cursive | NaN | 0.729 | 0.638 | 0.297 | 0.316 | 0.375 | 0.372 | 0.268 | 0.318 | 0.205 |

This reproduces Fraser et al. (2025) Fig 6 on real human data rather than
synthetic ellipses. Beta for a FIXED shape moves by a factor of ~3 purely
as a function of fc (phi=0.4: 0.167 to 0.455). At 4 Hz, phi=0.4 and phi=0.8
both read ~0.34 despite theoretical values of 0.620 and 0.528: spurious
one-third for shapes that should not have it, which is Schaal and Sternad's
(2001) result. Meanwhile Ellipse, whose theory IS one-third, only touches
0.330 at 0.5 Hz and reads 0.156 at the pre-registered 10 Hz.

### The 0.07 Hz regime is shape-blind

At fc = 0.07 Hz (reported in Zago et al. 2016 and Zarandi et al. 2023, per
Fraser et al. 2025 footnote 2) every shape reads 0.57-0.73 regardless of
its theoretical value: Square (theory 0.176) reads 0.570, Ellipse (0.330)
reads 0.583. The filter has stopped responding to shape. You are measuring
the Butterworth. Note this cohort's templated F50 is 0.94 Hz, so 0.07 Hz
sits more than a decade BELOW the median signal frequency; 0.07 Hz may well
be defensible for Drosophila larval locomotion (Zago et al. 2016) without
being defensible here.

### Why "best agreement with theory" is a trap

The sweep output makes the circularity concrete. Minimising
|PctOfTheory - 100| per shape picks a DIFFERENT cutoff for every shape:

| shape | "best" fc | beta | % of theory |
|---|---|---|---|
| phi=0.4 | 0.07 Hz | 0.647 | 104% |
| phi=0.8 | 0.07 Hz | 0.615 | 117% |
| Ellipse | 0.50 Hz | 0.330 | 100% |
| Square | 1.50 Hz | 0.178 | 101% |

And the two "best" agreements at 0.07 Hz are pure coincidence: a filter that
outputs ~0.6 for any input necessarily "agrees" with any shape whose theory
is ~0.6. So fc cannot be chosen by theory agreement; that is exactly the
circularity Schaal and Sternad warn about. **fc must be chosen from the
measured signal band** (templated F50 0.94 Hz / F95 1.88 Hz; Cursive F50
3.75 Hz / F95 6.56 Hz), which is an independent criterion. That no single fc
suits both a 1.88 Hz shape and a 6.56 Hz one is a real design tension, not
something to tune away.

### The theory column is itself filtered

`PctOfTheory` compares two differently-filtered quantities and should be
read as orientation, not as a measurement of agreement. Huh and Sejnowski's
(2015) experimental confirmation applies a bandpass centred on the TARGET
angular frequency nu_o, `exp(-5*nu_o*log2(nu/nu_o)^2)` (their Materials and
Methods), after spline-fitting the profiles. Three consequences:

- The filter is parameterised by the very quantity whose predicted beta is
  under test. They state the model prediction has no free parameters to fit,
  which is true of the prediction but not of the preprocessing.
- They report the log-speed/log-curvature scatter "became sharper after
  filtering", so the filtering demonstrably does work in the confirmation.
- Splining is itself akin to low-pass filtering, which Fraser et al. (2025)
  argues should be avoided for exactly this reason.

Their Fig 8 goes further: beta(nu) is framed as the frequency response
function of a linear low-pass filter, with the one-third power law having a
flat frequency response. Filtering is not incidental to their account, it is
their account. So our SG-filtered betas and their nu_o-bandpassed betas are
not the same measurement, and the 39-59% "deflation" quoted elsewhere in
this document should not be read as biology until that mismatch is
addressed.

### Standing implication

Beta's absolute magnitude is a joint property of movement and filter. The
confirmatory claim of this study is about RELIABILITY under a fixed,
pre-specified pipeline (SG6+IRLS), which is unaffected by any of the above:
every participant and visit goes through the identical filter. Absolute-beta
and beta-vs-theory statements are a separate matter and inherit everything
on this page. **Open and untested: whether ICC itself is fc-robust.** If
reliability holds while magnitude slides, the pre-registration is entirely
untouched; if reliability also moves, that is a different conversation. The
sweep now makes that testable.

### Is RELIABILITY fc-robust? (iccVsCutoff_2026)

The magnitude sweep above provokes the load-bearing question: the
confirmatory claim is about reliability under a fixed pipeline, so does ICC
move with fc the way beta's magnitude does?

A partial answer is already free in `icc_results_*`, because six pipelines
are computed there. Between-visit ICC(A,1), fc fixed at 10 Hz for BW:

| shape | BW_Lin | BW_LMLS | BW_IRLS | SG6_Lin | SG6_LMLS | SG6_IRLS | range |
|---|---|---|---|---|---|---|---|
| phi=0.4 | 0.874 | 0.862 | 0.898 | 0.893 | 0.871 | 0.898 | 0.036 |
| phi=0.8 | 0.925 | 0.885 | 0.941 | 0.923 | 0.875 | 0.941 | 0.066 |
| Ellipse | 0.861 | 0.870 | 0.873 | 0.861 | 0.876 | 0.868 | 0.015 |
| Square | 0.912 | 0.895 | 0.883 | 0.922 | 0.911 | 0.875 | 0.047 |
| Cursive | 0.620 | 0.139 | 0.368 | 0.548 | 0.121 | 0.323 | **0.499** |

The magnitudes those same pipelines report swing 30-35% (phi=0.4:
0.196-0.265; Square: 0.080-0.104). So for the templated shapes **reliability
is near-invariant while magnitude is not**, which is the dissociation the
pre-registration needs, reached independently of the fc argument.

Cursive again does not follow: ICC ranges 0.121 to 0.620, a 5x spread, so
for Cursive even the RELIABILITY is pipeline-dependent. The ordering inside
Cursive is the diagnostic one: Linear (0.55-0.62) > IRLS (0.32-0.37) >
LMLS (0.12-0.14). The LESS outlier-robust the regression, the HIGHER the
ICC. That is the pen-lift signature again -- outliers in Cursive carry
personally-stable structure, so a method that lets them through measures
something reproducible that is probably not motor control, and IRLS
downweighting it costs ICC. Filter choice matters far less here than
regression choice (BW vs SG differ by only 0.02-0.07).

`src/functions/iccVsCutoff_2026.m` extends this to fc specifically. It
reports two axes, deliberately:

- **Reliability**: ICC(A,1) between visits, per shape, per fc.
- **Validity**: across the four templated shapes at each fc, Spearman rho
  between mean beta and theoretical beta, plus the between-shape SD of mean
  beta. A shape-blind filter scores ~0 on both regardless of its ICC.

Both are needed because **ICC alone must not be used to choose fc, and this
project has the receipts**: pre-fix Cursive peak velocity had ICC 0.86,
higher than most shapes, while measuring an artifact. An over-filtered
signal could likewise be highly reliable if its output tracks something
stable-but-irrelevant (drawing tempo) while being blind to shape, which at
0.07 Hz it demonstrably is.

Stated in advance, so the data can refute it: ICC should PEAK at
intermediate fc rather than rise monotonically with filtering, because
heavy filtering suppresses within-subject noise (raising ICC) but also
suppresses between-subject differences (collapsing it), and ICC is their
ratio. Cursive's peak should sit at a higher fc than the templated shapes',
given its wider signal band.

Visit membership is resolved by joining `SessionDatetime` against the
newest `trial_level_results_*.csv` rather than re-deriving the grouping
(which has been wrong once before); the participant set therefore matches
the confirmatory N by construction.

```matlab
[icc, val] = iccVsCutoff_2026('participantIDs', [104 201], 'cutoffs', [2.5 10]);  % smoke test
[icc, val] = iccVsCutoff_2026();                                                   % full run
```

**Cost, measured**: ~7 s/participant fixed (file I/O) plus ~21 s per cutoff
per participant (IRLS-bound). The full 31-participant x 9-cutoff run is
~103 min serial, ~26-35 min on 3-4 workers. Run it via `batch` rather than
interactively.

## Environment hazard: FieldTrip/GPstuff silently breaks writetable

Found on the Windows machine (`Technicians`, R2025b Update 5) while
re-exporting the student dataset. `writetable` wrote a CSV with an
**empty header row** and reported success. Every value was correct; the
column names were simply gone, so `readtable` downstream would hand the
students `Var1..Var56`.

Root cause, established by bisecting the 523-entry user path:

```
.../FieldTrip/external/dmlt/external/gpstuff/diag/join.m
```

GPstuff (vendored inside FieldTrip) ships a `join.m` that is an unrelated
function ("join similar structures of arrays"). `writetable` builds its
header by calling `join` on the variable names. Direct comparison:

| | `join({'Alpha','Beta'}, ',')` |
|---|---|
| clean path | `"Alpha,Beta"` (cell) |
| with GPstuff on path | `class=double, isempty=1` |

MATLAB dispatches to the built-in for *string array* input, which is why
it is easy to miss: the shadow only wins for the cell input `writetable`
actually passes.

Two earlier hypotheses were wrong and are recorded here because the
wrong ones are instructive: `isstring` appeared shadowed by
`FieldTrip/external/neuroscope/private/isstring.m` (it was not -- `which
-all` lists private functions that are not actually on the path), and the
MATLAB "same name as a MATLAB built-in" warnings for `contains`,
`newline`, `startsWith` etc. were a red herring: those FieldTrip compat
shims self-remove. Only the bisection settled it.

**Mitigation.** `rmpath` the `gpstuff/diag` folder before running this
pipeline, or check `which join` resolves to
`toolbox/matlab/strfun/join.m`. `exportStudentDataset_2026` now calls
`verifyHeaderWritten()` after `writetable`: it re-reads the first line,
and if the header is missing or its first field is not the expected
variable name it **deletes the file** and errors with the diagnosis.
Deleting matters because `resolveLatestFile()` picks the newest match and
would otherwise keep serving the corrupt export. Guard tested both ways
(fires with the folder on the path, passes without).

This one is squarely why the Fail Loud rule exists: it was priority 4,
"silently degrades to look fine".

## ICC: both variants, one pass

`runICC_2026.m` computes, for every shape x parameter combination:

- **ICC(3,1) consistency** (Shrout & Fleiss 1979) -- appropriate for
  research validity when sessions are fixed but absolute drift isn't
  the concern
- **ICC(A,1) absolute agreement** (McGraw & Wong 1996, model A-1 case 3)
  -- penalises systematic between-visit shifts (e.g. practice effects);
  appropriate when beta is treated as a clinically meaningful absolute
  quantity (the pre-reg MDC framework)

Both at three levels: within-Visit-1, within-Visit-2, between-visit.
Results land in one table (`iccResults`) with an `ICCType` column, not
two separate files.

Smoke-tested against synthetic data (15 participants, 6 sessions, 5
shapes, no injected visit-drift): produced the expected 100 rows
(5 shapes x 10 parameters x 2 ICC types), with consistency and absolute
agreement giving near-identical values -- correct, since no systematic
drift was injected for either to penalise.

## Lin's CCC: the same statistic, and why we still report ICC(A,1)

CCC is the conventional agreement measure in the method-comparison /
Bland-Altman literature, so a reader from that side reasonably asks why
this project reports ICC(A,1). The answer is that for k=2 they are not
"similar": they are the same statistic. Given n, each determines the other
exactly.

```
ICC(A,1) = CCC / (1 - (1-CCC)/n)        CCC = (n-1)*ICC / (n - ICC)
```

Both have the form 1 - (observed disagreement)/(disagreement expected if
the two measurements were unrelated). Lin's denominator
`Sx^2 + Sy^2 + (mx-my)^2` is exactly what ICC(A,1) penalises: subject
variance, plus error, plus the between-visit mean shift. That last term is
what "absolute agreement" means, which is why CCC maps onto ICC(A,1) and
NOT onto ICC(3,1) (consistency drops the mean shift).

Derivation: for k=2 the ANOVA mean squares reduce to
`MSR - MSE = 2*n*Sxy/(n-1)` and `MSR + MSE = n*(Sx^2+Sy^2)/(n-1)`, and the
ICC(A,1) denominator collapses to `D - E[(x-y)^2]/n` where
`D = Sx^2 + Sy^2 + (mx-my)^2` is CCC's denominator. The two differ by one
1/n term. Nickerson (1997) makes the same point analytically.

`computeCCC.m` implements Lin (1989) and cross-checks the identity on every
call (fail loud if it is violated: it is exact, so a deviation means one of
the two implementations has drifted). `tests/test_computeCCC_matchesICC.m`
pins it on random data, at the edges, and at the study N. Real data,
Beta_SG6_IRLS visit means, final N=48 (2026-11-09, CCC from the exact
identity applied to `icc_results_20261109_112131`):

| Shape | CCC | ICC(A,1) | gap |
|---|---|---|---|
| phi=0.4 | 0.848 | 0.850 | 0.0027 |
| phi=0.8 | 0.876 | 0.878 | 0.0023 |
| Ellipse | 0.787 | 0.791 | 0.0035 |
| Square | 0.859 | 0.862 | 0.0025 |
| Cursive | 0.380 | 0.385 | 0.0050 |

N=31 (history):

| Shape | CCC | ICC(A,1) | gap |
|---|---|---|---|
| phi=0.4 | 0.895 | 0.898 | 0.0030 |
| phi=0.8 | 0.939 | 0.941 | 0.0019 |
| Ellipse | 0.864 | 0.868 | 0.0038 |
| Square | 0.873 | 0.877 | 0.0036 |
| Cursive | 0.309 | 0.317 | 0.0071 |

The gap is exactly `CCC*(1-CCC)/(n-1+CCC)`. Note the denominator is
`n-1+CCC`, NOT `n`: a first draft of this note used the `/n` approximation
and claimed 0.25/n as a bound, which is wrong (the true gap is slightly
larger, and 0.25/n is not an upper bound at all). The test suite caught it.
The correct bound is **0.25/(n-1)**, so at N=48 the worst case is 0.0053
(N=31: 0.0082, bound 0.0083). Two consequences:

- CCC and ICC(A,1) cannot disagree enough to move a Koo & Li
  classification unless the estimate sits within ~0.005 of a band edge (~0.008 at N=31).
- The gap vanishes at both extremes and peaks near 0.5, which is why
  Cursive (0.31 at N=31) showed 0.0071 and phi=0.8 (0.94) 0.0019. That is a
  property of the map, not something about Cursive.
- **Sign matters**: the transform inflates magnitude, so CCC < ICC when
  positive but CCC > ICC when negative. Do not assume CCC <= ICC in
  general.

**Why ICC(A,1) stays primary.** It is pre-specified, it is the Koo & Li
convention for test-retest reliability, and it carries the exact F-based
CI we classify on. CCC adds no information. There is also a small-sample
point: Lin's z-transform CI is asymptotic and conventionally wants n >= 30,
and the confirmatory N (31 at the time this was written, 48 now) clears
that only modestly (a shape-level subgroup would not). `computeCCC` therefore does not use Lin's asymptotic
interval at all: it maps ICC(A,1)'s exact F-based bounds through the
identity, which is legitimate because the map is strictly monotone
increasing.

**What n actually is here.** n = 48 participants = 48 pairs per shape, one
pair per participant: (visit-1 mean, visit-2 mean). Each of those means is
over ~30 trials (median 30, range 27-30 at N=31). The trials are collapsed before
the coefficient is computed; it is not a trial-level statistic.

## R cross-validation of computeICC.m -- what it actually found

**Correction (logged here because the first version of this section was
wrong and that matters more than tidying it away).** An earlier version
of this section claimed the original analysis_2025 absolute-agreement CI
formula was mathematically wrong and needed replacing. That claim did not
survive a direct check: comparing `old_computeICCA1.m` (the untouched
original) against the rewritten `computeICC.m` formula on identical data
gives a max difference of 1.22e-15 -- floating-point noise. **They are
the same formula**, algebraically rearranged. The rewrite was a no-op,
not a fix.

Here is what actually happened, in the order it was found:

**1. Consolidation itself: bit-identical (no bug).**
`tests/test_computeICC_matchesLegacy.m` proved the new `computeICC.m`
reproduces analysis_2025's original `computeICC31`/`computeICCA1`
formulas exactly (0.00000 diff, 200 random (n,k) trials).

**2. First R comparison showed a large CI discrepancy -- wrongly
attributed to the MATLAB formula.** Cross-validating against
`irr::icc(model="twoway", type="agreement", unit="single")` (which
explicitly labels its output `"ICC(A,1)"`, confirmed via the returned
`icc.name` field) showed the point estimate matching exactly but the CI
diverging substantially (mean |diff| on the lower bound 0.112, max 0.311,
over 25 trials). This was misdiagnosed as a flaw in the MATLAB CI formula
and "fixed" by rewriting `computeICC.m` to match `irr::icc`'s derivation
line-for-line -- a rewrite that, per point 1 above, changed nothing,
because the original formula was already equivalent.

**3. The real bug: the R wrapper's parameter units, not either formula.**
`computeICCA1_R.m` (the MATLAB->R wrapper written in this session) passed
`irr::icc`'s `conf.level` parameter the value `0.05` instead of `0.95` --
copied from the sibling `computeICC_R.m` wrapper, where the equivalent
`psych::ICC` parameter is literally named `alpha` and 0.05 is correct
there. `irr::icc` names the same kind of parameter `conf.level` and
expects the complement. This produced a valid-looking but wrong ~5% CI
from R -- which is what the MATLAB formula was actually being (wrongly)
compared against in point 2. Fixing this wrapper bug made old and new
MATLAB formulas both agree with R, because they were both already
correct.

**Net result:** `computeICC.m`'s absolute-agreement formula -- original
or rewritten, they're the same -- is bit-identical to `irr::icc`'s
ICC(A,1) for point estimate, lower bound, and upper bound (0.000000 mean
and max |diff| across 25 synthetic trials once the wrapper bug was
fixed). See `tests/test_computeICC_matchesR.m` for the permanent check,
and its history comment for this same account.

**What this means for analysis_2025's reported numbers: nothing changes.**
The phi=0.4/phi=0.8/Ellipse/Square/Cursive ICC(A,1) point estimates *and*
confidence intervals in `analysis_2025/README_TestRetest.md` were computed
with a formula now directly confirmed correct against R. The bug that
surfaced during this validation exercise existed only in a script written
during the validation exercise itself, and never touched any reported
result. No numbers need rechecking or flagging to Jen on this account.

## R power-analysis apparatus

Unchanged from analysis_2025 except path updates:

- `icc_power_analysis.R` -- Zou (2012) via `ICC.Sample.Size::calculateIccSampleSize`,
  reads/writes CSVs passed as CLI args, no project-specific paths, so no
  adaptation was needed
- `powerAnalysisICC_R.m` -- MATLAB wrapper, calls Rscript via `system()`,
  includes the macOS/Windows PATH-finding fix (MATLAB launched from
  Dock/GUI doesn't inherit shell PATH). Confirmed R 4.5.2 available via
  Rscript on this machine.
- `exportICCForPowerAnalysis.m` -- **new**, replaces analysis_2025's
  `report_IRLS_forPowerAnalysis.m` / `report_IRLS_ICC31_forPowerAnalysis.m`
  (which were hardcoded to one named pipeline each). Takes `parameter`
  and `iccType` as arguments, so it works for any of the 6 pipelines
  without copy-pasting a new function per method.

**Bug fix, found running this against real N=31 data for the first
time:** `powerAnalysisICC_R.m`'s verbose printout compared `N_required`
against a hardcoded `61` (the analysis_2025 pilot's target N), which
silently gave a misleading "YES" for every shape regardless of what N had
actually been achieved in the current run. Fixed by having
`exportICCForPowerAnalysis.m` also export each shape's `N_achieved`
(from `runICC_2026`'s own `ICC_BetweenVisit_N`, i.e. the N actually used
in that shape's between-visit ICC calculation) alongside `ICC_BetweenVisit`.
`powerAnalysisICC_R.m` now joins this back in after reading the R
output (the R script itself only ever reads/writes `ShapeName` +
`ICC_BetweenVisit`/`ICC_observed`, so this join happens on the MATLAB
side) and compares `N_required` against the real per-shape achieved N,
rather than a number that goes stale as the cohort grows. If an older
export predates this column, `powerAnalysisICC_R.m` now warns loudly
rather than silently falling back to a guess.

**Final N=48 (2026-11-09, `icc_power_output.csv`; p0=0.75, k=2,
alpha=0.05, power=0.80, Beta_SG6_IRLS, absolute agreement):**

| Shape | ICC | N required | N achieved | Required N cleared? |
|---|---|---|---|---|
| phi=0.8 | 0.878 | 41 | 48 | **YES** |
| Square | 0.862 | 59 | 48 | no |
| phi=0.4 | 0.850 | 78 | 48 | no |
| Ellipse | 0.791 | 620 | 48 | no (ICC close to p0) |
| Cursive | 0.385 | intractable (below p0=0.75) | 48 | no -- not an N problem |

N=48 was set by the students' preregistered Pearson design, not by this
calculation, so these are planning numbers for future studies, not a
failed power target (claude.md section 2). The 2026-11-03 run gave 41 / 60 / 77 / 632; the 0.001 ICC shifts from the finger-touch fix move Ellipse's N by 12, which is how sensitive it is. Interim N=45: 38 / 57 / 74 /
577. Required N is very sensitive to how far the ICC sits above 0.75,
which is why it rose sharply from N=31 as the ICCs settled lower.

**History: first real confirmatory power check (N=31, Beta_SG6_IRLS, absolute
agreement):**

| Shape | ICC | N required | N achieved | Confirmatory-ready? |
|---|---|---|---|---|
| phi=0.8 | 0.941 | 12 | 31 | **YES** |
| phi=0.4 | 0.898 | 27 | 31 | **YES** (narrow margin) |
| Square | 0.876 | 43 | 31 | no -- needs ~12 more |
| Ellipse | 0.868 | 51 | 31 | no -- needs ~20 more |
| Cursive | 0.246 | intractable (below p0=0.75 floor) | 31 | no -- not an N problem, see the Cursive template/content-variability finding above |

At N=31, phi=0.4 and phi=0.8 looked confirmatory-ready and Ellipse and
Square looked like a recruitment target. With more data the ICCs came
down and that reading did not hold (see the N=48 table above). Cursive cannot be fixed by
adding participants given the current free-text task design.

## Figures (the deferred gap, now closed)

analysis_2025's `runICC_2025.m` included ~200 lines of bar charts and
forest plots tied specifically to the 3-method comparison narrative.
Those were deliberately **not** ported: extending them to 6 methods
needed design thought (6-way grouped bars are cluttered), and it was out
of scope for the "get the analysis scripts in" pass. That gap is now
closed by two scripts, neither a direct port.

**`generateFigures_2026.m`** -- the confirmatory story, from
`icc_results_*`, `beta_vs_theory_*` and `icc_power_output.csv`:

- `iccComparison_BetaVsJerk_*.png` -- ICC comparison with Koo & Li 2016
  classification bands and 95% CI whiskers
- `betaVsTheory_*.png` -- observed vs Huh & Sejnowski 2015 predictions,
  four templated shapes, with percentage-of-theory labels
- `powerAnalysis_NrequiredVsAchieved_*.png` -- N required vs N achieved
  (read from the ICC file since 2026-11-03; it was hard-coded to 31),
  colour-coded by status, log y-axis so large required N (Ellipse 620)
  stay visible. Current set: `figures/*_20261109_113603.png` (N=48, after the finger-touch fix)

**`generateDayFigures_2026.m`** -- the day-1/day-2 story, straight from
the trial-level student dataset rather than pre-aggregated summaries, so
it shows the raw per-trial distributions:

- `dayComparison_Measures_*.png` -- beta full-width over a 3x3 grid of
  {Velocity, Acceleration, Jerk} x {Mean, Median, Peak}. Per shape: split
  violin of the per-trial distribution (day 1 left half, day 2 right),
  per-participant visit means as paired dots joined across days, median
  diamond per day.
- `dayICC_Heatmap_*.png` -- all 10 measures x 5 shapes, cell colour and
  large number = ICC(A,1), small value = ICC(3,1).

Both write 300 dpi PNGs to `figures/`. Notes worth keeping:

- The ICC heatmap reuses `computeICCFromLongTable`/`computeICC` rather
  than reimplementing ICC, so it inherits the validated McGraw & Wong
  formulas instead of forking a second copy. Cross-checked against an
  independent Python prototype: beta 0.898/0.941/0.868/0.877/0.245 to
  three decimals.
- Violins use a hand-rolled Gaussian KDE (`kdeProfile`, Silverman
  bandwidth) rather than `ksdensity`/`violinplot`, so the figure adds no
  toolbox dependency beyond the `finv` that `computeICC` already needs.
- **It was the day-figure that exposed the pen-lift bug.** Plotting peak
  alongside median, per shape, made a 6x peak/median anomaly in Cursive
  impossible to miss. The deferred-figures gap had been hiding it.
- No measure shifts significantly between days (all |dz| <= 0.31, nothing
  reaching p < .05 uncorrected), which is independent corroboration of
  the ICC(A,1)-vs-ICC(3,1) agreement below.

### Planned: Bayesian day 1 vs day 2 equivalence check (not yet run)

The `dz` non-significance above is a frequentist absence of evidence, not
evidence of equivalence. Captured here per Dagmar's request (chat session
2026-08-19) so the plan isn't lost before it's scheduled as active work.
Facts/decisions only, nothing below has been run yet:

- **Not a Welch's-t-test candidate.** Day 1 vs Day 2 is paired (same
  N=45 participants, both visits), so it reduces to a one-sample test on
  the per-participant Day2-minus-Day1 Beta_SG6_IRLS differences, per
  shape. There is only one variance to estimate (that of the
  differences), so the equal/unequal-variance concern that motivates
  Welch's t-test over Student's -- and its Bayesian analogue, the
  model-averaged Bayesian t-test (van den Bergh et al. 2024, now JASP's
  default for independent samples) -- does not apply here. That
  distinction only becomes relevant for a genuinely independent-groups
  comparison (e.g. cohort vs cohort), not this one.
- **Primary candidate: paired/one-sample Bayesian t-test** (Rouder et al.
  2009 JZS Bayes factor) on the per-shape Day2-Day1 differences. Gives
  BF10/BF01, quantifying evidence for a real difference vs no difference
  directly, which is the actual claim "little difference" is trying to
  support. Conventional bands (Jeffreys 1961 / Lee & Wagenmakers 2013):
  BF01 > 3 substantial, > 10 strong, > 30 very strong evidence for no
  difference. MATLAB-native: Krekelberg's `bayesFactor` toolbox,
  `bf.ttest(diff)` -- no R round-trip needed, consistent with this
  project's existing preference for MATLAB-local long-running/primary
  analysis.
- **Preferred over the plain BF: Kruschke's BEST (2013)** on the same
  differences, with a ROPE around zero. Consistent with this project's
  existing precision-framework convention (Zou 2012; CI lower bound, not
  point estimate, per the ICC classification rule elsewhere in this
  document) -- BEST reports the full posterior of the mean difference
  and the proportion of it inside a pre-specified ROPE, rather than a
  single point statistic. Its t-likelihood also gives outlier robustness
  for free, relevant given Cursive's already-documented elevated
  WithinSD. ROPE width not yet chosen -- needs a scientifically motivated
  minimal-meaningful-shift value for beta, not an arbitrary default.
- **Scope: exploratory, not pre-registered.** Beta_SG6_IRLS only, per
  shape, matching the confirmatory pipeline restriction used throughout
  this document. Not part of the ICC(A,1) confirmatory analysis; would
  need its own explicit sign-off before being reported alongside it.
- **Status: not yet implemented or run.**

### Literature note: Protzko (2026) on ICC threshold conservatism (2026-08-20)

Added to Zotero by Dagmar; read in full (Study 1 + Study 2 + Discussion)
and checked against this project's ICC choices, chat session 2026-08-20.
Citation: Protzko, J. (2026). *But r Won't Do That: The Limits of
Standardized Covariance*. PsyArXiv preprint,
https://osf.io/preprints/psyarxiv/qt54d_v1/.

**What it is.** Person-first Monte Carlo simulations (N=250, 10,000 reps)
with known ground-truth within-person reliability, testing which
statistics recover that truth. Study 1: Pearson's r fails badly (stays
.5-.89 even when true reliability is ~0), because r is a between-person
statistic asked a within-person question. Study 2 tests alternatives,
including ICC, against the same ground-truth scenarios.

**ICC model tested matches ours exactly.** Two-way mixed effects,
single-measurement, absolute agreement (McGraw & Wong 1996), benchmarked
against Koo & Li (2016) -- the same model and classification scheme this
project uses. Results: ICC=1.0 when truly perfect, but 0.40-0.55 across
every degraded ground-truth condition (true reliability ~0-0.4), landing
in or near the Koo & Li "moderate" band even when it shouldn't. Protzko's
conclusion: ICC thresholds are too lenient as conventionally applied to
the point estimate; he recommends treating ICC point estimates below 0.7
with more suspicion, and supplementing borderline/low ICC with a second,
independent diagnostic rather than trusting the number alone.

**How it bears on our choices (facts, not new decisions):**

- Our CI-lower-bound classification rule (Koo & Li 2016, already
  established practice here, not a point-estimate read) is already a
  stricter test than the one Protzko ran against his own "below 0.7"
  recommendation. phi=0.8's CI lower bound (0.789) clears Protzko's
  proposed conservative floor as well as the standard one, reinforcing
  its status as the one confirmatory-ready shape.
- phi=0.4 (CI lower 0.746) and Square (CI lower 0.760) sit close enough
  to both floors that Protzko's paper is a reason for extra caution
  reading their point estimates in isolation, not a reason to change
  their current classification.
- Cursive (ICC=0.350, CI straddles zero) is unambiguously poor under
  either threshold; unaffected by this note.
- Protzko's recommendation to corroborate a borderline/low ICC with an
  independent diagnostic is what the existing Cursive variance
  decomposition (elevated WithinSD, not collapsed BetweenSD) already
  does. No pipeline change indicated by this note.

**Caveat on transfer.** Protzko's ground-truth mechanism is deliberate
systematic misreporting (a subset of people lying by a fixed or variable
amount), a different generative process from motor variability in
repeated drawing. The qualitative warning (ICC point estimates, and even
moderate CIs, can look better than true reliability) transfers; the
specific numeric values (0.42, 0.52, etc.) are not calibration values for
this kinematic context and should not be quoted as such.

**Status: literature note only. No pipeline or classification change
made.** Relevant if/when Analysis_2026 reaches manuscript stage: worth
citing alongside Koo & Li (2016) as independent support for the
CI-lower-bound convention already in use, and as a caveat on reading
borderline shapes' point estimates.

### Literature note: Tomek, Caldwell & Eisner (2026) on equivalence testing / TOST (2026-08-21)

Added to Zotero by Dagmar; read in full (abstract first, then full text
once added), checked against the planned day 1 vs day 2 equivalence
check above, chat session 2026-08-21. Citation: Tomek, J., Caldwell, A.,
& Eisner, D. A. (2026). Beyond "non-significant" results: Why and how to
test for practical equivalence. *PNAS*, 123(33), e2611548123.
https://doi.org/10.1073/pnas.2611548123

**What it is.** A Perspective piece, not new data or simulation. Core
argument: P >= 0.05 is routinely misreported as "no effect," when it
only shows absence of evidence for a difference, which can arise from
genuine equivalence or from an underpowered/noisy test of a real
effect. Equivalence testing (TOST, two one-sided tests) is proposed as
the standard fix: pre-specify lower/upper equivalence bounds (the
smallest effect size of interest, SESOI) around zero, then test whether
the true difference can be excluded from being more extreme than either
bound. If both one-sided nulls are rejected at alpha, conclude
equivalence. TOST itself is not new -- it originates with Schuirmann
(1987) for pharmacokinetic bioequivalence testing, nearly 40 years old;
the paper's own stated motivation is that it remains underused outside
pharma/psychology despite that long history and despite repeated prior
warnings about the same p-value misinterpretation (their refs back to
Altman & Bland 1995).

**Mechanics relevant to us:**

- The 90% CI-within-bounds decision and the paired one-sided p<.05
  decision are mathematically the same decision expressed two ways, not
  two competing outputs.
- For unpaired comparisons the paper's own worked examples use Welch's
  t-test as the default (citing Delacre, Lakens & Leys 2017); for
  paired comparisons (their Fig. 1) it uses a one-sample t-test on the
  within-subject differences. This independently matches, rather than
  changes, this project's existing rule that Welch's-over-Student's
  applies only to independent two-group comparisons, and that a paired
  Day 1 vs Day 2 design is framed as a one-sample test on differences.
- Software: TOSTER package in R (Caldwell's updated version of Lakens'
  original), `t_TOST()` for the current paired/one-sample function; a
  no-code online calculator also exists, validated against TOSTER, but
  R is the fit for this project's existing system()+CSV pipeline.

**How it bears on the planned Day 1 vs Day 2 equivalence check
(above):** TOST is not a competitor to the planned Bayesian check, it
answers a related but distinct question by a different mechanism.
Rouder's JZS Bayes factor needs no bound and returns continuous
relative evidence (BF10/BF01); TOST and Kruschke's BEST+ROPE both
require a pre-specified "practically no difference" region and are the
closer Bayesian/frequentist pair. Running TOST alongside the Bayesian
check would be convergent evidence from two independent frameworks, not
duplication.

**Open item, not yet decided: the SESOI.** Neither this note nor the
existing Bayesian-check plan above states what beta difference for a
given shape (e.g. phi=0.8) would count as "practically no change"
between Day 1 and Day 2. The paper is explicit that this bound is a
subject-matter judgement, not a statistical one, and must be stated and
justified before the test is run, not fitted to the data afterward.
This is the concrete next step before either the TOST or the Bayesian
equivalence check can be run, not a pipeline change in itself.

**Status: literature note only. No pipeline change made; the day 1 vs
day 2 equivalence check (Bayesian, above) remains not yet implemented
or run, and now has a named prerequisite (the SESOI) rather than an
implicit one.**

## Test-retest stability at N=45, and exploratory trait correlations (2026-10-08)

> **Obsolete numbers (2026-11-09):** this section is from the 2026-08-04 N=45 run (9.73 scale, no finger-touch filter). The current N=45 is the 45 originals of the 2026-11-09 run (`data/processed/baseline_N45/`, rebuilt by `rebuildBaselineN45_2026`); current N=48 figures are in `claude.md` section 2 and `docs/SensitivityPlan_N48.md` (amendment 2026-11-09). Kept as the dated record.

**Reproducible, no participant count hard-coded** (n is read from the data, so
re-run after the extra participants arrive):

```matlab
mergeQuestionnaires_2026();          % CATI/M-EDL sheet + kinematics -> participant_kinematics_questionnaires_N<n>_*.csv
reportStability_2026();              % agreement + individual-level tables -> stability_agreement_/individual_/participants_N<n>_*.csv
diagnoseShapeStability_2026(5);      % Cursive variance/execution diagnostic -> stability_shapeDiagnostic_shape5_N<n>_*.csv
analyseTraitKinematics_2026(M, outDir, figDir)   % EXPLORATORY CATI_Total / M_EDL vs Beta/Jerk (M = merged table)
```

`reportStability_2026` asserts that its recomputed ICC(A,1) matches
`icc_results` to 1e-3, so a trial_level / icc_results mismatch fails loudly.
All numbers below: `trial_level_results_20260804_150537`,
`icc_results_20260804_155822`, Beta_SG6_IRLS visit means, V1 vs V2, N=45.
Pearson, Spearman and ICC use the shared `computeICC` / `buildVisitMatrices_2026`
(same session -> visit aggregation as `runICC_2026`).

**Test-retest agreement: ICC is the right tool, and here it agrees with Pearson
for four of five shapes.**

| Shape | Pearson | Spearman | ICC consistency | ICC absolute | Mean shift V2-V1 [95% CI] | MDC95 as % of mean |
|---|---|---|---|---|---|---|
| phi=0.4 | 0.852 | 0.834 | 0.850 | 0.852 | 0.003 [-0.017, 0.023] | 54% |
| phi=0.8 | 0.890 | 0.883 | 0.890 | 0.882 | 0.016 [0.001, 0.031] | 41% |
| Ellipse | 0.790 | 0.744 | 0.788 | 0.792 | 0.002 [-0.013, 0.017] | 50% |
| Square | 0.881 | 0.887 | 0.870 | 0.863 | 0.004 [-0.0001, 0.008] | 29% |
| Cursive | 0.376 | **0.702** | 0.348 | 0.350 | -0.004 [-0.015, 0.007] | 39% |

ICC measures agreement (and gives a CI for the Koo & Li lower-bound rule);
Pearson ignores constant shifts and rescaling; Spearman ignores magnitude.
Pearson and ICC differ little because the day-to-day mean shift is small
(0.02 to 0.15 SD). Cursive is the exception that shows the danger: Spearman
(0.70) would flatter it relative to the ICC (0.35). Absolute vs consistency
max |difference| is 0.008 across shapes (0.007 at N=31). **phi=0.8 (the
confirmatory shape) has a small positive shift, visit 2 about 6% higher, with
the CI just excluding 0 (uncorrected across 5 shapes): report it, do not
claim zero drift.** Square is borderline.

**Individual-level stability** (`stability_individual_N<n>_*.csv`):

| Shape | Beyond MDC95 | Median change in own value | 90th percentile | Same quartile | Jumped 2+ quartiles |
|---|---|---|---|---|---|
| phi=0.4 | 1/45 | 18% | 53% | 51% | 2% |
| phi=0.8 | 3/45 | 11% | 38% | 80% | 2% |
| Ellipse | 3/45 | 18% | 42% | 64% | 11% |
| Square | 1/45 | 9% | 20% | 67% | 2% |
| Cursive | 2/45 | 5% | 19% | 58% | 16% |

38 of 45 participants never exceed MDC95, 5 do on one shape, 1 on two, 1 on
three or more (about the 5% expected by chance, so no excess of unstable
people). IDs 209 and 321 exceed it on 2+ shapes; 209 is the participant with
the mislabelled sessions (`docs/EmailIngestionPipeline.md`), so confirm its two
visits are paired correctly before reading it as real instability. MDC95 is
29% to 54% of the mean beta: reliable for ranking people (between-person
comparisons), coarse for detecting change within one person. Within-visit ICC
(0.83 to 0.93) exceeds between-visit ICC for every shape except Square, so
day-to-day adds some error beyond session noise (modest, except Ellipse and
Cursive). **Caveat:** visit means average three sessions, so single-session
stability is lower than shown.

**Cursive at N=45 (`diagnoseShapeStability_2026(5)`), consistent with the
content-variability diagnosis above, not a replacement for it.** Between-person
SD is 0.0263 (Square 0.0254) and within-person SD 0.0134 (Square 0.0074), the
same pattern as N=31; SNR is the lowest of the five (1.96). The typical person
is the most stable of any shape (median change 5%; within-session trial CV of
beta 0.13 vs 0.18 to 0.23 elsewhere, though duration CV is about 3x higher,
0.069 vs about 0.02). The low ICC is driven by two participants: a robust rule
(|d| > median + 5 x 1.4826 x MAD of |d|, no IDs hard-coded) flags IDs 202 and
302 (visit change in beta -0.176 and -0.128 vs a median |d| of 0.008 for
everyone else), who also differ between visits by about 4 to 5 pen lifts per
trial and by 133 mm and 473 mm of path length (others: median 0.5 lifts, 26 mm). [Old 9.73 scale; at 5.209 pt/mm these are 248, 884 and 49 mm.]
**POST HOC DIAGNOSTIC, not a result:** ICC(A,1) is 0.350 [0.066, 0.582] with
all 45 and 0.753 [0.589, 0.858] without those two. Because the task is
free text, different path length and lift counts between visits are what
different written content would produce, so this does not separate content
from execution; the next step is to compare the raw V1 and V2 text for 202 and
302. Spearman correlations between |change in beta| and |change in path / lifts
/ strokes / duration| across all participants are weak (0.13 to 0.18) because only
two people drive it. The existing methods implication (a fixed repeated phrase)
still stands. An earlier chat remark that instructing participants to keep the
pen down might fix it is not supported by the free-text design and is withdrawn.

**Exploratory CATI_Total and M-EDL vs Beta/Jerk** (`analyseTraitKinematics_2026`;
Spearman primary because M-EDL is zero-inflated and jerk skewed; bootstrap 95%
CI over participants, B=4000, seed 20261008; estimation, no p-values; ICC is not
applicable here because trait and kinematics are different constructs, so
association is the right question). CATI subscale labels are unverified, so
only the totals are used. 0 of 20 visit-mean CIs exclude 0 (about 1 expected by
chance). CATI_Total vs beta is about 0 for phi=0.4/0.8/Ellipse/Square and
-0.20 [-0.44, 0.08] for Cursive; M-EDL vs beta is negative for every shape
(-0.14 to -0.29; Square -0.29 [-0.56, 0.02]) but all CIs include 0; jerk about
0; sign agrees across visits in 15 of 20 pairings. **Pearson vs Spearman:** the
two sets of r correlate 0.89, max |difference| 0.11, CIs excluding 0: Pearson 1,
Spearman 0, one sign disagreement, so the choice barely matters here. CIs
are about +/-0.3 wide: the earlier assumed r(CATI, beta) of 0.20 to 0.25 is
neither supported nor excluded, and the a-path of the planned mediation (CATI
to beta) is about 0, so there is nothing to mediate. M-EDL has 16 of 45 exact
zeros of unknown meaning (`docs/PublicationTodo.md` section 3).

**Note on numbers quoted earlier in conversation:** a few figures were first
computed ad hoc from raw trial means; the scripted versions aggregate session
means then visit means (as `runICC_2026` does) and differ slightly for
individuals (e.g. ID302 change in beta -0.128 scripted vs -0.132 ad hoc, ID202
path change 133 mm vs 153 mm; 248 vs 286 mm at 5.209 pt/mm). Use the scripted values.

## Pipeline robustness of test-retest reliability (2026-10-08)

**Reproducible, n read from the data:**

```matlab
reportPipelineRobustness_2026();   % -> data/processed/pipelineRobustness_N<n>_*.csv + figures/pipelineRobustness_specCurve_N<n>_*.png
```

It computes between-visit ICC(A,1) with exact CIs (`computeICC`) for all six filter x regression pipelines in all five shapes, then a PAIRED cluster bootstrap over participants (B=4000, seed 20261008, recorded in the CSV): the same resampled participants feed every pipeline, so delta-ICC against the primary pipeline reflects the pipeline, not sampling noise. Overlapping separate CIs are not a test of a difference. It asserts that every ICC matches `icc_results` to 1e-3 and verifies the CSV header.

**Why these six.** Fraser et al. (2025, Exp Brain Res 243:107) call Butterworth filtering + finite differences + log-log linear regression the *legacy* protocol, and Savitzky-Golay differentiation + LMLS or IRLS regression on untransformed data the *vetted* protocol. Vetted was chosen on two VALIDITY criteria (no spurious one-third from beta=0 synthetic data, Figs 5 and 6; recovery of one-third on real ellipses, Fig 7). The six pipelines here are the 2x3 grid of that paper Fig 7, so this is a published design, not a post hoc multiverse. The paper never tested reliability; this section adds it.

**Reliability is not validity.** Fig 6 of that paper shows a legacy Butterworth filter produces a spurious one-third from beta=0 data, so a legacy pipeline can be reliable and wrong (the 2026-07-16 pen-lift artefact was the same lesson: reliably measuring the wrong thing). The primary pipeline (SG6+IRLS) is chosen on validity grounds. Never choose or promote a pipeline because its ICC is higher, and do not write that the vetted protocol is more reliable.

Between-visit ICC(A,1), N=45 (`pipelineRobustness_N45_20261008_222827.csv`):

| Shape | BW Linear | BW LMLS | BW IRLS | SG6 Linear | SG6 LMLS | **SG6 IRLS (primary)** | Range |
|---|---|---|---|---|---|---|---|
| phi=0.4 | 0.843 | 0.832 | 0.852 | 0.852 | 0.837 | **0.852** | 0.021 |
| phi=0.8 | 0.862 | 0.842 | 0.882 | 0.864 | 0.838 | **0.882** | 0.045 |
| Ellipse | 0.794 | 0.822 | 0.795 | 0.797 | 0.828 | **0.792** | 0.036 |
| Square | 0.883 | 0.885 | 0.870 | 0.904 | 0.899 | **0.863** | 0.041 |
| Cursive | 0.558 | 0.158 | 0.406 | 0.542 | 0.143 | **0.350** | 0.415 |

**Findings.**
- For the four templated shapes, the whole grid moves ICC(A,1) by at most 0.045 (range 0.021 to 0.045). Reliability does not depend materially on the analysis pipeline there.
- Regression matters more than filter, but neither much. Mean ICC over the four templated shapes: Linear 0.850, LMLS 0.848, IRLS 0.849; Butterworth 0.847, Savitzky-Golay 0.851.
- The primary pipeline is NOT the most reliable: it ranks 1st (phi=0.4, tied), 2nd (phi=0.8, tied with BW IRLS), 6th of 6 (Ellipse), 6th of 6 (Square) and 4th (Cursive). It was not chosen by ICC, which is the right way round, and it can be reported as such.
- Paired bootstrap, delta-ICC against the primary: 2 of 25 CIs exclude 0, both Square and both favouring a non-primary pipeline (SG6 Linear +0.041 [+0.002, +0.073]; SG6 LMLS +0.036 [+0.007, +0.059]). With 25 uncorrected comparisons about 1.25 are expected by chance, so this is not evidence of a real difference. Vetted minus legacy (SG6 IRLS minus BW Linear): phi=0.4 +0.009, phi=0.8 +0.020, Ellipse -0.003, Square -0.020, Cursive -0.208, all with CIs that include 0.
- Koo and Li (2016) criterion (CI lower bound >= 0.75, not the Zou required-N test): phi=0.8 clears in 2 of 6 pipelines (BW IRLS 0.790, SG6 IRLS 0.789; the others sit at 0.721 to 0.74); Square clears in 6 of 6 (0.760 to 0.821, primary 0.760); phi=0.4 in 0 of 6 (0.714 to 0.747; primary 0.746); Ellipse 0 of 6 (0.651 to 0.707); Cursive 0 of 6. Square clearing the lower-bound rule is consistent with, not in conflict with, its Zou required N of 57: the lower bound is only just above 0.75, so 45 is too few to establish it with 80% power. The confirmatory call (phi=0.8 only) is unchanged.
- **Cursive is the exception and is regression-sensitive**: ICC runs from 0.143 to 0.558 across the grid, every CI is wide (lower bounds -0.157 to 0.317) and none reaches 0.75. The two LMLS pipelines are lowest (0.158, 0.143), Linear highest (0.558, 0.542), IRLS between. No cause has been tested; hypotheses to check before writing anything are LMLS non-convergence or outlier sensitivity on pen-lift-fragmented data (see the Cursive diagnosis in the N=45 stability section above). Report the 0.14 to 0.56 spread honestly as a limitation of Cursive, not as a choice of pipeline.
- Absolute beta differs by regression but barely by filter (mean over the four templated shapes: Linear 0.205, IRLS 0.194, LMLS 0.154; Butterworth vs SG6 differ by about 0.001 to 0.002). This echoes the paper observation that regressions have different plateaus under noise and is a reason to keep claims about reliability, not absolute beta.

**Caveats.** The same 45 people go through all six pipelines, so they are not six independent studies; the forest/spec-curve figure shows robustness, not replication. The bootstrap resamples participants only (not sessions or trials). Visit means average three sessions, so single-session reliability is lower. Pre-specification wording: Fraser et al. (May 2025) designates the SG + non-linear regression family before the 2026 data existed; the choice of IRLS within it rests on the analysis_2025 pilot, whose timestamp is still unconfirmed (`docs/PublicationTodo.md`). Figure: `figures/pipelineRobustness_specCurve_N45_*.png` (viewed 2026-10-08: five panels, six points each, CI bars and the 0.75 line render correctly).

## Literature note: prior test-retest work on drawing and handwriting kinematics (2026-10-08)

**Status: a quick, NON-systematic web search (three searches plus targeted fetches), not a literature review. Some sources were read at abstract level only; PMC pages were blocked for one fetch. Before any novelty claim in the paper, run a systematic search (Scopus or Web of Science: citing Lacquaniti et al. 1983 or Huh and Sejnowski 2015, AND reliab* or repeatab* or test-retest) and check the Zotero library.**

**Velocity-curvature power law beta.** The three searches turned up no test-retest or repeatability study of the beta exponent. Fraser et al. (2025) assessed validity only (spurious confirmation, recovery on real ellipses), not reliability. "To our knowledge" wording only, pending the systematic search.

**Related instrumented drawing and handwriting work found:**

| Source | Task and sample | Measures | Test-retest result |
|---|---|---|---|
| Scoping review, digitised Archimedes spiral (PMC12625189, 2025) | 14 to 15 test-retest studies, 11 in Parkinson disease or essential tremor | mixed kinematic and accuracy features | ICC 0.74 to 0.97 (PD/ET); outside PD/ET 0.2 to 0.95, called preliminary. Only 2 studies reported measurement error (MDC 51% to 67%, and 14% to 38%) |
| Digitizing tablet, essential tremor (Tremor Other Hyperkinet Mov, doi 10.5334/tohm.344) | N=18, Wacom Intuos 3, Archimedes spirals | tremor amplitude from spectral analysis | ICC (two-way random, absolute) 0.97 [0.91, 0.99]; MDC 51% of baseline |
| Tablet-based upper-limb tests (PubMed 32757680) | N=54 (29 neurological patients, 25 healthy); spiral, tapping, follow the dot, trace a star | accuracy, speed, path length | accuracy ICC 0.76 to 0.88; speed and path length 0.20 to 0.69 (poor to moderate) |
| Handwriting in MCI (JMIR Aging 2025, e73074) | 45 of 57 completed; cursive and block writing, list and free text; two same-day sessions at least 30 min apart | log dimensionless jerk (LDLJ), SPARC, peak differences (inertial, angular velocity) | cursive ICC 0.86 to 0.93; block letter weaker (e.g. LDLJ 0.55); sample sized for a minimum ICC of 0.42 |
| SOS-test, Parkinson handwriting (PLOS ONE 2017) | 67 retested, interval 1 week to 1 month | NOT instrumented (letters per 5 min, size, quality) | ICC above 0.769 |
| Gulde and Hermsdoerfer 2018 (Front Neurol) | 8 young, 8 older adults, making tea | NoP, SAL, SM, LDJ | NOT test-retest; LDJ separated groups best but they conclude trial duration must be controlled |

**What this means for us.**
- Positioning: instrumented reliability work is concentrated in clinical spiral and handwriting tasks, with ICCs 0.74 to 0.97 and little reporting of measurement error (MDC). Our paper reports ICC with exact CIs, SEM and MDC95, which is better than most of this literature.
- Speed and path measures are only poor to moderate in the tablet battery (0.20 to 0.69). Our beta (0.79 to 0.88 for four shapes, same at N=45 and N=48) sits above that, whereas our jerk is lower (0.34 to 0.66 for the templated shapes at N=48; 0.31 to 0.67 at N=31). Different tasks and populations: indicative only, not a head-to-head.
- Cursive: the MCI study reports high jerk-based ICCs for cursive (0.86 to 0.93) with same-day sessions in patients with large between-person spread; ours are about a week apart in healthy and autistic-trait-varying adults. Do not compare numbers without noting interval, population and signal (inertial pen vs tablet).
- N precedent: the MCI handwriting reliability study completed 45 participants (target 40 from a minimum-ICC power calculation); the tablet battery used N=54; the spiral tremor study N=18. Our N=48 (45 at the interim look) is typical for this literature, though COSMIN would still call it moderate.
- Jerk is duration-sensitive (Gulde and Hermsdoerfer 2018): mechanical overlap between beta, speed and jerk is another reason not to run a mediation through them.

## Trajectory scale: UIKit points, not pixels (2026-11-02)

**What was found.** The raw x,y in the StimuliAppUoB `tracingSection-enhanced.csv` files are UIKit points, not device pixels. On the M4 13 inch iPad Pro that is 5.209 points/mm. Two checks agree: a ruler on the on-screen ellipse gives about 116 x 55 mm, and the median traced extent over 7,259 ellipse trials is 629 to 637 x 292 to 294 points, which is about 121 x 56 mm in points but only 60 x 28 mm if read as pixels. The pipeline had divided by 9.73 (carried from analysis_2025), so every mm quantity was understated by 9.73/5.209 = 1.868x. The Fraser importer's 10.418 was 2.00x too large in the same way. (The earlier open item estimated about 10.39 from 264 PPI, which is the pixel density; at the 2x UIKit scale factor that is 132 points per inch, about 5.2 points/mm.)

**How it was confirmed to leave beta alone.** `calculatePowerLaw` was run on 60 real trials (6 randomly chosen session files, seed 1) at 9.73 and at 5.209. Max |dBeta|: SG6_IRLS 1.5e-7, SG6_LMLS 7.5e-6, BW_Linear 1.4e-10. `NumPoints_Regress_SG6` was identical on every trial. Velocity rose by exactly 1.8679 and VGF by a median 1.6789, matching the predicted 1.868^(1-beta). Nothing in `runAnalysis_2026` or `calculatePowerLaw` thresholds in mm: edge clip and SG window are in samples, pen lifts come from `time_seconds`, and the regression validity mask is `> 1e-10`.

**Action taken at source.** New `src/functions/ipadPointsPerMm.m` returns 5.209 and is the single source of the scale. It replaces the literal 9.73 in `runAnalysis_2026.m`, `iccVsCutoff_2026.m` and `sweepFilterCutoff_2026.m`. `test_runAnalysis_medianFieldsPropagate.m` keeps a literal 5.209 so the test catches any drift in the function. No vetted protocol file was edited.

**What is affected.** Stale until re-run: Mean/Median/Peak velocity, acceleration and jerk (both filters), `PathLength_mm`, and VGF for all six pipelines, plus the handover and student exports and any figure showing them. Unaffected: Beta, FitCorr, NumPoints, Duration and every beta ICC, CI, required N and TOST result.

**Full re-run, 2026-11-02 15:06 (`trial_level_results_20261102_150632`, `icc_results` of the same day).** Compared with `trial_level_results_20260804_150537`, all 13,488 trials matched on (ID, visit, session, trial). Velocity and PathLength_mm rose by exactly 1.8679 on every trial; VGF matched 1.868^(1-beta) to within 0.1%. Beta was NOT perfectly unchanged, which corrects the 60-trial check above: `filterForRegression` in `calculatePowerLaw` keeps samples with curvature > 1e-10 and velocity > 1e-10, and those absolute cut-offs are in mm units. Shrinking curvature by 1.868 moves a few near-straight samples (curvature down to 2.6e-12 /mm) across the cut-off, and in log-log space those samples are extreme leverage points. 48 trials changed their SG6 regression N (by -9 to +5 of about 1,830), mostly phi=0.4 and Square. Effect by pipeline: SG6_Linear up to 0.195 (40 trials > 0.01), SG6_LMLS up to 0.061 (13 trials > 0.01), SG6_IRLS up to 3.3e-4 (none > 0.01), BW all < 5e-5. IRLS flipped between a value and NaN ("Returning NaN" from regressDataEBR) on 8 trials (SG6: 4 lost, 1 gained; BW: 3 gained). Between-visit ICC changed by at most 0.0035 (SG6_Linear, Cursive); confirmatory SG6_IRLS by at most 0.0005, and no Koo and Li class changed. Kinematic ICCs are unchanged because the scaling is uniform. Implication: the 1e-10 mask is a units-dependent threshold sitting on near-zero curvature, and OLS on log curvature is sensitive to it. The confirmatory IRLS is robust to it; Linear and LMLS on the SG path are not.

**Still open.** (1) analysis_2025 still hard-codes 9.73 (`runAnalysis_2025.m` lines 212, 444 to 445; `diagnoseSGPeakVelocity.m` line 127), left as is because that analysis is complete. (2) The Fraser importer (10.418) is outside this folder. (3) 100% of Pencil x,y land on whole device pixels (.0 or .5 points), which suggests the app logs `location(in:)` rather than `preciseLocation(in:)`; unverified until the Swift source is checked. (4) Pencil timestamps may be rounded to whole ms on 240 Hz iPads (Apple forum report); untested on this device.

## Finger and palm touches in the Pencil stream (2026-11-09)

**What was found.** The `-enhanced.csv` files mix direct finger or palm touches (`touch_type` 0) with Apple Pencil samples (`touch_type` 2). No other value occurs. Dagmar first noticed this in 159 Ellipse trials (Pencil data check, 2026-11-03). Measured over the 48 included participants, it affects **926 of 14,389 trials** (all five shapes; phi=0.4 192, phi=0.8 181, Ellipse 159, Square 142, Cursive 252; 34 participants). The finger and the Pencil share **one** `touch_index` counter, with no index collisions, so the finger samples sit between Pencil samples (e.g. ID108 2026-07-28 113318 trial 14: Pencil at x about 865 pt, finger at x about 1176 pt, alternating). `runAnalysis_2026` de-duplicated and sorted on `touch_index` only, so these samples went straight into the trajectory. The result is 50-120 mm jumps and `time_seconds` stepping backwards.

**Why the fix renumbers the index.** Dropping the finger samples leaves holes in the Pencil's `touch_index` (steps of 2 to 4), and these would appear as false gaps in `t = touch_index/fs`. After filtering, the Pencil samples are renumbered 1..n. In the 13,463 clean trials the Pencil index already steps by exactly 1 (0 exceptions), so renumbering is a no-op there and their results are unchanged. Pen lifts are still found from `time_seconds` by `detectPenLifts` (see "Pen lifts in Cursive" above).

**Action at source.** New `src/functions/pencilSamplesOnly.m` (filter `touch_type == 2`, de-duplicate, sort, renumber; it errors if `touch_type` is missing). It replaces the de-duplicate/sort lines in `runAnalysis_2026.m` (lines 345-347), `sweepFilterCutoff_2026.m` (line 250) and `iccVsCutoff_2026.m` (line 275). No vetted EBR file was touched.

**Impact (interim, before the full re-run).** `diagnoseTouchTypeFilter_2026` re-processes every contaminated trial with and without the filter (`data/processed/touchTypeFilterEffect_20261109_105632.mat`). `reportTouchTypeFix_2026`, which calls `compareICCTouchFix_2026`, patches those trials into `trial_level_results_20261103_151020` and recomputes the between-visit ICC(A,1) (`touchTypeFix_trialSummary_20261109_105643.csv`, `touchTypeFix_ICC_20261109_105643.csv`).
- Trial level: SG6_IRLS beta median |d| 0.0005, max 0.075, 63 trials > 0.01, 4 Cursive trials change NaN status. Peak velocity, acceleration and jerk were inflated in about 30-90 trials per shape, by up to 14x (velocity) and 280x (jerk). Means and medians are within about 0.3% at the median. Cursive stroke count changes in 82 trials.
- ICC: beta, VGF and FitCorr change by < 0.01, with no class change. Peak kinematics rise on the templated shapes (SG peak jerk +0.17 to +0.45; BW peak jerk up to +0.63; peak acceleration +0.13 to +0.34) and fall on Cursive (SG peak jerk 0.517 -> 0.400). Lower-bound class changes: peak velocity phi=0.8 moderate -> good (SG and BW), Cursive SG moderate; peak acceleration phi=0.4/0.8 poor -> moderate; peak jerk phi=0.8 poor -> moderate. Means and medians change by <= 0.005 (BW mean jerk up to +0.04).
- Caveat: the "before" values from the diagnostic match the 3 Nov trial file to 0.7% relative for beta, but FitCorr differs by up to 33% on a few trials. The definitive numbers are the full re-run.

**Confirmed by the full re-run (2026-11-09).** Dagmar ran `runN48_2026('stage','all')` with the fix in place (`trial_level_results_20261109_112129`, `icc_results_20261109_112131`). `verifyTouchFixRun_2026` confirms the 13,462 clean trials are identical to 3 Nov, the 926 fixed trials match the diagnostic, and the official ICCs equal the interim ones (`touchFixRunCheck_ICC_20261109_113047.csv`). `refreshDownstream_2026` then re-ran trait, stability, shape-5 diagnostic, pipeline robustness, note evidence and figures. `diffRunOutputs_2026('20261103_15','20261109_11')` lists every changed output cell (`runDiff_20261103_15_vs_20261109_11.csv`); `summariseKeyNumbers_2026` and `makeDocTables_2026` regenerate the numbers and tables quoted in `claude.md` and this file. Beta conclusions are unchanged (largest headline shift: Zou N for Ellipse 632 -> 620). The handover was regenerated from this run.

## Usage

```matlab
% 1. Compute power law + kinematics for all trials
%    (add 'exactSessionsOnly', true to skip ambiguous-count participants
%    like ID103/ID212; add 'useParfor', true to parallelise -- both
%    optional, both off by default)
runAnalysis_2026('exactSessionsOnly', true, 'useParfor', true)

% 2. Compute ICC(3,1) and ICC(A,1) for all 6 pipelines + kinematics
iccResults = runICC_2026();

% 3. Export the confirmatory pipeline's ICC for the R power analysis
%    (defaults: Beta_SG6_IRLS, absolute agreement -- matches analysis_2025 precedent)
exportICCForPowerAnalysis(iccResults);

% 4. Run the R-based sample size calculation
powerAnalysisICC_R();

% 5. Regenerate the beta-vs-theory and ICC-type-symmetry evidence tables
%    cited above (also writes timestamped CSVs to data/processed/)
[thetaTable, iccSymmetryTable] = reportNoteEvidence_2026();

% 6. Export the one-row-per-trial student CSV + its README data dictionary
%    (guards its own header -- see the FieldTrip/GPstuff hazard above)
exportStudentDataset_2026();

% 7. Figures (300 dpi PNGs -> figures/)
generateFigures_2026();      % confirmatory: ICC, beta-vs-theory, power
generateDayFigures_2026();   % day 1 vs day 2 measures + ICC heatmap

% 8. Standalone: how far does beta move with the Butterworth cutoff?
%    Writes its own CSV + PNG; does not touch the confirmatory pipeline.
[sweepTable, sgRef] = sweepFilterCutoff_2026();
```

On Windows, check `which join` resolves to `toolbox/matlab/strfun/join.m`
before step 6, or `rmpath` FieldTrip's `gpstuff/diag`. See the
environment-hazard section above.

To check a different pipeline's ICC (e.g. to confirm the champion still
wins against the full 6-way grid once real data exists):

```matlab
exportICCForPowerAnalysis(iccResults, 'parameter', 'Beta_BW_IRLS', 'iccType', 'absolute');
powerAnalysisICC_R();
```
