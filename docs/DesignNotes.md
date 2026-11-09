# Design Notes: k=2 vs k=3 Visits for the Confirmatory Study

> **Outcome:** the study ran with k=2 visits (3 sessions each). This note is kept as the design analysis behind that choice and as planning material for a future k=3 study.

Carried forward from the analysis_2025 pilot (N=61). This was a real
design-analysis exercise run against the pilot's observed ICC(A,1) values,
between- and within-person SDs, using `computeICCA1_projected` to simulate
projected CI lower bounds under different (N, k) combinations, holding the
pilot's true variance structure fixed and varying only N and k.

## The question

Given the pilot's k=2 (two visits) design leaves phi=0.8 and Ellipse with
wide CI lower bounds despite strong point estimates (a known consequence of
MSC having only 1 degree of freedom at k=2), is it better to recruit more
participants at k=2, or add a third visit?

## The mechanism

Two independent effects favour k=3:

1. **MSC degrees of freedom double from 1 to 2.** This is the dominant
   effect for ICC(A,1) specifically, because the Satterthwaite
   approximation used to build the CI is most imprecise exactly when
   df=1. Doubling df from 1 to 2 is a disproportionately large gain in
   precision compared with, say, doubling df from 10 to 20.
2. **F-distribution denominator df doubles from (n-1) to 2(n-1)**,
   tightening the critical values used to construct the CI bound.

## The crossover: k=3 at N=80 vs k=2 at N=120

| Shape   | k=2, N=120 LB | k=3, N=80 LB |
|---------|---------------|--------------|
| phi=0.4 | 0.777*        | 0.770*       |
| phi=0.8 | 0.764*        | 0.756*       |
| Ellipse | 0.741         | 0.731        |
| Square  | 0.584         | 0.582        |
| Cursive | 0.603         | 0.607        |

(* = lower bound >= 0.75, Koo & Li 2016 "good" confirmed)

**k=3 at N=80 is essentially equivalent to k=2 at N=120** for the three
confirmatory shapes (phi=0.4, phi=0.8, Ellipse). Recruiting 40 additional
participants is substantially harder than adding one visit to 80,
particularly given this is a neurodivergent-recruitment pool.

At the pilot's own N=61, adding a third visit shifts the CI lower bound by
roughly +0.10 to +0.17 across the curvilinear shapes, versus needing to
scale all the way to N=150 under k=2 to gain a comparable +0.27 on
phi=0.4's lower bound alone.

## What neither design fixes

Square and Cursive do not reach LB >= 0.75 at any realistic N under either
design, because the ICC point estimates themselves sit too close to 0.75.
This is an effect-size problem, not a CI-width problem. Even at k=3 and
N=150, Cursive only just touches LB=0.750; Square does not clear 0.75 at
any N tested. **Report these two descriptively regardless of design.**

## The cost of k=3

Participant burden increases by 50% (three visits instead of two, each
with three sessions), and dropout between Visit 2 and Visit 3 becomes a
real risk on top of the existing Visit 1 -> Visit 2 dropout. Expect to
need to recruit roughly N=95 to retain N=80 with three visits.

The counterargument: a third visit also gives a genuine learning-curve
characterisation (Visit 1 vs 2 vs 3, not just "did a shift occur") which
has independent scientific value for the stable-trait/biomarker question,
beyond just tightening the CI.

## Recommendation carried into Analysis_2026

If participant retention is manageable, **k=3 at N=80 is the preferable
design** over k=2 at any feasible N: it definitively resolves phi=0.4 and
phi=0.8 by the Koo & Li CI-lower-bound criterion, where k=2 at N=80 alone
leaves phi=0.8 at LB=0.648 (still "moderate to excellent", not "good").

**This is a recommendation to revisit against the actual incoming MSc
cohort size and recruitment constraints, not a fixed decision** — update
this file once the real N and visit structure for Analysis_2026 is known.

## Verified confirmatory N (Zou 2012, k=2 baseline, from pilot)

| Shape   | N required |
|---------|-----------|
| phi=0.4 | 34        |
| phi=0.8 | 41        |
| Ellipse | 65        |
| Square  | pending   |
| Cursive | intractable at feasible N |

These are the Zou (2012) precision-framework values (`ICC.Sample.Size::calculateIccSampleSize`,
`tails=1`), cross-checked against the Walter (1998) hypothesis-testing
framework which gives smaller N throughout (see analysis_2025's two
power-analysis scripts for both).
