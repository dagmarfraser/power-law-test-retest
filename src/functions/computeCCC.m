function result = computeCCC(data)
% computeCCC - Lin's Concordance Correlation Coefficient (Lin 1989)
%
% Provided because CCC is the conventional agreement statistic in the
% method-comparison / Bland-Altman literature, and readers coming from that
% side reasonably ask why this project reports ICC(A,1) instead. The answer
% is that for k=2 they are the SAME STATISTIC: given n, each determines the
% other exactly. This function exists so that claim is reproducible rather
% than asserted, and so the number can be quoted directly if a reviewer
% wants it.
%
% INPUTS:
%   data - n x 2 matrix, n subjects x 2 raters/sessions/visits.
%          k=2 only: Lin's CCC is defined for paired measurements. A k>2
%          input is an error, not something to silently collapse.
%
% OUTPUTS:
%   result.ccc, .lb, .ub, .n, .k
%
% POINT ESTIMATE (Lin 1989), using population (1/n) moments as Lin defines:
%
%   CCC = 2*Sxy / (Sx^2 + Sy^2 + (mx - my)^2)
%
% Equivalently CCC = 1 - E[(x-y)^2] / (Sx^2 + Sy^2 + (mx-my)^2): one minus
% the observed disagreement over the disagreement expected if the two
% measurements were unrelated. That denominator is what ICC(A,1) also
% penalises (subject variance, plus error, plus the between-visit mean
% shift), which is why the two coincide -- it is what "absolute agreement"
% means. Consistency-flavoured ICC(3,1) drops the mean-shift term and so is
% NOT equivalent to CCC.
%
% EXACT RELATIONSHIP TO ICC(A,1), for k=2:
%
%   ICC(A,1) = CCC / (1 - (1-CCC)/n)        CCC = (n-1)*ICC / (n - ICC)
%
% Derivation: for k=2 the ANOVA mean squares reduce to
%   MSR - MSE = 2*n*Sxy/(n-1)
%   MSR + MSE = n*(Sx^2 + Sy^2)/(n-1)
% and the ICC(A,1) denominator collapses to D - E[(x-y)^2]/n, where
% D = Sx^2 + Sy^2 + (mx-my)^2 is exactly CCC's denominator. So the two
% differ only by one 1/n term. Verified to machine precision (residual
% ~1e-16) on all five 2026 shapes, and by tests/test_computeCCC_matchesICC.m
% on random data. Nickerson (1997) makes the same point analytically.
%
% Consequences worth knowing:
%   - CCC carries NO information beyond ICC(A,1) and n. Reporting both is a
%     presentational choice, not a second piece of evidence.
%   - The gap is exactly
%
%         ICC - CCC = CCC*(1-CCC) / (n - 1 + CCC)
%
%     (verified to 5.6e-16 over 500 random trials). Note the denominator is
%     n-1+CCC, NOT n: an earlier draft of this header used the CCC*(1-CCC)/n
%     approximation and claimed 0.25/n as an upper bound, which is wrong --
%     the true gap is slightly larger, and tests/test_computeCCC_matchesICC.m
%     caught it. The correct bound is 0.25/(n-1), since CCC*(1-CCC) <= 0.25
%     and n-1+CCC >= n-1 for CCC >= 0.
%   - The gap therefore vanishes as CCC -> 0 and as CCC -> 1, and peaks near
%     CCC = 0.5. At n=31 the true maximum is 0.0082 (bound 0.0083), so the
%     two can only disagree enough to matter for a Koo & Li classification if
%     the estimate sits within ~0.008 of a band edge.
%   - The gap shrinks as 1/n: true max 0.0025 at n=100.
%   - SIGN MATTERS. The transform divides by (1 - (1-CCC)/n) < 1, so it
%     inflates magnitude: CCC < ICC when both are positive, but CCC > ICC
%     when both are negative (the ordering flips at zero). Do not assume
%     CCC <= ICC in general; it holds only for CCC >= 0.
%
% CONFIDENCE INTERVAL: obtained by mapping computeICC(data,'absolute')'s
% exact F-based bounds through the identity above, NOT by Lin's asymptotic
% z-transform. Two reasons. (1) The map is strictly monotone increasing
% (d/dICC of (n-1)*ICC/(n-ICC) is n*(n-1)/(n-ICC)^2 > 0), so bounds
% transform directly and the interval keeps its exact coverage. (2) Lin's
% z-transform interval is asymptotic and conventionally wants n >= 30; this
% project's confirmatory N is 31, which clears that only barely, and would
% not clear it at all for a shape-level subgroup. Borrowing the F-based
% interval sidesteps the question rather than relying on an approximation
% at the edge of its validity.
%
% See docs/AnalysisPipeline.md ("ICC: both variants, one pass") for where
% this sits relative to the pre-specified primary, which remains ICC(A,1).

arguments
    data double
end

[n, k] = size(data);

if k ~= 2
    error('computeCCC:notPaired', '%s', ...
        ['Lin''s CCC is defined for paired measurements (k=2); got k=' num2str(k) ...
         '. For k>2 use computeICC(data, ''absolute'') instead.']);
end

if n < 2
    result = struct('ccc', NaN, 'lb', NaN, 'ub', NaN, 'n', n, 'k', k);
    return;
end

x = data(:,1);
y = data(:,2);
mx = mean(x);
my = mean(y);

% Population (1/n) moments, as Lin (1989) defines them.
Sx2 = mean((x - mx).^2);
Sy2 = mean((y - my).^2);
Sxy = mean((x - mx) .* (y - my));

denom = Sx2 + Sy2 + (mx - my)^2;
if denom <= 0
    % Zero variance and identical means: no disagreement to measure, but
    % also nothing to agree about. NaN rather than a fabricated 1.
    result = struct('ccc', NaN, 'lb', NaN, 'ub', NaN, 'n', n, 'k', k);
    return;
end

ccc = 2 * Sxy / denom;

% CI by transforming ICC(A,1)'s exact F-based bounds (see header).
iccResult = computeICC(data, 'absolute');
lb = (n - 1) * iccResult.lb / (n - iccResult.lb);
ub = (n - 1) * iccResult.ub / (n - iccResult.ub);

% Fail loud if the identity does not hold: it is exact, so any deviation
% means one of the two implementations has drifted and the number should
% not be trusted. This is a coherence check, not a fallback.
cccFromICC = (n - 1) * iccResult.icc / (n - iccResult.icc);
if abs(ccc - cccFromICC) > 1e-9
    error('computeCCC:identityViolated', '%s', ...
        ['CCC from Lin''s formula (' num2str(ccc, '%.12g') ') disagrees with CCC ' ...
         'derived from computeICC(...,''absolute'') (' num2str(cccFromICC, '%.12g') ...
         '). These are algebraically identical for k=2, so one of the two ' ...
         'implementations is wrong. See tests/test_computeCCC_matchesICC.m.']);
end

result = struct('ccc', ccc, 'lb', lb, 'ub', ub, 'n', n, 'k', k);

end
