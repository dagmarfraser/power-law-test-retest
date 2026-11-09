function [iccTable, validityTable] = iccVsCutoff_2026(options)
% ICCVSCUTOFF_2026 - Is beta's RELIABILITY robust to the filter cutoff?
%
% Standalone. Recomputes between-visit ICC(A,1) of beta at a range of
% Butterworth corner frequencies, per shape, and alongside it a validity
% measure (does beta still discriminate shape at that fc?). Writes only its
% own timestamped outputs; touches nothing in the confirmatory pipeline.
%
% WHY BOTH AXES
%
% sweepFilterCutoff_2026 showed beta's MAGNITUDE moves ~3x purely with fc.
% The confirmatory claim of this study is about RELIABILITY under a fixed
% pipeline, so the load-bearing question is whether ICC moves too. If
% reliability is fc-robust while magnitude slides, the pre-registration is
% untouched and the fc argument is confined to beta-vs-theory.
%
% But ICC alone must NOT be used to choose fc, and this project has the
% receipts. Before the pen-lift fix, Cursive peak velocity had ICC 0.86 --
% higher than most shapes -- because how far a person hops between letters
% is a stable personal habit. It was reliably measuring an artifact. A
% heavily over-filtered signal could likewise produce a high ICC if the
% filter's output tracks something stable-but-irrelevant (drawing tempo,
% say) while being blind to shape. At fc = 0.07 Hz the filter demonstrably
% IS shape-blind: every shape reads 0.57-0.73 regardless of its theoretical
% beta.
%
% So reliability and validity are separate axes and are reported separately:
%
%   Reliability - ICC(A,1) between visits, per shape, per fc.
%   Validity    - across the FOUR TEMPLATED shapes at each fc: Spearman rho
%                 between mean beta and Huh & Sejnowski's theoretical beta,
%                 plus the between-shape SD of mean beta. A filter that has
%                 gone shape-blind scores ~0 on both regardless of its ICC.
%                 Cursive is excluded from validity: it has no fixed
%                 template and hence no theoretical beta.
%
% EXPECTED SHAPE OF THE RESULT (stated in advance, so the data can refute it)
% ICC should PEAK at intermediate fc, not rise monotonically as filtering
% increases. Heavy filtering suppresses within-subject noise (raising ICC)
% but also suppresses between-subject differences (collapsing it), and ICC
% is their ratio. Cursive's peak should sit at a HIGHER fc than the
% templated shapes', because its signal band is wider (F95 6.56 Hz vs
% 1.88 Hz).
%
% INPUTS (name-value):
%   participantIDs - numeric IDs to include, or "all". Default "all".
%                    Subset for a quick check: the full 31-participant run
%                    is ~9,300 trials x nCutoffs regressions and takes
%                    minutes even under parfor, so smoke-test with two or
%                    three IDs first.
%   cutoffs      - corner frequencies (Hz). Default 9 points, 0.07 to 20.
%   filterOrder  - Butterworth order. Default 4 (Schaal & Sternad).
%   zeroLag      - false = single pass; true = filtfilt (doubles effective
%                  order). Default false.
%   regressType  - regressDataEBR code: 3=Linear, 4=LMLS, 5=IRLS. Default 5
%                  (IRLS, matching the pre-specified confirmatory method).
%   trialResults - path to a trial_level_results_*.csv. Default: newest.
%                  Used ONLY to resolve which sessions belong to which visit,
%                  by joining on SessionDatetime. runAnalysis_2026's
%                  visit-grouping has been wrong once before, so it is
%                  reused rather than re-implemented here.
%   useParfor    - parallelise over participants. Default true.
%
% OUTPUTS:
%   iccTable      - ShapeName x Cutoff_Hz: ICC, LB, UB, N, Beta_mean
%   validityTable - Cutoff_Hz: SpearmanRho vs theory, BetweenShapeSD, N shapes
%
% USAGE:
%   [icc, val] = iccVsCutoff_2026('participantIDs', [104 201], 'cutoffs', [2.5 10]);  % smoke test
%   [icc, val] = iccVsCutoff_2026();                                                   % full run
%   iccVsCutoff_2026('cutoffs', [1 2.5 10], 'useParfor', false);
%
% See docs/AnalysisPipeline.md ("Filter cutoff sweep").

arguments
    options.participantIDs = "all"
    options.cutoffs (1,:) double {mustBePositive} = [0.07 0.5 1 1.5 2.5 4 7 10 20]
    options.filterOrder (1,1) double {mustBeInteger, mustBePositive} = 4
    options.zeroLag (1,1) logical = false
    options.regressType (1,1) double {mustBeMember(options.regressType, [3 4 5])} = 5
    options.trialResults string = ""
    options.useParfor (1,1) logical = true
    options.saveResults (1,1) logical = true
    options.makeFigure (1,1) logical = true
end

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));
rawPath = fullfile(projectRoot, 'data', 'raw', 'automatic');
processedPath = fullfile(projectRoot, 'data', 'processed');
figuresPath = fullfile(projectRoot, 'figures');

fs = 240;
pxPerMm = ipadPointsPerMm();   % UIKit points/mm, see ipadPointsPerMm.m
edgeClip = 50;
shapeNames = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
cutoffs = options.cutoffs;

% Visit membership comes from the confirmatory results, joined on
% SessionDatetime. That file already has exactSessionsOnly applied, so the
% participant set here matches the confirmatory N by construction.
trialFile = resolveLatest(options.trialResults, processedPath, 'trial_level_results_2*.csv');
fprintf('Visit map from: %s\n', trialFile);
TR = readtable(trialFile, 'VariableNamingRule', 'preserve');
visitMap = unique(TR(:, {'ParticipantID', 'SessionDatetime', 'Visit'}), 'rows');
pIDs = unique(TR.ParticipantID);

% Optional subset, for smoke tests. Fail loud on an ID that is not in the
% confirmatory set rather than silently returning fewer participants.
if ~(isstring(options.participantIDs) || ischar(options.participantIDs)) ...
        || ~strcmpi(string(options.participantIDs), "all")
    want = double(options.participantIDs(:));
    missing = want(~ismember(want, pIDs));
    if ~isempty(missing)
        error('iccVsCutoff_2026:noSuchParticipant', '%s', ...
            ['Participant(s) not in the confirmatory set: ' ...
             char(strjoin(string(missing), ', '))]);
    end
    pIDs = want;
end

fprintf('Participants: %d, cutoffs: %d, order %d, %s, regress %d\n', ...
    numel(pIDs), numel(cutoffs), options.filterOrder, ...
    passName(options.zeroLag), options.regressType);

theory = loadTheory(processedPath, shapeNames);

% ---- per participant: beta per trial per cutoff, tagged with visit ----
nP = numel(pIDs);
out = cell(nP, 1);
cfg = struct('cutoffs', cutoffs, 'order', options.filterOrder, ...
    'zeroLag', options.zeroLag, 'regressType', options.regressType, ...
    'fs', fs, 'pxPerMm', pxPerMm, 'edgeClip', edgeClip);

t0 = tic;
if options.useParfor
    parfor p = 1:nP
        out{p} = oneParticipant(pIDs(p), rawPath, visitMap, cfg);
    end
else
    for p = 1:nP
        out{p} = oneParticipant(pIDs(p), rawPath, visitMap, cfg);
        fprintf('  %d/%d\n', p, nP);
    end
end
D = vertcat(out{:});
fprintf('Computed %d trial x cutoff betas in %.1f s\n', height(D)*numel(cutoffs), toc(t0));

% ---- ICC per shape per cutoff ----
rows = {};
for s = 1:numel(shapeNames)
    for c = 1:numel(cutoffs)
        M = pairedVisitMeans(D, s, c);
        if size(M, 1) < 3
            rows(end+1, :) = {shapeNames{s}, cutoffs(c), NaN, NaN, NaN, 0, NaN}; %#ok<AGROW>
            continue;
        end
        r = computeICC(M, 'absolute');
        rows(end+1, :) = {shapeNames{s}, cutoffs(c), r.icc, r.lb, r.ub, r.n, mean(M(:))}; %#ok<AGROW>
    end
end
iccTable = cell2table(rows, 'VariableNames', ...
    {'ShapeName', 'Cutoff_Hz', 'ICC', 'ICC_LB', 'ICC_UB', 'N', 'Beta_mean'});

% ---- validity per cutoff: does beta still discriminate shape? ----
vrows = {};
templated = 1:4;   % Cursive has no theoretical beta
for c = 1:numel(cutoffs)
    mb = nan(1, numel(templated));
    for s = templated
        r = iccTable(strcmp(iccTable.ShapeName, shapeNames{s}) & iccTable.Cutoff_Hz == cutoffs(c), :);
        mb(s) = r.Beta_mean(1);
    end
    ok = ~isnan(mb) & ~isnan(theory(templated));
    rho = NaN;
    if sum(ok) >= 3
        rho = corr(mb(ok)', theory(ok)', 'type', 'Spearman');
    end
    vrows(end+1, :) = {cutoffs(c), rho, std(mb(ok)), sum(ok)}; %#ok<AGROW>
end
validityTable = cell2table(vrows, 'VariableNames', ...
    {'Cutoff_Hz', 'SpearmanRho_vs_theory', 'BetweenShapeSD', 'NShapes'});

printResults(iccTable, validityTable, shapeNames, cutoffs);

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
if options.saveResults
    f1 = fullfile(processedPath, sprintf('iccVsCutoff_%s.csv', timestamp));
    writetable(iccTable, f1);
    verifyHeader(f1, iccTable.Properties.VariableNames);
    fprintf('Saved: %s\n', f1);
    f2 = fullfile(processedPath, sprintf('iccVsCutoff_validity_%s.csv', timestamp));
    writetable(validityTable, f2);
    verifyHeader(f2, validityTable.Properties.VariableNames);
    fprintf('Saved: %s\n', f2);
end
if options.makeFigure
    plotICCvsCutoff(iccTable, validityTable, shapeNames, options, figuresPath, timestamp);
end

end


% ---------------------------------------------------------------------

function s = passName(zeroLag)
if zeroLag, s = 'filtfilt (effective order doubled)'; else, s = 'single pass'; end
end


function f = resolveLatest(explicit, folder, pattern)
if strlength(explicit) > 0
    f = char(explicit);
    return;
end
d = dir(fullfile(folder, pattern));
if isempty(d)
    error('iccVsCutoff_2026:noMatch', '%s', ['No files matching ' pattern ' in ' folder]);
end
[~, i] = max([d.datenum]);
f = fullfile(d(i).folder, d(i).name);
end


function theory = loadTheory(processedPath, shapeNames)
% Read from beta_vs_theory_*.csv rather than duplicating the Huh &
% Sejnowski formula, which has been wrong once already.
d = dir(fullfile(processedPath, 'beta_vs_theory_2*.csv'));
if isempty(d)
    error('iccVsCutoff_2026:noTheory', '%s', ...
        'No beta_vs_theory_*.csv found. Run reportNoteEvidence_2026() first.');
end
[~, i] = max([d.datenum]);
T = readtable(fullfile(d(i).folder, d(i).name), 'VariableNamingRule', 'preserve');
theory = nan(1, numel(shapeNames));
for s = 1:numel(shapeNames)
    r = T(strcmp(T.ShapeName, shapeNames{s}), :);
    if ~isempty(r), theory(s) = r.Theoretical(1); end
end
end


function T = oneParticipant(pID, rawPath, visitMap, cfg)
% One row per trial: ParticipantID, Visit, ShapeType, and beta at each cutoff.
pFolder = fullfile(rawPath, sprintf('ID%d', pID));
T = table();
if ~isfolder(pFolder), return; end

vm = visitMap(visitMap.ParticipantID == pID, :);
enh = dir(fullfile(pFolder, '*tracingSection-enhanced.csv'));
nC = numel(cfg.cutoffs);

pid = []; vis = []; shp = []; bet = [];
for k = 1:numel(enh)
    ef = fullfile(enh(k).folder, enh(k).name);
    mf = strrep(ef, '-enhanced.csv', '.csv');
    if ~isfile(mf), continue; end

    % Session datetime is encoded in the filename; match it to the visit map
    % rather than re-deriving visit membership.
    dt = datetimeFromName(enh(k).name);
    if isnat(dt), continue; end
    hit = vm(abs(seconds(vm.SessionDatetime - dt)) < 2, :);
    if isempty(hit), continue; end   % session not in the confirmatory set
    thisVisit = hit.Visit(1);

    E = readtable(ef);
    M = readtable(mf);
    for r = 1:height(M)
        tr = M.trial(r);
        sh = M.tracingScene_object1_imageNumber(r);
        if sh < 1 || sh > 5, continue; end

        d = E(E.response_index == tr, :);
        d = pencilSamplesOnly(d);   % drop finger/palm samples (touch_type ~= 2)
        if height(d) <= 2*cfg.edgeClip + 100, continue; end
        d = d(cfg.edgeClip+1:end-cfg.edgeClip, :);

        x = d.x / cfg.pxPerMm;
        y = d.y / cfg.pxPerMm;
        sid = detectPenLifts(d.touch_index, d.time_seconds, cfg.fs);

        b = nan(1, nC);
        for c = 1:nC
            b(c) = betaAtCutoff(x, y, sid, cfg.cutoffs(c), cfg.order, ...
                cfg.zeroLag, cfg.regressType, cfg.fs);
        end
        pid(end+1,1) = pID; %#ok<AGROW>
        vis(end+1,1) = thisVisit; %#ok<AGROW>
        shp(end+1,1) = sh; %#ok<AGROW>
        bet(end+1,:) = b; %#ok<AGROW>
    end
end
if isempty(pid), return; end
T = table(pid, vis, shp, bet, 'VariableNames', {'ParticipantID','Visit','ShapeType','Beta'});
end


function dt = datetimeFromName(name)
% e.g. 'betaTestv002 2026-05-28 121220 tracingSection-enhanced.csv'
tok = regexp(name, '(\d{4}-\d{2}-\d{2})\s+(\d{6})', 'tokens', 'once');
if isempty(tok)
    dt = NaT;
    return;
end
dt = datetime([tok{1} ' ' tok{2}], 'InputFormat', 'yyyy-MM-dd HHmmss');
end


function M = pairedVisitMeans(D, shapeType, cutoffIdx)
% n x 2 of (visit1 mean, visit2 mean) for participants having both.
sub = D(D.ShapeType == shapeType, :);
b = sub.Beta(:, cutoffIdx);
keep = ~isnan(b);
sub = sub(keep, :);
b = b(keep);
if isempty(sub), M = zeros(0,2); return; end
pIDs = unique(sub.ParticipantID);
M = [];
for i = 1:numel(pIDs)
    m1 = mean(b(sub.ParticipantID == pIDs(i) & sub.Visit == 1));
    m2 = mean(b(sub.ParticipantID == pIDs(i) & sub.Visit == 2));
    if ~isnan(m1) && ~isnan(m2)
        M(end+1, :) = [m1 m2]; %#ok<AGROW>
    end
end
end


function verifyHeader(outFile, expectedNames)
fid = fopen(outFile, 'r');
if fid == -1, return; end
l1 = fgetl(fid);
fclose(fid);
bad = ~ischar(l1) || isempty(strtrim(l1));
if ~bad
    p = strsplit(l1, ',');
    bad = ~strcmp(strtrim(p{1}), expectedNames{1});
end
if bad
    delete(outFile);
    error('iccVsCutoff_2026:badHeader', '%s', ...
        ['writetable wrote a missing/incorrect header, so the file was deleted. ' ...
         'Check  which join  resolves to toolbox/matlab/strfun/join.m ' ...
         '(FieldTrip/GPstuff shadows it). See docs/AnalysisPipeline.md.']);
end
end


function printResults(iccTable, validityTable, shapeNames, cutoffs)
fprintf('\nRELIABILITY: between-visit ICC(A,1) of beta, by Butterworth cutoff\n\n');
fprintf('%-9s', 'shape'); fprintf('%8s', "c"+string(cutoffs)); fprintf('%10s\n', 'peak fc');
for s = 1:numel(shapeNames)
    r = iccTable(strcmp(iccTable.ShapeName, shapeNames{s}), :);
    if isempty(r), continue; end
    fprintf('%-9s', shapeNames{s});
    v = nan(1, numel(cutoffs));
    for c = 1:numel(cutoffs)
        v(c) = r.ICC(r.Cutoff_Hz == cutoffs(c));
        fprintf('%8.3f', v(c));
    end
    [~, i] = max(v);
    fprintf('%10.2f\n', cutoffs(i));
end
fprintf('\nVALIDITY: does beta still discriminate shape? (4 templated shapes)\n\n');
fprintf('%-22s', 'cutoff (Hz)'); fprintf('%8.2f', validityTable.Cutoff_Hz); fprintf('\n');
fprintf('%-22s', 'Spearman rho vs theory'); fprintf('%8.2f', validityTable.SpearmanRho_vs_theory); fprintf('\n');
fprintf('%-22s', 'between-shape SD'); fprintf('%8.3f', validityTable.BetweenShapeSD); fprintf('\n');
fprintf('\n(rho ~ 0 or SD ~ 0 = filter has gone shape-blind, regardless of ICC)\n');
end


function plotICCvsCutoff(iccTable, validityTable, shapeNames, options, figuresPath, timestamp)
if ~isfolder(figuresPath), mkdir(figuresPath); end
cols = [0.165 0.616 0.561; 0.271 0.482 0.616; 0.906 0.435 0.318; ...
        0.514 0.220 0.925; 0.690 0.541 0.408];

fig = figure('Position', [100 100 1000 900], 'Color', 'w');
t = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(t);
hold(ax1, 'on');
for b = [0.5 0.75 0.9]
    yline(ax1, b, ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8);
end
h = gobjects(1, numel(shapeNames));
for s = 1:numel(shapeNames)
    r = sortrows(iccTable(strcmp(iccTable.ShapeName, shapeNames{s}), :), 'Cutoff_Hz');
    if isempty(r), continue; end
    h(s) = plot(ax1, r.Cutoff_Hz, r.ICC, '-o', 'Color', cols(s,:), 'LineWidth', 1.8, ...
        'MarkerSize', 4, 'MarkerFaceColor', cols(s,:));
end
set(ax1, 'XScale', 'log', 'FontSize', 11, 'Box', 'off');
grid(ax1, 'on'); ax1.GridAlpha = 0.12;
ylabel(ax1, 'between-visit ICC(A,1)');
legend(ax1, h(isgraphics(h)), shapeNames(isgraphics(h)), 'Location', 'best', ...
    'Box', 'off', 'Interpreter', 'none');
title(ax1, 'RELIABILITY: is beta reproducible at this cutoff?', 'Interpreter', 'none');

ax2 = nexttile(t);
yyaxis(ax2, 'left');
plot(ax2, validityTable.Cutoff_Hz, validityTable.SpearmanRho_vs_theory, '-o', ...
    'LineWidth', 1.8, 'MarkerSize', 4);
ylabel(ax2, 'Spearman rho vs theory');
ylim(ax2, [-1.05 1.05]);
yyaxis(ax2, 'right');
plot(ax2, validityTable.Cutoff_Hz, validityTable.BetweenShapeSD, '-s', ...
    'LineWidth', 1.8, 'MarkerSize', 4);
ylabel(ax2, 'between-shape SD of beta');
set(ax2, 'XScale', 'log', 'FontSize', 11, 'Box', 'off');
grid(ax2, 'on'); ax2.GridAlpha = 0.12;
xlabel(ax2, 'Butterworth corner frequency (Hz, log scale)');
title(ax2, 'VALIDITY: does beta still discriminate shape? (0 = shape-blind)', 'Interpreter', 'none');

title(t, sprintf('Analysis_2026 | reliability and validity vs filter cutoff (order %d, %s, regress %d)', ...
    options.filterOrder, passName(options.zeroLag), options.regressType), ...
    'FontWeight', 'bold', 'Interpreter', 'none');

outFile = fullfile(figuresPath, sprintf('iccVsCutoff_%s.png', timestamp));
exportgraphics(fig, outFile, 'Resolution', 300);
fprintf('Saved: %s\n', outFile);
close(fig);
end
