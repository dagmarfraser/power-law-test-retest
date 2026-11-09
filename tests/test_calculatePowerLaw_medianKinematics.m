classdef test_calculatePowerLaw_medianKinematics < matlab.unittest.TestCase
% test_calculatePowerLaw_medianKinematics - Verifies the Median{Metric}_{Filter}
% fields added to calculatePowerLaw.m for the MSc student dataset export
% (exportStudentDataset_2026.m).
%
% Three checks, each targeting a different failure mode a silent bug
% could hide behind:
%   1. Constant-speed trajectory (circle): Mean, Median, Peak should all
%      collapse to the same value (within floating-point tolerance) --
%      catches a Median that isn't actually computed from the same
%      per-sample series as Mean/Peak.
%   2. Ellipse (genuinely varying speed): Median must sit strictly below
%      Peak, and must differ from Mean -- catches a copy-paste bug where
%      Median silently duplicates Mean or Peak instead of computing its
%      own statistic.
%   3. Degenerate/too-short trajectory: all Median fields must be NaN,
%      matching the existing Mean/Peak NaN-fallback behaviour in
%      setNaNResults -- catches a Median field left out of that fallback
%      (which would otherwise leave stale/uninitialised data in a row
%      that should be entirely NaN).
%
% Run with: run_matlab_test_file or runtests('test_calculatePowerLaw_medianKinematics')

    methods (Test)

        function constantSpeedCollapsesMeanMedianPeak(testCase)
            fs = 240;
            t = (0:1/fs:5)';
            radius = 50; omega = 2*pi*1;  % 1 Hz circle, constant speed = radius*omega
            x = radius*cos(omega*t);
            y = radius*sin(omega*t);

            r = calculatePowerLaw(x, y, t, fs);

            testCase.verifyEqual(r.MedianVelocity_SG, r.MeanVelocity_SG, 'RelTol', 1e-3);
            testCase.verifyEqual(r.MedianVelocity_SG, r.PeakVelocity_SG, 'RelTol', 1e-3);
            testCase.verifyEqual(r.MedianVelocity_BW, r.MeanVelocity_BW, 'RelTol', 1e-3);
            testCase.verifyEqual(r.MedianAcceleration_SG, r.MeanAcceleration_SG, 'RelTol', 1e-3);
        end

        function varyingSpeedMedianDiffersFromMeanAndPeak(testCase)
            fs = 240;
            t = (0:1/fs:3)';
            a = 50; b = 25;  % ellipse major/minor mm -- speed genuinely varies with curvature
            theta = 2*pi*t;
            x = a*cos(theta);
            y = b*sin(theta);

            r = calculatePowerLaw(x, y, t, fs);

            testCase.verifyLessThan(r.MedianVelocity_SG, r.PeakVelocity_SG);
            testCase.verifyNotEqual(r.MedianVelocity_SG, r.MeanVelocity_SG);
            testCase.verifyLessThan(r.MedianJerk_SG, r.PeakJerk_SG);
        end

        function degenerateTrajectoryReturnsNaNForMedianFields(testCase)
            % Too-short trajectory: SG boundary NaN-ing (sgPad, see
            % calculatePowerLaw comments) wipes the entire valid range,
            % triggering the "No valid data points" / setNaNResults path.
            fs = 240;
            n = 30;  % < 2*sgPad (40 at 240 Hz) -> entirely NaN'd out
            t = (0:n-1)'/fs;
            x = 5*ones(n,1);
            y = 5*ones(n,1);

            r = calculatePowerLaw(x, y, t, fs);

            testCase.verifyTrue(isnan(r.MedianVelocity_BW));
            testCase.verifyTrue(isnan(r.MedianVelocity_SG));
            testCase.verifyTrue(isnan(r.MedianAcceleration_BW));
            testCase.verifyTrue(isnan(r.MedianAcceleration_SG));
            testCase.verifyTrue(isnan(r.MedianJerk_BW));
            testCase.verifyTrue(isnan(r.MedianJerk_SG));
            testCase.verifyEqual(r.NumPoints, 0);
        end

        function allExpectedMedianFieldsExist(testCase)
            % Guards against a field silently missing from the output
            % struct (e.g. calculatePowerLaw's doc header lists them but
            % the code doesn't set them) -- would surface downstream as
            % exportStudentDataset_2026's fail-loud missingColumns error,
            % but better to catch it here, closer to the source.
            fs = 240;
            t = (0:1/fs:1)';
            x = 20*cos(2*pi*t);
            y = 20*sin(2*pi*t);
            r = calculatePowerLaw(x, y, t, fs);

            expectedFields = {'MedianVelocity_BW', 'MedianVelocity_SG', ...
                'MedianAcceleration_BW', 'MedianAcceleration_SG', ...
                'MedianJerk_BW', 'MedianJerk_SG'};
            for i = 1:length(expectedFields)
                testCase.verifyTrue(isfield(r, expectedFields{i}), ...
                    ['Missing field: ' expectedFields{i}]);
            end
        end

    end

end
