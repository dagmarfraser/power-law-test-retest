function generateDayFigures_2026(options)
% GENERATEDAYFIGURES_2026 - Day 1 vs Day 2 visualisation of the student
% dataset: mean/median/peak velocity, acceleration and jerk, plus the
% power-law exponent beta, and the two between-visit ICCs for each.
%
% Companion to generateFigures_2026.m (which covers the confirmatory
% ICC/theory/power panels). This one reads the trial-level student
% dataset exported by exportStudentDataset_2026.m, so it shows the raw
% per-trial distributions rather than pre-aggregated summaries.
%
%   1. dayComparison_Measures_*.png
%      Beta (full-width top panel, with the 1/3 Lacquaniti reference)
%      over a 3x3 grid of {Velocity, Acceleration, Jerk} x {Mean, Median,
%      Peak}. Per shape: split violin of the per-trial distribution
%      (day 1 left half, day 2 right half), per-participant visit means
%      as paired dots joined across days, and a median diamond per day.
%
%   2. dayICC_Heatmap_*.png
%      Between-visit ICC for all 10 measures x 5 shapes. Cell colour and
%      the large number are ICC(A,1) absolute agreement, banded per Koo &
%      Li (2016); the small value beneath is ICC(3,1) consistency.
%
% USAGE:
%   generateDayFigures_2026()
%   generateDayFigures_2026('dataFile', 'path.csv', 'Filter', 'BW')
%
% Defaults to the most recent StudentDataset_2026_*.csv in
% data/processed/. Figures are written to figures/ as timestamped PNGs
% (300 dpi).
%
% NOTE: absolute kinematic magnitudes use the provisional px-to-mm
% calibration flagged in docs/EmailIngestionPipeline.md (Known Issues).
% Fine for the reliability comparison this figure makes; verify the
% calibration before quoting absolute values.

arguments
    options.dataFile string = ""
    options.Filter (1,:) char {mustBeMember(options.Filter, {'SG', 'BW'})} = 'SG'
    options.BetaParam (1,:) char = 'Beta_SG6_IRLS'
end

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));
processedPath = fullfile(projectRoot, 'data', 'processed');
figuresPath = fullfile(projectRoot, 'figures');

if ~isfolder(figuresPath)
    mkdir(figuresPath);
end

dataFile = resolveLatestFile(options.dataFile, processedPath, 'StudentDataset_2026_2*.csv');
fprintf('Student dataset: %s\n', dataFile);

trialData = readtable(dataFile, 'VariableNamingRule', 'preserve');

[measureCols, measureLabels] = measureList(options.Filter, options.BetaParam);
requireColumns(trialData, [{'ParticipantID', 'Visit', 'ShapeName'}, measureCols]);

visitData = buildVisitMeans(trialData, measureCols);
reportVisitCoverage(visitData);

timestamp = datestr(now, 'yyyymmdd_HHMMSS');

measuresPanel(trialData, visitData, measureCols, measureLabels, options, figuresPath, timestamp);
iccHeatmapPanel(visitData, measureCols, measureLabels, figuresPath, timestamp);

end


% ---------------------------------------------------------------------
% Data preparation
% ---------------------------------------------------------------------

function f = resolveLatestFile(explicit, processedPath, pattern)
if explicit ~= ""
    f = explicit;
    return;
end
files = dir(fullfile(processedPath, pattern));
if isempty(files)
    error('generateDayFigures_2026:noMatch', 'No files matching %s found in %s', pattern, processedPath);
end
[~, idx] = max([files.datenum]);
f = fullfile(processedPath, files(idx).name);
end


function shapeOrder = shapeOrder2026()
shapeOrder = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
end


function [cols, labels] = measureList(filt, betaParam)
% Beta stays on the pre-specified confirmatory pipeline regardless of
% which filter the kinematics use; the two are reported together but are
% not the same choice.
cols = {betaParam, ...
    ['MeanVelocity_' filt], ['MedianVelocity_' filt], ['PeakVelocity_' filt], ...
    ['MeanAcceleration_' filt], ['MedianAcceleration_' filt], ['PeakAcceleration_' filt], ...
    ['MeanJerk_' filt], ['MedianJerk_' filt], ['PeakJerk_' filt]};
labels = {strrep(betaParam, '_', ' '), ...
    'Mean Velocity', 'Median Velocity', 'Peak Velocity', ...
    'Mean Accel', 'Median Accel', 'Peak Accel', ...
    'Mean Jerk', 'Median Jerk', 'Peak Jerk'};
end


function requireColumns(tbl, needed)
missing = needed(~ismember(needed, tbl.Properties.VariableNames));
if ~isempty(missing)
    error('generateDayFigures_2026:missingColumns', ...
        'Dataset is missing required column(s): %s', strjoin(missing, ', '));
end
end


function visitData = buildVisitMeans(trialData, measureCols)
% One row per participant x visit x shape: the mean across that visit's
% trials. NaN trials are excluded per measure (omitnan) rather than
% dropping the whole row.
visitData = groupsummary(trialData, {'ParticipantID', 'Visit', 'ShapeName'}, ...
    'mean', measureCols);
for m = 1:length(measureCols)
    visitData.(measureCols{m}) = visitData.(['mean_' measureCols{m}]);
end
end


function reportVisitCoverage(visitData)
% Fail loud on incomplete visit coverage: the between-visit ICC silently
% drops these participants, so say so here rather than let N shrink
% unannounced.
participants = unique(visitData.ParticipantID);
nBoth = 0;
incomplete = [];
for p = 1:length(participants)
    visits = unique(visitData.Visit(visitData.ParticipantID == participants(p)));
    if isequal(sort(visits(:))', [1 2])
        nBoth = nBoth + 1;
    else
        incomplete(end+1) = participants(p); %#ok<AGROW>
    end
end
fprintf('Participants with both visits: %d of %d\n', nBoth, length(participants));
if ~isempty(incomplete)
    warning('generateDayFigures_2026:incompleteVisits', ...
        'Participant(s) without both visits, excluded from ICC: %s', ...
        strjoin(string(incomplete), ', '));
end
end


% ---------------------------------------------------------------------
% Figure 1: day 1 vs day 2 measures
% ---------------------------------------------------------------------

function measuresPanel(trialData, visitData, measureCols, measureLabels, options, figuresPath, timestamp)
% Units are mm/s, mm/s^2, mm/s^3: runAnalysis_2026 divides the trajectory by
% pxPerMm BEFORE differentiating, so these are millimetre units, not pixels.
% (An earlier draft of this figure mislabelled them px/s.)
yUnits = {'', 'mm/s', 'mm/s', 'mm/s', 'mm/s^2', 'mm/s^2', 'mm/s^2', 'mm/s^3', 'mm/s^3', 'mm/s^3'};

fig = figure('Position', [100 100 1360 1240], 'Color', 'w');
t = tiledlayout(fig, 4, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

% Beta spans the full top row
ax = nexttile(t, [1 3]);
splitViolinPanel(ax, trialData, visitData, measureCols{1}, measureLabels{1}, 'beta', true);
ylim(ax, [-0.05 0.8]);

for m = 2:10
    ax = nexttile(t);
    splitViolinPanel(ax, trialData, visitData, measureCols{m}, measureLabels{m}, yUnits{m}, false);
end

title(t, sprintf('Analysis_2026 | Day 1 vs Day 2 | kinematics (%s) and power-law beta', options.Filter), ...
    'FontWeight', 'bold', 'FontSize', 15, 'Interpreter', 'none');
subtitle(t, ['Split violin = per-trial distribution (day 1 left / day 2 right). ' ...
    'Open dots = day 1, filled = day 2, line joins the same participant. Diamond = median.'], ...
    'FontSize', 9, 'Interpreter', 'none');

outFile = fullfile(figuresPath, sprintf('dayComparison_Measures_%s.png', timestamp));
exportgraphics(fig, outFile, 'Resolution', 300);
fprintf('Saved: %s\n', outFile);
close(fig);
end


function splitViolinPanel(ax, trialData, visitData, param, label, yUnit, isBeta)
shapes = shapeOrder2026();
cols = shapeColours();
hold(ax, 'on');

for s = 1:length(shapes)
    c = cols(s,:);
    cLight = c + (1 - c)*0.5;

    isShape = strcmp(trialData.ShapeName, shapes{s});
    for v = 1:2
        vals = trialData.(param)(isShape & trialData.Visit == v);
        if v == 1
            halfViolin(ax, vals, s, cLight, 'left', 0.75);
        else
            halfViolin(ax, vals, s, c, 'right', 0.30);
        end
    end

    [d1, d2] = pairedVisitMeans(visitData, shapes{s}, param);
    if isempty(d1)
        continue;
    end
    x1 = repmat(s-0.30, size(d1));
    x2 = repmat(s+0.30, size(d2));

    plot(ax, [x1 x2]', [d1 d2]', 'Color', [c 0.28], 'LineWidth', 0.7);
    scatter(ax, x1, d1, 13, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', c, 'LineWidth', 0.9);
    scatter(ax, x2, d2, 13, 'MarkerFaceColor', c, 'MarkerEdgeColor', 'w', 'LineWidth', 0.4);
    scatter(ax, s-0.30, median(d1), 70, 'd', 'MarkerFaceColor', 'w', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 1.4);
    scatter(ax, s+0.30, median(d2), 70, 'd', 'MarkerFaceColor', 'k', ...
        'MarkerEdgeColor', 'w', 'LineWidth', 1.0);
end

if isBeta
    yline(ax, 1/3, '--', '1/3 (Lacquaniti)', 'Color', [0.2 0.2 0.2], ...
        'LineWidth', 1.2, 'FontSize', 8, 'LabelHorizontalAlignment', 'right');
    ylabel(ax, 'beta');
elseif ~isempty(yUnit)
    ylabel(ax, yUnit);
end

set(ax, 'XTick', 1:length(shapes), 'XTickLabel', shapes, 'XLim', [0.3 length(shapes)+0.75], ...
    'FontSize', 8.5, 'TickLabelInterpreter', 'none');
title(ax, label, 'FontSize', 10.5, 'Interpreter', 'none');
grid(ax, 'on');
ax.YGrid = 'on';
ax.XGrid = 'off';
box(ax, 'off');
end


function halfViolin(ax, vals, centre, colour, side, alpha)
[xs, dens] = kdeProfile(vals, 120);
if isempty(xs)
    return;
end
w = 0.38 * dens / max(dens);
if strcmp(side, 'left')
    xPatch = centre - w;
else
    xPatch = centre + w;
end
patch(ax, [repmat(centre, 1, numel(xs)) fliplr(xPatch)], [xs fliplr(xs)], colour, ...
    'FaceAlpha', alpha, 'EdgeColor', 'none');
end


function [xs, dens] = kdeProfile(vals, nGrid)
% Gaussian KDE with a Silverman rule-of-thumb bandwidth. Written out
% rather than calling ksdensity/violinplot so the figure has no toolbox
% dependency beyond what computeICC already needs.
vals = vals(~isnan(vals));
vals = vals(:);
n = numel(vals);
if n < 2 || std(vals) <= 0
    xs = [];
    dens = [];
    return;
end
bw = 1.06 * std(vals) * n^(-1/5);
xs = linspace(min(vals) - 3*bw, max(vals) + 3*bw, nGrid);
dens = mean(exp(-0.5*((xs - vals)/bw).^2), 1) / (bw*sqrt(2*pi));
end


function [d1, d2] = pairedVisitMeans(visitData, shapeName, param)
% Participants with a value at both visits, in matched order.
isShape = strcmp(visitData.ShapeName, shapeName);
sub = visitData(isShape, :);
participants = unique(sub.ParticipantID);
d1 = [];
d2 = [];
for p = 1:length(participants)
    v1 = sub.(param)(sub.ParticipantID == participants(p) & sub.Visit == 1);
    v2 = sub.(param)(sub.ParticipantID == participants(p) & sub.Visit == 2);
    if isscalar(v1) && isscalar(v2) && ~isnan(v1) && ~isnan(v2)
        d1(end+1,1) = v1; %#ok<AGROW>
        d2(end+1,1) = v2; %#ok<AGROW>
    end
end
end


% ---------------------------------------------------------------------
% Figure 2: ICC heatmap
% ---------------------------------------------------------------------

function iccHeatmapPanel(visitData, measureCols, measureLabels, figuresPath, timestamp)
shapes = shapeOrder2026();
nM = length(measureCols);
nS = length(shapes);

iccA = nan(nM, nS);
iccC = nan(nM, nS);
for m = 1:nM
    for s = 1:nS
        sub = visitData(strcmp(visitData.ShapeName, shapes{s}), :);
        allP = unique(sub.ParticipantID);
        rA = computeICCFromLongTable(sub, measureCols{m}, allP, 'Visit', 'absolute');
        rC = computeICCFromLongTable(sub, measureCols{m}, allP, 'Visit', 'consistency');
        iccA(m,s) = rA.icc;
        iccC(m,s) = rC.icc;
    end
end

fig = figure('Position', [100 100 920 1100], 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');

bandCols = [0.90 0.22 0.27; 0.96 0.64 0.38; 0.56 0.79 0.90; 0.16 0.62 0.56];
for m = 1:nM
    for s = 1:nS
        cellCol = bandCols(kooLiBand(iccA(m,s)), :);
        rectangle(ax, 'Position', [s-0.5 m-0.5 1 1], 'FaceColor', cellCol, ...
            'EdgeColor', 'w', 'LineWidth', 2);
        if iccA(m,s) < 0.5
            txtCol = [1 1 1];
        else
            txtCol = [0.13 0.13 0.23];
        end
        text(ax, s, m-0.13, sprintf('%.2f', iccA(m,s)), 'HorizontalAlignment', 'center', ...
            'FontSize', 11.5, 'FontWeight', 'bold', 'Color', txtCol);
        text(ax, s, m+0.22, sprintf('C %.2f', iccC(m,s)), 'HorizontalAlignment', 'center', ...
            'FontSize', 7.5, 'Color', txtCol);
    end
end

% Separate beta (row 1) from the kinematic measures
plot(ax, [0.5 nS+0.5], [1.5 1.5], 'k-', 'LineWidth', 2);

set(ax, 'YDir', 'reverse', 'XTick', 1:nS, 'XTickLabel', shapes, ...
    'YTick', 1:nM, 'YTickLabel', measureLabels, 'TickLabelInterpreter', 'none', ...
    'XLim', [0.5 nS+0.5], 'YLim', [0.5 nM+0.5], 'FontSize', 10.5, 'TickLength', [0 0]);
title(ax, {'Analysis\_2026 | Between-visit test-retest reliability', ...
    'large = ICC(A,1) absolute agreement | small = ICC(3,1) consistency'}, 'FontSize', 13);

% Koo & Li band legend
bandLabels = {'Poor <0.50', 'Moderate 0.50-0.75', 'Good 0.75-0.90', 'Excellent >=0.90'};
h = gobjects(1,4);
for b = 1:4
    h(b) = patch(ax, NaN, NaN, bandCols(b,:), 'EdgeColor', 'none');
end
legend(ax, h, bandLabels, 'Location', 'southoutside', 'Orientation', 'horizontal', ...
    'Box', 'off', 'FontSize', 9);

outFile = fullfile(figuresPath, sprintf('dayICC_Heatmap_%s.png', timestamp));
exportgraphics(fig, outFile, 'Resolution', 300);
fprintf('Saved: %s\n', outFile);
close(fig);
end


function b = kooLiBand(icc)
% Koo & Li (2016) bands. NaN is not silently binned: it fails loud.
if isnan(icc)
    error('generateDayFigures_2026:nanICC', '%s', 'ICC returned NaN -- check visit coverage for this measure/shape');
end
if icc < 0.5
    b = 1;
elseif icc < 0.75
    b = 2;
elseif icc < 0.9
    b = 3;
else
    b = 4;
end
end


function cols = shapeColours()
cols = [0.165 0.616 0.561;   % phi=0.4
        0.271 0.482 0.616;   % phi=0.8
        0.906 0.435 0.318;   % Ellipse
        0.514 0.220 0.925;   % Square
        0.690 0.541 0.408];  % Cursive
end
