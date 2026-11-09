function [allResults, participantSummary] = runAnalysis_2026(options)
% RUNANALYSIS_2026 - Power law analysis pipeline for Analysis_2026
%
% USAGE:
%   runAnalysis_2026()                    % Full run, all participants
%   runAnalysis_2026('limitedRun', true)  % Single complete participant
%   runAnalysis_2026('participantID', 'ID112321')  % Specific participant
%   runAnalysis_2026('exactSessionsOnly', true)  % Skip ambiguous-count participants (e.g. ID103, ID212)
%   runAnalysis_2026('useParfor', true)   % Parallelise across participants
%
% OPTIONS:
%   limitedRun         - logical, run only first complete participant (default: false)
%   participantID      - string, run specific participant (overrides limitedRun)
%   minSessions        - minimum sessions required (default: 6; see docs/DesignNotes.md
%                        if the k=3 design is adopted -- update to 9)
%   exactSessionsOnly  - logical, exclude participants whose raw session
%                        count doesn't exactly match minSessions (default:
%                        false). Participants with MORE sessions than
%                        expected (e.g. ID103 with 7, ID212 with 9) still
%                        get processed by default via the visit-grouping
%                        truncation in the discovery loop below -- this
%                        flag is for excluding them entirely instead,
%                        e.g. while an ambiguous extra session is still
%                        being resolved with the student who collected it.
%   useParfor          - logical, parallelise the per-participant loop
%                        (default: false). Each participant's trial
%                        extraction is independent, so this parallelises
%                        cleanly; see nWorkers.
%   nWorkers           - number of parallel workers to use if useParfor
%                        is true (default: max(numcores-1, 1), i.e. one
%                        fewer than all cores so the machine stays usable
%                        -- matches Dagmar's standing convention).
%   saveResults        - logical, save outputs (default: true)
%   verbose            - logical, detailed output (default: true)
%
% OUTPUTS:
%   [allResults, participantSummary] - returned for programmatic/test use;
%   safe to ignore if not captured. Also saves to data/processed/ (unless
%   saveResults=false):
%     - trial_level_results_{timestamp}.mat / .csv
%     - participant_summary_{timestamp}.csv
%
% Adapted from analysis_2025/runAnalysis_2025.m. Trial extraction logic
% unchanged; calculatePowerLaw now returns all 6 pipelines (was 3), so
% the row-building step below loops the 6 combinations instead of naming
% 3 fields by hand. Visualization figures from the analysis_2025 version
% are deliberately NOT ported -- see docs/AnalysisPipeline.md for why and
% what to do about it. Output moved from a top-level results/ folder to
% data/processed/, per the reproducible-MATLAB layout.
%
% Per-participant extraction was refactored into the local function
% processParticipant() below so the main loop can run under parfor --
% each iteration now returns its own results/summary tables instead of
% accumulating into a shared growing table, which parfor disallows.
%
% Based on Fraser et al. (2025) methodology
% d.s.fraser@bham.ac.uk

arguments
    options.limitedRun logical = false
    options.participantID string = ""
    options.minSessions double = 6
    options.expectedVisits double = NaN   % default minSessions/3; set explicitly to analyse incomplete participants (analyseOrphanRuns_2026)
    options.exactSessionsOnly logical = false
    options.useParfor logical = false
    options.nWorkers double = max(feature('numcores') - 1, 1)
    options.saveResults logical = true
    options.verbose logical = true
end

fprintf('=== Power Law Analysis Pipeline 2026 ===\n');
fprintf('Started: %s\n\n', datestr(now));
tic;

%% Setup paths
scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));  % src/functions -> src -> root
addpath(scriptDir);

dataPath = fullfile(projectRoot, 'data', 'raw', 'automatic');
processedPath = fullfile(projectRoot, 'data', 'processed');

if ~exist(processedPath, 'dir'), mkdir(processedPath); end

filterCodes = {'BW', 'SG6'};
methodNames = {'Linear', 'LMLS', 'IRLS'};

%% Discover participants
participants = dir(fullfile(dataPath, 'ID*'));
participants = participants([participants.isdir]);
fprintf('Found %d participant folders\n', length(participants));

%% Filter to complete participants
participantInfo = struct('ID', {}, 'sessions', {}, 'nSessions', {}, 'visits', {}, 'rawSessionCount', {});

for pIdx = 1:length(participants)
    pID = participants(pIdx).name;
    pPath = fullfile(dataPath, pID);

    sessionFiles = dir(fullfile(pPath, '*tracingSection.csv'));
    sessionFiles = sessionFiles(~contains({sessionFiles.name}, '-enhanced') & ...
                                ~contains({sessionFiles.name}, '-trajectories'));
    rawSessionCount = length(sessionFiles);

    if rawSessionCount >= options.minSessions
        sessions = struct('filename', {}, 'datetime', {}, 'datenum', {});
        for sIdx = 1:length(sessionFiles)
            fname = sessionFiles(sIdx).name;
            tokens = regexp(fname, '(\d{4}-\d{2}-\d{2})\s+(\d{6})', 'tokens');
            if ~isempty(tokens)
                dtStr = [tokens{1}{1} ' ' tokens{1}{2}];
                dt = datetime(dtStr, 'InputFormat', 'yyyy-MM-dd HHmmss');
                sessions(end+1).filename = fname; %#ok<AGROW>
                sessions(end).datetime = dt;
                sessions(end).datenum = datenum(dt);
            end
        end

        [~, sortIdx] = sort([sessions.datenum]);
        sessions = sessions(sortIdx);

        if ~isempty(sessions)
            nSess = length(sessions);
            sessionsPerVisit = 3;

            % Visit assignment: group chronologically by same-visit proximity
            % first (mirrors analyzeTimings.py's 90-min PROXIMITY_THRESHOLD),
            % THEN truncate any oversized visit to its first 3 sessions.
            % Previously this chunked the flat sorted list into blocks of 3
            % and truncated the whole participant to the first N sessions --
            % which silently misassigns visits and drops the wrong session
            % when a single visit has an extra/mislabeled email (e.g. ID103
            % had 4 same-day emails: blind chunking put 4 in visit 1's slot,
            % spilling the genuine 4th into visit 2 and losing the real
            % third visit-2 session entirely).
            proximityThresholdDays = 90 / (24 * 60);
            visitOfSession = zeros(1, nSess);
            visitOfSession(1) = 1;
            for sIdx = 2:nSess
                gapDays = sessions(sIdx).datenum - sessions(sIdx-1).datenum;
                if gapDays > proximityThresholdDays
                    visitOfSession(sIdx) = visitOfSession(sIdx-1) + 1;
                else
                    visitOfSession(sIdx) = visitOfSession(sIdx-1);
                end
            end

            keepMask = false(1, nSess);
            visits = [];
            for vNum = 1:max(visitOfSession)
                idxInVisit = find(visitOfSession == vNum);
                if length(idxInVisit) > sessionsPerVisit
                    warning('%s visit %d has %d sessions -- using first %d (by timestamp within this visit)', ...
                        pID, vNum, length(idxInVisit), sessionsPerVisit);
                    idxInVisit = idxInVisit(1:sessionsPerVisit);
                end
                keepMask(idxInVisit) = true;
                visits = [visits, repmat(vNum, 1, length(idxInVisit))]; %#ok<AGROW>
            end

            sessions = sessions(keepMask);
            nSess = length(sessions);

            expectedVisits = options.expectedVisits;
            if isnan(expectedVisits), expectedVisits = options.minSessions / sessionsPerVisit; end
            if max(visits) > expectedVisits
                warning('%s has %d visits -- using first %d only', pID, max(visits), expectedVisits);
                visitKeep = visits <= expectedVisits;
                sessions = sessions(visitKeep);
                visits = visits(visitKeep);
                nSess = length(sessions);
            end

            participantInfo(end+1).ID = pID; %#ok<AGROW>
            participantInfo(end).sessions = sessions;
            participantInfo(end).nSessions = nSess;
            participantInfo(end).visits = visits;
            participantInfo(end).rawSessionCount = rawSessionCount;
        end
    end
end

fprintf('Found %d participants with >= %d sessions\n\n', length(participantInfo), options.minSessions);

if options.exactSessionsOnly
    keepP = [participantInfo.rawSessionCount] == options.minSessions;
    excludedIDs = {participantInfo(~keepP).ID};
    if ~isempty(excludedIDs)
        fprintf('exactSessionsOnly: excluding %d participant(s) with ambiguous/extra session counts: %s\n\n', ...
            numel(excludedIDs), strjoin(excludedIDs, ', '));
    end
    participantInfo = participantInfo(keepP);
end

%% Select participants to process
if options.participantID ~= ""
    idx = find(strcmp({participantInfo.ID}, options.participantID));
    if isempty(idx)
        error('Participant %s not found or has < %d sessions', options.participantID, options.minSessions);
    end
    participantInfo = participantInfo(idx);
    fprintf('*** Processing specific participant: %s ***\n\n', options.participantID);
elseif options.limitedRun
    idx = find([participantInfo.nSessions] == options.minSessions, 1);
    if isempty(idx)
        error('No participant with exactly %d sessions found', options.minSessions);
    end
    participantInfo = participantInfo(idx);
    fprintf('*** LIMITED RUN: Processing %s (%d sessions) ***\n\n', participantInfo(1).ID, options.minSessions);
end

%% Process participants
sessionsPerVisit = 3;
nP = length(participantInfo);
resultsCell = cell(nP, 1);
summaryCell = cell(nP, 1);

if options.useParfor
    pool = gcp('nocreate');
    if isempty(pool)
        pool = parpool(options.nWorkers);
    end
    fprintf('Parallel pool: %d workers\n\n', pool.NumWorkers);

    parfor pIdx = 1:nP
        [resultsCell{pIdx}, summaryCell{pIdx}] = processParticipant( ...
            participantInfo(pIdx), dataPath, filterCodes, methodNames, sessionsPerVisit, options.verbose); %#ok<PFBNS>
    end
else
    for pIdx = 1:nP
        if options.verbose
            fprintf('Processing %s (%d/%d)\n', participantInfo(pIdx).ID, pIdx, nP);
        end
        [resultsCell{pIdx}, summaryCell{pIdx}] = processParticipant( ...
            participantInfo(pIdx), dataPath, filterCodes, methodNames, sessionsPerVisit, options.verbose);
    end
end

allResults = vertcat(resultsCell{:});
participantSummary = vertcat(summaryCell{:});

%% Summary statistics
fprintf('\n=== Summary ===\n');
fprintf('Participants processed: %d\n', height(participantSummary));
fprintf('Total trials: %d\n', height(allResults));

if height(allResults) > 0
    fprintf('Valid trials (non-NaN Beta_SG6_IRLS): %d\n', sum(~isnan(allResults.Beta_SG6_IRLS)));

    fprintf('\nTrials per shape:\n');
    for st = 1:5
        fprintf('  Shape %d: %d trials\n', st, sum(allResults.ShapeType == st));
    end

    fprintf('\nBeta comparison across all 6 pipelines (mean +/- std):\n');
    for f = 1:length(filterCodes)
        for m = 1:length(methodNames)
            col = sprintf('Beta_%s_%s', filterCodes{f}, methodNames{m});
            fprintf('  %-12s: %.3f +/- %.3f (N=%d valid, %d NaN)\n', col, ...
                mean(allResults.(col), 'omitnan'), std(allResults.(col), 'omitnan'), ...
                sum(~isnan(allResults.(col))), sum(isnan(allResults.(col))));
        end
    end

    fprintf('\nSampling frequency: %.1f +/- %.1f Hz\n', ...
        mean(allResults.SamplingFrequency, 'omitnan'), std(allResults.SamplingFrequency, 'omitnan'));
end

%% Save results
if options.saveResults
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');

    if options.limitedRun || options.participantID ~= ""
        suffix = '_LIMITED';
    else
        suffix = '';
    end

    matFile = fullfile(processedPath, sprintf('trial_level_results%s_%s.mat', suffix, timestamp));
    save(matFile, 'allResults', 'participantSummary', 'participantInfo');
    fprintf('\nSaved: %s\n', matFile);

    csvFile = fullfile(processedPath, sprintf('trial_level_results%s_%s.csv', suffix, timestamp));
    writetable(allResults, csvFile);
    fprintf('Saved: %s\n', csvFile);

    sumFile = fullfile(processedPath, sprintf('participant_summary%s_%s.csv', suffix, timestamp));
    writetable(participantSummary, sumFile);
    fprintf('Saved: %s\n', sumFile);
end

fprintf('\nCompleted in %.1f seconds\n', toc);
fprintf('=== Done ===\n');

end


function [pResults, pSum] = processParticipant(pInfo, dataPath, filterCodes, methodNames, sessionsPerVisit, verbose)
% PROCESSPARTICIPANT - Extract trial-level power-law/kinematic results
% for a single participant. Split out from the main loop in
% runAnalysis_2026 so each participant's work is self-contained (no
% shared accumulator), which is what allows the caller to run this under
% parfor.

pID = pInfo.ID;
pPath = fullfile(dataPath, pID);
pResults = table();

if verbose
    fprintf('  %s: %d sessions across %d visits\n', pID, pInfo.nSessions, max(pInfo.visits));
end

for sIdx = 1:length(pInfo.sessions)
    session = pInfo.sessions(sIdx);
    visit = pInfo.visits(sIdx);
    sessionNum = sIdx;

    baseFilename = strrep(session.filename, ' tracingSection.csv', '');
    metaFile = fullfile(pPath, session.filename);
    trajFile = fullfile(pPath, [baseFilename ' tracingSection-enhanced.csv']);

    if ~isfile(trajFile)
        warning('Missing trajectory file: %s', trajFile);
        continue;
    end

    metaData = readtable(metaFile);
    trajData = readtable(trajFile);

    trials = unique(trajData.response_index);
    trials = trials(trials > 0 & trials <= 50);

    for tIdx = 1:length(trials)
        trialNum = trials(tIdx);

        metaRow = metaData(metaData.trial == trialNum, :);
        if isempty(metaRow)
            continue;
        end
        shapeType = metaRow.tracingScene_object1_imageNumber;

        trajMask = trajData.response_index == trialNum;
        trialTraj = trajData(trajMask, :);

        % Pencil only (touch_type 2): finger/palm samples share the
        % touch_index counter and were being interleaved. See pencilSamplesOnly.
        trialTraj = pencilSamplesOnly(trialTraj);

        edgeClip = 50;
        if height(trialTraj) <= 2*edgeClip + 100
            continue;
        end
        trialTraj = trialTraj(edgeClip+1:end-edgeClip, :);

        fs = 240;
        t = trialTraj.touch_index / fs;
        x = trialTraj.x;
        y = trialTraj.y;

        % Pen lifts. Cursive is free handwriting, so the pen leaves the
        % glass between letters and the digitiser records nothing while it
        % is up; the templated shapes are single continuous strokes and
        % yield exactly one stroke here (so their results are unchanged).
        % See src/functions/detectPenLifts.m for why time_seconds is used
        % only to find the lifts and never to time the samples.
        [strokeId, nMissingSamples] = detectPenLifts(trialTraj.touch_index, ...
            trialTraj.time_seconds, fs);

        % Raw x,y are UIKit points, not pixels. Scale set once in
        % ipadPointsPerMm (5.209 pt/mm, M4 13" iPad Pro, 2 Nov 2026); it
        % replaced 9.73, which understated every mm quantity by 1.87x.
        % Beta is scale-invariant; velocity, PathLength_mm and VGF are not.
        pxPerMm = ipadPointsPerMm();
        x_mm = x / pxPerMm;
        y_mm = y / pxPerMm;

        try
            results = calculatePowerLaw(x_mm, y_mm, t, fs, strokeId);
        catch ME
            warning('Failed trial %d in %s session %d: %s', trialNum, pID, sessionNum, ME.message);
            continue;
        end

        row = struct();
        row.ParticipantID = str2double(pID(3:end));
        row.Visit = visit;
        row.Session = sessionNum;
        row.SessionInVisit = sessionNum - (visit-1)*sessionsPerVisit;
        row.TrialNum = trialNum;
        row.ShapeType = shapeType;
        row.SessionDatetime = string(session.datetime);

        % Power law parameters -- all 6 pipelines
        for f = 1:length(filterCodes)
            for m = 1:length(methodNames)
                fieldSuffix = sprintf('%s_%s', filterCodes{f}, methodNames{m});
                row.(['Beta_' fieldSuffix]) = results.(['Beta_' fieldSuffix]);
                row.(['VGF_' fieldSuffix]) = results.(['VGF_' fieldSuffix]);
                row.(['FitCorr_' fieldSuffix]) = results.(['FitCorr_' fieldSuffix]);
            end
        end

        % Kinematics - BW
        row.MeanVelocity_BW = results.MeanVelocity_BW;
        row.MedianVelocity_BW = results.MedianVelocity_BW;
        row.PeakVelocity_BW = results.PeakVelocity_BW;
        row.MeanAcceleration_BW = results.MeanAcceleration_BW;
        row.MedianAcceleration_BW = results.MedianAcceleration_BW;
        row.PeakAcceleration_BW = results.PeakAcceleration_BW;
        row.MeanJerk_BW = results.MeanJerk_BW;
        row.MedianJerk_BW = results.MedianJerk_BW;
        row.StdJerk_BW = results.StdJerk_BW;
        row.PeakJerk_BW = results.PeakJerk_BW;

        % Kinematics - SG
        row.MeanVelocity_SG = results.MeanVelocity_SG;
        row.MedianVelocity_SG = results.MedianVelocity_SG;
        row.PeakVelocity_SG = results.PeakVelocity_SG;
        row.MeanAcceleration_SG = results.MeanAcceleration_SG;
        row.MedianAcceleration_SG = results.MedianAcceleration_SG;
        row.PeakAcceleration_SG = results.PeakAcceleration_SG;
        row.MeanJerk_SG = results.MeanJerk_SG;
        row.MedianJerk_SG = results.MedianJerk_SG;
        row.StdJerk_SG = results.StdJerk_SG;
        row.PeakJerk_SG = results.PeakJerk_SG;

        % Metadata
        row.NumPoints = results.NumPoints;
        row.NumPoints_Regress_BW = results.NumPoints_Regress_BW;
        row.NumPoints_Regress_SG6 = results.NumPoints_Regress_SG6;
        row.SamplingFrequency = results.SamplingFrequency;

        % Duration. t is the touch_index clock, so t(end)-t(1) counts only
        % pen-DOWN time: for Cursive that silently omitted every pen lift
        % (ID104 trial 3 reported 4.10 s for a 6.25 s trial). Kept with its
        % original meaning and now named honestly by DurationElapsed beside
        % it, which adds the inferred pen-up samples back. For the templated
        % shapes there are no lifts, so the two are equal.
        row.Duration = t(end) - t(1);                                    % pen-down only
        row.DurationElapsed = (numel(t) - 1 + sum(nMissingSamples)) / fs;
        row.NumLifts = numel(nMissingSamples);
        row.NumStrokes = results.NumStrokes;
        row.NumSamplesDropped = results.NumSamplesDropped;

        % Path length within strokes only. Summing across a lift would count
        % the hop between letters as distance the pen actually drew.
        segLen = sqrt(diff(x_mm).^2 + diff(y_mm).^2);
        row.PathLength_mm = sum(segLen(diff(strokeId) == 0));

        pResults = [pResults; struct2table(row)]; %#ok<AGROW>
    end

    if verbose
        fprintf('    %s Session %d (Visit %d): %d valid trials\n', pID, sessionNum, visit, ...
            sum(pResults.Session == sessionNum));
    end
end

pSum = struct();
pSum.ParticipantID = str2double(pID(3:end));
pSum.nSessions = pInfo.nSessions;
pSum.nVisits = max(pInfo.visits);
pSum.nTrials = height(pResults);
pSum.nValidTrials = sum(~isnan(pResults.Beta_SG6_IRLS));
for st = 1:5
    pSum.(sprintf('nShape%d', st)) = sum(pResults.ShapeType == st);
end
pSum = struct2table(pSum);

if verbose
    fprintf('    %s Total: %d valid trials\n', pID, pSum.nValidTrials);
end

end
