classdef test_computeICC_matchesLegacy < matlab.unittest.TestCase
% test_computeICC_matchesLegacy - Regression test: consolidated
% computeICC.m must be bit-identical to analysis_2025's original
% computeICC31 (in runICC_2025.m) and computeICCA1 (in
% runICC_2025_AbsAgree.m), reproduced here as old_computeICC31.m /
% old_computeICCA1.m for comparison purposes only.
%
% This exists because computeICC.m consolidates two previously-separate,
% independently-maintained functions into one switch-based function.
% That consolidation should be behaviour-preserving -- this test proves
% it, rather than asserting it from having "just refactored carefully".
%
% Run with: run_matlab_test_file or runtests('test_computeICC_matchesLegacy')

    methods (Test)
        function consistencyMatchesLegacyExactly(testCase)
            % ICC(3,1) consistency: formula unchanged by consolidation,
            % must match the original old_computeICC31.m bit-for-bit.
            rng(7);
            for trial = 1:200
                n = randi([10 100]);
                k = randi([2 3]);
                data = randn(n,1) + 0.3*randn(n,k);

                oldC = old_computeICC31(data);
                newC = computeICC(data, 'consistency');
                testCase.verifyEqual(newC.icc, oldC.icc, 'AbsTol', 0);
                testCase.verifyEqual(newC.lb,  oldC.lb,  'AbsTol', 0);
                testCase.verifyEqual(newC.ub,  oldC.ub,  'AbsTol', 0);
            end
        end

        function absoluteAgreementPointEstimateMatchesLegacy(testCase)
            % ICC(A,1) point estimate formula unchanged by consolidation --
            % only the CI construction was rewritten (see below), after R
            % validation showed the original CI approximation in
            % old_computeICCA1.m was wrong despite the point estimate
            % being right. So: point estimate must still match old code;
            % CI is deliberately NOT compared against old_computeICCA1
            % here (that comparison now lives against irr::icc directly,
            % see docs/AnalysisPipeline.md -- this is a MATLAB-only test
            % file with no R dependency, so it can't call irr::icc here).
            rng(7);
            for trial = 1:200
                n = randi([10 100]);
                k = randi([2 3]);
                data = randn(n,1) + 0.3*randn(n,k);

                oldA = old_computeICCA1(data);
                newA = computeICC(data, 'absolute');
                testCase.verifyEqual(newA.icc, oldA.icc, 'AbsTol', 0);
            end
        end

        function degenerateInputsReturnNaN(testCase)
            % n<2 or k<2 should return NaN, not error
            result = computeICC(ones(1,3), 'consistency');
            testCase.verifyTrue(isnan(result.icc));

            result = computeICC(ones(5,1), 'absolute');
            testCase.verifyTrue(isnan(result.icc));
        end
    end

end
