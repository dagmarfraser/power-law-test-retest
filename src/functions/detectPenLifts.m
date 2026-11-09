function [strokeId, nMissing] = detectPenLifts(touchIndex, timeSeconds, fs, liftThreshold)
% DETECTPENLIFTS - Label contiguous pen-down strokes within one trial.
%
% Promoted from a local function inside runAnalysis_2026.m (2026-07-17) so
% that sweepFilterCutoff_2026 and any other caller can segment strokes
% without duplicating the logic. Behaviour is unchanged; runAnalysis_2026's
% output was verified byte-identical after the move.
%
% The digitiser samples uniformly at fs while the pen is on the glass and
% records nothing while it is lifted. That makes touch_index the correct
% clock (it is exactly uniform) but blind: it steps by 1 across a lift, so
% t = touch_index/fs collapses an arbitrarily long pen-up interval into a
% single sample period.
%
% time_seconds cannot be used as the clock instead. It is quantised to 3 d.p.
% and 1/240 = 0.0041667 s does not fit that grid, so consecutive stamps step
% by 0.004/0.005 and sometimes 0.000 (measured: 648 duplicate stamps in
% ~608k samples, i.e. dt = 0, and occasional NEGATIVE steps to -0.006 s --
% it is not even monotonic).
%
% The way out is the residual between the two clocks:
%
%     r = time_seconds - touch_index/fs
%
% Within a stroke both advance at the same rate, so the 1/fs increment
% cancels and r is piecewise-constant: quantisation noise does not
% accumulate (measured SD ~0.0005 s, max excursion ~0.002 s). A pen lift
% steps r by the lift duration (measured floor 0.029 s), giving ~16x
% separation between noise and signal, against only ~4x for raw diff(t).
% time_seconds is therefore used ONLY to locate and size lifts, at a
% resolution where its 1 ms quantisation is irrelevant, and never to time
% an individual sample.
%
% INPUTS:
%   touchIndex    - digitiser sample index for this trial
%   timeSeconds   - recorded wall-clock stamps for this trial (3 d.p.)
%   fs            - sampling frequency (Hz)
%   liftThreshold - OPTIONAL seconds; a step in r above this is a lift.
%                   Default 0.0125 (3 sample periods at 240 Hz): ~6x above
%                   the observed residual noise and ~2.3x below the smallest
%                   real gap, so it is defensible from both sides rather
%                   than tuned against one.
%
% OUTPUTS:
%   strokeId - contiguous stroke label per sample (1,1,...,2,2,...)
%   nMissing - samples missing during each lift, round(step*fs). Validated
%              on ID104 trial 3: 985 pen-down samples + 424 inferred missing
%              = 5.871 s against 5.841 s of recorded elapsed time (0.5%).

if nargin < 4 || isempty(liftThreshold)
    liftThreshold = 0.0125;
end

r = timeSeconds(:) - touchIndex(:)/fs;
dr = diff(r);
isLift = dr > liftThreshold;

strokeId = cumsum([1; double(isLift)]);
nMissing = round(dr(isLift) * fs);

end
