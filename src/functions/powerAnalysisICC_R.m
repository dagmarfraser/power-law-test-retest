function results = powerAnalysisICC_R(options)
% powerAnalysisICC_R  Sample-size analysis via R ICC.Sample.Size package
%
% Calls icc_power_analysis.R via Rscript system call.
% Reads ICC values from ICC_PilotData_for_R.csv (produced by
% exportICCForPowerAnalysis), passes them to R, reads back required N.
%
% USAGE:
%   results = powerAnalysisICC_R()
%
% REQUIRES:
%   - R installed with Rscript on PATH
%   - ICC.Sample.Size package (auto-installed by the R script if missing)
%   - icc_power_analysis.R in the same directory as this file
%   - data/processed/ICC_PilotData_for_R.csv (run exportICCForPowerAnalysis first)
%
% OUTPUTS:
%   results  -- table with columns: ShapeName, ICC_observed, N_required
%   data/processed/icc_power_output.csv saved to disk
%
% Adapted from analysis_2025/powerAnalysisICC_R.m: paths updated for the
% Analysis_2026 clean layout (data/processed/ instead of results/);
% macOS/Windows PATH-finding logic for Rscript unchanged.

arguments
    options.verbose logical = true
    options.inputCSV string = ""    % default data/processed/ICC_PilotData_for_R.csv
    options.outputCSV string = ""   % default data/processed/icc_power_output.csv
end

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));  % src/functions -> src -> root
processedPath = fullfile(projectRoot, 'data', 'processed');
rScript = fullfile(scriptDir, 'icc_power_analysis.R');

%% Ensure R is findable
% MATLAB launched from Dock/GUI does not inherit the shell PATH.
if ismac
    rPaths = {'/usr/local/bin', '/Library/Frameworks/R.framework/Resources/bin'};
    for rp = rPaths
        if ~contains(getenv('PATH'), rp{1})
            setenv('PATH', [rp{1} ':' getenv('PATH')]);
        end
    end
elseif ispc
    [~, found] = system('dir /s /b "C:\Program Files\R\Rscript.exe" 2>nul');
    found = strtrim(found);
    if ~isempty(found)
        parts = strsplit(strtrim(found), newline);
        rBin = fileparts(parts{1});
        if ~contains(getenv('Path'), rBin)
            setenv('Path', [rBin ';' getenv('Path')]);
        end
    end
end

%% Check R is available
[status, ~] = system('which Rscript 2>/dev/null || where Rscript 2>nul');
if status ~= 0
    error(['Rscript not found.\n' ...
           'macOS: install R from https://cran.r-project.org\n' ...
           'Windows: check R is installed and re-run -- script will locate it.']);
end

%% Locate input CSV
inputCSV = fullfile(processedPath, 'ICC_PilotData_for_R.csv');
if options.inputCSV ~= "", inputCSV = char(options.inputCSV); end
if ~isfile(inputCSV)
    error(['ICC_PilotData_for_R.csv not found.\n' ...
           'Run exportICCForPowerAnalysis() first.']);
end

outputCSV = fullfile(processedPath, 'icc_power_output.csv');
if options.outputCSV ~= "", outputCSV = char(options.outputCSV); end

%% Call R script
cmd = sprintf('Rscript "%s" "%s" "%s" 2>&1', rScript, inputCSV, outputCSV);

if options.verbose
    fprintf('Running: %s\n\n', cmd);
end

[status, rOut] = system(cmd);

if options.verbose || status ~= 0
    fprintf('%s\n', rOut);
end

if status ~= 0
    error('R script failed (exit status %d). See output above.', status);
end

%% Read results
results = readtable(outputCSV);

% Merge in N_achieved from the input CSV (added by exportICCForPowerAnalysis;
% the R script only reads/writes ShapeName + ICC_BetweenVisit/ICC_observed,
% so this has to be joined back in on the MATLAB side, not read from R's output).
inputTable = readtable(inputCSV);
if ismember('N_achieved', inputTable.Properties.VariableNames)
    results = outerjoin(results, inputTable(:, {'ShapeName', 'N_achieved'}), ...
        'Keys', 'ShapeName', 'MergeKeys', true, 'Type', 'left');
else
    % Older exports (before N_achieved was added) won't have this column.
    % Fail loud rather than silently falling back to a stale hardcoded N.
    warning('N_achieved not found in %s -- re-run exportICCForPowerAnalysis to get an up to date export. N=61 comparison below is NOT reliable.', inputCSV);
    results.N_achieved = nan(height(results), 1);
end

if options.verbose
    fprintf('\n=== ICC Power Analysis (Zou 2012 via ICC.Sample.Size) ===\n');
    fprintf('p0=0.75, k=2, alpha=0.05, power=0.80  [Koo & Li 2016 threshold]\n\n');
    fprintf('%-12s  %8s  %10s  %10s  %10s\n', 'Shape', 'ICC', 'N_required', 'N_achieved', 'Achieved OK?');
    fprintf('%s\n', repmat('-', 1, 62));
    for i = 1:height(results)
        if isnan(results.N_required(i))
            nStr = '  --';
            okStr = 'intractable';
        else
            nStr = sprintf('%d', results.N_required(i));
            okStr = ternary(results.N_achieved(i) >= results.N_required(i), 'YES', 'no');
        end
        if isnan(results.N_achieved(i))
            achievedStr = '?';
        else
            achievedStr = sprintf('%d', results.N_achieved(i));
        end
        fprintf('%-12s  %8.3f  %10s  %10s  %10s\n', ...
            results.ShapeName{i}, results.ICC_observed(i), nStr, achievedStr, okStr);
    end
    fprintf('\nSaved: %s\n', outputCSV);
end

end

function out = ternary(cond, a, b)
    if cond; out = a; else; out = b; end
end
