function outputTable = exportICCForPowerAnalysis(iccResults, options)
% exportICCForPowerAnalysis - Extract ShapeName/ICC_BetweenVisit for the
% R power-analysis script, from the consolidated runICC_2026 output
%
% Replaces analysis_2025's report_IRLS_forPowerAnalysis.m /
% report_IRLS_ICC31_forPowerAnalysis.m, which were tied to a single named
% pipeline (SG6+IRLS) and duplicated between the two ICC types. This
% version takes the pipeline and ICC type as arguments so it works for
% any of the 6 pipelines without copy-pasting the function.
%
% INPUTS:
%   iccResults - output table from runICC_2026()
%   options.parameter - which pipeline column to export (default 'Beta_SG6_IRLS',
%                        the analysis_2025 pre-specified confirmatory method)
%   options.iccType    - 'absolute' (default) or 'consistency'. Absolute
%                        agreement is the analysis_2025 precedent for the
%                        confirmatory N target (penalises practice-effect
%                        drift; see docs/DesignNotes.md).
%   options.savePath   - where to write the CSV (default data/processed/
%                        relative to project root)
%
% OUTPUTS:
%   outputTable - table with ShapeName, ICC_BetweenVisit (also written to CSV)

arguments
    iccResults table
    options.parameter (1,:) char = 'Beta_SG6_IRLS'
    options.iccType (1,:) char {mustBeMember(options.iccType, {'absolute', 'consistency'})} = 'absolute'
    options.savePath string = ""
end

mask = strcmp(iccResults.Parameter, options.parameter) & strcmp(iccResults.ICCType, options.iccType);
subset = iccResults(mask, :);

if isempty(subset)
    error('No rows found for parameter=%s, ICCType=%s. Check runICC_2026() was run and the parameter name matches a Beta_{Filter}_{Method} column.', ...
        options.parameter, options.iccType);
end

outputTable = table();
outputTable.ShapeName = string(subset.ShapeName);
outputTable.ICC_BetweenVisit = subset.ICC_BetweenVisit;
outputTable.N_achieved = subset.ICC_BetweenVisit_N;

if options.savePath == ""
    scriptDir = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(fileparts(scriptDir));
    options.savePath = fullfile(projectRoot, 'data', 'processed', 'ICC_PilotData_for_R.csv');
end

writetable(outputTable, options.savePath);
fprintf('Exported %d rows (%s, %s) to: %s\n', height(outputTable), options.parameter, options.iccType, options.savePath);

% N_achieved is the per-shape N actually used in the between-visit ICC
% calculation (from runICC_2026's ICC_BetweenVisit_N) -- carried through
% so powerAnalysisICC_R can compare N_required against what was actually
% achieved, rather than a hardcoded target that goes stale as the cohort
% grows (see powerAnalysisICC_R.m's own history note on this).

end
