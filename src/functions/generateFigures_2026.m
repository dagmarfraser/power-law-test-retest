function generateFigures_2026(options)
% GENERATEFIGURES_2026 - Produces the 3 figures flagged as deferred in
% docs/AnalysisPipeline.md ("Deliberately deferred: figures"), now that
% real N=31 confirmatory data exists. Small-multiples approach (one
% focused panel per question) rather than a single 6-way grouped bar,
% per that section's own design note.
%
%   1. iccComparison_BetaVsJerk_*.png
%      Between-visit ICC (absolute agreement), Beta_SG6_IRLS vs
%      MeanJerk_SG, per shape, with 95% CI whiskers and Koo & Li (2016)
%      classification bands. The headline crossover: beta wins for
%      phi=0.4/0.8. At N=31 jerk won for Cursive; at N=48 both are poor
%      and their CIs overlap (0.43 vs 0.39), so do not call it a crossover.
%
%   2. betaVsTheory_*.png
%      Observed Beta_SG6_IRLS vs Huh & Sejnowski (2015) theoretical
%      prediction, per shape (Cursive excluded, no single theoretical
%      phi). %-of-theory labelled above each pair.
%
%   3. powerAnalysis_NrequiredVsAchieved_*.png
%      N required (Zou 2012, absolute agreement, Beta_SG6_IRLS) vs
%      N achieved (from the ICC file), per shape. Colour flags confirmatory-ready vs not
%      vs intractable (Cursive).
%
% USAGE:
%   generateFigures_2026()
%   generateFigures_2026('iccFile', 'path.csv', ...)
%
% Defaults to the most recent icc_results_*.csv and beta_vs_theory_*.csv,
% and the single icc_power_output.csv, in data/processed/. Figures are
% written to figures/ as timestamped PNGs (300 dpi).

arguments
    options.iccFile string = ""
    options.thetaFile string = ""
    options.powerFile string = ""
end

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));
processedPath = fullfile(projectRoot, 'data', 'processed');
figuresPath = fullfile(projectRoot, 'figures');

iccFile = resolveLatestFile(options.iccFile, processedPath, 'icc_results_2*.csv');
thetaFile = resolveLatestFile(options.thetaFile, processedPath, 'beta_vs_theory_2*.csv');
powerFile = options.powerFile;
if powerFile == ""
    powerFile = fullfile(processedPath, 'icc_power_output.csv');
end
if ~isfile(powerFile)
    error('generateFigures_2026:missingFile', '%s', 'icc_power_output.csv not found -- run powerAnalysisICC_R first');
end

fprintf('ICC data:   %s\n', iccFile);
fprintf('Theta data: %s\n', thetaFile);
fprintf('Power data: %s\n\n', powerFile);

iccResults = readtable(iccFile);
thetaTable = readtable(thetaFile);
powerTable = readtable(powerFile);

timestamp = datestr(now, 'yyyymmdd_HHMMSS');

iccComparisonPanel(iccResults, figuresPath, timestamp);
betaVsTheoryPanel(thetaTable, figuresPath, timestamp);
nAchieved = max(iccResults.ICC_BetweenVisit_N);   % derived from the data, never hard-coded
powerAnalysisPanel(powerTable, figuresPath, timestamp, nAchieved);

end


function f = resolveLatestFile(explicit, processedPath, pattern)
if explicit ~= ""
    f = explicit;
    return;
end
files = dir(fullfile(processedPath, pattern));
if isempty(files)
    error('generateFigures_2026:noMatch', 'No files matching %s found in %s', pattern, processedPath);
end
[~, idx] = max([files.datenum]);
f = fullfile(processedPath, files(idx).name);
end


function shapeOrder = shapeOrder2026()
shapeOrder = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
end


function iccComparisonPanel(iccResults, figuresPath, timestamp)
shapes = shapeOrder2026();
nShapes = length(shapes);

betaICC = nan(nShapes, 1); betaLB = nan(nShapes, 1); betaUB = nan(nShapes, 1);
jerkICC = nan(nShapes, 1); jerkLB = nan(nShapes, 1); jerkUB = nan(nShapes, 1);

for s = 1:nShapes
    bRow = iccResults(strcmp(iccResults.ShapeName, shapes{s}) & ...
        strcmp(iccResults.Parameter, 'Beta_SG6_IRLS') & strcmp(iccResults.ICCType, 'absolute'), :);
    jRow = iccResults(strcmp(iccResults.ShapeName, shapes{s}) & ...
        strcmp(iccResults.Parameter, 'MeanJerk_SG') & strcmp(iccResults.ICCType, 'absolute'), :);
    betaICC(s) = bRow.ICC_BetweenVisit; betaLB(s) = bRow.ICC_BetweenVisit_LB; betaUB(s) = bRow.ICC_BetweenVisit_UB;
    jerkICC(s) = jRow.ICC_BetweenVisit; jerkLB(s) = jRow.ICC_BetweenVisit_LB; jerkUB(s) = jRow.ICC_BetweenVisit_UB;
end

fig = figure('Position', [100 100 780 520], 'Color', 'w');
ax = axes(fig); hold(ax, 'on');

bandColors = [0.93 0.93 0.93; 0.85 0.90 0.85; 0.80 0.88 0.98; 0.85 0.93 0.85];
bandEdges = [0 0.5 0.75 0.9 1];
bandLabels = {'poor', 'moderate', 'good', 'excellent'};
for b = 1:4
    patch(ax, [0 nShapes+1 nShapes+1 0], [bandEdges(b) bandEdges(b) bandEdges(b+1) bandEdges(b+1)], ...
        bandColors(b,:), 'EdgeColor', 'none', 'FaceAlpha', 0.6, 'HandleVisibility', 'off');
    text(ax, nShapes+0.55, mean(bandEdges(b:b+1)), bandLabels{b}, 'FontSize', 8, ...
        'Color', [0.4 0.4 0.4], 'HorizontalAlignment', 'left');
end

x = (1:nShapes)';
w = 0.17;
colBeta = [0.20 0.35 0.65];
colJerk = [0.80 0.40 0.15];

bar(ax, x-w, betaICC, 0.32, 'FaceColor', colBeta, 'EdgeColor', 'none');
bar(ax, x+w, jerkICC, 0.32, 'FaceColor', colJerk, 'EdgeColor', 'none');
errorbar(ax, x-w, betaICC, betaICC-betaLB, betaUB-betaICC, 'k.', 'LineWidth', 1.1, 'CapSize', 5);
errorbar(ax, x+w, jerkICC, jerkICC-jerkLB, jerkUB-jerkICC, 'k.', 'LineWidth', 1.1, 'CapSize', 5);

set(ax, 'XTick', x, 'XTickLabel', shapes, 'XLim', [0.5 nShapes+1.3], 'YLim', [-0.15 1]);
ylabel(ax, 'Between-visit ICC (absolute agreement, 95% CI)');
title(ax, 'Beta (SG6+IRLS) vs mean jerk: test-retest reliability by shape');
legend(ax, {'Beta SG6+IRLS', 'Mean jerk (SG)'}, 'Location', 'southwest', 'Box', 'off');
box(ax, 'off');

outFile = fullfile(figuresPath, sprintf('iccComparison_BetaVsJerk_%s.png', timestamp));
exportgraphics(fig, outFile, 'Resolution', 300);
fprintf('Saved: %s\n', outFile);
close(fig);
end


function betaVsTheoryPanel(thetaTable, figuresPath, timestamp)
templated = thetaTable(~isnan(thetaTable.Theoretical), :);
[~, ord] = sort(templated.Phi);
templated = templated(ord, :);
nShapes = height(templated);

fig = figure('Position', [100 100 700 480], 'Color', 'w');
ax = axes(fig); hold(ax, 'on');

x = (1:nShapes)';
w = 0.18;
colTheory = [0.6 0.6 0.6];
colObs = [0.20 0.35 0.65];

bar(ax, x-w, templated.Theoretical, 0.32, 'FaceColor', colTheory, 'EdgeColor', 'none');
bar(ax, x+w, templated.Beta_SG6_IRLS_mean, 0.32, 'FaceColor', colObs, 'EdgeColor', 'none');
errorbar(ax, x+w, templated.Beta_SG6_IRLS_mean, templated.Beta_SG6_IRLS_SD, templated.Beta_SG6_IRLS_SD, ...
    'k.', 'LineWidth', 1.1, 'CapSize', 5);

for s = 1:nShapes
    text(ax, x(s)+w, templated.Beta_SG6_IRLS_mean(s) + templated.Beta_SG6_IRLS_SD(s) + 0.02, ...
        sprintf('%.0f%%', templated.PctOfTheory_SG6IRLS(s)), 'HorizontalAlignment', 'center', 'FontSize', 9);
end

set(ax, 'XTick', x, 'XTickLabel', templated.ShapeName, 'XLim', [0.5 nShapes+0.5]);
ylabel(ax, 'Beta (velocity-curvature exponent)');
title(ax, 'Observed beta vs Huh & Sejnowski (2015) theoretical prediction');
legend(ax, {'Theoretical (H&S 2015)', 'Observed, SG6+IRLS (+/-1 SD)'}, 'Location', 'northeast', 'Box', 'off');
box(ax, 'off');

outFile = fullfile(figuresPath, sprintf('betaVsTheory_%s.png', timestamp));
exportgraphics(fig, outFile, 'Resolution', 300);
fprintf('Saved: %s\n', outFile);
close(fig);
end


function powerAnalysisPanel(powerTable, figuresPath, timestamp, nAchieved)
shapes = shapeOrder2026();
nShapes = length(shapes);

nRequired = nan(nShapes, 1);
isIntractable = false(nShapes, 1);
for s = 1:nShapes
    row = powerTable(strcmp(powerTable.ShapeName, shapes{s}), :);
    if isnumeric(row.N_required) && ~isnan(row.N_required)
        nRequired(s) = row.N_required;
    else
        isIntractable(s) = true;
    end
end

fig = figure('Position', [100 100 700 480], 'Color', 'w');
ax = axes(fig); hold(ax, 'on');

colReady = [0.30 0.60 0.35];
colNotReady = [0.80 0.35 0.25];
colIntractable = [0.6 0.6 0.6];

for s = 1:nShapes
    if isIntractable(s)
        barVal = 5; barColor = colIntractable;
    else
        barVal = nRequired(s);
        if nRequired(s) <= nAchieved
            barColor = colReady;
        else
            barColor = colNotReady;
        end
    end
    bar(ax, s, barVal, 0.6, 'FaceColor', barColor, 'EdgeColor', 'none', 'BaseValue', 1);
    if isIntractable(s)
        text(ax, s, barVal * 1.15, 'intractable', 'HorizontalAlignment', 'left', 'FontSize', 8, 'Rotation', 90);
    else
        text(ax, s, barVal * 1.12, sprintf('N=%d', nRequired(s)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 9);
    end
end

yline(ax, nAchieved, 'k--', sprintf('N achieved = %d', nAchieved), 'LineWidth', 1.2, 'LabelHorizontalAlignment', 'left');

% Log scale so every N required stays visible (e.g. Ellipse needs hundreds), limits from the data
yTop = 10^ceil(log10(max([nRequired; nAchieved], [], 'omitnan') * 2));
set(ax, 'XTick', 1:nShapes, 'XTickLabel', shapes, 'XLim', [0.3 nShapes+0.7], 'YScale', 'log', 'YLim', [1 yTop]);
ylabel(ax, 'N required for 80% power (Zou 2012, absolute agreement)');
title(ax, 'Confirmatory readiness by shape: Beta SG6+IRLS');
box(ax, 'off');

outFile = fullfile(figuresPath, sprintf('powerAnalysis_NrequiredVsAchieved_%s.png', timestamp));
exportgraphics(fig, outFile, 'Resolution', 300);
fprintf('Saved: %s\n', outFile);
close(fig);
end
