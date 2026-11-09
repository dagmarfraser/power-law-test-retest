function iccResults = computeICCA1_R(data, alpha)
% Compute ICC(A,1) absolute agreement using R's irr package via system call
%
% Uses R's irr::icc() with model="twoway", type="agreement", unit="single" --
% this is the correct R equivalent of McGraw & Wong (1996) model A-1 case 3
% (two-way MIXED effects, absolute agreement, single measures), the same
% formula implemented in computeICC.m(data, 'absolute').
%
% NOTE on why this is NOT psych::ICC: psych::ICC's absolute-agreement rows
% (2 and 5) are documented for a two-way RANDOM effects model. irr::icc
% explicitly labels its twoway+agreement output "ICC(A,1)" -- confirmed by
% running it and inspecting icc.name, rather than assumed from the package
% docs alone. This is the companion function to computeICC_R.m, which
% validates the 'consistency' path against psych::ICC row 3 (ICC3).
%
% INPUTS:
%   data:  [n_subjects x n_sessions] matrix
%   alpha: confidence level (default 0.05)
%
% OUTPUTS:
%   iccResults: struct with fields
%     .ICC      - ICC(A,1) coefficient
%     .LowerCI  - Lower confidence bound
%     .UpperCI  - Upper confidence bound
%     .N        - Number of subjects
%     .k        - Number of measurements/sessions
%     .alpha    - Alpha level used
%
% REFERENCE:
%   Gamer M, Lemon J, Fellows I, Singh P (2019) irr: Various Coefficients
%   of Interrater Reliability and Agreement. R package version 0.84.1.
%   ICC(A,1): McGraw & Wong (1996), Table 7, model A-1 case 3.

if nargin < 2
    alpha = 0.05;
end

tempData = fullfile(tempdir, 'matlab_to_r_data_absagree.csv');
tempResults = fullfile(tempdir, 'r_to_matlab_results_absagree.csv');

writematrix(data, tempData);

rScript = sprintf([...
    'suppressMessages(library(irr))\n' ...
    'data_wide <- as.matrix(read.csv("%s", header=FALSE))\n' ...
    'n_subj <- as.integer(nrow(data_wide))\n' ...
    'n_sess <- as.integer(ncol(data_wide))\n' ...
    '\n' ...
    'icc_result <- icc(data_wide, model="twoway", type="agreement", unit="single", conf.level=%f)\n' ...
    '\n' ...
    'stopifnot(icc_result$icc.name == "ICC(A,1)")\n' ...
    '\n' ...
    'result_df <- data.frame(\n' ...
    '  ICC = icc_result$value,\n' ...
    '  LowerCI = icc_result$lbound,\n' ...
    '  UpperCI = icc_result$ubound,\n' ...
    '  N = n_subj,\n' ...
    '  k = n_sess\n' ...
    ')\n' ...
    'write.csv(result_df, "%s", row.names=FALSE)\n'], ...
    tempData, 1 - alpha, tempResults);  % irr::icc wants conf.level (0.95), not alpha (0.05) -- this was the bug

tempScript = fullfile(tempdir, 'compute_icca1.R');
fid = fopen(tempScript, 'w');
fprintf(fid, '%s', rScript);
fclose(fid);

[status, cmdout] = system(sprintf('Rscript %s 2>&1', tempScript));

if status ~= 0
    error('R execution failed:\n%s\nTry installing irr package: Rscript -e "install.packages(''irr'')"', cmdout);
end

opts = detectImportOptions(tempResults);
resultsTable = readtable(tempResults, opts);

iccResults.ICC = resultsTable.ICC(1);
iccResults.LowerCI = resultsTable.LowerCI(1);
iccResults.UpperCI = resultsTable.UpperCI(1);
iccResults.N = resultsTable.N(1);
iccResults.k = resultsTable.k(1);
iccResults.alpha = alpha;

delete(tempData, tempResults, tempScript);

if nargout == 0 || nargin == 0
    fprintf('ICC(A,1) = %.3f [%.3f, %.3f] (N=%d subjects, k=%d sessions)\n', ...
        iccResults.ICC, iccResults.LowerCI, iccResults.UpperCI, ...
        iccResults.N, iccResults.k);
end

end
