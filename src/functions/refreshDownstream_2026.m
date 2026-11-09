function out = refreshDownstream_2026()
% refreshDownstream_2026 - Re-run every output that runN48_2026 does not cover
%
% The second half of the re-run checklist (docs/PublicationTodo.md), in order:
%   mergeQuestionnaires_2026 -> analyseTraitKinematics_2026
%   reportStability_2026, diagnoseShapeStability_2026(5)
%   reportPipelineRobustness_2026, reportNoteEvidence_2026, generateFigures_2026
% Each reads the newest trial_level_results / icc_results, so run it straight
% after runN48_2026('stage','all'). Stops on the first error (no partial
% silent refresh). Records which trial/ICC files it used, and when each step finished.
%
% Long: run in the console (or via parfeval), not through the MCP.
%
% d.s.fraser@bham.ac.uk

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
proc = fullfile(root, 'data', 'processed');
fig = fullfile(root, 'figures');
out.trialFile = newest(proc, 'trial_level_results_2*.csv');
out.iccFile = newest(proc, 'icc_results_2*.csv');
fprintf('refreshDownstream_2026 using %s and %s\n', out.trialFile, out.iccFile);
note = @(s) fprintf('[%s] %s done\n', datestr(now, 'HH:MM:SS'), s);

q = mergeQuestionnaires_2026(root);                         note('mergeQuestionnaires_2026');
out.trait = analyseTraitKinematics_2026(q.merged, proc, fig);   note('analyseTraitKinematics_2026');
out.stability = reportStability_2026(root);                 note('reportStability_2026');
out.shape5 = diagnoseShapeStability_2026(5, root);          note('diagnoseShapeStability_2026(5)');
out.robustness = reportPipelineRobustness_2026(root);       note('reportPipelineRobustness_2026');
[out.theta, out.iccSymmetry] = reportNoteEvidence_2026();  note('reportNoteEvidence_2026');
generateFigures_2026();                                     note('generateFigures_2026');
end

function f = newest(folder, pattern)
d = dir(fullfile(folder, pattern));
assert(~isempty(d), 'refreshDownstream:notFound', 'No %s in %s', pattern, folder);
[~, i] = max([d.datenum]); f = d(i).name;
end
