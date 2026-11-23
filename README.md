# power-law-test-retest

MATLAB code (with supplementary R models) for a test-retest reliability study of the speed-curvature power law (the exponent beta, Lacquaniti et al. 1983) measured from Apple Pencil drawing on an iPad. It takes the raw session files from the iPad app to trial-level beta and kinematics, between-visit reliability (ICC), and the sensitivity, stability and robustness analyses reported in the paper.

The method follows Fraser, Di Luca & Cook (2025), *Exp Brain Res* 243:107. The functions `differentiateKinematicsEBR.m`, `regressDataEBR.m` and `curvatureKinematicEBR.m` come from that paper's protocol and are used unchanged.

## Study design

- 51 adults took part and 48 completed both visits. The 3 non-completers were replaced, and their partial data are analysed only descriptively (`analyseOrphanRuns_2026`).
- There were 2 visits about a week apart, each with 3 sessions of about 50 trials (10 repetitions x 5 shapes).
- The 5 shapes were traced templates with phi=0.4, phi=0.8, an ellipse and a square, plus free-text cursive handwriting.
- Data were recorded with an Apple Pencil on a 13" M4 iPad Pro at 240 Hz.

## Analysis in brief

- **Primary pipeline:** Savitzky-Golay differentiation (SG6) with IRLS robust regression of log speed on log curvature. Five comparator pipelines ({Butterworth, SG6} x {Linear, LMLS, IRLS}) run alongside it.
- **Reliability:** ICC(A,1), absolute agreement, on visit means. ICC(3,1) is reported as a secondary measure. Reliability is classified from the 95% CI lower bound (Koo & Li 2016), never from the point estimate. The required N comes from Zou (2012), computed in R with `ICC.Sample.Size`. `src/R/powerCalcN48.R` reproduces the a-priori calculation behind N=48 (ANCOVA, f = 0.5, power .80) and the pilot-based Zou N per shape.
- **Benchmarks:** mean and peak velocity, acceleration and jerk, all from the same SG path.
- **Data handling** (see `docs/AnalysisPipeline.md`):
  - Raw x,y are UIKit points at 5.209 per mm (`ipadPointsPerMm.m`).
  - Only Apple Pencil samples are kept (`touch_type == 2`, `pencilSamplesOnly.m`).
  - Pen lifts are found from the timestamp residual (`detectPenLifts.m`).
  - The first and last 50 samples of each trial are clipped, and the SG boundary samples at each pen lift are masked, so nothing is differentiated across a lift.
- **Sensitivity analysis:** the original 45 completers are compared with the final 48, both on the same pipeline. The pre-specified plan is in `docs/SensitivityPlan_N48.md`.

## Requirements

- MATLAB (developed on R2025a/b), with the Signal Processing Toolbox and the Statistics and Machine Learning Toolbox. The Parallel Computing Toolbox is optional and is used for the per-participant loop.
- R, with `ICC.Sample.Size`, for the Zou sample-size step, and with `lme4`, `lmerTest`, `brms`, `emmeans`, `lavaan`, `dplyr`, `tidyr`, `ggplot2` and `readxl` for the supplementary and registered analyses in `src/R` (brms uses `cmdstanr` if CmdStan is installed, otherwise `rstan`). `test_computeICC_matchesR` also needs `psych` and `irr`.
- Python 3, standard library only, for the optional email-ingestion scripts.

## Layout

```
src/functions/   analysis code (MATLAB), Zou step (R + shell), email ingestion (Python)
src/R/           supplementary variance decomposition (lme4, brms), the registered ANCOVA and mediation, and the power calculation
tests/           matlab.unittest tests; old_*.m are legacy ICC references used by one test
docs/            Claims.md (register of current claims), AnalysisPipeline.md (methods and decision log), SensitivityPlan_N48.md, DesignNotes.md
data/            not in the repository (see Data)
```

## Running

Put the participant folders under `data/raw/automatic/ID<nnn>/`, with each session's `* tracingSection.csv` and `* tracingSection-enhanced.csv` files as the iPad app exports them. Then, from the project root:

```matlab
addpath(genpath('src'))
runN48_2026('stage', 'preflight')   % read-only readiness check
runN48_2026('stage', 'all')         % runAnalysis_2026 -> runICC_2026 -> Zou N -> N=45 vs N=48 comparison
refreshDownstream_2026()            % stability, robustness, trait correlations, figures
summariseKeyNumbers_2026()          % the headline numbers, written to data/processed/keyNumbers_*.txt
```

All outputs are timestamped files in `data/processed/` and `figures/`. Every number quoted in the docs comes from one of these scripts, not from console work.

The supplementary variance decomposition (R) reads the SG6+IRLS handover CSV from `handover/` and the questionnaire full-scores sheet from `data/`, neither of which is in the repository, and writes to `reports/R/<timestamp>/`:

```
Rscript src/R/mixedModel_N48.R                 # lme4 / lmerTest
Rscript src/R/bayesMixedModel_N48.R            # brms; default the 4 templated shapes, or name shapes
Rscript src/R/varianceSupplementTable_N48.R <lmerRunDir> <shape>=<bayesRunDir> ...
Rscript src/R/regAncova_N48.R                  # registered repeated-measures ANCOVA (mixed-model form)
Rscript src/R/mediation_N48.R                  # registered mediation CATI -> beta -> jerk (lavaan)
Rscript src/R/powerCalcN48.R                   # N=48 a-priori power calculation and pilot ICC planning N
```

Tests: `runtests('tests')`. Run them with warnings enabled, because some tests check for warnings. The R cross-validation tests are skipped if `Rscript` is not found.

## Data

The participant data are not in this repository. They will be released separately with a DOI, subject to the participants' consent terms. The link will be added here.

## Citation and licence

See `CITATION.cff`. The code is released under the MIT licence (`LICENSE`).
