function tests = test_compareCohortsN45N48_2026
% TEST_COMPARECOHORTSN45N48_2026 - Exercise the N=48 comparison on SYNTHETIC replacements
%
% Built before the real replacement data existed. Takes the real frozen baseline, relabels three of its
% participants as 401-403 (with 5% multiplicative noise on Beta_SG6_IRLS) and checks the comparison runs,
% reproduces the frozen baseline, enumerates the exact reference sets, and fails loudly on bad input.
% Needs baseline_N45/ only; writes to a temp folder; R not needed (runZou=false).
% Run:  runtests('test_compareCohortsN45N48_2026')

tests = functiontests(localfunctions);
end

function setupOnce(tc)
here = fileparts(mfilename('fullpath')); root = fileparts(here);
addpath(fullfile(root, 'src', 'functions'));
d = dir(fullfile(root, 'data', 'processed', 'baseline_N45', 'trial_level_results_2*.csv'));
assert(numel(d) == 1, 'Expected one frozen baseline trial-level csv.');
tc.TestData.baseFile = fullfile(d.folder, d.name);
tc.TestData.B = readtable(tc.TestData.baseFile, 'VariableNamingRule', 'preserve');
tc.TestData.ids = unique(tc.TestData.B.ParticipantID);
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp);
end

function teardownOnce(tc)
rmdir(tc.TestData.tmp, 's');
end

function testRunsAndReproducesBaseline(tc)
f = makeRun(tc, tc.TestData.ids(1:3), [401 402 403], 'run3.csv');
n45 = numel(tc.TestData.ids);
out = compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp);
verifyEqual(tc, out.main.nOriginal(1), n45);
verifyEqual(tc, out.main.nAll(1), n45 + 3);
verifyLessThan(tc, max(out.main.DriftVsFrozen), 1e-9);           % originals reproduce the frozen baseline
verifyLessThan(tc, max(out.main.FrozenICCdiff), 1e-3);
verifyEqual(tc, out.newIDs(:)', [401 402 403]);
verifyTrue(tc, all(out.tests.P_exact > 0 & out.tests.P_exact <= 1));
verifyTrue(tc, all(out.tests.P_Holm >= out.tests.P_exact));
verifyTrue(tc, all(out.main.RefP > 0 & out.main.RefP <= 1));
verifyTrue(tc, all(out.main.RefLo < out.main.RefHi));
verifyEqual(tc, height(out.newP), 3 * 5);
verifyTrue(tc, all(cellfun(@isfile, out.files)));
verifyTrue(tc, all(startsWith(out.main.ZouStatus, "SKIPPED")));  % disclosed, not faked
verifyTrue(tc, all(isnan(out.main.ZouN_all)));
end

function testExactReferenceSize(tc)
% One replacement: the reference distribution has exactly n45 members, so RefP is a multiple of 1/n45
f = makeRun(tc, tc.TestData.ids(5), 450, 'run1.csv');
n45 = numel(tc.TestData.ids);
out = compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp);
verifyEqual(tc, out.main.nAll(1), n45 + 1);
verifyLessThan(tc, max(abs(out.main.RefP * n45 - round(out.main.RefP * n45))), 1e-9);
end

function testErrorsWithoutNewParticipants(tc)
f = fullfile(tc.TestData.tmp, 'copyOfBaseline.csv'); copyfile(tc.TestData.baseFile, f);
verifyError(tc, @() compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp), 'compareCohorts:noNewParticipants');
verifyError(tc, @() compareCohortsN45N48_2026('trialFile', tc.TestData.baseFile, 'runZou', false, 'outDir', tc.TestData.tmp), 'compareCohorts:noNewRun');
end

function testErrorsOnUnexpectedIDAndTooMany(tc)
f = makeRun(tc, tc.TestData.ids(1), 999, 'badID.csv');
verifyError(tc, @() compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp), 'compareCohorts:unexpectedID');
f = makeRun(tc, tc.TestData.ids(1:4), 401:404, 'four.csv');
verifyError(tc, @() compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp), 'compareCohorts:tooManyNew');
end

function testErrorsWhenBaselineParticipantLost(tc)
f = makeRun(tc, tc.TestData.ids(1:3), [401 402 403], 'lost.csv', tc.TestData.ids(7));
verifyError(tc, @() compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp), 'compareCohorts:lostBaseline');
end

function testWarnsOnDriftAndStrictErrors(tc)
f = makeRun(tc, tc.TestData.ids(1:3), [401 402 403], 'drift.csv', [], tc.TestData.ids(9));
verifyWarning(tc, @() compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp), 'compareCohorts:driftFromBaseline');
verifyError(tc, @() compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'strictDrift', true, 'outDir', tc.TestData.tmp), 'compareCohorts:driftFromBaseline');
end

function testComputeTOSTMatchesTtest(tc)
% Paired: 90% CI must equal ttest's; decision must match; Welch version vs ttest2 unequal variances
rng(3); d = 0.01 + 0.04 * randn(45, 1);
r = computeTOST(d, 0.03);
[~, ~, ci] = ttest(d, 0, 'Alpha', 0.10);
verifyEqual(tc, [r.lo90 r.hi90], ci', 'AbsTol', 1e-12);
verifyEqual(tc, r.equivalent, ci(1) > -0.03 && ci(2) < 0.03);
x = 0.02 + 0.08 * randn(3, 1); y = 0.05 * randn(45, 1);
rw = computeTOST(x, 0.03, 'ref', y);
[~, ~, ciw] = ttest2(x, y, 'Alpha', 0.10, 'Vartype', 'unequal');
verifyEqual(tc, [rw.lo90 rw.hi90], ciw', 'AbsTol', 1e-10);
r1 = computeTOST(1, 0.03, 'ref', y);                       % one observation: NaN with a note, never a guess
verifyTrue(tc, isnan(r1.est) && ~r1.equivalent && strlength(r1.note) > 0);
verifyError(tc, @() computeTOST([0.1; NaN], 0.03), 'computeTOST:nan');
end

function testTostTableInComparison(tc)
f = makeRun(tc, tc.TestData.ids(1:3), [401 402 403], 'tost.csv');
out = compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp);
verifyEqual(tc, height(out.tost), 15);                       % 5 shapes x 3 contrasts
verifyEqual(tc, numel(out.files), 6);
sh = out.tost(out.tost.Contrast == "Shift_original", :);
verifyTrue(tc, all(sh.Equivalent));                          % frozen 45 are equivalent at +/-0.03 (checked 2026-11-01)
welch = out.tost(out.tost.Contrast == "MeanBeta_replacement_minus_original", :);
verifyTrue(tc, ~any(welch.Equivalent));                      % 3 vs 45 cannot show equivalence at +/-0.03
end

function testCorridorRuns(tc)
out = plotCorridorOfStability_2026('trialFile', tc.TestData.baseFile, 'nBoot', 60, 'outDir', tc.TestData.tmp);
verifyTrue(tc, isfile(out.pngFile));
verifyEqual(tc, height(out.stability), 10);                  % 5 shapes x 2 widths
verifyTrue(tc, all(out.stability.nStable95 >= 10 & out.stability.nStable95 <= out.stability.N));
last = out.summary(out.summary.n == max(out.summary.n), :);
verifyEqual(tc, last.Median, last.ICC_final, 'AbsTol', 1e-12);   % every ordering ends at the final value
delete(out.pngFile);
end

function testLeaveOutFlagsAndSuspect(tc)
% Ordinary replacements: Flag columns exist, every flag valid, ranges ordered, no SUSPECT in the mean-beta shift
f = makeRun(tc, tc.TestData.ids(1:3), [401 402 403], 'flags.csv');
out = compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp);
for nm = ["ICC", "LB", "MeanBeta", "Shift"]
    verifyTrue(tc, all(ismember(out.main.(char("Flag_" + nm)), ["ok", "outside95", "SUSPECT"])));
    verifyTrue(tc, all(out.main.(char("Min_" + nm)) <= out.main.(char("Lo95_" + nm))));
    verifyTrue(tc, all(out.main.(char("Hi95_" + nm)) <= out.main.(char("Max_" + nm))));
end
% Replacements scaled x2: mean beta must be flagged SUSPECT and the warning raised
f = makeRun(tc, tc.TestData.ids(1:3), [401 402 403], 'scaled.csv', [], [], 2);
verifyWarning(tc, @() compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp), 'compareCohorts:outsideLeaveOut');
out = compareCohortsN45N48_2026('trialFile', f, 'runZou', false, 'outDir', tc.TestData.tmp);
verifyTrue(tc, any(out.main.Flag_MeanBeta == "SUSPECT"));
end

function f = makeRun(tc, srcIDs, newIDs, name, dropID, driftID, scale)
% Baseline rows + relabelled noisy copies of srcIDs as newIDs; optionally drop one original, perturb one, or scale the copies
if nargin < 5, dropID = []; end
if nargin < 6, driftID = []; end
if nargin < 7, scale = 1; end
rng(7); B = tc.TestData.B; T = B;
for i = 1:numel(srcIDs)
    R = B(B.ParticipantID == srcIDs(i), :); R.ParticipantID(:) = newIDs(i);
    R.Beta_SG6_IRLS = scale * R.Beta_SG6_IRLS .* (1 + 0.05 * randn(height(R), 1));
    T = [T; R]; %#ok<AGROW>
end
if ~isempty(dropID), T = T(T.ParticipantID ~= dropID, :); end
if ~isempty(driftID), m = T.ParticipantID == driftID; T.Beta_SG6_IRLS(m) = T.Beta_SG6_IRLS(m) * 1.1; end
f = fullfile(tc.TestData.tmp, name); writetable(T, f);
fid = fopen(f, 'r'); hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(T.Properties.VariableNames, ',')), 'Test CSV has a bad header (join.m shadowing?)');
end
