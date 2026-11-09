function out = plotCorridorOfStability_2026(options)
% plotCorridorOfStability_2026 - How stable is the test-retest ICC as participants accumulate?
%
% After Schonbrodt & Perugini (2013, J Res Pers 47:609): draw many random orderings of the participants,
% compute ICC(A,1) on the first n of each ordering for n = nMin..N, and plot the trajectories' median and
% 2.5-97.5% band against n, with a corridor of +/-width around the final (all-N) value. Per shape.
%
% NOTE: random orderings of the SAME sample (no resampling with replacement), so every trajectory ends at the
% final value by construction. Read the spread at n = N-3 as "how far the estimate sits from its final value
% with 3 participants still to come" (this is the delete-3 jackknife band). Descriptive, no inference.
% The corridor widths are conventions, not thresholds; both are reported.
%
% INPUTS (name-value): trialFile (default newest data/processed/trial_level_results_2*.csv), param
%   ("Beta_SG6_IRLS"), nBoot (2000 orderings), nMin (10), width ([0.05 0.10]), markN (default N-3), seed (1),
%   outDir (data/processed; the PNG goes to figures/)
% OUTPUT  out.summary (per shape x n), out.stability (n after which 95% of orderings stay inside each corridor),
%         out.pngFile, out.files. FAILS LOUDLY if the point-estimate ICC disagrees with computeICC.

arguments
    options.trialFile string = ""
    options.param (1,1) string = "Beta_SG6_IRLS"
    options.nBoot (1,1) double {mustBeInteger, mustBePositive} = 2000
    options.nMin (1,1) double {mustBeInteger, mustBePositive} = 10
    options.width (1,2) double {mustBePositive} = [0.05 0.10]
    options.markN double = []
    options.seed (1,1) double = 1
    options.outDir string = ""
end
rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
procDir = fullfile(rootDir, 'data', 'processed'); figDir = fullfile(rootDir, 'figures');
if options.outDir == "", options.outDir = procDir; end
if options.trialFile == ""
    d = dir(fullfile(procDir, 'trial_level_results_2*.csv'));
    assert(~isempty(d), 'corridor:noFile', 'No trial_level_results_2*.csv in %s', procDir);
    [~, k] = max([d.datenum]); trialFile = fullfile(d(k).folder, d(k).name);
else
    trialFile = char(options.trialFile); assert(isfile(trialFile), 'corridor:noFile', 'File not found: %s', trialFile);
end
T = readtable(trialFile, 'VariableNamingRule', 'preserve');
[ids, X, sT] = buildVisitMatrices_2026(T, char(options.param));
N = numel(ids); B = options.nBoot; w = options.width;
markN = options.markN; if isempty(markN), markN = N - 3; end
assert(options.nMin >= 5 && options.nMin < markN && markN < N, 'corridor:range', 'Need 5 <= nMin (%d) < markN (%d) < N (%d).', options.nMin, markN, N);
shapeNames = ["phi=0.4", "phi=0.8", "Ellipse", "Square", "Cursive"];
ns = options.nMin:N; rng(options.seed, 'twister');

sumRows = {}; stabRows = {};
fig = figure('Visible', 'off', 'Position', [100 100 1400 800]); tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact');
for s = 1:numel(sT)
    x = X{s}; final = iccA1(x);
    assert(abs(final - computeICC(x, 'absolute').icc) < 1e-12, 'corridor:iccMismatch', 'iccA1 disagrees with computeICC (shape %d).', sT(s));
    traj = zeros(B, numel(ns));
    for b = 1:B
        p = randperm(N);
        for j = 1:numel(ns), traj(b, j) = iccA1(x(p(1:ns(j)), :)); end
    end
    med = median(traj, 1); lo = prctile(traj, 2.5, 1); hi = prctile(traj, 97.5, 1);
    within = zeros(numel(ns), 2);
    for c = 1:2
        outside = abs(traj - final) > w(c); within(:, c) = 100 * mean(~outside, 1)';
        lastOut = arrayfun(@(b) find(outside(b, :), 1, 'last'), 1:B, 'UniformOutput', false);
        nStab = cellfun(@(k) ternary(isempty(k), options.nMin, ns(k) + 1), lastOut);
        stabRows(end+1, :) = {sT(s), shapeNames(sT(s)), N, final, w(c), prctile(nStab, 95), within(ns == markN, c)}; %#ok<AGROW>
    end
    for j = 1:numel(ns)
        sumRows(end+1, :) = {sT(s), shapeNames(sT(s)), ns(j), final, med(j), lo(j), hi(j), within(j, 1), within(j, 2)}; %#ok<AGROW>
    end
    ax = nexttile(tl); hold(ax, 'on');
    fill(ax, [ns fliplr(ns)], [lo fliplr(hi)], [0.8 0.85 0.95], 'EdgeColor', 'none', 'DisplayName', '2.5-97.5% of orderings');
    plot(ax, ns, med, 'b-', 'LineWidth', 1.5, 'DisplayName', 'median');
    yline(ax, final, 'k-', 'DisplayName', sprintf('final (N=%d)', N));
    yline(ax, final + [-1 1] * w(1), 'k--', 'HandleVisibility', 'off'); yline(ax, final + [-1 1] * w(2), 'k:', 'HandleVisibility', 'off');
    xline(ax, markN, 'r-', 'DisplayName', sprintf('n=%d (N-%d)', markN, N - markN));
    xlabel(ax, 'participants n'); ylabel(ax, 'ICC(A,1)'); box(ax, 'on'); xlim(ax, [ns(1) N]);
    title(ax, sprintf('%s: final %.3f; 95%% inside +/-%g from n=%d', shapeNames(sT(s)), final, w(1), round(stabRows{end-1, 6})));
    if s == 1, legend(ax, 'Location', 'southeast'); end
end
title(tl, sprintf('Corridor of stability, %s ICC(A,1), %d random orderings (dashed +/-%g, dotted +/-%g)', options.param, B, w(1), w(2)), 'Interpreter', 'none');
S = cell2table(sumRows, 'VariableNames', {'ShapeType', 'ShapeName', 'n', 'ICC_final', 'Median', 'Lo95', 'Hi95', 'PctWithinW1', 'PctWithinW2'});
St = cell2table(stabRows, 'VariableNames', {'ShapeType', 'ShapeName', 'N', 'ICC_final', 'Width', 'nStable95', 'PctWithinAtMarkN'});
fprintf('Corridor of stability, N=%d, %d orderings. nStable95 = n after which 95%% of orderings stay inside the corridor; PctWithinAtMarkN at n=%d:\n', N, B, markN);
disp(St);
ts = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
if ~exist(figDir, 'dir'), mkdir(figDir); end
if ~exist(options.outDir, 'dir'), mkdir(options.outDir); end
png = fullfile(figDir, sprintf('corridorOfStability_N%d_%s.png', N, ts)); exportgraphics(fig, png, 'Resolution', 200); close(fig);
files = {fullfile(options.outDir, sprintf('corridorSummary_N%d_%s.csv', N, ts)), fullfile(options.outDir, sprintf('corridorStability_N%d_%s.csv', N, ts))};
writeVerified(S, files{1}); writeVerified(St, files{2});
fprintf('Wrote %s\n       %s\n       %s\n', png, files{1}, files{2});
out = struct('summary', S, 'stability', St, 'pngFile', png, 'files', {files}, 'trialFile', trialFile);
end

function v = iccA1(x)
% ICC(A,1) point estimate (McGraw & Wong), same algebra as computeICC; checked against it per shape above
[n, k] = size(x); gm = mean(x(:)); rm = mean(x, 2); cm = mean(x, 1);
MSR = k * sum((rm - gm).^2) / (n - 1); MSC = n * sum((cm - gm).^2) / (k - 1);
MSE = (sum((x(:) - gm).^2) - (n - 1) * MSR - (k - 1) * MSC) / ((n - 1) * (k - 1));
v = (MSR - MSE) / (MSR + (k - 1) * MSE + (k / n) * (MSC - MSE));
end

function o = ternary(c, a, b)
if c, o = a; else, o = b; end
end

function writeVerified(tbl, path)
writetable(tbl, path);
fid = fopen(path, 'r'); assert(fid > 0, 'corridor:writeFail', 'Cannot reopen %s', path);
hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(tbl.Properties.VariableNames, ',')), 'corridor:badHeader', 'Bad header in %s', path);
end
