function out = diagnoseShapeStability_2026(shapeType, rootDir, param, kMAD)
% diagnoseShapeStability_2026 - Why is one shape's test-retest ICC low?
%
% Built for Cursive (ShapeType 5) but works for any shape. Produces, from the
% saved trial-level and ICC results:
%   1. variance decomposition for every shape (BetweenSD, WithinSD, SEM, SNR)
%   2. within-session trial-to-trial CV of param, PathLength_mm and Duration
%      for every shape (is a person consistent within a sitting?)
%   3. per-participant V2-V1 change in param, PathLength_mm, NumLifts,
%      NumStrokes, Duration for the chosen shape, and the Spearman correlation
%      between |change in param| and |change in each other metric|
%   4. POST HOC DIAGNOSTIC (not a result to report): ICC(A,1) with robust
%      movers removed. A mover is |d| > median(|d|) + kMAD*1.4826*MAD(|d|).
%      The rule is data-driven (no IDs hard-coded) and the flagged IDs are
%      printed so the exclusion is visible.
% n is taken from the data; nothing assumes a participant count.
%
% INPUTS (optional except shapeType)
%   shapeType  1-5 (5 = Cursive)
%   rootDir    Analysis_2026 folder (default: derived from this file)
%   param      outcome column (default 'Beta_SG6_IRLS')
%   kMAD       robust threshold multiplier (default 5)
%
% Writes data/processed/stability_shapeDiagnostic_shape<s>_N<n>_<ts>.csv
% (header verified). FAILS LOUDLY on missing columns/cells, fewer than 5
% participants after removing movers, or an ICC/results run mismatch.

if nargin < 2 || isempty(rootDir), rootDir = fileparts(fileparts(fileparts(mfilename('fullpath')))); end
if nargin < 3 || isempty(param),   param   = 'Beta_SG6_IRLS'; end
if nargin < 4 || isempty(kMAD),    kMAD    = 5; end
procDir = fullfile(rootDir,'data','processed');
tlFile  = latestFile(procDir,'trial_level_results_*.csv');
iccFile = latestFile(procDir,'icc_results_*.csv');
T = readtable(tlFile,  'VariableNamingRule','preserve');
I = readtable(iccFile, 'VariableNamingRule','preserve');
metrics = {'PathLength_mm','NumLifts','NumStrokes','Duration'};
cols = [{param}, metrics];
assert(all(ismember(cols, T.Properties.VariableNames)), 'diagnoseShapeStability_2026:noCol', ...
    'Missing column(s): %s', strjoin(setdiff(cols, T.Properties.VariableNames), ', '));
sT = unique(T.ShapeType)'; assert(ismember(shapeType, sT), 'diagnoseShapeStability_2026:badShape', 'ShapeType %d not in data', shapeType);

% ---- 1. variance decomposition, all shapes
V = I(strcmp(string(I.Parameter),param) & strcmp(string(I.ICCType),'absolute'), {'ShapeType','ShapeName','BetweenSD','WithinSD','SEM','SNR','ICC_WithinVisit1','ICC_WithinVisit2','ICC_BetweenVisit'});
fprintf('Variance decomposition, %s (absolute):\n', param); disp(sortrows(V,'ShapeType'));

% ---- 2. within-session trial CV, all shapes
G = findgroups(T.ParticipantID, T.Session, T.ShapeType);
cv = @(x) std(x,'omitnan')/abs(mean(x,'omitnan'));
cvT = table(splitapply(@(x) x(1), T.ShapeType, G), splitapply(cv, T.(param), G), splitapply(cv, T.PathLength_mm, G), splitapply(cv, T.Duration, G), ...
    'VariableNames', {'ShapeType','CV_param','CV_path','CV_duration'});
CV = varfun(@(x) median(x,'omitnan'), cvT, 'InputVariables', {'CV_param','CV_path','CV_duration'}, 'GroupingVariables', 'ShapeType');
CV.Properties.VariableNames = {'ShapeType','nSessions','MedianCV_param','MedianCV_path','MedianCV_duration'};
fprintf('Within-session trial-to-trial CV (median over sessions):\n'); disp(CV);

% ---- 3. per-participant change and its link to execution metrics
[ids, X] = buildVisitMatrices_2026(T, param); s = find(sT == shapeType); x = X{s}; n = numel(ids);
assert(size(x,2) == 2, 'diagnoseShapeStability_2026:needTwoVisits', 'Needs exactly 2 visits');
vis = aggregateToVisitMeans(aggregateToSessionMeans(T, cols), cols);
D = table(ids, x(:,2)-x(:,1), 'VariableNames', {'ParticipantID','d_param'});
for m = 1:numel(metrics)
    D.(['d_' metrics{m}]) = arrayfun(@(p) vis.(metrics{m})(vis.ParticipantID==p & vis.ShapeType==shapeType & vis.Visit==max(vis.Visit)) - ...
                                          vis.(metrics{m})(vis.ParticipantID==p & vis.ShapeType==shapeType & vis.Visit==min(vis.Visit)), ids);
end
fprintf('Shape %d: Spearman between |d_param| and |d metric| across participants (n=%d):\n', shapeType, n);
for m = 1:numel(metrics)
    fprintf('  %-14s rho=%5.2f\n', metrics{m}, corr(abs(D.d_param), abs(D.(['d_' metrics{m}])), 'Type','Spearman','Rows','complete'));
end

% ---- 4. POST HOC DIAGNOSTIC: robust movers
dAbs = abs(D.d_param); thr = median(dAbs) + kMAD*1.4826*mad(dAbs,1); D.Flagged = dAbs > thr;
assert(sum(~D.Flagged) >= 5, 'diagnoseShapeStability_2026:tooFew', 'Fewer than 5 participants remain after removing movers');
iAll = computeICC(x,'absolute'); iKeep = computeICC(x(~D.Flagged,:),'absolute');
fprintf('\nPOST HOC DIAGNOSTIC (rule: |d| > median + %g*1.4826*MAD = %.3f; not a result to report)\n', kMAD, thr);
fprintf('  flagged IDs: %s\n', mat2str(D.ParticipantID(D.Flagged)'));
fprintf('  ICC(A,1) all n=%d: %.3f [%.3f, %.3f]; without flagged (n=%d): %.3f [%.3f, %.3f]\n', n, iAll.icc, iAll.lb, iAll.ub, sum(~D.Flagged), iKeep.icc, iKeep.lb, iKeep.ub);
fl = D(D.Flagged,:); ot = D(~D.Flagged,:);
for k = 1:height(fl), fprintf('  ID %d: d_param %6.3f, d_path %7.1f, d_lifts %5.1f\n', fl.ParticipantID(k), fl.d_param(k), fl.d_PathLength_mm(k), fl.d_NumLifts(k)); end
fprintf('  others (median |d|): d_param %.3f, d_path %.1f, d_lifts %.1f\n', median(abs(ot.d_param)), median(abs(ot.d_PathLength_mm)), median(abs(ot.d_NumLifts)));

ts = char(datetime('now','Format','yyyyMMdd_HHmmss'));
f = fullfile(procDir, sprintf('stability_shapeDiagnostic_shape%d_N%d_%s.csv', shapeType, n, ts));
writetable(D, f);
fid = fopen(f,'r'); assert(fid > 0, 'diagnoseShapeStability_2026:writeFail', 'Cannot reopen %s', f);
hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(D.Properties.VariableNames, ',')), 'diagnoseShapeStability_2026:badHeader', 'Bad header in %s', f);
fprintf('Wrote %s\n', f);
out = struct('variance', V, 'withinSessionCV', CV, 'participants', D, 'iccAll', iAll, 'iccWithoutFlagged', iKeep, 'file', f);
end

function f = latestFile(dirPath, pattern)
d = dir(fullfile(dirPath, pattern));
assert(~isempty(d), 'diagnoseShapeStability_2026:noFile', 'No %s in %s', pattern, dirPath);
[~,k] = max([d.datenum]); f = fullfile(d(k).folder, d(k).name);
end
