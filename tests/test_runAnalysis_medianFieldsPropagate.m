classdef test_runAnalysis_medianFieldsPropagate < matlab.unittest.TestCase
% test_runAnalysis_medianFieldsPropagate - Closes the gap flagged after
% adding Median{Metric}_{Filter} to calculatePowerLaw.m: unit tests prove
% calculatePowerLaw computes Median correctly in isolation, and prove
% exportStudentDataset_2026 reshapes a table correctly in isolation, but
% neither proves runAnalysis_2026's ingestion pipeline (raw CSV read ->
% px-to-mm scaling -> edgeClip -> calculatePowerLaw call -> row
% assignment) actually carries a correct value all the way through.
%
% This test builds a minimal but realistic fixture participant (ID999,
% clearly outside the real 1XX/2XX/3XX MSc numbering scheme) with a known
% synthetic circular trajectory, runs the REAL runAnalysis_2026 against
% it, and compares the resulting table row against an independently
% computed ground truth that replicates the same transform
% (edgeClip -> pxPerMm -> calculatePowerLaw) by hand in the test, so
% the only thing "trusted" is calculatePowerLaw itself (already covered
% by test_calculatePowerLaw_medianKinematics.m).
%
% Fixture files are written under the REAL data/raw/automatic/ folder
% (runAnalysis_2026 hard-codes this path from its own file location, so
% there's no way to redirect it to a temp folder without changing
% production code) and are ALWAYS removed via addTeardown, including on
% test failure/error, so no fixture data is left behind to contaminate
% a real run.
%
% Run with: run_matlab_test_file or runtests('test_runAnalysis_medianFieldsPropagate')

    properties
        FixtureDir
    end

    methods (TestMethodSetup)
        function makeFixture(testCase)
            scriptDir = fileparts(mfilename('fullpath'));
            projectRoot = fileparts(scriptDir);  % tests/ -> Analysis_2026
            dataPath = fullfile(projectRoot, 'data', 'raw', 'automatic');
            testCase.FixtureDir = fullfile(dataPath, 'ID999');

            if isfolder(testCase.FixtureDir)
                rmdir(testCase.FixtureDir, 's');  % clean slate if a previous run crashed mid-test
            end
            mkdir(testCase.FixtureDir);
            testCase.addTeardown(@() cleanupFixture(testCase.FixtureDir));

            % 3 sessions, 10 min apart, same day -> all Visit 1 under
            % the 90-min proximity threshold (minSessions=3 -> 1 visit).
            timestamps = {'090000', '091000', '092000'};
            for i = 1:3
                writeFixtureSession(testCase.FixtureDir, timestamps{i});
            end
        end
    end

    methods (Test)

        function medianFieldsMatchIndependentGroundTruth(testCase)
            [allResults, participantSummary] = runAnalysis_2026( ...
                'participantID', 'ID999', 'minSessions', 3, ...
                'saveResults', false, 'verbose', false);

            % One valid trial per session -> 3 rows total
            testCase.verifyEqual(height(allResults), 3);
            testCase.verifyEqual(participantSummary.nValidTrials, 3);
            testCase.verifyTrue(all(allResults.ParticipantID == 999));
            testCase.verifyTrue(all(allResults.ShapeType == 1));

            expected = independentGroundTruth();

            for i = 1:height(allResults)
                testCase.verifyEqual(allResults.MeanVelocity_SG(i), expected.MeanVelocity_SG, 'RelTol', 1e-9);
                testCase.verifyEqual(allResults.MedianVelocity_SG(i), expected.MedianVelocity_SG, 'RelTol', 1e-9);
                testCase.verifyEqual(allResults.PeakVelocity_SG(i), expected.PeakVelocity_SG, 'RelTol', 1e-9);
                testCase.verifyEqual(allResults.MedianAcceleration_SG(i), expected.MedianAcceleration_SG, 'RelTol', 1e-9);
                testCase.verifyEqual(allResults.MedianJerk_BW(i), expected.MedianJerk_BW, 'RelTol', 1e-9);
                testCase.verifyEqual(allResults.MedianVelocity_BW(i), expected.MedianVelocity_BW, 'RelTol', 1e-9);
            end
        end

    end

end


function cleanupFixture(fixtureDir)
% Dropbox can hold a lock on the just-emptied folder for a few seconds
% (seen 2026-11-09: an empty ID999 was left behind, which preflightN48_2026
% would then count). Retry, then fail loudly rather than leave it silently.
for attempt = 1:10
    if ~isfolder(fixtureDir), return; end
    [ok, msg] = rmdir(fixtureDir, 's');
    if ok, return; end
    pause(1);
end
error('test_runAnalysis:fixtureNotRemoved', 'Could not remove %s (%s). Delete it by hand before any pipeline run.', fixtureDir, msg);
end


function [t, x_px, y_px] = fixtureTrajectory()
% Ellipse (not a circle): a circle has constant curvature, which makes
% the velocity-vs-curvature power-law regression degenerate (IRLS fails
% to converge, Beta_SG6_IRLS -> NaN) -- an artifact of the fixture, not
% a real pipeline behaviour worth testing here. An ellipse has genuine
% curvature variation, same as it is for both the raw fixture CSVs and
% the independent ground-truth calculation -- must be generated
% identically in both places or this stops being a fair comparison.
fs = 240;
n = 400;  % > 2*edgeClip(50)+100 = 200, so it survives runAnalysis_2026's edgeClip check
touchIndex = (1:n)';
t = touchIndex / fs;
a_px = 500; b_px = 250; freqHz = 1;  % 2:1 aspect ratio
theta = 2*pi*freqHz*t;
x_px = a_px*cos(theta) + 1000;  % offset mimics real screen coordinates, irrelevant to kinematics
y_px = b_px*sin(theta) + 1000;
end


function writeFixtureSession(fixtureDir, timeStr)
[~, x_px, y_px] = fixtureTrajectory();
n = length(x_px);
touchIndex = (1:n)';

metaTable = table(1, 1, 'VariableNames', {'trial', 'tracingScene_object1_imageNumber'});
% time_seconds is required since the 2026-07-16 pen-lift fix (detectPenLifts).
% touch_type (2 = Apple Pencil) is required since the 2026-11-09 finger-touch fix (pencilSamplesOnly).
% Uniform at 1/240 s = one continuous stroke, so the expected value is unchanged.
enhTable = table(ones(n,1), repmat({'tracingScene'}, n, 1), ones(n,1), touchIndex, touchIndex/240, x_px, y_px, 2*ones(n,1), ...
    'VariableNames', {'trial', 'scene_name', 'response_index', 'touch_index', 'time_seconds', 'x', 'y', 'touch_type'});

baseName = sprintf('fixture 2026-07-15 %s', timeStr);
writetable(metaTable, fullfile(fixtureDir, [baseName ' tracingSection.csv']));
writetable(enhTable, fullfile(fixtureDir, [baseName ' tracingSection-enhanced.csv']));
end


function expected = independentGroundTruth()
% Replicates runAnalysis_2026's processParticipant transform by hand:
% edgeClip(50 each side) -> pxPerMm(5.209) -> calculatePowerLaw. If this
% test ever needs updating because that transform changes, this is the
% one place to change it to match.
[~, x_px, y_px] = fixtureTrajectory();
edgeClip = 50;
fs = 240;
touchIndex = (1:length(x_px))';

touchIndexClipped = touchIndex(edgeClip+1:end-edgeClip);
x_clipped = x_px(edgeClip+1:end-edgeClip);
y_clipped = y_px(edgeClip+1:end-edgeClip);
tClipped = touchIndexClipped / fs;

pxPerMm = 5.209;   % literal on purpose: guards ipadPointsPerMm() against drift
x_mm = x_clipped / pxPerMm;
y_mm = y_clipped / pxPerMm;

expected = calculatePowerLaw(x_mm, y_mm, tClipped, fs);
end
