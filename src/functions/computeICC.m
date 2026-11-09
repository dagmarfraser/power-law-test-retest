function result = computeICC(data, type)
% computeICC - ICC(3,1) consistency or ICC(A,1) absolute agreement
%
% Consolidates analysis_2025's computeICC31 (in runICC_2025.m) and
% computeICCA1 (in runICC_2025_AbsAgree.m) into one function. Those two
% were near-identical MSR/MSE/MSC derivations with different final
% formulas -- analysis_2025's own README flagged this duplication as
% technical debt to fix. This is that fix.
%
% INPUTS:
%   data - n x k matrix, n subjects x k raters/sessions/visits
%   type - 'consistency' for ICC(3,1) (Shrout & Fleiss 1979)
%          'absolute'    for ICC(A,1) (McGraw & Wong 1996, Table 7, model A-1 case 3)
%
% OUTPUTS:
%   result.icc, .lb, .ub, .n, .k
%
% Formulas:
%   ICC(3,1) consistency:      (MSR - MSE) / (MSR + (k-1)*MSE)
%   ICC(A,1) absolute agree.:  (MSR - MSE) / (MSR + (k-1)*MSE + (k/n)*(MSC - MSE))
%
% The extra (k/n)*(MSC-MSE) term in absolute agreement penalises
% systematic between-session/between-visit shifts (e.g. practice effects);
% consistency ignores them. See docs/DesignNotes.md and
% docs/EmailIngestionPipeline.md for when each is appropriate.
%
% Cross-validated against R:
%   consistency -- psych::ICC row 3 (ICC3), via computeICC_R.m
%   absolute    -- irr::icc(model="twoway", type="agreement", unit="single"),
%                  via computeICCA1_R.m (irr explicitly labels this output
%                  "ICC(A,1)" -- confirmed by inspecting the returned
%                  icc.name field, not assumed from package docs)
%
% NOTE on the absolute-agreement formula below: it is written to mirror
% irr::icc's Satterthwaite CI derivation directly (obtained by printing
% irr:::icc's R source), but is algebraically IDENTICAL to the original
% analysis_2025 computeICCA1 formula it replaced -- confirmed directly,
% max diff 1.22e-15 across 200 random (n,k) trials. That original formula
% was never wrong; an earlier debugging pass momentarily concluded
% otherwise after miscomparing against a validation wrapper that itself
% had a units bug (irr::icc's conf.level parameter, passed 0.05 instead
% of 0.95). See docs/AnalysisPipeline.md for the full, corrected account.
% Both forms are kept mathematically interchangeable; this one is kept
% for direct traceability against the R source it was checked against.

arguments
    data double
    type (1,:) char {mustBeMember(type, {'consistency', 'absolute'})}
end

[n, k] = size(data);

if n < 2 || k < 2
    result = struct('icc', NaN, 'lb', NaN, 'ub', NaN, 'n', n, 'k', k);
    return;
end

grandMean    = mean(data(:));
subjectMeans = mean(data, 2);   % n x 1
raterMeans   = mean(data, 1);   % 1 x k

SST = sum((data(:) - grandMean).^2);
SSR = k * sum((subjectMeans - grandMean).^2);   % Between subjects
SSC = n * sum((raterMeans   - grandMean).^2);   % Between sessions/visits
SSE = SST - SSR - SSC;                           % Residual error

MSR = SSR / (n - 1);
MSC = SSC / (k - 1);
MSE = SSE / ((n - 1) * (k - 1));

alpha = 0.05;
df1 = n - 1;
df2 = (n - 1) * (k - 1);

switch type
    case 'consistency'
        % ICC(3,1) -- Shrout & Fleiss (1979)
        icc = (MSR - MSE) / (MSR + (k - 1) * MSE);

        F = MSR / MSE;
        F_L = F / finv(1 - alpha/2, df1, df2);
        F_U = F * finv(1 - alpha/2, df2, df1);

        lb = (F_L - 1) / (F_L + k - 1);
        ub = (F_U - 1) / (F_U + k - 1);

    case 'absolute'
        % ICC(A,1) -- McGraw & Wong (1996), model A-1 case 3
        icc = (MSR - MSE) / (MSR + (k - 1)*MSE + (k/n)*(MSC - MSE));

        % CI: exact port of irr::icc(model="twoway", type="agreement",
        % unit="single") -- NOT the ad hoc Satterthwaite approximation this
        % replaced. That approximation matched R's point estimate exactly
        % but diverged substantially on the CI (mean|diff| 0.112, max 0.311
        % on the lower bound across 25 synthetic (n,k) trials -- see
        % docs/AnalysisPipeline.md R validation section). This formula was
        % obtained by printing irr:::icc's source directly, not from the
        % package docs alone, and reproduces its CI bounds exactly.
        a = (k * icc) / (n * (1 - icc));
        b = 1 + (k * icc * (n - 1)) / (n * (1 - icc));
        v = (a*MSC + b*MSE)^2 / ( (a*MSC)^2/(k-1) + (b*MSE)^2/((n-1)*(k-1)) );

        F_L = finv(1 - alpha/2, df1, v);
        F_U = finv(1 - alpha/2, v, df1);

        lb = (n*(MSR - F_L*MSE)) / (F_L*(k*MSC + (k*n - k - n)*MSE) + n*MSR);
        ub = (n*(F_U*MSR - MSE)) / (k*MSC + (k*n - k - n)*MSE + n*F_U*MSR);
end

result = struct('icc', icc, 'lb', lb, 'ub', ub, 'n', n, 'k', k);

end
