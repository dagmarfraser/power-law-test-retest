function C = compareMDCThresholds_2026(semFile)
% compareMDCThresholds_2026 - Table 1 MDC95/SEM against 0.03 (clinical difference) and 0.0108 (BRM SEM limit)
%
% 0.0108 = 0.03/2.77 is the BRM registration's adequacy limit for SEM (SEM < MDC/2.77),
% i.e. an SEM-scale number. The like-for-like comparisons are therefore
%   MDC95 vs 0.03   and   SEM vs 0.0108,
% which give the same ratio (MDC95 = 1.96*sqrt(2)*SEM = 2.772*SEM). MDC95 vs 0.0108 mixes
% scales; it is written out only so the mismatch is visible, flagged in column Note.
% Note also: BRM's SEM is a within-occasion pipeline repeatability (simulated replicates);
% the MSc SEM is between-visit (two sessions days apart), so it includes day-to-day change.
%
% Writes data/processed/mdcThresholdComparison_<ts>.csv beside semFile.
% USAGE: C = compareMDCThresholds_2026();   % newest semReliability_N48_*.csv
% d.s.fraser@bham.ac.uk

proc = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'data', 'processed');
if nargin < 1
    d = dir(fullfile(proc, 'semReliability_N48_*.csv'));
    assert(~isempty(d), 'compareMDC:noFile', 'No semReliability_N48_*.csv in %s', proc);
    [~, i] = max([d.datenum]); semFile = fullfile(proc, d(i).name);
end
S = readtable(semFile, 'VariableNamingRule', 'preserve');
CLIN = 0.03; SEMLIM = 0.03/2.77;                 % 0.01083, quoted as 0.0108 by BRM
C = table(string(S.ShapeName), S.SEM_A, S.SEM_A_LB, S.SEM_A_UB, S.MDC95_A, S.MDC95_A_LB, S.MDC95_A_UB, ...
    'VariableNames', {'Shape','SEM_A','SEM_LB','SEM_UB','MDC95','MDC95_LB','MDC95_UB'});
C.MDC95_over_0p03 = C.MDC95 / CLIN;  C.MDC95_over_0p03_LB = C.MDC95_LB / CLIN;  C.MDC95_over_0p03_UB = C.MDC95_UB / CLIN;
C.SEM_over_0p0108 = C.SEM_A / SEMLIM; C.SEM_over_0p0108_LB = C.SEM_LB / SEMLIM;  C.SEM_over_0p0108_UB = C.SEM_UB / SEMLIM;
C.MDC95_over_0p0108_MISMATCHED = C.MDC95 / SEMLIM;
C.Meets_0p03 = C.MDC95_UB < CLIN;  C.Meets_0p0108 = C.SEM_UB < SEMLIM;
C.Note = repmat("MDC95/0.0108 compares an MDC with an SEM limit; do not report", height(C), 1);
[~, n] = fileparts(semFile);
out = fullfile(proc, "mdcThresholdComparison_" + string(datetime('now'), 'yyyyMMdd_HHmmss') + ".csv");
writetable(C, out);
fprintf('Source: %s\nWrote %s\n', n, out);
disp(C(:, {'Shape','SEM_A','MDC95','MDC95_over_0p03','SEM_over_0p0108','MDC95_over_0p0108_MISMATCHED','Meets_0p03','Meets_0p0108'}));
end
