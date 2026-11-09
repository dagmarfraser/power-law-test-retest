function out = reportRetestInterval_2026(options)
% reportRetestInterval_2026 - Visit 1 to Visit 2 interval, and whether between-visit ICC depends on it
%
% The protocol asked for visits about a week apart; the real gaps run from 6 to 43 days.
% This reports the interval (first session of Visit 1 to first session of Visit 2) per
% participant, then per shape:
%   - ICC(A,1) on visit means for everyone, and excluding gaps > each threshold
%   - Spearman correlation of the gap with |V2 - V1| and with V2 - V1
% Sensitivity analysis (post hoc, footnote level), not pre-registered.
% Writes data/processed/retestInterval_N<n>_<ts>.csv and retestInterval_participants_N<n>_<ts>.csv.
%
% USAGE: out = reportRetestInterval_2026();                      % newest trial-level file
%        out = reportRetestInterval_2026('thresholdsDays', [14 28]);
%
% d.s.fraser@bham.ac.uk

arguments
    options.trialFile string = ""
    options.param (1,1) string = "Beta_SG6_IRLS"
    options.thresholdsDays (1,:) double = [14 28]
end
proc = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'data', 'processed');
if options.trialFile == ""
    d = dir(fullfile(proc, 'trial_level_results_2*.csv')); [~, i] = max([d.datenum]);
    options.trialFile = string(fullfile(proc, d(i).name));
end
T = readtable(options.trialFile, 'VariableNamingRule', 'preserve');
if ~isdatetime(T.SessionDatetime)
    T.SessionDatetime = datetime(string(T.SessionDatetime), 'InputFormat', 'dd-MMM-yyyy HH:mm:ss', 'Locale', 'en_US');
end
assert(~any(isnat(T.SessionDatetime)), 'retestInterval:dates', 'Unparsed SessionDatetime values.');

%% Interval per participant
[ids, X, sT] = buildVisitMatrices_2026(T, char(options.param));
gap = nan(numel(ids), 1);
for p = 1:numel(ids)
    t = T.SessionDatetime(T.ParticipantID == ids(p) & T.Visit == 1); u = T.SessionDatetime(T.ParticipantID == ids(p) & T.Visit == 2);
    gap(p) = days(min(u) - min(t));
end
assert(all(gap > 0), 'retestInterval:order', 'Visit 2 does not follow Visit 1 for IDs %s.', mat2str(ids(gap <= 0)'));
P = table(ids, round(gap, 2), 'VariableNames', {'ParticipantID', 'Interval_days'});

%% Per shape: ICC with and without long gaps, and gap vs change
names = ["phi=0.4", "phi=0.8", "Ellipse", "Square", "Cursive"];
rows = {};
for s = 1:numel(sT)
    x = X{s}; dlt = x(:, 2) - x(:, 1);
    [rA, pA] = corr(gap, abs(dlt), 'Type', 'Spearman'); [rS, pS] = corr(gap, dlt, 'Type', 'Spearman');
    for th = [Inf options.thresholdsDays]
        k = gap <= th; r = computeICC(x(k, :), 'absolute');
        rows{end+1} = table(sT(s), names(sT(s)), th, sum(k), r.icc, r.lb, r.ub, rA, pA, rS, pS, ...
            'VariableNames', {'ShapeType', 'ShapeName', 'MaxInterval_days', 'N', 'ICC_A1', 'LB', 'UB', ...
            'Spearman_gap_absChange', 'p_absChange', 'Spearman_gap_change', 'p_change'}); %#ok<AGROW>
    end
end
R = vertcat(rows{:});

%% Save and print
ts = datestr(now, 'yyyymmdd_HHMMSS'); n = numel(ids);
f1 = fullfile(proc, sprintf('retestInterval_N%d_%s.csv', n, ts)); f2 = fullfile(proc, sprintf('retestInterval_participants_N%d_%s.csv', n, ts));
writeTableVerified(R, f1); writeTableVerified(P, f2);
fprintf('Retest interval (%s, N=%d): median %.1f days, IQR %.1f-%.1f, range %.1f-%.1f; >14 d: %d; >28 d: %d (IDs %s)\n', ...
    options.param, n, median(gap), prctile(gap, 25), prctile(gap, 75), min(gap), max(gap), sum(gap > 14), sum(gap > 28), mat2str(ids(gap > 28)'));
disp(R);
fprintf('Saved: %s\nSaved: %s\n', f1, f2);
out = struct('table', R, 'participants', P, 'files', {{f1, f2}});
end
