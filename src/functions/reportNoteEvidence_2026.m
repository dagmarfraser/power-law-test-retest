function [thetaTable, iccSymmetryTable] = reportNoteEvidence_2026(options)
% REPORTNOTEEVIDENCE_2026 - Reproduces the two evidence tables cited in
% docs/AnalysisPipeline.md's "Absolute beta magnitude vs theoretical
% predictions" section:
%   1. Observed beta (SG6+IRLS, BW+Linear) vs Huh & Sejnowski (2015)
%      theoretical prediction, per shape, as %-of-theory.
%   2. ICC(absolute agreement) vs ICC(consistency), between-visit, for
%      Beta_SG6_IRLS and MeanJerk_SG across all 5 shapes -- confirming
%      the two ICC types are near-interchangeable in this cohort (no
%      shared systematic between-visit shift for either parameter).
%
% USAGE:
%   [thetaTable, iccSymmetryTable] = reportNoteEvidence_2026()
%   reportNoteEvidence_2026('trialFile', 'path.mat', 'iccFile', 'path.mat')
%
% Defaults to the most recent trial_level_results_*.mat and
% icc_results_*.mat in data/processed/. Both output tables are also
% written there as timestamped CSVs, so the numbers in the doc note can
% be regenerated and diffed against rather than hand-copied from a
% console session.

arguments
    options.trialFile string = ""
    options.iccFile string = ""
    options.verbose logical = true
end

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));
processedPath = fullfile(projectRoot, 'data', 'processed');

trialFile = resolveLatestFile(options.trialFile, processedPath, 'trial_level_results_2*.mat');
iccFile = resolveLatestFile(options.iccFile, processedPath, 'icc_results_2*.mat');

fprintf('Trial data: %s\n', trialFile);
fprintf('ICC data:   %s\n\n', iccFile);

load(trialFile, 'allResults');
load(iccFile, 'iccResults');

thetaTable = betaVsTheory(allResults);
iccSymmetryTable = iccTypeSymmetry(iccResults);

if options.verbose
    fprintf('=== Beta vs theoretical (Huh & Sejnowski 2015) ===\n');
    disp(thetaTable);
    fprintf('\n=== ICC absolute vs consistency, between-visit (Beta_SG6_IRLS, MeanJerk_SG) ===\n');
    disp(iccSymmetryTable);
    fprintf('\nMax |absolute - consistency| across all rows: %.4f\n', max(abs(iccSymmetryTable.Diff)));
end

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
writetable(thetaTable, fullfile(processedPath, sprintf('beta_vs_theory_%s.csv', timestamp)));
writetable(iccSymmetryTable, fullfile(processedPath, sprintf('icc_type_symmetry_%s.csv', timestamp)));

end


function f = resolveLatestFile(explicit, processedPath, pattern)
if explicit ~= ""
    f = explicit;
    return;
end
files = dir(fullfile(processedPath, pattern));
if isempty(files)
    error('No files matching %s found in %s', pattern, processedPath);
end
[~, idx] = max([files.datenum]);
f = fullfile(processedPath, files(idx).name);
end


function t = betaVsTheory(allResults)
shapeNames = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
% Cursive has no single theoretical phi -- freehand is a weighted
% combination of frequencies (Huh & Sejnowski 2015), not a pure one --
% so no theoretical value is given for it.
phiValues = [0.4, 0.8, 2, 4, NaN];

nShapes = length(shapeNames);
ShapeName = shapeNames(:);
Phi = phiValues(:);
Theoretical = arrayfun(@hsTheoreticalBeta, Phi);
Beta_SG6_IRLS_mean = nan(nShapes, 1);
Beta_SG6_IRLS_SD = nan(nShapes, 1);
Beta_BW_Linear_mean = nan(nShapes, 1);
Beta_BW_Linear_SD = nan(nShapes, 1);

for s = 1:nShapes
    mask = allResults.ShapeType == s;
    Beta_SG6_IRLS_mean(s) = mean(allResults.Beta_SG6_IRLS(mask), 'omitnan');
    Beta_SG6_IRLS_SD(s) = std(allResults.Beta_SG6_IRLS(mask), 'omitnan');
    Beta_BW_Linear_mean(s) = mean(allResults.Beta_BW_Linear(mask), 'omitnan');
    Beta_BW_Linear_SD(s) = std(allResults.Beta_BW_Linear(mask), 'omitnan');
end

PctOfTheory_SG6IRLS = 100 * Beta_SG6_IRLS_mean ./ Theoretical;
PctOfTheory_BWLinear = 100 * Beta_BW_Linear_mean ./ Theoretical;

t = table(ShapeName, Phi, Theoretical, Beta_SG6_IRLS_mean, Beta_SG6_IRLS_SD, ...
    Beta_BW_Linear_mean, Beta_BW_Linear_SD, PctOfTheory_SG6IRLS, PctOfTheory_BWLinear);
end


function beta = hsTheoreticalBeta(phi)
% H&S (2015) analytic prediction: beta(phi) = 2/3 * (1+phi^2/2) / (1+phi^2+phi^4/15)
% NaN phi (freehand, no single frequency) -> NaN beta, not an error.
% Verified against Cook et al. (2026)'s stated theoretical values across
% their full shape range (phi = 2/33 .. 4): matches to within ~0.02-0.09
% everywhere, confirming this is the right form of the formula (an
% earlier version of this function had phi^2/2 in the denominator by
% mistake, copied over from the numerator term -- that version matched
% nothing and silently overstated every theoretical anchor except phi
% near zero; caught by cross-checking this function's own output against
% Cook's explicitly stated values before trusting it, not by inspection).
if isnan(phi)
    beta = NaN;
    return;
end
beta = (2/3) * (1 + phi^2/2) / (1 + phi^2 + phi^4/15);
end


function t = iccTypeSymmetry(iccResults)
params = {'Beta_SG6_IRLS', 'MeanJerk_SG'};
shapeNames = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};

rows = struct('Parameter', {}, 'ShapeName', {}, 'ICC_Absolute', {}, 'ICC_Consistency', {}, 'Diff', {});
for p = 1:length(params)
    for s = 1:length(shapeNames)
        a = iccResults.ICC_BetweenVisit(strcmp(iccResults.Parameter, params{p}) & ...
            strcmp(iccResults.ICCType, 'absolute') & strcmp(iccResults.ShapeName, shapeNames{s}));
        c = iccResults.ICC_BetweenVisit(strcmp(iccResults.Parameter, params{p}) & ...
            strcmp(iccResults.ICCType, 'consistency') & strcmp(iccResults.ShapeName, shapeNames{s}));
        rows(end+1).Parameter = params{p}; %#ok<AGROW>
        rows(end).ShapeName = shapeNames{s};
        rows(end).ICC_Absolute = a;
        rows(end).ICC_Consistency = c;
        rows(end).Diff = a - c;
    end
end
t = struct2table(rows);
end
