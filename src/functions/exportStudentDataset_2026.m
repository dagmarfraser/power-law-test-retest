function outFile = exportStudentDataset_2026(options)
% EXPORTSTUDENTDATASET_2026 - One-stop-shop CSV for MSc students
%
% Takes the latest trial_level_results_*.csv (one row per trial, all 6
% power-law pipelines + BW/SG kinematics) and re-shapes it into a
% student-facing long table: one row per
% ParticipantID x Visit x Session(InVisit) x ShapeName x TrialNum,
% with a readable column order and a ShapeName label (no numeric-code
% lookup required downstream). No aggregation, no CI computed here --
% students get raw per-trial values and can compute their own ICC (or
% any other test-retest statistic) at whatever grouping level they
% choose, using these grouping columns directly.
%
% USAGE:
%   exportStudentDataset_2026()
%   exportStudentDataset_2026('trialFile', 'path/to/trial_level_results.csv')
%
% OUTPUTS:
%   Writes data/processed/StudentDataset_2026_{timestamp}.csv
%   Writes data/processed/StudentDataset_2026_{timestamp}_README.md
%   Returns the CSV path.
%
% Confirmatory pipeline is Beta_SG6_IRLS (pre-specified); all 6 are
% included so students can cross-check, per Dagmar's instruction.
%
% d.s.fraser@bham.ac.uk

arguments
    options.trialFile string = ""
end

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));
processedPath = fullfile(projectRoot, 'data', 'processed');

trialFile = resolveLatestFile(options.trialFile, processedPath, 'trial_level_results_2*.csv');
fprintf('Source: %s\n', trialFile);

opts = detectImportOptions(trialFile, 'VariableNamingRule', 'preserve');
allResults = readtable(trialFile, opts);

%% Fail loud: confirm all expected columns are present before reshaping
requiredCols = {'ParticipantID', 'Visit', 'Session', 'SessionInVisit', 'TrialNum', 'ShapeType', ...
    'MedianVelocity_BW', 'MedianVelocity_SG'};
missing = requiredCols(~ismember(requiredCols, allResults.Properties.VariableNames));
if ~isempty(missing)
    error('exportStudentDataset_2026:missingColumns', ...
        '%s', ['Source file is missing expected column(s): ' strjoin(missing, ', ') ...
        '. Was calculatePowerLaw.m''s Median_* addition run before this trial_level_results file was generated? ' ...
        'Re-run runAnalysis_2026 to regenerate.']);
end

%% Shape name lookup (ShapeType 1-5, see reportNoteEvidence_2026.m for same mapping)
shapeNames = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
allResults.ShapeName = shapeNames(allResults.ShapeType)';

%% Column order: identifiers, shape, confirmatory pipeline first, then all pipelines, then kinematics, then metadata
idCols = {'ParticipantID', 'Visit', 'Session', 'SessionInVisit', 'TrialNum', 'ShapeType', 'ShapeName', 'SessionDatetime'};

confirmatoryCols = {'Beta_SG6_IRLS', 'VGF_SG6_IRLS', 'FitCorr_SG6_IRLS'};

filterCodes = {'BW', 'SG6'};
methodNames = {'Linear', 'LMLS', 'IRLS'};
otherPipelineCols = {};
for f = 1:length(filterCodes)
    for m = 1:length(methodNames)
        suffix = sprintf('%s_%s', filterCodes{f}, methodNames{m});
        if strcmp(suffix, 'SG6_IRLS'), continue; end  % already listed first
        otherPipelineCols = [otherPipelineCols, {['Beta_' suffix], ['VGF_' suffix], ['FitCorr_' suffix]}]; %#ok<AGROW>
    end
end

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

colOrder = [idCols, confirmatoryCols, otherPipelineCols, kinematicCols, metaCols];
missingOut = colOrder(~ismember(colOrder, allResults.Properties.VariableNames));
if ~isempty(missingOut)
    error('exportStudentDataset_2026:columnOrderMismatch', '%s', ...
        ['Expected output column(s) not found in source table: ' strjoin(missingOut, ', ')]);
end

studentTable = allResults(:, colOrder);
studentTable = sortrows(studentTable, {'ParticipantID', 'Visit', 'SessionInVisit', 'ShapeType', 'TrialNum'});

%% Save
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
outFile = fullfile(processedPath, sprintf('StudentDataset_2026_%s.csv', timestamp));
writetable(studentTable, outFile);
verifyHeaderWritten(outFile, studentTable.Properties.VariableNames);
fprintf('Saved: %s (%d rows, %d columns)\n', outFile, height(studentTable), width(studentTable));

readmeFile = fullfile(processedPath, sprintf('StudentDataset_2026_%s_README.md', timestamp));
writeReadme(readmeFile, outFile, shapeNames);
fprintf('Saved: %s\n', readmeFile);

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
% VERIFYHEADERWRITTEN - Fail loud if writetable produced no header row.
%
% On 2026-07-16 writetable silently wrote a headerless CSV on the Windows
% machine and still reported success. Cause: FieldTrip bundles GPstuff
% (external/dmlt/external/gpstuff/diag), whose join.m shadows the MATLAB
% builtin that writetable uses to assemble the header line. GPstuff's join is
% an unrelated function (it joins structures of arrays) and returns [] for
% cell input, so the header came out empty with no error. Downstream readtable
% would then hand the students Var1..Var56 instead of column names.
%
% Verifying costs one fgetl, so verify. The corrupt file is deleted rather
% than left on disk, because resolveLatestFile() picks the newest match and
% would otherwise keep serving the broken export.

fid = fopen(outFile, 'r');
if fid == -1
    error('exportStudentDataset_2026:cannotVerify', '%s', ...
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
    error('exportStudentDataset_2026:badHeader', '%s', ...
        ['writetable wrote a missing/incorrect header row, so the export was deleted. ' ...
         'Run  which join  -- if it resolves anywhere other than ' ...
         'toolbox/matlab/strfun/join.m (e.g. FieldTrip/GPstuff), rmpath that folder ' ...
         'and re-run. See docs/AnalysisPipeline.md, Corrections log.']);
end

end


function writeReadme(readmeFile, csvFile, shapeNames)
[~, csvName] = fileparts(csvFile);
lines = {
    '# Student Dataset 2026: Data Dictionary'
    ''
    sprintf('Source CSV: `%s.csv`', csvName)
    ''
    'One row per trial. No aggregation or CI is pre-computed here -- you have'
    'the raw per-trial values so you can group and compute whatever test-retest'
    'statistic you need (ICC, Bland-Altman, CV, etc.) yourself, at whatever'
    'level you choose (within-session, within-visit, between-visit).'
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
    'given ShapeName will NOT run 1-10 contiguously (e.g. phi=0.4 trials might be'
    'numbered 4, 9, 14... within a session of ~50 total trials). This is expected --'
    'only ~10 of the ~50 session-wide trial numbers belong to any one shape. Not'
    'missing data, not a failed pen-touch. Safe to ignore for aggregation: group by'
    '(ParticipantID, Session, ShapeName) and take whatever summary statistic you need'
    'over however many trials land in that group. |'
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
    'Six pipelines are included, each a {filter} x {regression method} combination:'
    '`Beta_{Filter}_{Method}`, `VGF_{Filter}_{Method}`, `FitCorr_{Filter}_{Method}`.'
    ''
    '**`Beta_SG6_IRLS` is the pre-specified confirmatory pipeline** (Savitzky-Golay'
    'differentiation + iteratively reweighted least squares regression) -- use this'
    'one unless you have a specific reason to compare against the others. The other'
    'five (BW_Linear, BW_LMLS, BW_IRLS, SG6_Linear, SG6_LMLS) are included so you can'
    'cross-check, not because any of them is preferred.'
    ''
    'FitCorr is the Pearson correlation in log-log space (not R-squared).'
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
    'are UIKit points, converted to mm at 5.209 points/mm (M4 13 inch iPad Pro,'
    'verified 2026-11-02) before differentiation, so these are NOT points/s.'
    'Exports dated before 2026-11-09 used 9.73 and understate every mm quantity'
    '(and VGF) by about 1.87x.'
    ''
    '## Finger and palm touches'
    ''
    'The iPad records finger or palm contacts in the same stream as the Pencil.'
    'Only Apple Pencil samples (touch_type 2) are analysed; finger/palm samples'
    'are removed from every trial before differentiation. Exports dated before'
    '2026-11-09 kept them, which inflated the Peak kinematic columns.'
    ''
    '## Pen lifts -- read this before using the Cursive kinematics'
    ''
    'Cursive is free handwriting, so the pen leaves the glass between letters and'
    'the digitiser records nothing while it is up. Until 2026-07-16 the pipeline'
    'differentiated straight across those gaps, turning the hop between letters'
    'into a step discontinuity: a 67 mm hop treated as a single 1/240 s sample'
    'produces a 16,097 mm/s spike, which the filter then smears into an inflated'
    'peak. Every Cursive trial contained pen lifts (360/360 in the sample checked);'
    'the templated shapes are single continuous strokes and essentially never do.'
    ''
    'This is now fixed: each pen-down stroke is differentiated separately, and'
    'nothing is differentiated across a lift. `NumStrokes`, `NumLifts` and'
    '`NumSamplesDropped` record what happened per trial.'
    ''
    'If you have an export dated BEFORE 2026-07-16, its Cursive kinematic columns'
    'are affected and you should re-pull this file. Mean Peak Velocity for Cursive'
    'fell from ~1039 to ~222 mm/s, which brings it roughly into line with Ellipse'
    '(~161) as expected. The templated shapes are unchanged.'
    ''
    'Worth understanding: the Cursive kinematic ICCs went DOWN once the artifact'
    'was removed (mean jerk 0.81 -> 0.64, peak velocity 0.86 -> 0.74). The old'
    'high values were partly reliable measurement of an artifact, because how far'
    'someone hops between letters is a stable personal habit. A high ICC does not'
    'make a measure valid.'
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
    'quality problem. See `docs/AnalysisPipeline.md` for the full account.'
    ''
    'This diagnosis survived the 2026-07-16 pen-lift fix. With pen lifts handled'
    'correctly, Cursive between-visit beta ICC(A,1) rose only from 0.246 to 0.323'
    'and its confidence interval still straddles zero. Cursive-beta is unreliable'
    'for a design reason, not an artifact reason, so collecting more participants'
    'will not fix it.'
    ''
    '## Recomputing ICC yourself'
    ''
    'To compute test-retest ICC on this long-format data, you need each'
    'participant''s value at each visit for a given shape/parameter (e.g. mean'
    'or median of the per-trial values across a visit''s trials), then feed a'
    'wide participant x visit matrix into an ICC function -- e.g. R''s'
    '`irr::icc()` (absolute agreement: `type="agreement"`) or MATLAB''s'
    '`computeICCFromLongTable.m` in this project''s `src/functions/` if you have'
    'access to it. Ask your supervisor if you''re not sure which ICC type'
    '(absolute agreement vs consistency) is appropriate for your question.'
};
fid = fopen(readmeFile, 'w');
if fid == -1
    error('writeReadme:cannotOpen', '%s', ['Could not open ' readmeFile ' for writing']);
end
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end
