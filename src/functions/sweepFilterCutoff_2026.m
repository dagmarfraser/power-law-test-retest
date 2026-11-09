function [sweepTable, sgRef] = sweepFilterCutoff_2026(options)
% SWEEPFILTERCUTOFF_2026 - Butterworth corner-frequency sweep for beta
%
% Recomputes the velocity-curvature power-law exponent across a range of
% low-pass corner frequencies (fc), per shape, on real 2026 cohort data.
% Standalone: it does not touch the confirmatory pipeline and writes only
% its own timestamped outputs.
%
% WHY THIS EXISTS
%
% Beta's absolute magnitude is not a property of the movement alone; it is
% a joint property of the movement and the filter. Schaal and Sternad (2001)
% showed that passing a NON-law-compliant ellipse (generated with beta = 0,
% i.e. constant tangential velocity) through a 4th order low-pass
% Butterworth manufactures a spurious beta of one-third. Fraser et al.
% (2025) reproduced that on synthetic data (their Fig 6) and concluded the
% legacy 4th order Butterworth "must be avoided in the analysis", which is
% why Analysis_2026's pre-specified confirmatory pipeline is SG6+IRLS and
% the BW columns are retained only as a legacy comparator.
%
% This function reproduces that finding on REAL data, and quantifies how far
% beta moves for a given shape purely as a function of fc. Observed on ID104
% (4th order, single pass): phi=0.4 ranges 0.150 (40 Hz) to 0.436 (1.5 Hz),
% and at 4 Hz both phi=0.4 and phi=0.8 land on ~0.333 despite theoretical
% values of 0.620 and 0.528 -- spurious one-third for shapes that should not
% have it. Meanwhile Ellipse, whose theory IS one-third, never reaches it.
%
% CHOOSING fc IS NOT FREE. Cutoffs in the literature span two orders of
% magnitude: ~10 Hz is the field default (2nd order zero-lag, hence 4th
% order effective); Schaal and Sternad used 2.5 Hz; Fraser et al. (2025)
% footnote 2 reports 0.07 Hz in Zago et al. (2016) and Zarandi et al.
% (2023). On this cohort 0.07 Hz is deep in the artifact regime: every shape
% reads 0.58-0.75 regardless of its theoretical value, i.e. the filter has
% become shape-blind and you are measuring the Butterworth, not the hand.
%
% The principled anchor is the SIGNAL BAND, not the theory agreement.
% Measured on this cohort, the four templated shapes are spectrally
% identical (F50 0.94 Hz, F95 1.88 Hz); Cursive is broadband (F50 3.75 Hz,
% F95 6.56 Hz). So no single fc suits all five shapes: 2.5 Hz sits just
% above the templated band but would cut into Cursive's real signal, while
% 10 Hz is ~5x the templated band and admits mostly noise. Selecting fc
% because it reproduces the expected answer is precisely the circularity
% Schaal and Sternad warn about; selecting it from the measured signal band
% is not.
%
% NOTE ON THE THEORY COLUMN. Huh and Sejnowski's (2015) predictions are not
% filter-free either: their experimental confirmation applies a bandpass
% centred on the TARGET angular frequency nu_o, exp(-5*nu_o*log2(nu/nu_o)^2)
% (their Materials and Methods), having first spline-fitted the profiles.
% The filter is thus parameterised by the very quantity whose predicted beta
% is under test, and they report the log-speed/log-curvature scatter became
% "sharper after filtering". Their Fig 8 goes further and frames beta(nu)
% itself as the frequency response of a linear low-pass filter. So
% "PctOfTheory" below compares two differently-filtered quantities and
% should be read as a rough orientation, not a measurement of agreement.
%
% INPUTS (name-value):
%   participantIDs - string array of IDs, or "all". Default "ID104".
%   cutoffs        - corner frequencies in Hz. Default spans 0.07 to 40.
%   filterOrder    - Butterworth order. Default 4 (Schaal and Sternad).
%   zeroLag        - false = single pass (Schaal and Sternad); true = filtfilt,
%                    which DOUBLES the effective order (4 -> 8). Default false.
%   regressType    - regressDataEBR code: 3=Linear (legacy), 5=IRLS. Default 3,
%                    since the legacy Linear+BW pairing is what the artifact
%                    literature is about.
%   saveResults    - write timestamped CSV to data/processed/. Default true.
%   makeFigure     - write 300 dpi PNG to figures/. Default true.
%
% OUTPUTS:
%   sweepTable - one row per shape x cutoff: Beta_mean, Beta_SD, N,
%                Theoretical, PctOfTheory
%   sgRef      - one row per shape: the SG6+IRLS confirmatory reference,
%                which is what the sweep should be judged against
%
% USAGE:
%   [sw, sg] = sweepFilterCutoff_2026();
%   sweepFilterCutoff_2026('participantIDs', "all", 'zeroLag', true);
%
% See docs/AnalysisPipeline.md ("Filter cutoff sweep").

arguments
    options.participantIDs (1,:) string = "ID104"
    options.cutoffs (1,:) double {mustBePositive} = [0.07 0.25 0.5 0.7 1 1.5 2 2.5 3 4 5 10 20 40]
    options.filterOrder (1,1) double {mustBeInteger, mustBePositive} = 4
    options.zeroLag (1,1) logical = false
    options.regressType (1,1) double {mustBeMember(options.regressType, [3 4 5])} = 3
    options.saveResults (1,1) logical = true
    options.makeFigure (1,1) logical = true
    options.verbose (1,1) logical = true
end

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));
rawPath = fullfile(projectRoot, 'data', 'raw', 'automatic');
processedPath = fullfile(projectRoot, 'data', 'processed');
figuresPath = fullfile(projectRoot, 'figures');

fs = 240;
pxPerMm = ipadPointsPerMm();   % UIKit points/mm, see ipadPointsPerMm.m
edgeClip = 50;
shapeNames = shapeOrderLocal();

pIDs = resolveParticipants(options.participantIDs, rawPath);
if options.verbose
    fprintf('Sweeping fc over %d cutoffs, %d participant(s), order %d, %s\n', ...
        numel(options.cutoffs), numel(pIDs), options.filterOrder, ...
        ternaryStr(options.zeroLag, 'filtfilt (effective order doubled)', 'single pass'));
end

theory = loadTheory(processedPath, shapeNames);

% Accumulate per-trial beta: rows = trials, cols = cutoffs, sliced by shape
betaByShape = cell(1, numel(shapeNames));
sgByShape = cell(1, numel(shapeNames));

for p = 1:numel(pIDs)
    [trialBeta, trialSG, trialShape] = sweepParticipant(fullfile(rawPath, pIDs(p)), ...
        options.cutoffs, options.filterOrder, options.zeroLag, options.regressType, ...
        fs, pxPerMm, edgeClip);
    for s = 1:numel(shapeNames)
        m = trialShape == s;
        betaByShape{s} = [betaByShape{s}; trialBeta(m, :)];
        sgByShape{s} = [sgByShape{s}; trialSG(m)];
    end
    if options.verbose
        fprintf('  %s done (%d trials)\n', pIDs(p), numel(trialShape));
    end
end

% Assemble output tables
rows = {};
for s = 1:numel(shapeNames)
    B = betaByShape{s};
    if isempty(B), continue; end
    for c = 1:numel(options.cutoffs)
        v = B(:, c);
        v = v(~isnan(v));
        pct = NaN;
        if ~isnan(theory(s)) && theory(s) ~= 0
            pct = 100 * mean(v) / theory(s);
        end
        rows(end+1, :) = {shapeNames{s}, options.cutoffs(c), mean(v), std(v), ...
            numel(v), theory(s), pct}; %#ok<AGROW>
    end
end
sweepTable = cell2table(rows, 'VariableNames', ...
    {'ShapeName', 'Cutoff_Hz', 'Beta_mean', 'Beta_SD', 'N', 'Theoretical', 'PctOfTheory'});

sgRows = {};
for s = 1:numel(shapeNames)
    v = sgByShape{s};
    v = v(~isnan(v));
    if isempty(v), continue; end
    sgRows(end+1, :) = {shapeNames{s}, mean(v), std(v), numel(v), theory(s)}; %#ok<AGROW>
end
sgRef = cell2table(sgRows, 'VariableNames', ...
    {'ShapeName', 'Beta_SG6_IRLS_mean', 'Beta_SG6_IRLS_SD', 'N', 'Theoretical'});

if options.verbose
    printSweep(sweepTable, sgRef, shapeNames, options.cutoffs);
end

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
if options.saveResults
    outFile = fullfile(processedPath, sprintf('filterCutoffSweep_%s.csv', timestamp));
    writetable(sweepTable, outFile);
    verifyHeader(outFile, sweepTable.Properties.VariableNames);
    fprintf('Saved: %s\n', outFile);
end
if options.makeFigure
    plotSweep(sweepTable, sgRef, shapeNames, options, figuresPath, timestamp);
end

end


% ---------------------------------------------------------------------

function s = ternaryStr(cond, a, b)
% MATLAB has no ternary operator; this is the project's usual stand-in.
if cond, s = a; else, s = b; end
end


function names = shapeOrderLocal()
names = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
end


function pIDs = resolveParticipants(spec, rawPath)
if isscalar(spec) && strcmpi(spec, "all")
    d = dir(fullfile(rawPath, 'ID*'));
    pIDs = string({d([d.isdir]).name});
else
    pIDs = spec;
end
missing = pIDs(~arrayfun(@(p) isfolder(fullfile(rawPath, p)), pIDs));
if ~isempty(missing)
    error('sweepFilterCutoff_2026:noSuchParticipant', '%s', ...
        ['No raw folder for: ' char(strjoin(missing, ', '))]);
end
end


function theory = loadTheory(processedPath, shapeNames)
% Read theoretical beta from the newest beta_vs_theory_*.csv rather than
% re-implementing the Huh & Sejnowski formula. A duplicated formula is a
% formula that can drift, and this one has been wrong before (see
% claude.md: a wrong theoretical-beta formula was caught and fixed).
% reportNoteEvidence_2026() writes that file.
f = dir(fullfile(processedPath, 'beta_vs_theory_2*.csv'));
if isempty(f)
    error('sweepFilterCutoff_2026:noTheory', '%s', ...
        ['No beta_vs_theory_*.csv in ' processedPath '. Run reportNoteEvidence_2026() first.']);
end
[~, i] = max([f.datenum]);
T = readtable(fullfile(f(i).folder, f(i).name), 'VariableNamingRule', 'preserve');
theory = nan(1, numel(shapeNames));
for s = 1:numel(shapeNames)
    r = T(strcmp(T.ShapeName, shapeNames{s}), :);
    if ~isempty(r)
        theory(s) = r.Theoretical(1);
    end
end
end


function [trialBeta, trialSG, trialShape] = sweepParticipant(pPath, cutoffs, order, zeroLag, regressType, fs, pxPerMm, edgeClip)
trialBeta = [];
trialSG = [];
trialShape = [];

enh = dir(fullfile(pPath, '*tracingSection-enhanced.csv'));
for k = 1:numel(enh)
    ef = fullfile(enh(k).folder, enh(k).name);
    mf = strrep(ef, '-enhanced.csv', '.csv');
    if ~isfile(mf)
        warning('sweepFilterCutoff_2026:noMeta', '%s', ['No metadata file for ' ef]);
        continue;
    end
    E = readtable(ef);
    M = readtable(mf);

    for r = 1:height(M)
        tr = M.trial(r);
        sh = M.tracingScene_object1_imageNumber(r);
        if sh < 1 || sh > 5, continue; end

        d = E(E.response_index == tr, :);
        d = pencilSamplesOnly(d);   % drop finger/palm samples (touch_type ~= 2)
        if height(d) <= 2*edgeClip + 100, continue; end
        d = d(edgeClip+1:end-edgeClip, :);

        x = d.x / pxPerMm;
        y = d.y / pxPerMm;
        strokeId = detectPenLifts(d.touch_index, d.time_seconds, fs);
        t = (1:height(d))' / fs;

        % SG6+IRLS reference via the confirmatory function itself, so the
        % comparator is the real pipeline rather than a re-implementation.
        ws = warning('off', 'all');
        ref = calculatePowerLaw(x, y, t, fs, strokeId);
        warning(ws);

        b = nan(1, numel(cutoffs));
        for c = 1:numel(cutoffs)
            b(c) = betaAtCutoff(x, y, strokeId, cutoffs(c), order, zeroLag, regressType, fs);
        end
        trialBeta(end+1, :) = b; %#ok<AGROW>
        trialSG(end+1, 1) = ref.Beta_SG6_IRLS; %#ok<AGROW>
        trialShape(end+1, 1) = sh; %#ok<AGROW>
    end
end
end


function verifyHeader(outFile, expectedNames)
% Guard against the FieldTrip/GPstuff join() shadowing bug that makes
% writetable emit an empty header with no error. See
% docs/AnalysisPipeline.md, environment hazard section.
fid = fopen(outFile, 'r');
if fid == -1, return; end
firstLine = fgetl(fid);
fclose(fid);
bad = ~ischar(firstLine) || isempty(strtrim(firstLine));
if ~bad
    parts = strsplit(firstLine, ',');
    bad = ~strcmp(strtrim(parts{1}), expectedNames{1});
end
if bad
    delete(outFile);
    error('sweepFilterCutoff_2026:badHeader', '%s', ...
        ['writetable wrote a missing/incorrect header, so the file was deleted. ' ...
         'Run  which join  -- if it resolves anywhere other than ' ...
         'toolbox/matlab/strfun/join.m (e.g. FieldTrip/GPstuff), rmpath that folder.']);
end
end


function printSweep(sweepTable, sgRef, shapeNames, cutoffs)
fprintf('\nBeta vs Butterworth corner frequency\n\n');
fprintf('%-9s%9s', 'shape', 'theory');
fprintf('%8s', "c" + string(cutoffs));
fprintf('%10s\n', 'SG6_IRLS');
for s = 1:numel(shapeNames)
    r = sweepTable(strcmp(sweepTable.ShapeName, shapeNames{s}), :);
    if isempty(r), continue; end
    g = sgRef(strcmp(sgRef.ShapeName, shapeNames{s}), :);
    fprintf('%-9s%9.3f', shapeNames{s}, r.Theoretical(1));
    for c = 1:numel(cutoffs)
        fprintf('%8.3f', r.Beta_mean(r.Cutoff_Hz == cutoffs(c)));
    end
    fprintf('%10.3f\n', g.Beta_SG6_IRLS_mean(1));
end
fprintf('\n(1/3 = 0.333)\n');
end


function plotSweep(sweepTable, sgRef, shapeNames, options, figuresPath, timestamp)
if ~isfolder(figuresPath), mkdir(figuresPath); end
cols = [0.165 0.616 0.561; 0.271 0.482 0.616; 0.906 0.435 0.318; ...
        0.514 0.220 0.925; 0.690 0.541 0.408];

fig = figure('Position', [100 100 1000 680], 'Color', 'w');
ax = axes(fig); hold(ax, 'on');

yline(ax, 1/3, '-', '1/3', 'Color', [0.2 0.2 0.2], 'LineWidth', 1.5, ...
    'Alpha', 0.6, 'LabelHorizontalAlignment', 'left', 'FontSize', 10);

h = gobjects(1, numel(shapeNames));
for s = 1:numel(shapeNames)
    r = sweepTable(strcmp(sweepTable.ShapeName, shapeNames{s}), :);
    if isempty(r), continue; end
    r = sortrows(r, 'Cutoff_Hz');
    h(s) = plot(ax, r.Cutoff_Hz, r.Beta_mean, '-o', 'Color', cols(s,:), ...
        'LineWidth', 1.8, 'MarkerSize', 4, 'MarkerFaceColor', cols(s,:));
    if ~isnan(r.Theoretical(1))
        yline(ax, r.Theoretical(1), '--', 'Color', [cols(s,:) 0.5], 'LineWidth', 1);
    end
    g = sgRef(strcmp(sgRef.ShapeName, shapeNames{s}), :);
    if ~isempty(g)
        plot(ax, xlim(ax), [g.Beta_SG6_IRLS_mean(1) g.Beta_SG6_IRLS_mean(1)], ':', ...
            'Color', [cols(s,:) 0.35], 'LineWidth', 1, 'HandleVisibility', 'off');
    end
end

set(ax, 'XScale', 'log', 'FontSize', 11, 'Box', 'off');
grid(ax, 'on'); ax.GridAlpha = 0.12;
xlabel(ax, 'Butterworth corner frequency (Hz, log scale)');
ylabel(ax, 'beta');
legend(ax, h(isgraphics(h)), shapeNames(isgraphics(h)), 'Location', 'best', ...
    'Box', 'off', 'Interpreter', 'none');
title(ax, {sprintf('Analysis_2026 | beta vs Butterworth cutoff (order %d, %s)', ...
    options.filterOrder, ternaryStr(options.zeroLag, 'filtfilt', 'single pass')), ...
    'dashed = Huh & Sejnowski theory per shape, dotted = SG6+IRLS confirmatory reference'}, ...
    'FontSize', 12, 'Interpreter', 'none');

outFile = fullfile(figuresPath, sprintf('filterCutoffSweep_%s.png', timestamp));
exportgraphics(fig, outFile, 'Resolution', 300);
fprintf('Saved: %s\n', outFile);
close(fig);
end
