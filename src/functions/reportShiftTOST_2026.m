function out = reportShiftTOST_2026(options)
% reportShiftTOST_2026 - Equivalence (TOST) of the within-person V2 minus V1 mean shift, per shape
%
% Tests whether the mean day-to-day shift in beta is equivalent to zero within +/-margin
% (default 0.03 beta units, the same absolute value for every shape; fixed 2026-11-01 by Dagmar,
% consistent with the +/-0.03 used in the companion preprint). Visit means, paired differences.
% This is an equivalence test on the GROUP mean shift; it says nothing about individual changes
% (see reportStability_2026: MDC95 and limits of agreement). Not pre-registered; sensitivity analysis.
%
% INPUTS (name-value): trialFile (default newest data/processed/trial_level_results_2*.csv),
%   param ("Beta_SG6_IRLS"), margin (0.03), outDir (data/processed)
% OUTPUT  out.table, out.file. Writes tostShift_N<n>_<timestamp>.csv (header verified).
% FAILS LOUDLY if no trial file, a participant x visit x shape cell is missing, or visits are not 2.

arguments
    options.trialFile string = ""
    options.param (1,1) string = "Beta_SG6_IRLS"
    options.margin (1,1) double {mustBePositive} = 0.03
    options.outDir string = ""
end
rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
procDir = fullfile(rootDir, 'data', 'processed');
if options.outDir == "", options.outDir = procDir; end
if options.trialFile == ""
    d = dir(fullfile(procDir, 'trial_level_results_2*.csv'));
    assert(~isempty(d), 'reportShiftTOST:noFile', 'No trial_level_results_2*.csv in %s', procDir);
    [~, k] = max([d.datenum]); trialFile = fullfile(d(k).folder, d(k).name);
else
    trialFile = char(options.trialFile); assert(isfile(trialFile), 'reportShiftTOST:noFile', 'File not found: %s', trialFile);
end
T = readtable(trialFile, 'VariableNamingRule', 'preserve');
[ids, X, sT] = buildVisitMatrices_2026(T, char(options.param));
assert(size(X{1}, 2) == 2, 'reportShiftTOST:needTwoVisits', 'Expected 2 visits, got %d.', size(X{1}, 2));
shapeNames = ["phi=0.4", "phi=0.8", "Ellipse", "Square", "Cursive"];
n = numel(ids); rows = cell(numel(sT), 1);
for s = 1:numel(sT)
    x = X{s}; dlt = x(:, 2) - x(:, 1); r = computeTOST(dlt, options.margin);
    tc = tinv(0.975, n - 1);
    rows{s} = {sT(s), shapeNames(sT(s)), n, mean(x(:)), r.est, r.est - tc * r.se, r.est + tc * r.se, r.lo90, r.hi90, ...
        options.margin, 100 * options.margin / mean(x(:)), r.p, r.equivalent};
end
tbl = cell2table(vertcat(rows{:}), 'VariableNames', {'ShapeType', 'ShapeName', 'n', 'MeanBeta', 'Shift', 'CI95_Lo', 'CI95_Hi', ...
    'CI90_Lo', 'CI90_Hi', 'Margin', 'MarginPctOfMeanBeta', 'P_TOST', 'Equivalent'});
fprintf('TOST of V2-V1 mean shift, %s, n=%d, margin +/-%g (equivalent if the 90%% CI lies inside the margin)\n', options.param, n, options.margin);
disp(tbl(:, {'ShapeName', 'Shift', 'CI90_Lo', 'CI90_Hi', 'MarginPctOfMeanBeta', 'P_TOST', 'Equivalent'}));
if ~exist(options.outDir, 'dir'), mkdir(options.outDir); end
file = fullfile(options.outDir, sprintf('tostShift_N%d_%s.csv', n, char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))));
writetable(tbl, file);
fid = fopen(file, 'r'); assert(fid > 0, 'reportShiftTOST:writeFail', 'Cannot reopen %s', file);
hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(tbl.Properties.VariableNames, ',')), 'reportShiftTOST:badHeader', 'Bad header in %s', file);
fprintf('Wrote %s\n', file);
out = struct('table', tbl, 'file', file, 'trialFile', trialFile);
end
