function out = reportTouchTypeFix_2026(options)
% reportTouchTypeFix_2026 - Tables for the finger/palm (touch_type ~= 2) fix
%
% Reads the newest data/processed/touchTypeFilterEffect_*.mat (from
% diagnoseTouchTypeFilter_2026) and writes, next to it:
%   touchTypeFix_trialSummary_<ts>.csv  per-shape effect on each parameter in the contaminated trials
%   touchTypeFix_ICC_<ts>.csv           between-visit ICC(A,1) before/after (compareICCTouchFix_2026)
% and prints both. Interim check only: the definitive ICCs come from the
% full runN48_2026 re-run with pencilSamplesOnly in place.
%
% USAGE: out = reportTouchTypeFix_2026();
%        out = reportTouchTypeFix_2026('effectFile', ..., 'trialFile', ...);
%
% d.s.fraser@bham.ac.uk

arguments
    options.effectFile string = ""
    options.trialFile string = ""
end

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
proc = fullfile(root, 'data', 'processed');
eff = newest(options.effectFile, proc, 'touchTypeFilterEffect_*.mat');
trl = newest(options.trialFile, proc, 'trial_level_results_2*.csv');
fprintf('Effect file: %s\nTrial file:  %s\n', eff, trl);

S = load(eff);
D = S.D;
fprintf('Clean trials: %d (Pencil index steps > 1: %d). Contaminated trials: %d\n', ...
    S.nClean, S.nCleanGap, height(D));

shapes = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
params = regexprep(D.Properties.VariableNames(endsWith(D.Properties.VariableNames, '_new')), '_new$', '');

%% Per-shape effect in the contaminated trials
rows = {};
for s = 1:5
    k = D.ShapeType == s;
    for p = params
        o = D.([p{1} '_old'])(k); n = D.([p{1} '_new'])(k);
        if startsWith(p{1}, {'Beta', 'FitCorr', 'NumStrokes'})   % report differences
            d = n - o;
            rows{end+1} = table(string(shapes{s}), string(p{1}), sum(k), "difference", ...
                median(abs(d), 'omitnan'), prctile(abs(d), 95), max(abs(d)), sum(abs(d) > 0.01), ...
                sum(isnan(n) ~= isnan(o)), 'VariableNames', ...
                {'Shape', 'Param', 'nTrials', 'Measure', 'Median', 'P95', 'Extreme', 'nOver', 'nNaNChange'}); %#ok<AGROW>
        else                                                     % report new/old ratios
            r = n ./ o;
            rows{end+1} = table(string(shapes{s}), string(p{1}), sum(k), "ratio new/old", ...
                median(r, 'omitnan'), prctile(r, 5), min(r), sum(r < 0.9), ...
                sum(isnan(n) ~= isnan(o)), 'VariableNames', ...
                {'Shape', 'Param', 'nTrials', 'Measure', 'Median', 'P95', 'Extreme', 'nOver', 'nNaNChange'}); %#ok<AGROW>
        end
    end
end
out.trialSummary = vertcat(rows{:});
% Column meanings differ by Measure: difference -> P95 = 95th pct |d|, Extreme = max |d|, nOver = |d| > 0.01;
% ratio -> P95 = 5th pct of ratio, Extreme = min ratio, nOver = ratio < 0.9.
out.trialSummary.Properties.VariableDescriptions = {'', '', '', '', ...
    'median |d| or median ratio', '95th pct |d| or 5th pct ratio', 'max |d| or min ratio', ...
    '#|d|>0.01 or #ratio<0.9', '#trials whose NaN status changed'};

%% ICC before/after
out.icc = compareICCTouchFix_2026(eff, trl);

ts = datestr(now, 'yyyymmdd_HHMMSS');
f1 = fullfile(proc, ['touchTypeFix_trialSummary_' ts '.csv']);
f2 = fullfile(proc, ['touchTypeFix_ICC_' ts '.csv']);
writetable(out.trialSummary, f1);
writetable(out.icc, f2);
fprintf('Saved: %s\nSaved: %s\n', f1, f2);
disp(out.trialSummary); disp(out.icc);
end

function f = newest(explicit, folder, pattern)
if explicit ~= "", f = explicit; return; end
d = dir(fullfile(folder, pattern));
assert(~isempty(d), 'reportTouchTypeFix:notFound', 'No %s in %s', pattern, folder);
[~, i] = max([d.datenum]);
f = fullfile(folder, d(i).name);
end
