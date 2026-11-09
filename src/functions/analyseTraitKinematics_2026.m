function res = analyseTraitKinematics_2026(M, outDir, figDir, nBoot, seed)
% analyseTraitKinematics_2026 - EXPLORATORY continuous trait vs kinematics
%
% Correlates CATI_Total and M_EDL (neither depends on the unverified CATI
% subscale labels) with per-participant Beta_/Jerk_ outcomes from the table
% returned by mergeQuestionnaires_2026 (out.merged). Per outcome column
% (shape mean, and _V<k> per visit) reports Spearman (primary: M-EDL is
% zero-inflated, jerk is skewed) and Pearson r with percentile bootstrap
% 95% CIs over participants. Estimation, not testing: no p-values.
%
% n is taken from the data; nothing assumes a particular participant count.
%
% INPUTS
%   M      merged table (ParticipantID, CATI_Total, M_EDL, Beta_*, Jerk_*)
%   outDir folder for the timestamped results CSV (must exist)
%   figDir folder for the forest plot PNG (default outDir)
%   nBoot  bootstrap resamples (default 4000)
%   seed   RNG seed for reproducible CIs (default 20261008)
%
% FAILS LOUDLY if a trait or any outcome column is missing, a pairing has
% fewer than 5 complete cases, or too many bootstrap resamples are degenerate.

if nargin < 3 || isempty(figDir), figDir = outDir; end
if nargin < 4 || isempty(nBoot),  nBoot = 4000;    end
if nargin < 5 || isempty(seed),   seed  = 20261008; end
traits = {'CATI_Total','M_EDL'};
vn = M.Properties.VariableNames;
assert(all(ismember(traits, vn)), 'analyseTraitKinematics_2026:noTrait', ...
    'Missing trait column(s): %s', strjoin(setdiff(traits, vn), ', '));
assert(isfolder(outDir) && isfolder(figDir), 'analyseTraitKinematics_2026:noDir', 'outDir/figDir must exist');
parts = cellfun(@(s) strsplit(s, '_'), vn, 'UniformOutput', false);
isOut = cellfun(@(p) ismember(p{1}, {'Beta','Jerk'}) && ismember(numel(p), [2 3]), parts);
outIdx = find(isOut);
assert(~isempty(outIdx), 'analyseTraitKinematics_2026:noOutcome', 'No Beta_*/Jerk_* columns in table');
stream = RandStream('mt19937ar', 'Seed', seed);
methods = {'Spearman','Pearson'};

rows = {};
for t = 1:numel(traits)
    for j = outIdx
        tk = parts{j}; visit = 'Mean'; if numel(tk) == 3, visit = tk{3}; end
        for m = 1:numel(methods)
            x = M.(traits{t}); y = M.(vn{j}); ok = ~isnan(x) & ~isnan(y); x = x(ok); y = y(ok);
            assert(numel(x) >= 5, 'analyseTraitKinematics_2026:fewCases', ...
                '%s vs %s: only %d complete cases', traits{t}, vn{j}, numel(x));
            [lo, hi] = bootCI(x, y, methods{m}, nBoot, stream);
            rows(end+1,:) = {traits{t}, tk{1}, tk{2}, visit, methods{m}, numel(x), ...
                corr(x, y, 'Type', methods{m}), lo, hi}; %#ok<AGROW>
        end
    end
end
res = cell2table(rows, 'VariableNames', {'Trait','Outcome','Shape','Visit','Method','n','r','CI_lo','CI_hi'});
n = height(M); ts = char(datetime('now','Format','yyyyMMdd_HHmmss'));

% ---- console summary: Spearman, visit means
sp = res(strcmp(res.Method,'Spearman') & strcmp(res.Visit,'Mean'), :);
fprintf('EXPLORATORY trait vs kinematics, N=%d (Spearman, visit means, bootstrap 95%% CI, B=%d)\n', n, nBoot);
for i = 1:height(sp)
    fprintf('  %-10s %-4s %-8s r=%6.2f [%6.2f, %6.2f]\n', sp.Trait{i}, sp.Outcome{i}, sp.Shape{i}, sp.r(i), sp.CI_lo(i), sp.CI_hi(i));
end
excl = sum(sp.CI_lo > 0 | sp.CI_hi < 0);
fprintf('%d of %d CIs exclude 0 (about %.1f expected by chance if no effects; %d correlations are not independent).\n', ...
    excl, height(sp), 0.05*height(sp), height(sp));
v = res(strcmp(res.Method,'Spearman') & startsWith(res.Visit,'V'), :);
if ~isempty(v)
    [~,~,g] = unique(v(:,{'Trait','Outcome','Shape'}), 'rows'); agree = 0; tot = 0;
    for k = 1:max(g)
        rr = v.r(g==k); if numel(rr) >= 2, tot = tot + 1; agree = agree + (all(sign(rr) == sign(rr(1)))); end
    end
    fprintf('Sign of r agrees across visits in %d of %d trait x outcome x shape pairings.\n', agree, tot);
end
% ---- Pearson vs Spearman: does the choice of correlation matter in these data?
pe = res(strcmp(res.Method,'Pearson') & strcmp(res.Visit,'Mean'), :);
assert(isequal(pe(:,{'Trait','Outcome','Shape'}), sp(:,{'Trait','Outcome','Shape'})), 'analyseTraitKinematics_2026:rowOrder', 'Pearson/Spearman rows misaligned');
fprintf('Pearson vs Spearman (visit means): r sets correlate %.2f; max |difference| %.2f; CIs excluding 0: Pearson %d, Spearman %d; sign disagreements %d.\n', ...
    corr(pe.r, sp.r), max(abs(pe.r - sp.r)), sum(pe.CI_lo > 0 | pe.CI_hi < 0), excl, sum(sign(pe.r) ~= sign(sp.r)));
fprintf('M-EDL zeros: %d of %d.\n', sum(M.M_EDL == 0), n);

% ---- write results (timestamped, header verified)
f = fullfile(outDir, sprintf('exploratory_traitKinematics_N%d_%s.csv', n, ts));
writetable(res, f);
fid = fopen(f,'r'); assert(fid > 0, 'analyseTraitKinematics_2026:writeFail', 'Cannot reopen %s', f);
hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(res.Properties.VariableNames, ',')), 'analyseTraitKinematics_2026:badHeader', 'Bad header in %s', f);

% ---- forest plot (Spearman, visit means)
fig = figure('Visible','off','Color','w','Position',[100 100 760 640]); ax = axes(fig); hold(ax,'on');
y = (1:height(sp))';
errorbar(ax, sp.r, y, [], [], sp.r - sp.CI_lo, sp.CI_hi - sp.r, 'o', 'LineWidth', 1.2);
xline(ax, 0, 'k:'); ax.YTick = y; ax.YTickLabel = strcat(sp.Trait, ' | ', sp.Outcome, ' | ', sp.Shape);
ax.TickLabelInterpreter = 'none'; ax.YDir = 'reverse'; xlabel(ax, 'Spearman r (bootstrap 95% CI)'); xlim(ax, [-1 1]);
title(ax, sprintf('EXPLORATORY: trait vs kinematics, N = %d', n)); box(ax,'off');
fp = fullfile(figDir, sprintf('exploratory_traitKinematics_forest_N%d_%s.png', n, ts));
exportgraphics(fig, fp, 'Resolution', 200); close(fig);
fprintf('Wrote:\n  %s\n  %s\n', f, fp);
end

function [lo, hi] = bootCI(x, y, method, B, stream)
% Percentile bootstrap CI for a correlation, resampling participants.
n = numel(x); idx = randi(stream, n, n, B); r = nan(B,1);
for b = 1:B
    r(b) = corr(x(idx(:,b)), y(idx(:,b)), 'Type', method);
end
r = r(~isnan(r));
assert(numel(r) > 0.9*B, 'analyseTraitKinematics_2026:degenerate', ...
    'More than 10%% of bootstrap resamples were degenerate (constant input)');
q = prctile(r, [2.5 97.5]); lo = q(1); hi = q(2);
end
