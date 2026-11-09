#!/bin/bash
# zouCohort_M5.sh - Zou (2012) required N for the N=45 vs N=48 sensitivity analysis, on the Mac
#
# The PC has no R, so compareCohortsN45N48_2026('zouDir', <proc>/zou) writes the ICCs to
# data/processed/zou/zouInput_N45.csv and zouInput_N48.csv; this runs icc_power_analysis.R on each
# and writes zouOutput_N45.csv / zouOutput_N48.csv beside them. Then re-run compareCohorts on the PC
# (it checks the outputs were made from the same ICCs). Fails loudly if an input is missing.
#
# USAGE (Terminal on a Mac with R):  bash src/functions/zouCohort_M5.sh  [project root]
#
# d.s.fraser@bham.ac.uk
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"   # default: the project this script sits in
Z="$ROOT/data/processed/zou"
command -v Rscript >/dev/null || { echo "Rscript not found on PATH" >&2; exit 1; }
for t in N45 N48; do
  [ -f "$Z/zouInput_$t.csv" ] || { echo "Missing $Z/zouInput_$t.csv: run compareCohortsN45N48_2026 on the PC first" >&2; exit 1; }
  echo "== $t"
  Rscript "$ROOT/src/functions/icc_power_analysis.R" "$Z/zouInput_$t.csv" "$Z/zouOutput_$t.csv"
done
echo "Done. Once the files are on the analysis machine, re-run compareCohortsN45N48_2026 there."
