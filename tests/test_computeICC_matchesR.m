classdef test_computeICC_matchesR < matlab.unittest.TestCase
% test_computeICC_matchesR - Cross-validate computeICC.m against R
%
% consistency -- vs psych::ICC row 3 (ICC3), via computeICC_R.m
% absolute    -- vs irr::icc(model="twoway", type="agreement", unit="single"),
%                via computeICCA1_R.m
%
% Requires Rscript on PATH plus the psych and irr packages (both
% auto-checked/installed by the respective wrapper functions the first
% time they run). Tests are skipped, not failed, if Rscript is
% unavailable -- this is a cross-validation check, not a core
% correctness test (that's test_computeICC_matchesLegacy.m, pure MATLAB).
%
% History: cross-validating against R surfaced a units bug in
% computeICCA1_R.m itself (irr::icc's conf.level parameter was passed
% 0.05 instead of 0.95, copied from the sibling psych::ICC wrapper where
% the equivalent parameter really is named alpha). That bug briefly
% looked like it meant the original MATLAB absolute-agreement CI formula
% was wrong -- it wasn't; direct comparison showed the original and
% rewritten MATLAB formulas are algebraically identical (diff ~1e-15).
% The only real bug was in the validation script, not the analysis code.
% See docs/AnalysisPipeline.md for the full corrected account.
%
% Run with: run_matlab_test_file or runtests('test_computeICC_matchesR')

    methods (TestClassSetup)
        function checkRAvailable(testCase)
            [status, ~] = system('which Rscript 2>/dev/null || where Rscript 2>nul');
            testCase.assumeEqual(status, 0, 'Rscript not found on PATH -- skipping R cross-validation tests.');
        end
    end

    methods (Test)
        function consistencyMatchesPsychICC(testCase)
            rng(13);
            iccDiffs = []; lbDiffs = []; ubDiffs = [];
            for trial = 1:10
                n = randi([15 50]); k = randi([2 3]);
                data = randn(n,1) + 0.4*randn(n,k);

                m = computeICC(data, 'consistency');
                r = computeICC_R(data);

                iccDiffs(end+1) = abs(m.icc - r.ICC); %#ok<AGROW>
                lbDiffs(end+1)  = abs(m.lb  - r.LowerCI); %#ok<AGROW>
                ubDiffs(end+1)  = abs(m.ub  - r.UpperCI); %#ok<AGROW>
            end
            % Small numerical tolerance expected here (analysis_2025 precedent:
            % mean 0.0004, max 0.0079) -- psych::ICC's F-based CI construction
            % is algebraically equivalent but not bit-identical to ours.
            testCase.verifyLessThan(max(iccDiffs), 0.01);
            testCase.verifyLessThan(max(lbDiffs), 0.02);
            testCase.verifyLessThan(max(ubDiffs), 0.01);
        end

        function absoluteAgreementMatchesIrrICCExactly(testCase)
            rng(13);
            for trial = 1:10
                n = randi([15 50]); k = randi([2 3]);
                data = randn(n,1) + 0.4*randn(n,k);

                m = computeICC(data, 'absolute');
                r = computeICCA1_R(data);

                % Exact match expected: computeICC.m's absolute-agreement CI
                % is a direct port of irr::icc's formula (see computeICC.m
                % docstring), not an independent approximation.
                testCase.verifyEqual(m.icc, r.ICC, 'AbsTol', 1e-9);
                testCase.verifyEqual(m.lb,  r.LowerCI, 'AbsTol', 1e-9);
                testCase.verifyEqual(m.ub,  r.UpperCI, 'AbsTol', 1e-9);
            end
        end
    end

end
