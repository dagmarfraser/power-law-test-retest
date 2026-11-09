classdef test_writeTableVerified < matlab.unittest.TestCase
% test_writeTableVerified - header check passes on a normal write and fails on a corrupted header

    methods (Test)
        function testGoodHeaderPasses(tc)
            f = [tempname '.csv']; c = onCleanup(@() delete(f));
            T = table([1; 2], ["a"; "b"], 'VariableNames', {'ParticipantID', 'Shape'});
            writeTableVerified(T, f);
            tc.verifyEqual(readtable(f, 'TextType', 'string'), T);
        end

        function testBadHeaderErrors(tc)
            % Simulate the join.m shadow: a writetable whose header is wrong
            f = [tempname '.csv']; c = onCleanup(@() delete(f));
            T = table(1, 'VariableNames', {'probe'});
            shadow = fullfile(tempname); mkdir(shadow); cs = onCleanup(@() rmdir(shadow, 's'));
            fid = fopen(fullfile(shadow, 'writetable.m'), 'w');
            fprintf(fid, 'function writetable(~, f)\nfid = fopen(f, ''w''); fprintf(fid, ''Var1\\n1\\n''); fclose(fid);\nend\n'); fclose(fid);
            addpath(shadow); cp = onCleanup(@() rmpath(shadow));
            tc.verifyError(@() writeTableVerified(T, f), 'writeTableVerified:badHeader');
        end
    end
end
