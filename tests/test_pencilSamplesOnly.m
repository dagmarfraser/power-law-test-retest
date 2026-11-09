function tests = test_pencilSamplesOnly
% Finger/palm samples (touch_type 0) interleaved on the Pencil's touch_index
% counter must be removed and the Pencil index closed up to 1..n
% (see docs/AnalysisPipeline.md, "Finger and palm touches in the Pencil stream").
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'src', 'functions'));
end

function testDropsFingerAndRenumbers(tc)
idx = (1:10)';
type = [2 2 2 0 0 2 2 0 2 2]';
d = table(idx, idx/240, idx*10, -idx, type, 'VariableNames', {'touch_index', 'time_seconds', 'x', 'y', 'touch_type'});
d = d([10 1:9], :);                         % out of order on input
d = [d; d(3, :)];                           % plus a duplicated Pencil sample
out = pencilSamplesOnly(d);
tc.verifyEqual(out.touch_type, 2*ones(7, 1));
tc.verifyEqual(out.touch_index, (1:7)');
tc.verifyEqual(out.x, [1 2 3 6 7 9 10]'*10);   % Pencil samples kept, in original order
end

function testCleanTrialUnchanged(tc)
idx = (5:20)';
d = table(idx, idx/240, idx, idx, 2*ones(16, 1), 'VariableNames', {'touch_index', 'time_seconds', 'x', 'y', 'touch_type'});
out = pencilSamplesOnly(d);
tc.verifyEqual(out.x, d.x);
tc.verifyEqual(out.time_seconds, d.time_seconds);
end

function testMissingTouchTypeErrors(tc)
d = table((1:3)', (1:3)'/240, (1:3)', (1:3)', 'VariableNames', {'touch_index', 'time_seconds', 'x', 'y'});
tc.verifyError(@() pencilSamplesOnly(d), 'pencilSamplesOnly:noTouchType');
end
