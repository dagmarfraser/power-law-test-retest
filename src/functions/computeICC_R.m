function iccResults = computeICC_R(data, alpha)
% Compute ICC(3,1) using R's psych package via system call
%
% Uses R's psych::ICC() function with explicit type="ICC3" 
% to match MATLAB's ICC(3,1) implementation (two-way mixed, consistency).
%
% INPUTS:
%   data: [n_subjects x n_sessions] matrix 
%   alpha: confidence level (default 0.05)
%
% OUTPUTS:
%   iccResults: struct with fields
%     .ICC      - ICC(3,1) coefficient
%     .LowerCI  - Lower confidence bound
%     .UpperCI  - Upper confidence bound
%     .N        - Number of subjects
%     .k        - Number of measurements/sessions
%     .varw     - Within-subject variance (MSW)
%     .vara     - Between-subject variance (MSb - MSW)/k
%     .alpha    - Alpha level used
%
% REFERENCE:
%   Revelle W (2024) psych: Procedures for Psychological, 
%   Psychometric, and Personality Research. R package version 2.4.6.
%   ICC(3,1): Shrout & Fleiss (1979) Case 3 - two-way mixed effects
%
% Companion function: computeICCA1_R.m, which validates the 'absolute'
% path against irr::icc (not psych::ICC -- see that function's docstring
% for why psych::ICC's absolute-agreement rows are not the right
% comparison for a two-way mixed-effects ICC(A,1)).
%
% Unchanged from analysis_2025/computeICC_R.m -- uses tempdir for I/O,
% no project-specific paths, so no adaptation was needed.

if nargin < 2
    alpha = 0.05;
end

% Write data to temporary CSV
tempData = fullfile(tempdir, 'matlab_to_r_data.csv');
tempResults = fullfile(tempdir, 'r_to_matlab_results.csv');

writematrix(data, tempData);

% R script using psych package for ICC(3,1)
rScript = sprintf([...
    'suppressMessages(library(psych))\n' ...
    'data_wide <- as.matrix(read.csv("%s", header=FALSE))\n' ...
    'n_subj <- as.integer(nrow(data_wide))\n' ...
    'n_sess <- as.integer(ncol(data_wide))\n' ...
    '\n' ...
    '# Suppress lme4 warnings\n' ...
    'suppressWarnings({\n' ...
    '  icc_result <- ICC(data_wide, alpha=%f)\n' ...
    '})\n' ...
    '\n' ...
    '# Extract ICC(3,1) - row 3 is "Single_fixed_raters" (ICC3)\n' ...
    'icc_val <- as.numeric(icc_result$results[3, "ICC"])\n' ...
    'lb_val <- as.numeric(icc_result$results[3, "lower bound"])\n' ...
    'ub_val <- as.numeric(icc_result$results[3, "upper bound"])\n' ...
    '\n' ...
    '# Variance components: MSW directly, MSb from stats[1,3]\n' ...
    'msb <- as.numeric(icc_result$stats[1, 3])  # Row 1 (subjects), Column 3 (MS)\n' ...
    'msw <- as.numeric(icc_result$MSW)          # Within-subject MS\n' ...
    'varw_val <- msw\n' ...
    'vara_val <- (msb - msw) / n_sess\n' ...
    '\n' ...
    'result_df <- data.frame(\n' ...
    '  ICC = icc_val,\n' ...
    '  LowerCI = lb_val,\n' ...
    '  UpperCI = ub_val,\n' ...
    '  N = n_subj,\n' ...
    '  k = n_sess,\n' ...
    '  varw = varw_val,\n' ...
    '  vara = vara_val\n' ...
    ')\n' ...
    'write.csv(result_df, "%s", row.names=FALSE)\n'], ...
    tempData, alpha, tempResults);

tempScript = fullfile(tempdir, 'compute_icc.R');
fid = fopen(tempScript, 'w');
fprintf(fid, '%s', rScript);
fclose(fid);

% Execute R (suppress warnings)
[status, cmdout] = system(sprintf('Rscript %s 2>&1', tempScript));

if status ~= 0
    error('R execution failed:\n%s\nTry installing psych package: Rscript -e "install.packages(''psych'')"', cmdout);
end

% Read results
opts = detectImportOptions(tempResults);
resultsTable = readtable(tempResults, opts);

% Extract values
iccResults.ICC = resultsTable.ICC(1);
iccResults.LowerCI = resultsTable.LowerCI(1);
iccResults.UpperCI = resultsTable.UpperCI(1);
iccResults.N = resultsTable.N(1);
iccResults.k = resultsTable.k(1);
iccResults.varw = resultsTable.varw(1);
iccResults.vara = resultsTable.vara(1);
iccResults.alpha = alpha;

% Cleanup
delete(tempData, tempResults, tempScript);

% Optional: Print summary
if nargout == 0 || nargin == 0
    fprintf('ICC(3,1) = %.3f [%.3f, %.3f] (N=%d subjects, k=%d sessions)\n', ...
        iccResults.ICC, iccResults.LowerCI, iccResults.UpperCI, ...
        iccResults.N, iccResults.k);
end

end
