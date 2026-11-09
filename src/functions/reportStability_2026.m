function out = reportStability_2026(rootDir, param)
% reportStability_2026 - Test-retest agreement and individual-level stability
%
% Reproduces, from the saved trial-level and ICC results, the tables behind
% the "Test-retest stability" section of docs/AnalysisPipeline.md. Per shape
% (visit means, Visit 1 vs Visit 2):
%   agreement   Pearson, Spearman, ICC consistency and absolute (computeICC,
%               with CIs), mean shift V2-V1 with 95% CI and in SD units,
%               Bland-Altman 95% limits, SEM, MDC95 (from icc_results),
%               within-visit ICCs
%   individual  participants beyond MDC95, median and 90th-percentile change
%               in own value (%), quartile agreement and 2+ quartile jumps
% n is taken from the data; nothing assumes a participant count.
%
% INPUTS (both optional)
%   rootDir  Analysis_2026 folder (default: derived from this file's location)
%   param    outcome column (default 'Beta_SG6_IRLS')
%
% Writes three timestamped, header-verified CSVs to data/processed/:
%   stability_agreement_N<n>_<ts>.csv, stability_individual_N<n>_<ts>.csv,
%   stability_participants_N<n>_<ts>.csv
%
% FAILS LOUDLY if the newest trial_level_results and icc_results are not from
% the same run (recomputed ICC(A,1) must match icc_results to 1e-3), if a
% participant x visit x shape cell is missing, or if there are not exactly
% two visits.

if nargin < 1 || isempty(rootDir), rootDir = fileparts(fileparts(fileparts(mfilename('fullpath')))); end
if nargin < 2 || isempty(param),   param   = 'Beta_SG6_IRLS'; end
procDir = fullfile(rootDir,'data','processed');
tlFile  = latestFile(procDir,'trial_level_results_*.csv');
iccFile = latestFile(procDir,'icc_results_*.csv');
T = readtable(tlFile,  'VariableNamingRule','preserve');
I = readtable(iccFile, 'VariableNamingRule','preserve');
[ids, X, sT] = buildVisitMatrices_2026(T, param);
n = numel(ids);
assert(size(X{1},2) == 2, 'reportStability_2026:needTwoVisits', 'Agreement metrics assume 2 visits, got %d', size(X{1},2));
tc = tinv(0.975, n-1); q = @(x) ceil(4*tiedrank(x)/numel(x));

rowsA = cell(numel(sT),23); rowsB = cell(numel(sT),8);
P = table(ids, 'VariableNames', {'ParticipantID'});
for s = 1:numel(sT)
    x = X{s}; d = x(:,2) - x(:,1); mu = mean(x(:));
    iA = computeICC(x,'absolute'); iC = computeICC(x,'consistency');
    r = I(I.ShapeType == sT(s) & strcmp(string(I.Parameter),param) & strcmp(string(I.ICCType),'absolute'), :);
    assert(height(r) == 1, 'reportStability_2026:noIccRow', 'Need exactly one icc_results row for shape %d / %s, got %d', sT(s), param, height(r));
    assert(abs(iA.icc - r.ICC_BetweenVisit) < 1e-3, 'reportStability_2026:iccMismatch', ...
        'Recomputed ICC(A,1)=%.4f vs icc_results %.4f (shape %d): trial_level and icc_results are from different runs?', iA.icc, r.ICC_BetweenVisit, sT(s));
    se = std(d)/sqrt(n); big = abs(d) > r.MDC95; rel = 100*abs(d)./mean(x,2); dq = abs(q(x(:,1)) - q(x(:,2)));
    rowsA(s,:) = {sT(s), r.ShapeName{1}, n, mu, corr(x(:,1),x(:,2)), corr(x(:,1),x(:,2),'Type','Spearman'), ...
        iC.icc, iC.lb, iC.ub, iA.icc, iA.lb, iA.ub, mean(d), mean(d)-tc*se, mean(d)+tc*se, mean(d)/std(x(:)), ...
        mean(d)-1.96*std(d), mean(d)+1.96*std(d), r.SEM, r.MDC95, 100*r.MDC95/mu, r.ICC_WithinVisit1, r.ICC_WithinVisit2};
    rowsB(s,:) = {sT(s), r.ShapeName{1}, sum(big), 100*mean(big), median(rel), prctile(rel,90), 100*mean(dq==0), 100*mean(dq>=2)};
    P.(sprintf('d_Shape%d', sT(s))) = d; P.(sprintf('beyondMDC95_Shape%d', sT(s))) = big;
end
P.nShapesBeyondMDC95 = sum(P{:, startsWith(P.Properties.VariableNames,'beyondMDC95_')}, 2);
A = cell2table(rowsA, 'VariableNames', {'ShapeType','ShapeName','n','MeanValue','Pearson','Spearman', ...
    'ICC_consistency','ICC_cons_LB','ICC_cons_UB','ICC_absolute','ICC_abs_LB','ICC_abs_UB', ...
    'MeanShift','MeanShift_LB','MeanShift_UB','Shift_SD','LoA_LB','LoA_UB','SEM','MDC95','MDC95_pctOfMean','ICC_withinV1','ICC_withinV2'});
B = cell2table(rowsB, 'VariableNames', {'ShapeType','ShapeName','nBeyondMDC95','pctBeyondMDC95', ...
    'MedianPctChange','P90PctChange','PctSameQuartile','PctJump2PlusQuartiles'});

ts = char(datetime('now','Format','yyyyMMdd_HHmmss'));
fA = fullfile(procDir, sprintf('stability_agreement_N%d_%s.csv', n, ts));
fB = fullfile(procDir, sprintf('stability_individual_N%d_%s.csv', n, ts));
fP = fullfile(procDir, sprintf('stability_participants_N%d_%s.csv', n, ts));
writeVerified(A, fA); writeVerified(B, fB); writeVerified(P, fP);
fprintf('%s, V1 vs V2 visit means, n=%d\n  trials: %s\n  icc:    %s\n', param, n, tlFile, iccFile);
disp(A(:, {'ShapeName','Pearson','Spearman','ICC_consistency','ICC_absolute','MeanShift','MeanShift_LB','MeanShift_UB','MDC95_pctOfMean'}));
disp(B);
fprintf('Participants beyond MDC95 in 0/1/2/3+ shapes: %d / %d / %d / %d\n', sum(P.nShapesBeyondMDC95==0), sum(P.nShapesBeyondMDC95==1), sum(P.nShapesBeyondMDC95==2), sum(P.nShapesBeyondMDC95>=3));
fprintf('IDs beyond MDC95 in 2+ shapes: %s\nWrote:\n  %s\n  %s\n  %s\n', mat2str(P.ParticipantID(P.nShapesBeyondMDC95>=2)'), fA, fB, fP);
out = struct('agreement', A, 'individual', B, 'participants', P, 'files', {{fA, fB, fP}});
end

function f = latestFile(dirPath, pattern)
d = dir(fullfile(dirPath, pattern));
assert(~isempty(d), 'reportStability_2026:noFile', 'No %s in %s', pattern, dirPath);
[~,k] = max([d.datenum]); f = fullfile(d(k).folder, d(k).name);
end

function writeVerified(tbl, path)
% Write CSV and fail if the header row on disk is not the table's variable names.
writetable(tbl, path);
fid = fopen(path,'r'); assert(fid > 0, 'reportStability_2026:writeFail', 'Cannot reopen %s', path);
hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(tbl.Properties.VariableNames, ',')), 'reportStability_2026:badHeader', 'Bad header in %s', path);
end
