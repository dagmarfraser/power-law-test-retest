function writeTableVerified(T, file)
% writeTableVerified - writetable, then fail loudly if the CSV header on disk is wrong
%
% A join.m from FieldTrip or GPstuff earlier on the MATLAB path silently
% breaks writetable (the header row comes out wrong). This writes the table,
% re-reads the first line and errors unless it is exactly the variable names.
% Call it with a one-column probe table before a long run to fail fast.
%
% USAGE: writeTableVerified(T, 'out.csv')
%
% d.s.fraser@bham.ac.uk

writetable(T, file);
fid = fopen(file, 'r');
assert(fid > 0, 'writeTableVerified:reopen', 'Cannot reopen %s after writing.', file);
hdr = fgetl(fid); fclose(fid);
expected = strjoin(T.Properties.VariableNames, ',');
assert(ischar(hdr) && strcmp(hdr, expected), 'writeTableVerified:badHeader', ...
    ['CSV header in %s is wrong (got "%s"). Usually a FieldTrip/GPstuff join.m shadows MATLAB''s: ' ...
     'remove them from the path (which join -all) and re-run.'], file, string(hdr));
end
