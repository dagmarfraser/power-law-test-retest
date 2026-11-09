classdef test_exportStudentDataset_2026 < matlab.unittest.TestCase
% test_exportStudentDataset_2026 - Verifies the student-facing CSV export
% doesn't silently drop rows, mislabel shapes, or produce a wrong column
% order, and that it fails loudly (rather than silently omitting columns)
% if a required field is missing from the source trial-level table.
%
% Uses a small synthetic trial_level_results CSV (not real participant
% data) written to a temp file, so this test is independent of whatever
% real trial_level_results_*.csv currently exists in data/processed.
%
% NOTE: exportStudentDataset_2026 resolves its OWN project root from its
% own file location (not from the trialFile path), so outputs always land
% in the real data/processed/ folder. This test tracks and deletes every
% file it causes to be written, in TestMethodTeardown, so it leaves no
% residue for Dagmar to accidentally hand to students.
%
% Run with: run_matlab_test_file or runtests('test_exportStudentDataset_2026')

    properties
        TempTrialFile
        FilesToDelete = {}
    end

    methods (TestMethodTeardown)
        function cleanup(testCase)
            for i = 1:length(testCase.FilesToDelete)
                if isfile(testCase.FilesToDelete{i})
                    delete(testCase.FilesToDelete{i});
                end
            end
            testCase.FilesToDelete = {};
            if ~isempty(testCase.TempTrialFile) && isfile(testCase.TempTrialFile)
                delete(testCase.TempTrialFile);
            end
        end
    end

    methods (Test)

        function rowCountShapeNameAndColumnOrderPreserved(testCase)
            t = makeSyntheticTrialTable();
            tempFile = [tempname() '.csv'];
            writetable(t, tempFile);
            testCase.TempTrialFile = tempFile;

            outFile = exportStudentDataset_2026('trialFile', tempFile);
            testCase.FilesToDelete{end+1} = outFile;
            [d, n] = fileparts(outFile);
            testCase.FilesToDelete{end+1} = fullfile(d, [n '_README.md']);

            out = readtable(outFile, 'VariableNamingRule', 'preserve');

            % Row count preserved -- no silent row drops in the reshape
            testCase.verifyEqual(height(out), height(t));

            % ShapeName mapping correct for every ShapeType 1-5
            expectedNames = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
            for s = 1:5
                rows = out(out.ShapeType == s, :);
                testCase.verifyTrue(all(strcmp(rows.ShapeName, expectedNames{s})), ...
                    sprintf('ShapeType %d not uniformly labelled %s', s, expectedNames{s}));
            end

            % Confirmatory pipeline listed first, ahead of the other 5
            firstCols = out.Properties.VariableNames(1:11);
            testCase.verifyEqual(firstCols, {'ParticipantID', 'Visit', 'Session', 'SessionInVisit', ...
                'TrialNum', 'ShapeType', 'ShapeName', 'SessionDatetime', ...
                'Beta_SG6_IRLS', 'VGF_SG6_IRLS', 'FitCorr_SG6_IRLS'});

            % Sort order: ParticipantID, Visit, SessionInVisit, ShapeType, TrialNum
            resorted = sortrows(out, {'ParticipantID', 'Visit', 'SessionInVisit', 'ShapeType', 'TrialNum'});
            testCase.verifyEqual(out.ParticipantID, resorted.ParticipantID);
            testCase.verifyEqual(out.TrialNum, resorted.TrialNum);
        end

        function missingMedianColumnFailsLoudly(testCase)
            t = makeSyntheticTrialTable();
            t.MedianVelocity_SG = [];  % simulate a pre-Median trial_level_results file
            tempFile = [tempname() '.csv'];
            writetable(t, tempFile);
            testCase.TempTrialFile = tempFile;

            testCase.verifyError(@() exportStudentDataset_2026('trialFile', tempFile), ...
                'exportStudentDataset_2026:missingColumns');
        end

    end

end


function t = makeSyntheticTrialTable()
% Minimal synthetic trial-level table covering all 5 shapes, 2 visits,
% with every column exportStudentDataset_2026 requires. Values are
% arbitrary but distinct per row so row-identity can be traced through
% the reshape/sort.
nRows = 10;
ParticipantID = repelem([104; 105], 5);
Visit = repmat([1;1;1;2;2], 2, 1);
Session = repmat([1;1;2;4;5], 2, 1);
SessionInVisit = repmat([1;1;2;1;2], 2, 1);
TrialNum = (1:nRows)';
ShapeType = repmat((1:5)', 2, 1);
SessionDatetime = repmat("15-Jul-2026 12:00:00", nRows, 1);

filterCodes = {'BW', 'SG6'};
methodNames = {'Linear', 'LMLS', 'IRLS'};
t = table(ParticipantID, Visit, Session, SessionInVisit, TrialNum, ShapeType, SessionDatetime);

for f = 1:length(filterCodes)
    for m = 1:length(methodNames)
        suffix = sprintf('%s_%s', filterCodes{f}, methodNames{m});
        t.(['Beta_' suffix]) = 0.2 + 0.01*(1:nRows)';
        t.(['VGF_' suffix]) = 50 + (1:nRows)';
        t.(['FitCorr_' suffix]) = 0.8*ones(nRows,1);
    end
end

for filt = {'BW', 'SG'}
    t.(['MeanVelocity_' filt{1}]) = 100 + (1:nRows)';
    t.(['MedianVelocity_' filt{1}]) = 95 + (1:nRows)';
    t.(['PeakVelocity_' filt{1}]) = 200 + (1:nRows)';
    t.(['MeanAcceleration_' filt{1}]) = 1000 + (1:nRows)';
    t.(['MedianAcceleration_' filt{1}]) = 950 + (1:nRows)';
    t.(['PeakAcceleration_' filt{1}]) = 3000 + (1:nRows)';
    t.(['MeanJerk_' filt{1}]) = 20000 + (1:nRows)';
    t.(['MedianJerk_' filt{1}]) = 18000 + (1:nRows)';
    t.(['StdJerk_' filt{1}]) = 5000*ones(nRows,1);
    t.(['PeakJerk_' filt{1}]) = 80000 + (1:nRows)';
end

t.NumPoints = 2000*ones(nRows,1);
t.NumPoints_Regress_BW = 2000*ones(nRows,1);
t.NumPoints_Regress_SG6 = 2000*ones(nRows,1);
t.SamplingFrequency = 240*ones(nRows,1);
t.Duration = 8*ones(nRows,1);
t.PathLength_mm = 1000*ones(nRows,1);
% Pen-lift metadata, required by the export since the 2026-07-16 pen-lift fix
% (the fixture predated it; found failing 2026-11-09).
t.DurationElapsed = 8*ones(nRows,1);
t.NumStrokes = ones(nRows,1);
t.NumLifts = zeros(nRows,1);
t.NumSamplesDropped = zeros(nRows,1);
end
