function out = runN48_2026(options)
% runN48_2026 - Single entry point for the N=48 re-run (core of the checklist in docs/PublicationTodo.md)
%
% STAGES (options.stage)
%   'preflight'  (default) read-only readiness report: preflightN48_2026
%   'pipeline'   preflight -> runAnalysis_2026 -> runICC_2026 -> exportICCForPowerAnalysis -> powerAnalysisICC_R
%   'compare'    preflight -> compareCohortsN45N48_2026, reportShiftTOST_2026, plotCorridorOfStability_2026
%                (needs a finished 'pipeline' run)
%   'all'        pipeline then compare
%
% The 'pipeline' and 'all' stages are long: run them yourself in the MATLAB console, not via the MCP.
% Stops with an error if preflight is not ready, or if the number of participants processed differs
% from the number preflight expected (no silent N). Plan: docs/SensitivityPlan_N48.md.
%
% NOT run here (need inputs or a decision first; see docs/PublicationTodo.md re-run checklist):
%   updated CATI/M-EDL sheet -> mergeQuestionnaires_2026 -> analyseTraitKinematics_2026
%   reportStability_2026, diagnoseShapeStability_2026(5), reportPipelineRobustness_2026, generateFigures_2026
%   regenerate handover/, then refresh every literal N=45 number in the docs

arguments
    options.stage (1,1) string {mustBeMember(options.stage, ["preflight", "pipeline", "compare", "all"])} = "preflight"
    options.useParfor (1,1) logical = true
end
out = struct();
out.preflight = preflightN48_2026();
if options.stage == "preflight", return; end
assert(out.preflight.ready, 'runN48:notReady', 'Preflight says the data are not ready (report above); nothing was run.');

if any(options.stage == ["pipeline", "all"])
    [out.allResults, out.participantSummary] = runAnalysis_2026('verbose', true, 'useParfor', options.useParfor);
    nDone = height(out.participantSummary);
    assert(nDone == out.preflight.expectedN, 'runN48:unexpectedN', ...
        'runAnalysis_2026 processed %d participants but preflight expected %d.', nDone, out.preflight.expectedN);
    out.iccResults = runICC_2026();
    exportICCForPowerAnalysis(out.iccResults);      % overwrites data/processed/ICC_PilotData_for_R.csv (baseline copy is frozen)
    out.power = powerAnalysisICC_R();               % overwrites data/processed/icc_power_output.csv (baseline copy is frozen)
end
if any(options.stage == ["compare", "all"])
    zd = ""; if ispc, zd = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'data', 'processed', 'zou'); end
    out.comparison = compareCohortsN45N48_2026('zouDir', zd);   % PC has no R: Zou N via zouCohort_M5.sh on the Mac
    out.shiftTOST = reportShiftTOST_2026();            % V2-V1 shift equivalence on the newest (final-N) run
    out.corridor = plotCorridorOfStability_2026();     % ICC stability vs n; PNG to figures/
end
end
