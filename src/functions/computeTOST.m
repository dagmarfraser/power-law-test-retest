function r = computeTOST(x, margin, options)
% computeTOST - Two one-sided tests (TOST) of equivalence to zero within +/-margin (Schuirmann 1987)
%
%   r = computeTOST(d, margin)                  one sample / paired: d = within-person differences
%   r = computeTOST(x, margin, 'ref', y)        independent groups, mean(x) - mean(y), Welch SE and
%                                               Satterthwaite df (no equal-variance assumption)
%
% Equivalent when the (1-2*alpha) CI (90% for alpha=0.05) lies inside (-margin, +margin), which is the
% same decision as both one-sided tests rejecting at alpha. The margin is a smallest effect size of
% interest and must be fixed and justified BEFORE seeing the data.
%
% OUTPUT struct: n (n or [nx ny] as text), est, se, df, lo90, hi90, pLower, pUpper, p (= max of the two),
%   equivalent (logical), margin, note. FAILS LOUDLY on NaN input; returns NaN fields with a note (never a
%   guess) if there are fewer than 2 observations in a group.

arguments
    x (:,1) double
    margin (1,1) double {mustBePositive}
    options.ref (:,1) double = double.empty(0, 1)
    options.alpha (1,1) double {mustBeInRange(options.alpha, 0, 0.5)} = 0.05
end
assert(~any(isnan(x)) && ~any(isnan(options.ref)), 'computeTOST:nan', 'NaN in input; remove or fix upstream.');
paired = isempty(options.ref); y = options.ref;
r = struct('n', "", 'est', NaN, 'se', NaN, 'df', NaN, 'lo90', NaN, 'hi90', NaN, 'pLower', NaN, 'pUpper', NaN, ...
    'p', NaN, 'equivalent', false, 'margin', margin, 'note', "");
if paired
    r.n = string(numel(x));
    if numel(x) < 2, r.note = "needs >= 2 observations"; return; end
    r.est = mean(x); r.se = std(x) / sqrt(numel(x)); r.df = numel(x) - 1;
else
    r.n = sprintf('%d|%d', numel(x), numel(y)); r.n = string(r.n);
    if numel(x) < 2 || numel(y) < 2, r.note = "needs >= 2 observations per group"; return; end
    vx = var(x) / numel(x); vy = var(y) / numel(y);
    r.est = mean(x) - mean(y); r.se = sqrt(vx + vy);
    r.df = (vx + vy)^2 / (vx^2 / (numel(x) - 1) + vy^2 / (numel(y) - 1));
end
tc = tinv(1 - options.alpha, r.df);
r.lo90 = r.est - tc * r.se; r.hi90 = r.est + tc * r.se;
r.pLower = 1 - tcdf((r.est + margin) / r.se, r.df);     % H0: true difference <= -margin
r.pUpper = tcdf((r.est - margin) / r.se, r.df);         % H0: true difference >= +margin
r.p = max(r.pLower, r.pUpper);
r.equivalent = r.lo90 > -margin && r.hi90 < margin;
assert(r.equivalent == (r.p < options.alpha), 'computeTOST:inconsistent', 'CI and p-value decisions disagree.');
end
