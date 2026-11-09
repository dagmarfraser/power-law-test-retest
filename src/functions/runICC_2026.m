function iccResults = runICC_2026(options)
% RUNICC_2026 - Test-retest reliability analysis: ICC(3,1) and ICC(A,1)
% for all 6 power-law pipelines plus kinematic benchmarks
%
% Consolidates analysis_2025's runICC_2025.m (ICC(3,1) consistency) and
% runICC_2025_AbsAgree.m (ICC(A,1) absolute agreement) into a single
% driver over a single aggregation pass, producing ONE results table
% with an ICCType column rather than two near-duplicate files that had
% to be kept in sync by hand (analysis_2025's own README flagged this).
%
% Computes both ICC(3,1) and ICC(A,1), at three levels (within-Visit-1,
% within-Visit-2, between-visit), for all 6 beta pipelines
% ({BW,SG6} x {Linear,LMLS,IRLS}) plus 4 SG-path kinematic benchmarks.
%
% NOTE: figure generation (bar charts, forest plots) from analysis_2025's
% runICC_2025.m is deliberately NOT ported here -- that was report-styling
% layered on top of the stats, tied to exactly 3 methods, and would need
% redesigning for 6. Flagging this as a deferred item rather than silently
% dropping it: see docs/AnalysisPipeline.md.
%
% USAGE:
%   iccResults = runICC_2026()                    % uses most recent processed trial-level file
%   iccResults = runICC_2026('dataFile', 'path/to/file.mat')
%
% OUTPUTS:
%   Saves data/processed/icc_results_{timestamp}.csv and .mat
%   Returns iccResults table

arguments
    options.dataFile string = ""
    options.verbose logical = true
end

fprintf('=== ICC Test-Retest Analysis 2026 (consistency + absolute agreement) ===\n');
fprintf('Started: %s\n\n', datestr(now));

%% Load data
scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));  % src/functions -> src -> root
processedPath = fullfile(projectRoot, 'data', 'processed');

if options.dataFile == ""
    matFiles = dir(fullfile(processedPath, 'trial_level_results_2*.mat'));
    if isempty(matFiles)
        error('No results files found in %s. Run runAnalysis_2026() first.', processedPath);
    end
    [~, idx] = max([matFiles.datenum]);
    dataFile = fullfile(processedPath, matFiles(idx).name);
else
    dataFile = options.dataFile;
end

fprintf('Loading: %s\n', dataFile);
load(dataFile, 'allResults');
fprintf('  %d trials loaded\n\n', height(allResults));

%% Define parameters: all 6 beta pipelines + SG-path kinematic benchmarks
filterCodes = {'BW', 'SG6'};
methodNames = {'Linear', 'LMLS', 'IRLS'};

betaParams = {};
betaLabels = {};
for f = 1:length(filterCodes)
    for m = 1:length(methodNames)
        betaParams{end+1} = sprintf('Beta_%s_%s', filterCodes{f}, methodNames{m}); %#ok<AGROW>
        betaLabels{end+1} = sprintf('beta %s+%s', filterCodes{f}, methodNames{m}); %#ok<AGROW>
    end
end

% Kinematic benchmarks -- SG path to match SG6+IRLS beta (apples-to-apples).
% PeakVelocity_SG is included for completeness; PeakVelocity_BW is the fair
% reference for peak velocity specifically (see docs/EmailIngestionPipeline.md
% Known Issues -- SG polynomial overshoots instantaneous peaks).
kinParams = {'MeanVelocity_SG', 'PeakVelocity_SG', 'MeanAcceleration_SG', 'MeanJerk_SG'};
kinLabels = {'Mean Velocity (SG)', 'Peak Velocity (SG)', 'Mean Acceleration (SG)', 'Mean Jerk (SG)'};

allParams = [betaParams, kinParams];
allLabels = [betaLabels, kinLabels];

shapeNames = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
nShapes = 5;
iccTypes = {'consistency', 'absolute'};

%% Aggregate once (shared across both ICC types -- the fix for the
%  duplicated aggregation blocks in analysis_2025)
fprintf('=== Aggregating to Session Means ===\n');
sessionData = aggregateToSessionMeans(allResults, allParams);
fprintf('  Session-level observations: %d\n\n', height(sessionData));

fprintf('=== Aggregating to Visit Means ===\n');
visitData = aggregateToVisitMeans(sessionData, allParams);
fprintf('  Visit-level observations: %d\n\n', height(visitData));

participants = unique(allResults.ParticipantID);
nParticipants = length(participants);

%% ICC analysis: both types, all params, all shapes
fprintf('=== ICC Analysis (consistency and absolute agreement) ===\n\n');

iccResults = table();

for shapeType = 1:nShapes
    if options.verbose
        fprintf('--- %s ---\n', shapeNames{shapeType});
    end

    for paramIdx = 1:length(allParams)
        param = allParams{paramIdx};
        label = allLabels{paramIdx};

        for tIdx = 1:length(iccTypes)
            iccType = iccTypes{tIdx};

            v1_sessions = sessionData(sessionData.Visit == 1 & sessionData.ShapeType == shapeType, :);
            icc_v1 = computeICCFromLongTable(v1_sessions, param, participants, 'SessionInVisit', iccType);

            v2_sessions = sessionData(sessionData.Visit == 2 & sessionData.ShapeType == shapeType, :);
            icc_v2 = computeICCFromLongTable(v2_sessions, param, participants, 'SessionInVisit', iccType);

            shapeVisitData = visitData(visitData.ShapeType == shapeType, :);
            icc_bv = computeICCFromLongTable(shapeVisitData, param, participants, 'Visit', iccType);

            row = struct();
            row.ShapeType = shapeType;
            row.ShapeName = shapeNames(shapeType);
            row.Parameter = {param};
            row.Label = {label};
            row.ICCType = {iccType};
            row.ICC_WithinVisit1 = icc_v1.icc;
            row.ICC_WithinVisit1_LB = icc_v1.lb;
            row.ICC_WithinVisit1_UB = icc_v1.ub;
            row.ICC_WithinVisit1_N = icc_v1.n;
            row.ICC_WithinVisit2 = icc_v2.icc;
            row.ICC_WithinVisit2_LB = icc_v2.lb;
            row.ICC_WithinVisit2_UB = icc_v2.ub;
            row.ICC_WithinVisit2_N = icc_v2.n;
            row.ICC_BetweenVisit = icc_bv.icc;
            row.ICC_BetweenVisit_LB = icc_bv.lb;
            row.ICC_BetweenVisit_UB = icc_bv.ub;
            row.ICC_BetweenVisit_N = icc_bv.n;

            % Variance components (from visit-level data; same regardless
            % of ICC type, but SEM/MDC below depend on which icc_bv.icc is used)
            pMeansForVar = NaN(nParticipants, 1);
            pWithinSD = NaN(nParticipants, 1);
            for pIdx2 = 1:nParticipants
                pID2 = participants(pIdx2);
                pVals = shapeVisitData.(param)(shapeVisitData.ParticipantID == pID2);
                if length(pVals) >= 2
                    pMeansForVar(pIdx2) = mean(pVals, 'omitnan');
                    pWithinSD(pIdx2) = std(pVals, 'omitnan');
                end
            end
            pMeansForVar = pMeansForVar(~isnan(pMeansForVar));
            pWithinSD = pWithinSD(~isnan(pWithinSD));

            row.BetweenSD = std(pMeansForVar, 'omitnan');
            row.WithinSD = mean(pWithinSD, 'omitnan');

            if ~isnan(icc_bv.icc) && icc_bv.n > 0
                sd_pooled = std(shapeVisitData.(param), 'omitnan');
                row.SEM = sd_pooled * sqrt(1 - icc_bv.icc);
                row.MDC95 = row.SEM * 1.96 * sqrt(2);

                if row.WithinSD > 0
                    row.SNR = row.BetweenSD / row.WithinSD;
                else
                    row.SNR = NaN;
                end

                pRange = range(pMeansForVar);
                if pRange > 0
                    row.MDC_pct = (row.MDC95 / pRange) * 100;
                else
                    row.MDC_pct = NaN;
                end
            else
                row.SEM = NaN; row.MDC95 = NaN; row.SNR = NaN; row.MDC_pct = NaN;
            end

            iccResults = [iccResults; struct2table(row)]; %#ok<AGROW>

            if options.verbose
                fprintf('  [%s] %s: Between ICC=%.3f [%.3f, %.3f] N=%d\n', ...
                    iccType, label, icc_bv.icc, icc_bv.lb, icc_bv.ub, icc_bv.n);
            end
        end
    end
    if options.verbose, fprintf('\n'); end
end

%% Save
if ~exist(processedPath, 'dir'), mkdir(processedPath); end
timestamp = datestr(now, 'yyyymmdd_HHMMSS');

csvFile = fullfile(processedPath, sprintf('icc_results_%s.csv', timestamp));
writetable(iccResults, csvFile);
fprintf('\nSaved: %s\n', csvFile);

matFile = fullfile(processedPath, sprintf('icc_results_%s.mat', timestamp));
save(matFile, 'iccResults', 'sessionData', 'visitData');
fprintf('Saved: %s\n', matFile);

fprintf('\n=== ICC Analysis Complete (both types, all 6 pipelines) ===\n');

end
