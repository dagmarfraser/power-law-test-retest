function out = leaveKOutReference_2026(options)
% leaveKOutReference_2026 - Exact delete-k jackknife of the test-retest results
%
% Holds out EVERY combination of k participants (default k=3: nchoosek(n,3) = 14,190
% for n=45) and records, per shape, how far the remaining participants' results move
% from the full-sample values: ICC(A,1) and its CI lower bound, mean beta, and the
% V2 minus V1 mean shift. Visit means, confirmatory parameter by default.
%
% Purpose: how much do these numbers fluctuate when 3 people are added or removed, so the
% change seen when the replacements arrive can be judged against it (see
% docs/SensitivityPlan_N48.md). Delete-d jackknife: Shao & Wu (1989); exact enumeration
% means no Monte Carlo error. Descriptive, not a test.
%
% INPUTS (name-value)
%   k          participants held out (default 3)
%   param      outcome column (default "Beta_SG6_IRLS")
%   trialFile  trial-level csv (default: the frozen baseline_N45 file)
%   outDir     where to write the summary csv (default data/processed)
%
% Change = remaining minus full. Sign: positive dICC means the ICC rises when those k leave.
% OUTPUT  out.summary (one row per shape), out.dist (raw changes per shape), out.file
% FAILS LOUDLY if the baseline file is not unique, a participant x visit x shape cell is missing,
% or there are not exactly two visits.

arguments
    options.k (1,1) double {mustBeInteger, mustBePositive} = 3
    options.param (1,1) string = "Beta_SG6_IRLS"
    options.trialFile string = ""
    options.outDir string = ""
end
rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
procDir = fullfile(rootDir, 'data', 'processed');
if options.outDir == "", options.outDir = procDir; end
if options.trialFile == ""
    d = dir(fullfile(procDir, 'baseline_N45', 'trial_level_results_2*.csv'));
    assert(isscalar(d), 'leaveKOut:baseline', 'Expected exactly one frozen baseline trial-level csv, found %d.', numel(d));
    trialFile = fullfile(d.folder, d.name);
else
    trialFile = char(options.trialFile);
    assert(isfile(trialFile), 'leaveKOut:noFile', 'File not found: %s', trialFile);
end
T = readtable(trialFile, 'VariableNamingRule', 'preserve');
[ids, X, sT] = buildVisitMatrices_2026(T, char(options.param));
n = numel(ids); k = options.k;
assert(size(X{1}, 2) == 2, 'leaveKOut:needTwoVisits', 'Expected 2 visits, got %d.', size(X{1}, 2));
assert(k < n - 2, 'leaveKOut:kTooLarge', 'k=%d leaves too few of n=%d participants.', k, n);
C = nchoosek(1:n, k); nC = size(C, 1);
shapeNames = ["phi=0.4", "phi=0.8", "Ellipse", "Square", "Cursive"];
thr = [0.5 0.75 0.9];                                   % Koo & Li (2016) bands, applied to the CI lower bound
statNames = ["dICC", "dLB", "dMeanBeta", "dShift"];

rows = cell(numel(sT), 1); dist = struct();
for s = 1:numel(sT)
    x = X{s}; full = computeICC(x, 'absolute');
    mFull = mean(x(:)); sFull = mean(x(:, 2) - x(:, 1));
    D = zeros(nC, 4); lbR = zeros(nC, 1);
    for r = 1:nC
        keep = true(n, 1); keep(C(r, :)) = false; xr = x(keep, :);
        i = computeICC(xr, 'absolute'); lbR(r) = i.lb;
        D(r, :) = [i.icc - full.icc, i.lb - full.lb, mean(xr(:)) - mFull, mean(xr(:, 2) - xr(:, 1)) - sFull];
    end
    row = {sT(s), shapeNames(sT(s)), n, k, nC, full.icc, full.lb, mFull, sFull};
    for j = 1:4
        q = prctile(D(:, j), [2.5 97.5]);
        row = [row, {std(D(:, j)), q(1), q(2), max(abs(D(:, j)))}]; %#ok<AGROW>
    end
    row = [row, {100 * mean(sum(lbR >= thr, 2) ~= sum(full.lb >= thr)), 100 * mean((lbR >= thr(2)) ~= (full.lb >= thr(2)))}];
    rows{s} = row; dist.(sprintf('shape%d', sT(s))) = array2table(D, 'VariableNames', cellstr(statNames));
end
vn = {'ShapeType', 'ShapeName', 'n', 'k', 'nCombos', 'ICC_full', 'LB_full', 'MeanBeta_full', 'Shift_full'};
for j = 1:4, vn = [vn, strcat(char(statNames(j)), {'_SD', '_Lo95', '_Hi95', '_MaxAbs'})]; end %#ok<AGROW>
vn = [vn, {'PctClassChanged', 'PctLBcrossesP0'}];
S = cell2table(vertcat(rows{:}), 'VariableNames', vn);

fprintf('Hold out %d of %d (all %d combinations), %s, visit means. Change = remaining minus full.\n', k, n, nC, options.param);
disp(S(:, {'ShapeName', 'ICC_full', 'LB_full', 'dICC_SD', 'dICC_Lo95', 'dICC_Hi95', 'dMeanBeta_SD', 'dMeanBeta_Lo95', 'dMeanBeta_Hi95', 'dShift_SD', 'PctClassChanged', 'PctLBcrossesP0'}));
if ~exist(options.outDir, 'dir'), mkdir(options.outDir); end
file = fullfile(options.outDir, sprintf('leaveKOut_N%d_k%d_%s.csv', n, k, char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))));
writetable(S, file);
fid = fopen(file, 'r'); assert(fid > 0, 'leaveKOut:writeFail', 'Cannot reopen %s', file);
hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(S.Properties.VariableNames, ',')), 'leaveKOut:badHeader', 'Bad header in %s', file);
fprintf('Wrote %s\n', file);
out = struct('summary', S, 'dist', dist, 'file', file, 'trialFile', trialFile);
end
