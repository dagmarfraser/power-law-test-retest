function tests = test_computeCCC_matchesICC
% TEST_COMPUTECCC_MATCHESICC - Lin's CCC and ICC(A,1) are the same statistic
%
% For k=2, ICC(A,1) = CCC / (1 - (1-CCC)/n) exactly. These tests pin that
% identity down on random data, on the real 2026 shapes, and at the edges,
% so that if either computeCCC or computeICC is ever changed the tie
% between them breaks loudly rather than quietly.
%
% Pure MATLAB, no R needed. Run:  runtests('test_computeCCC_matchesICC')

tests = functiontests(localfunctions);
end


function setupOnce(testCase)
here = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(here), 'src', 'functions'));
testCase.TestData.tol = 1e-10;
end


function testIdentityOnRandomData(testCase)
% The identity must hold for arbitrary paired data, not just well-behaved
% data: correlated, uncorrelated, shifted, rescaled.
rng(42);
for trial = 1:200
    n = randi([3, 80]);
    shift = randn * 2;
    scale = 0.5 + rand * 2;
    x = randn(n, 1) * scale;
    y = x * (0.3 + rand) + randn(n, 1) * (0.1 + rand) + shift;

    c = computeCCC([x y]);
    i = computeICC([x y], 'absolute');

    predicted = c.ccc / (1 - (1 - c.ccc) / n);
    verifyEqual(testCase, predicted, i.icc, 'AbsTol', testCase.TestData.tol, ...
        sprintf('Identity failed on random trial %d (n=%d)', trial, n));
end
end


function testInverseIdentity(testCase)
% The map inverts: CCC = (n-1)*ICC / (n - ICC).
rng(7);
for trial = 1:100
    n = randi([3, 60]);
    x = randn(n, 1);
    y = x * 0.8 + randn(n, 1) * 0.4 + 0.2;

    c = computeCCC([x y]);
    i = computeICC([x y], 'absolute');

    predicted = (n - 1) * i.icc / (n - i.icc);
    verifyEqual(testCase, predicted, c.ccc, 'AbsTol', testCase.TestData.tol);
end
end


function testCCCNotExceedingICCWhenPositive(testCase)
% CCC <= ICC(A,1), but ONLY for CCC >= 0.
%
% The transform ICC = CCC/(1-(1-CCC)/n) divides by a quantity < 1, so it
% inflates magnitude. For positive coefficients that means ICC > CCC; for
% NEGATIVE coefficients it means ICC is more negative, i.e. CCC > ICC. An
% earlier version of this test asserted CCC <= ICC unconditionally and
% failed on ~20 random cases with negative agreement. The ordering flips at
% zero; that is a property of the map, not a bug.
rng(11);
nPos = 0; nNeg = 0;
for trial = 1:200
    n = randi([3, 50]);
    x = randn(n, 1);
    y = x * (rand * 2 - 0.5) + randn(n, 1) * rand;
    c = computeCCC([x y]);
    i = computeICC([x y], 'absolute');
    if isnan(c.ccc), continue; end
    if c.ccc >= 0
        nPos = nPos + 1;
        verifyLessThanOrEqual(testCase, c.ccc, i.icc + 1e-12, ...
            'CCC should not exceed ICC(A,1) when CCC >= 0');
    else
        nNeg = nNeg + 1;
        verifyGreaterThanOrEqual(testCase, c.ccc, i.icc - 1e-12, ...
            'CCC should not be below ICC(A,1) when CCC < 0 (ordering flips)');
    end
end
verifyGreaterThan(testCase, nPos, 0, 'expected some positive-CCC cases');
verifyGreaterThan(testCase, nNeg, 0, 'expected some negative-CCC cases');
end


function testExactGapFormula(testCase)
% The gap has a closed form: ICC - CCC = CCC*(1-CCC)/(n-1+CCC).
% Note the denominator is n-1+CCC, not n. Pinning the exact form rather
% than the CCC*(1-CCC)/n approximation that a first draft of computeCCC's
% header used, which understated the gap and made 0.25/n look like a valid
% bound when it is not.
rng(3);
for trial = 1:300
    n = randi([4, 90]);
    x = randn(n, 1);
    y = x * (rand*2 - 0.5) + randn(n, 1) * (rand + 0.05) + randn * 0.5;
    c = computeCCC([x y]);
    i = computeICC([x y], 'absolute');
    if isnan(c.ccc), continue; end
    predicted = c.ccc * (1 - c.ccc) / (n - 1 + c.ccc);
    verifyEqual(testCase, i.icc - c.ccc, predicted, 'AbsTol', 1e-12, ...
        sprintf('Exact gap formula failed at n=%d', n));
end
end


function testGapBoundedByQuarterOverNMinus1(testCase)
% Gap <= 0.25/(n-1) for CCC in [0,1], since CCC*(1-CCC) <= 0.25 and
% n-1+CCC >= n-1. This bound is what justifies the docs' claim that CCC and
% ICC cannot disagree enough to move a Koo & Li classification unless the
% estimate sits within ~0.008 (at n=31) of a band edge.
rng(13);
for trial = 1:300
    n = randi([10, 80]);
    x = randn(n, 1);
    y = x * (rand * 1.5) + randn(n, 1) * (rand + 0.05);
    c = computeCCC([x y]);
    i = computeICC([x y], 'absolute');
    if isnan(c.ccc) || c.ccc < 0
        continue;   % bound is derived for CCC in [0,1]
    end
    verifyLessThanOrEqual(testCase, i.icc - c.ccc, 0.25/(n-1) + 1e-12, ...
        sprintf('Gap exceeded 0.25/(n-1) at n=%d', n));
end
end


function testGapAtStudyN(testCase)
% Concrete: at the confirmatory N=31 the worst-case gap is ~0.0082, and the
% loose bound 0.25/(n-1) is 0.0083. Guards the specific numbers quoted in
% computeCCC's header and docs/AnalysisPipeline.md.
n = 31;
c = linspace(0, 1, 200001);
trueMax = max(c .* (1 - c) ./ (n - 1 + c));
verifyEqual(testCase, trueMax, 0.0082, 'AbsTol', 5e-5);
verifyLessThanOrEqual(testCase, trueMax, 0.25/(n-1));
end


function testMonotoneCIMapping(testCase)
% The CI bounds must stay ordered and must bracket the point estimate,
% including when the lower bound is negative (as it is for Cursive).
rng(17);
for trial = 1:100
    n = randi([5, 60]);
    x = randn(n, 1);
    y = randn(n, 1) * 0.9 + x * (rand - 0.2);
    c = computeCCC([x y]);
    if isnan(c.ccc), continue; end
    verifyLessThanOrEqual(testCase, c.lb, c.ccc + 1e-9);
    verifyLessThanOrEqual(testCase, c.ccc, c.ub + 1e-9);
end
end


function testRejectsNonPairedInput(testCase)
% k>2 must error, not silently collapse to something CCC-shaped.
verifyError(testCase, @() computeCCC(randn(20, 3)), 'computeCCC:notPaired');
verifyError(testCase, @() computeCCC(randn(20, 1)), 'computeCCC:notPaired');
end


function testPerfectAgreement(testCase)
% Identical columns: CCC = 1 exactly.
x = randn(25, 1);
c = computeCCC([x x]);
verifyEqual(testCase, c.ccc, 1, 'AbsTol', 1e-12);
end


function testMeanShiftPenalised(testCase)
% CCC must penalise a pure location shift (that is the whole point of
% absolute agreement): perfectly correlated but offset data scores < 1,
% whereas ICC(3,1) consistency ignores the shift and stays at 1.
x = randn(30, 1);
y = x + 1.5;
c = computeCCC([x y]);
iCons = computeICC([x y], 'consistency');
verifyLessThan(testCase, c.ccc, 0.95);
verifyEqual(testCase, iCons.icc, 1, 'AbsTol', 1e-9);
end
