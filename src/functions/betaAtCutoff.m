function b = betaAtCutoff(x, y, strokeId, fc, order, zeroLag, regressType, fs, sgPad, LMseeds)
% BETAATCUTOFF - Power-law beta for one trial at one Butterworth corner freq
%
% Promoted out of sweepFilterCutoff_2026 (2026-07-17) so that
% iccVsCutoff_2026 can reuse it rather than fork the logic. Behaviour
% unchanged.
%
% Strokes are differentiated independently (never across a pen lift) and
% each stroke's own boundary samples are masked, matching
% calculatePowerLaw's treatment. Strokes too short to yield a usable
% interior are excluded rather than fabricated.
%
% INPUTS:
%   x, y        - trajectory (mm), column vectors
%   strokeId    - contiguous pen-down stroke label, from detectPenLifts
%   fc          - Butterworth corner frequency (Hz)
%   order       - Butterworth order (4 = Schaal & Sternad)
%   zeroLag     - false = single pass; true = filtfilt (DOUBLES effective order)
%   regressType - regressDataEBR code: 3=Linear, 4=LMLS, 5=IRLS
%   fs          - sampling frequency (Hz)
%   sgPad       - OPTIONAL boundary samples to mask per stroke. Default 20,
%                 matching calculatePowerLaw's SG pad at 240 Hz.
%   LMseeds     - OPTIONAL [VGF, beta] initial conditions for the nonlinear
%                 solvers (types 4 and 5). Default [1, 1/3], matching
%                 calculatePowerLaw line 224. Ignored by type 3 (Linear),
%                 which is why an earlier version passing [] worked for
%                 Linear and errored for IRLS. Note the beta seed IS
%                 one-third; that is the pipeline's own convention, not a
%                 choice made here.
%
% OUTPUT:
%   b - beta, or NaN if too few valid samples survived

arguments
    x double
    y double
    strokeId double
    fc (1,1) double {mustBePositive}
    order (1,1) double {mustBeInteger, mustBePositive}
    zeroLag (1,1) logical
    regressType (1,1) double {mustBeMember(regressType, [3 4 5])}
    fs (1,1) double {mustBePositive}
    sgPad (1,1) double {mustBeInteger, mustBePositive} = 20
    LMseeds (1,2) double = [1, 1/3]
end

b = NaN;

if fc >= fs/2
    warning('betaAtCutoff:cutoffAboveNyquist', ...
        'Cutoff %g Hz is at or above Nyquist (%g Hz); returning NaN', fc, fs/2);
    return;
end

v = [];
k = [];
ws = warning('off', 'all');
for s = unique(strokeId)'
    seg = find(strokeId == s);
    if numel(seg) < 3*sgPad
        continue;   % too short for a usable interior; excluded, not faked
    end
    [dx, dy] = differentiateKinematicsEBR(x(seg), y(seg), 2, [order fc double(zeroLag)], fs);
    vel = sqrt(dx(:,2).^2 + dy(:,2).^2);
    cur = curvatureKinematicEBR(dx(:,2), dy(:,2), dx(:,3), dy(:,3));
    vel([1:sgPad, end-sgPad+1:end]) = NaN;
    v = [v; vel]; %#ok<AGROW>
    k = [k; cur]; %#ok<AGROW>
end
warning(ws);

ok = ~isnan(v) & ~isnan(k) & v > 1e-10 & k > 1e-10;
if sum(ok) > 50
    ws = warning('off', 'all');
    b = regressDataEBR(v(ok), k(ok), regressType, LMseeds, 0, 0);
    warning(ws);
end

end
