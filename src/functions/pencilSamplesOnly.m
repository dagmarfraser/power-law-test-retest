function d = pencilSamplesOnly(d)
% PENCILSAMPLESONLY - Keep one trial's Apple Pencil samples, in order, on a gap-free index.
%
% The -enhanced.csv stream mixes finger/palm touches (touch_type 0) with the
% Pencil (touch_type 2). Both share ONE touch_index counter, so a finger
% sample sits between two Pencil samples (measured 2026-11-09: 926 of 14,389
% N=48 trials, all five shapes, jumps of 50-120 mm, time_seconds stepping
% backwards). They are dropped here.
%
% Dropping them leaves holes in the Pencil's touch_index, which would put
% false gaps into t = touch_index/fs. touch_index is therefore renumbered
% 1..n after filtering. In clean trials the Pencil index already steps by 1
% (0 of 13,463 clean trials had a step > 1), so their results are unchanged.
% Pen lifts are still found from time_seconds by detectPenLifts.
%
% INPUT/OUTPUT: d - table for one trial with touch_type, touch_index, time_seconds, x, y
%
% See diagnoseTouchTypeFilter_2026 for the impact check.
% d.s.fraser@bham.ac.uk

assert(ismember('touch_type', d.Properties.VariableNames), 'pencilSamplesOnly:noTouchType', ...
    'touch_type column missing: cannot separate Pencil from finger samples.');
d = d(d.touch_type == 2, :);
[~, ui] = unique(d.touch_index, 'stable');
d = sortrows(d(ui, :), 'touch_index');
d.touch_index = (1:height(d))';
end
