function outFile = exportHandoverDataset_2026(options)
% EXPORTHANDOVERDATASET_2026 - Confirmatory-pipeline-only CSV for handover
%
% Same source and row structure as exportStudentDataset_2026, but the
% pipeline columns are restricted to Beta_SG6_IRLS / VGF_SG6_IRLS /
% FitCorr_SG6_IRLS only (the pre-specified confirmatory pipeline). The
% other five pipelines (BW_Linear, BW_LMLS, BW_IRLS, SG6_Linear,
% SG6_LMLS) are omitted -- students on the handover don't need the
% method-comparison detail, just the one number the study is built on.
%
% Written to a new top-level `handover/` folder, sibling to Analysis_2026,
% not into data/processed/ -- kept separate from the internal working
% dataset so it can be handed over cleanly on its own.
%
% USAGE:
%   exportHandoverDataset_2026()
%   exportHandoverDataset_2026('trialFile', 'path/to/trial_level_results.csv')
%
% OUTPUTS:
%   Writes <projectRoot>/../handover/StudentDataset_2026_SG6IRLS_{timestamp}.csv
%   Writes <projectRoot>/../handover/StudentDataset_2026_SG6IRLS_{timestamp}_README.md
%   Returns the CSV path.
%
% NOTE: the README's "Demo figures" section references
% handover/function/generateDayFigures_2026.m, computeICC.m and
% computeICCFromLongTable.m. This function does not create or copy those
% -- if handover/function/ doesn't exist yet, copy them there separately
% (portable versions, not the src/functions/ originals -- see
% Analysis_2026 claude.md Corrections log, 2026-07-17) before handing
% this over, or the README will reference files that aren't there.
%
% d.s.fraser@bham.ac.uk

arguments
    options.trialFile string = ""
end

guardAgainstJoinShadow();

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));
processedPath = fullfile(projectRoot, 'data', 'processed');
handoverPath = fullfile(fileparts(projectRoot), 'handover');
if ~isfolder(handoverPath)
    mkdir(handoverPath);
end

trialFile = resolveLatestFile(options.trialFile, processedPath, 'trial_level_results_2*.csv');
fprintf('Source: %s\n', trialFile);

opts = detectImportOptions(trialFile, 'VariableNamingRule', 'preserve');
allResults = readtable(trialFile, opts);

%% Fail loud: confirm all expected columns are present before reshaping
requiredCols = {'ParticipantID', 'Visit', 'Session', 'SessionInVisit', 'TrialNum', 'ShapeType', ...
    'MedianVelocity_BW', 'MedianVelocity_SG'};
missing = requiredCols(~ismember(requiredCols, allResults.Properties.VariableNames));
if ~isempty(missing)
    error('exportHandoverDataset_2026:missingColumns', '%s', ...
        ['Source file is missing expected column(s): ' strjoin(missing, ', ') ...
        '. Re-run runAnalysis_2026 to regenerate.']);
end

%% Shape name lookup (ShapeType 1-5, see reportNoteEvidence_2026.m for same mapping)
shapeNames = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
allResults.ShapeName = shapeNames(allResults.ShapeType)';

%% Column order: identifiers, shape, confirmatory pipeline only, then kinematics, then metadata
idCols = {'ParticipantID', 'Visit', 'Session', 'SessionInVisit', 'TrialNum', 'ShapeType', 'ShapeName', 'SessionDatetime'};
confirmatoryCols = {'Beta_SG6_IRLS', 'VGF_SG6_IRLS', 'FitCorr_SG6_IRLS'};

kinematicMetrics = {'Velocity', 'Acceleration', 'Jerk'};
kinematicStats = {'Mean', 'Median', 'Peak'};
kinematicCols = {};
for filt = {'BW', 'SG'}
    for k = 1:length(kinematicMetrics)
        for s = 1:length(kinematicStats)
            kinematicCols = [kinematicCols, {sprintf('%s%s_%s', kinematicStats{s}, kinematicMetrics{k}, filt{1})}]; %#ok<AGROW>
        end
        if strcmp(kinematicMetrics{k}, 'Jerk')
            kinematicCols = [kinematicCols, {sprintf('StdJerk_%s', filt{1})}]; %#ok<AGROW>
        end
    end
end

metaCols = {'NumPoints', 'NumPoints_Regress_BW', 'NumPoints_Regress_SG6', 'SamplingFrequency', ...
    'Duration', 'DurationElapsed', 'PathLength_mm', 'NumStrokes', 'NumLifts', 'NumSamplesDropped'};

colOrder = [idCols, confirmatoryCols, kinematicCols, metaCols];
missingOut = colOrder(~ismember(colOrder, allResults.Properties.VariableNames));
if ~isempty(missingOut)
    error('exportHandoverDataset_2026:columnOrderMismatch', '%s', ...
        ['Expected output column(s) not found in source table: ' strjoin(missingOut, ', ')]);
end

studentTable = allResults(:, colOrder);
studentTable = sortrows(studentTable, {'ParticipantID', 'Visit', 'SessionInVisit', 'ShapeType', 'TrialNum'});

%% Save
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
outFile = fullfile(handoverPath, sprintf('StudentDataset_2026_SG6IRLS_%s.csv', timestamp));
writetable(studentTable, outFile);
verifyHeaderWritten(outFile, studentTable.Properties.VariableNames);
fprintf('Saved: %s (%d rows, %d columns)\n', outFile, height(studentTable), width(studentTable));

readmeFile = fullfile(handoverPath, sprintf('StudentDataset_2026_SG6IRLS_%s_README.md', timestamp));
writeReadme(readmeFile, outFile, shapeNames);
fprintf('Saved: %s\n', readmeFile);

end


function guardAgainstJoinShadow()
% GUARDAGAINSTJOINSHADOW - Self-heal the FieldTrip/GPstuff join.m shadow.
%
% FieldTrip's own init (ft_defaults) path-adds external/dmlt/external/
% gpstuff/diag on every MATLAB startup, whose join.m shadows the builtin
% toolbox/matlab/strfun/join.m that writetable depends on -- causing a
% silent headerless CSV (see Corrections log, 2026-07-16). This recurs
% every session regardless of manual rmpath, so fix it here rather than
% relying on remembering to do it by hand.
badJoin = which('join');
if ~isempty(badJoin) && ~contains(badJoin, fullfile('toolbox', 'matlab', 'strfun'))
    warning('exportHandoverDataset_2026:joinShadowed', '%s', ...
        ['join.m was shadowed by ' badJoin '; removing that folder from the path for this session.']);
    rmpath(fileparts(badJoin));
    stillBad = which('join');
    if ~contains(stillBad, fullfile('toolbox', 'matlab', 'strfun'))
        error('exportHandoverDataset_2026:joinShadowStillBad', '%s', ...
            ['join still resolves to ' stillBad ' after rmpath. Resolve manually before re-running.']);
    end
end
end


function f = resolveLatestFile(explicit, processedPath, pattern)
if explicit ~= ""
    f = explicit;
    return;
end
files = dir(fullfile(processedPath, pattern));
if isempty(files)
    error('resolveLatestFile:notFound', '%s', ['No files matching ' pattern ' found in ' processedPath]);
end
[~, idx] = max([files.datenum]);
f = fullfile(processedPath, files(idx).name);
end


function verifyHeaderWritten(outFile, expectedNames)
% See exportStudentDataset_2026.m Corrections log (2026-07-16) for why this
% check exists: writetable can silently write a headerless CSV if a
% third-party join.m (e.g. FieldTrip/GPstuff) shadows the builtin.
fid = fopen(outFile, 'r');
if fid == -1
    error('exportHandoverDataset_2026:cannotVerify', '%s', ...
        ['Could not reopen ' outFile ' to verify its header']);
end
firstLine = fgetl(fid);
fclose(fid);

headerBad = ~ischar(firstLine) || isempty(strtrim(firstLine));
if ~headerBad
    written = strsplit(firstLine, ',');
    headerBad = ~strcmp(strtrim(written{1}), expectedNames{1});
end

if headerBad
    delete(outFile);
    error('exportHandoverDataset_2026:badHeader', '%s', ...
        ['writetable wrote a missing/incorrect header row, so the export was deleted. ' ...
         'Run  which join  -- if it resolves anywhere other than ' ...
         'toolbox/matlab/strfun/join.m (e.g. FieldTrip/GPstuff), rmpath that folder ' ...
         'and re-run.']);
end

end


function writeReadme(readmeFile, csvFile, shapeNames)
[~, csvName] = fileparts(csvFile);
lines = {
    '# Handover Dataset 2026: Data Dictionary'
    ''
    sprintf('Source CSV: `%s.csv`', csvName)
    ''
    'One row per trial. No aggregation or CI is pre-computed here -- you have'
    'the raw per-trial values so you can group and compute whatever test-retest'
    'statistic you need (ICC, Bland-Altman, CV, etc.) yourself, at whatever'
    'level you choose (within-session, within-visit, between-visit).'
    ''
    'This handover file includes only the pre-specified confirmatory'
    'pipeline (Savitzky-Golay differentiation + iteratively reweighted'
    'least squares regression, "SG6+IRLS"). The five other candidate'
    'pipelines used during method development are not included here --'
    'if you need those for a methods comparison, ask your supervisor.'
    ''
    '## Grouping / identifier columns'
    ''
    '| Column | Meaning |'
    '|---|---|'
    '| ParticipantID | Numeric participant ID (3-digit cohort code, see your MSc supervisor for the ID scheme) |'
    '| Visit | Visit number (1 = day 1, 2 = day 2) |'
    '| Session | Session number overall (1-6 across both visits, 3 sessions per visit) |'
    '| SessionInVisit | Session number within the visit (1-3) |'
    '| TrialNum | Trial number within the **session** (not per-shape). Stimulus order is'
    'randomised/interleaved across all 5 shapes within a session, so TrialNum for any'
    'given ShapeName will NOT run 1-10 contiguously. This is expected -- only ~10 of'
    'the ~50 session-wide trial numbers belong to any one shape. Not missing data.'
    'Safe to ignore for aggregation: group by (ParticipantID, Session, ShapeName)'
    'and take whatever summary statistic you need over however many trials land'
    'in that group. |'
    '| ShapeType | Numeric shape code (1-5), see ShapeName for the label |'
    '| ShapeName | Human-readable shape/task name |'
    '| SessionDatetime | Timestamp the session was recorded |'
    ''
    '## Task / shape codes'
    ''
    '| ShapeType | ShapeName |'
    '|---|---|'
    sprintf('| 1 | %s |', shapeNames{1})
    sprintf('| 2 | %s |', shapeNames{2})
    sprintf('| 3 | %s |', shapeNames{3})
    sprintf('| 4 | %s |', shapeNames{4})
    sprintf('| 5 | %s (freehand, no template -- see note below) |', shapeNames{5})
    ''
    '## Beta (power law exponent), VGF, FitCorr'
    ''
    '`Beta_SG6_IRLS`, `VGF_SG6_IRLS`, `FitCorr_SG6_IRLS` -- Savitzky-Golay'
    'differentiation + iteratively reweighted least squares regression, the'
    'pre-specified confirmatory pipeline for this study. FitCorr is the'
    'Pearson correlation in log-log space (not R-squared).'
    ''
    '## Kinematics'
    ''
    'For each of Velocity, Acceleration, Jerk, and each differentiation method'
    '(`_BW` = Butterworth, `_SG` = Savitzky-Golay), three summary statistics'
    'over that trial''s full time series are given: `Mean{Metric}_{Filter}`,'
    '`Median{Metric}_{Filter}`, `Peak{Metric}_{Filter}` (peak = maximum). Jerk'
    'additionally has `StdJerk_{Filter}` (standard deviation across the trial).'
    ''
    '**Units: velocity mm/s, acceleration mm/s^2, jerk mm/s^3.** The raw x,y'
    'are UIKit points, converted to mm at 5.209 points/mm (M4 13 inch iPad Pro)'
    'before differentiation, so these are NOT points/s. Exports dated before'
    '2026-11-09 used 9.73 and understate every mm quantity (and VGF) by about 1.87x.'
    ''
    '## Finger and palm touches'
    ''
    'The iPad records finger or palm contacts in the same stream as the Pencil.'
    'Only Apple Pencil samples (touch_type 2) are analysed; finger/palm samples'
    'were removed from 926 of the 14,388 trials before differentiation. Exports'
    'dated before 2026-11-09 kept them, which inflated the Peak kinematic columns.'
    ''
    '## Pen lifts -- read this before using the Cursive kinematics'
    ''
    'Cursive is free handwriting, so the pen leaves the glass between letters'
    'and the digitiser records nothing while it is up. Each pen-down stroke is'
    'differentiated separately; nothing is differentiated across a lift.'
    '`NumStrokes`, `NumLifts` and `NumSamplesDropped` record what happened per'
    'trial. If you have an export dated before 2026-07-16, its Cursive'
    'kinematic columns are stale and should be re-pulled.'
    ''
    '## Metadata'
    ''
    '| Column | Meaning |'
    '|---|---|'
    '| NumPoints | Number of valid samples after differentiation/clipping |'
    '| NumPoints_Regress_BW / _SG6 | Number of points entering that filter''s power-law regression |'
    '| SamplingFrequency | Hz (240 for iPad Pro) |'
    '| Duration | Pen-DOWN time in seconds. For the templated shapes this is the trial duration; for Cursive it is NOT, because the pen is off the glass between letters. |'
    '| DurationElapsed | Wall-clock time from first to last sample: Duration plus the pen-up intervals. Equals Duration for the templated shapes. |'
    '| PathLength_mm | Distance drawn in mm, summed WITHIN pen-down strokes (the hop between letters is not counted) |'
    '| NumStrokes | Contiguous pen-down strokes (1 for the templated shapes; typically 5-9 for Cursive) |'
    '| NumLifts | Detected pen lifts (= NumStrokes - 1) |'
    '| NumSamplesDropped | Samples excluded because their stroke was shorter than the 41-sample Savitzky-Golay window (too short to differentiate). Reported, not silently absorbed. |'
    ''
    '## A note on Cursive'
    ''
    'Cursive has no fixed template (free handwriting), so visit-to-visit'
    'differences in beta conflate genuine motor drift with content variability'
    '(different letterforms each time). This is a known, diagnosed reason for'
    'poor between-visit reliability specifically for Cursive-beta -- not a data'
    'quality problem.'
    ''
    '## Demo figures + how to reproduce them'
    ''
    'Two pre-made figures are included alongside this CSV:'
    ''
    '- `dayComparison_Measures_*.png` -- beta plus the 3x3 velocity/'
    'acceleration/jerk grid, split violin per shape (day 1 vs day 2), with'
    'paired per-participant dots and a median diamond per day.'
    '- `dayICC_Heatmap_*.png` -- between-visit ICC for all 10 measures x 5'
    'shapes, colour-banded per Koo & Li (2016), ICC(A,1) large / ICC(3,1)'
    'small in each cell.'
    ''
    'Both were produced by `function/generateDayFigures_2026.m`, included'
    'in this handover so you can regenerate them yourself or adapt the code'
    'for your own plots. It is self-contained: `function/computeICC.m` and'
    '`function/computeICCFromLongTable.m` are its only dependencies, both'
    'included alongside it. Open MATLAB with `function/` as your current'
    'folder (or add it to your path) and run:'
    ''
    '```matlab'
    'generateDayFigures_2026()'
    '```'
    ''
    'It auto-finds this CSV (one folder up from `function/`) and writes new'
    'timestamped PNGs alongside it -- it will not overwrite the ones already'
    'here. Pass `''Filter'', ''BW''` to see the figures with Butterworth'
    'kinematics instead of Savitzky-Golay.'
    ''
    '## Recomputing ICC yourself'
    ''
    'To compute test-retest ICC on this long-format data, you need each'
    'participant''s value at each visit for a given shape/parameter (e.g. mean'
    'or median of the per-trial values across a visit''s trials), then feed a'
    'wide participant x visit matrix into an ICC function -- e.g. R''s'
    '`irr::icc()` (absolute agreement: `type="agreement"`). Ask your'
    'supervisor if you''re not sure which ICC type (absolute agreement vs'
    'consistency) is appropriate for your question.'
};
fid = fopen(readmeFile, 'w');
if fid == -1
    error('writeReadme:cannotOpen', '%s', ['Could not open ' readmeFile ' for writing']);
end
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end
