function out = reportPipelineRobustness_2026(rootDir, primary, B, seed)
% reportPipelineRobustness_2026 - Is test-retest reliability robust to the analysis pipeline?
%
% Computes between-visit ICC(A,1) with exact CIs (computeICC) for every
% filter x regression pipeline (the 2x3 grid of Fraser et al. 2025, Fig 7)
% in every shape, and tests each pipeline against the primary one with a
% PAIRED cluster bootstrap over participants (the same resampled participants
% are used for every pipeline, so delta-ICC reflects pipeline differences, not
% sampling noise; overlapping separate CIs are NOT a test of a difference).
%
% Protocol labels follow Fraser et al. (2025): 'legacy' = BW + Linear,
% 'vetted' = SG6 + LMLS or IRLS, everything else 'mixed'.
% READ THIS BEFORE QUOTING: reliability is not validity. The legacy Butterworth
% filter can yield a spurious one-third from beta=0 data (Fraser et al. 2025
% Fig 6), so a legacy pipeline can be reliable and wrong. The primary pipeline
% is chosen on validity grounds; this function only shows what that choice
% costs (or not) in reliability. Do not select a pipeline by its ICC.
%
% INPUTS (all optional)
%   rootDir  Analysis_2026 folder (default: derived from this file)
%   primary  primary outcome column (default 'Beta_SG6_IRLS')
%   B        bootstrap replicates (default 4000)
%   seed     RandStream seed (default 20261008; recorded in the CSV)
%
% Writes timestamped files: data/processed/pipelineRobustness_N<n>_<ts>.csv
% (header verified) and figures/pipelineRobustness_specCurve_N<n>_<ts>.png.
% n comes from the data. FAILS LOUDLY if ICCs do not match icc_results (1e-3),
% if the participant/shape sets differ between pipelines, or if a file is not
% written.

if nargin < 1 || isempty(rootDir), rootDir = fileparts(fileparts(fileparts(mfilename('fullpath')))); end
if nargin < 2 || isempty(primary), primary = 'Beta_SG6_IRLS'; end
if nargin < 3 || isempty(B),       B = 4000; end
if nargin < 4 || isempty(seed),    seed = 20261008; end
procDir = fullfile(rootDir,'data','processed'); figDir = fullfile(rootDir,'figures');
assert(isfolder(figDir), 'reportPipelineRobustness_2026:noFigDir', 'Missing folder %s', figDir);
tlFile = latestFile(procDir,'trial_level_results_*.csv'); iccFile = latestFile(procDir,'icc_results_*.csv');
T = readtable(tlFile, 'VariableNamingRule','preserve'); I = readtable(iccFile, 'VariableNamingRule','preserve');

order = {'BW_Linear','BW_LMLS','BW_IRLS','SG6_Linear','SG6_LMLS','SG6_IRLS'};   % Fig 7 order
params = strcat('Beta_', order); P = numel(params);
assert(all(ismember(params, T.Properties.VariableNames)) && all(ismember(params, string(I.Parameter))), ...
    'reportPipelineRobustness_2026:missingPipeline', 'Not all six Beta_* pipelines are in the trial/ICC tables');
pIdx = find(strcmp(params, primary)); assert(isscalar(pIdx), 'reportPipelineRobustness_2026:badPrimary', '%s is not one of the six pipelines', primary);

X = cell(1,P);
for p = 1:P
    [ids_p, X{p}, sT_p] = buildVisitMatrices_2026(T, params{p});
    if p == 1, ids = ids_p; sT = sT_p; end
    assert(isequal(ids, ids_p) && isequal(sT, sT_p), 'reportPipelineRobustness_2026:setMismatch', 'Participants/shapes differ for %s', params{p});
    assert(size(X{p}{1},2) == 2, 'reportPipelineRobustness_2026:needTwoVisits', 'Needs exactly 2 visits');
end
n = numel(ids); S = numel(sT);

% ---- point estimates, checked against icc_results
icc = nan(P,S); lb = icc; ub = icc; mu = icc;
for p = 1:P, for s = 1:S
    r = computeICC(X{p}{s}, 'absolute'); icc(p,s) = r.icc; lb(p,s) = r.lb; ub(p,s) = r.ub; mu(p,s) = mean(X{p}{s}(:));
    row = I(I.ShapeType == sT(s) & strcmp(string(I.Parameter), params{p}) & strcmp(string(I.ICCType),'absolute'), :);
    assert(height(row) == 1 && abs(r.icc - row.ICC_BetweenVisit) < 1e-3, 'reportPipelineRobustness_2026:iccMismatch', ...
        'ICC(A,1) %.4f vs icc_results for %s shape %d: different runs?', r.icc, params{p}, sT(s));
    assert(abs(iccA1(X{p}{s}) - r.icc) < 1e-9, 'reportPipelineRobustness_2026:fastIccMismatch', 'Bootstrap ICC differs from computeICC');
end, end

% ---- paired cluster bootstrap of delta-ICC vs primary
stream = RandStream('mt19937ar','Seed',seed); bootICC = nan(B,P,S);
for b = 1:B
    idx = randi(stream, n, n, 1);
    for p = 1:P, for s = 1:S, bootICC(b,p,s) = iccA1(X{p}{s}(idx,:)); end, end
end
dBoot = bootICC - bootICC(:,pIdx,:); dCI = prctile(dBoot, [2.5 97.5], 1);   % 2 x P x S
nanFrac = mean(isnan(bootICC(:)));
assert(nanFrac < 0.001, 'reportPipelineRobustness_2026:bootNaN', '%.2f%% of bootstrap ICCs are NaN', 100*nanFrac);

% ---- assemble
shapeNames = cell(1,S);
for s = 1:S, shapeNames{s} = I.ShapeName{find(I.ShapeType == sT(s), 1)}; end
rows = cell(P*S, 19); k = 0;
for s = 1:S, for p = 1:P
    k = k + 1; isP = (p == pIdx); parts = strsplit(order{p}, '_');
    if strcmp(order{p},'BW_Linear'), proto = 'legacy'; elseif startsWith(order{p},'SG6') && ~strcmp(parts{2},'Linear'), proto = 'vetted'; else, proto = 'mixed'; end
    lo = dCI(1,p,s); hi = dCI(2,p,s);
    rows(k,:) = {sT(s), shapeNames{s}, params{p}, parts{1}, parts{2}, proto, n, mu(p,s), icc(p,s), lb(p,s), ub(p,s), classify(lb(p,s)), isP, ...
        icc(p,s)-icc(pIdx,s), lo, hi, ~isP && (lo > 0 || hi < 0), B, seed};
end, end
R = cell2table(rows, 'VariableNames', {'ShapeType','ShapeName','Pipeline','Filter','Regression','Protocol','n','MeanBeta','ICC_abs','ICC_LB','ICC_UB', ...
    'KooLiClass','IsPrimary','dICC_vs_primary','dICC_LB','dICC_UB','dCI_excludes0','B','Seed'});

% ---- console summary
fprintf('Between-visit ICC(A,1), n=%d, primary %s, paired bootstrap B=%d seed %d\n  trials: %s\n  icc:    %s\n', n, primary, B, seed, tlFile, iccFile);
fprintf('%-10s', 'Shape'); fprintf('%12s', order{:}); fprintf('   range\n');
for s = 1:S, fprintf('%-10s', shapeNames{s}); fprintf('%12.3f', icc(:,s)); fprintf('   %.3f\n', max(icc(:,s)) - min(icc(:,s))); end
fprintf('\ndelta-ICC vs %s (paired bootstrap 95%% CI); * = CI excludes 0\n', primary);
for s = 1:S
    fprintf('%-10s', shapeNames{s});
    for p = 1:P
        if p == pIdx, fprintf('%22s', '(primary)'); else
            star = ' '; if dCI(1,p,s) > 0 || dCI(2,p,s) < 0, star = '*'; end
            fprintf('  %+.3f [%+.3f,%+.3f]%s', icc(p,s)-icc(pIdx,s), dCI(1,p,s), dCI(2,p,s), star); end
    end, fprintf('\n');
end
fprintf('\nVetted vs legacy (SG6_IRLS minus BW_Linear), per shape: %s\n', strjoin(arrayfun(@(s) sprintf('%s %+.3f', shapeNames{s}, icc(strcmp(order,'SG6_IRLS'),s) - icc(strcmp(order,'BW_Linear'),s)), 1:S, 'UniformOutput', false), '; '));
fprintf('Pipelines whose delta-ICC CI excludes 0: %d of %d comparisons\n', sum(R.dCI_excludes0), S*(P-1));

% ---- write CSV (header verified) and figure
ts = char(datetime('now','Format','yyyyMMdd_HHmmss'));
fCsv = fullfile(procDir, sprintf('pipelineRobustness_N%d_%s.csv', n, ts)); writetable(R, fCsv);
fid = fopen(fCsv,'r'); assert(fid > 0, 'reportPipelineRobustness_2026:writeFail', 'Cannot reopen %s', fCsv); hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(R.Properties.VariableNames, ',')), 'reportPipelineRobustness_2026:badHeader', 'Bad header in %s', fCsv);
fPng = fullfile(figDir, sprintf('pipelineRobustness_specCurve_N%d_%s.png', n, ts));
fig = figure('Visible','off','Position',[100 100 1500 420]); tl = tiledlayout(fig, 1, S, 'TileSpacing','compact');
cols = [repmat([0.55 0.55 0.55], 3, 1); repmat([0 0.447 0.741], 3, 1)];
for s = 1:S
    ax = nexttile(tl); hold(ax,'on'); yline(ax, 0.75, '--', 'Color', [0.3 0.3 0.3]);
    for p = 1:P
        errorbar(ax, p, icc(p,s), icc(p,s)-lb(p,s), ub(p,s)-icc(p,s), 'o', 'Color', cols(p,:), 'MarkerFaceColor', cols(p,:), 'LineWidth', 1.2, 'CapSize', 6);
    end
    plot(ax, pIdx, icc(pIdx,s), 'o', 'MarkerSize', 11, 'Color', [0.85 0.1 0.1], 'LineWidth', 1.5);
    xlim(ax,[0.5 P+0.5]); ylim(ax,[-0.2 1]); xticks(ax,1:P); xticklabels(ax, strrep(order,'_','\_')); xtickangle(ax,45); title(ax, shapeNames{s});
    if s == 1, ylabel(ax,'ICC(A,1), 95% CI'); end
end
title(tl, sprintf('Between-visit reliability across pipelines (n=%d). Grey: Butterworth, blue: Savitzky-Golay, red ring: primary; dashed: 0.75', n));
exportgraphics(fig, fPng, 'Resolution', 300); close(fig);
assert(isfile(fPng), 'reportPipelineRobustness_2026:figFail', 'Figure not written: %s', fPng);
fprintf('Wrote:\n  %s\n  %s\n', fCsv, fPng);
out = struct('results', R, 'icc', icc, 'lb', lb, 'ub', ub, 'dCI', dCI, 'pipelines', {params}, 'shapes', {shapeNames}, 'files', {{fCsv, fPng}});
end

function r = iccA1(x)
% ICC(A,1) absolute agreement (McGraw & Wong), point estimate only (bootstrap speed).
[n,k] = size(x); gm = mean(x(:)); rm = mean(x,2); cm = mean(x,1);
msr = k*sum((rm-gm).^2)/(n-1); msc = n*sum((cm-gm).^2)/(k-1); mse = sum((x - rm - cm + gm).^2, 'all')/((n-1)*(k-1));
r = (msr - mse)/(msr + (k-1)*mse + k*(msc - mse)/n);
end

function c = classify(lb)
% Koo & Li (2016) class from the CI LOWER bound.
if lb < 0.5, c = 'poor'; elseif lb < 0.75, c = 'moderate'; elseif lb < 0.9, c = 'good'; else, c = 'excellent'; end
end

function f = latestFile(dirPath, pattern)
d = dir(fullfile(dirPath, pattern));
assert(~isempty(d), 'reportPipelineRobustness_2026:noFile', 'No %s in %s', pattern, dirPath);
[~,k] = max([d.datenum]); f = fullfile(d(k).folder, d(k).name);
end
