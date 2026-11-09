#!/usr/bin/env python3
"""
Analyze session timestamps in data/raw/automatic/ to find visit groupings
and anomalies.

Trusts timestamps over email subject lines -- analysis_2025 saw multiple
emails labelled "pt2" whose timestamps confirmed they were actually
Visit 1. Do not resolve flagged issues by reading the subject text;
resolve them by checking the timestamp grouping this script prints.

Adapted from analysis_2025/data2025/analyzeTimings.py. Logic unchanged;
paths updated, constants pulled to the top, `import re` moved out of the
loop (was previously imported once per participant).
"""
import re
from pathlib import Path
from datetime import datetime, timedelta

ROOT = Path(__file__).resolve().parents[2]
AUTOMATIC_DIR = ROOT / 'data' / 'raw' / 'automatic'

# Keep in sync with mergeNewData.py / countSessions.py if the k=2 vs k=3
# design decision (docs/DesignNotes.md) changes the study design.
SESSIONS_PER_PARTICIPANT = 6
SESSIONS_PER_VISIT = 3
EXPECTED_VISITS = SESSIONS_PER_PARTICIPANT // SESSIONS_PER_VISIT
# 30 min was too tight for the 2026 cohort: largest genuine within-visit
# gap observed is 67.5 min (P300), smallest genuine between-visit gap is
# 5.82 days (P102) -- 90 min clears all same-day trios with large margin
# and stays far below visit-scale gaps.
PROXIMITY_THRESHOLD_MINUTES = 90


def parse_datetime(date_str, time_str):
    """Parse date and time strings to datetime."""
    return datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H%M%S")


def group_by_proximity(sessions, max_gap_minutes=PROXIMITY_THRESHOLD_MINUTES):
    """Group sessions that are within max_gap_minutes of each other."""
    if not sessions:
        return []

    sessions = sorted(sessions, key=lambda x: x[0])  # sort by datetime
    groups = [[sessions[0]]]

    for session in sessions[1:]:
        last_dt = groups[-1][-1][0]
        curr_dt = session[0]

        if (curr_dt - last_dt) <= timedelta(minutes=max_gap_minutes):
            groups[-1].append(session)
        else:
            groups.append([session])

    return groups


def main():
    if not AUTOMATIC_DIR.exists():
        print(f"ERROR: {AUTOMATIC_DIR} does not exist. Run processEmails.py or mergeNewData.py first.")
        return

    print(f"\n{'=' * 60}")
    print("AUTOMATIC - Session Timing Analysis")
    print(f"{'=' * 60}")

    for participant_dir in sorted(AUTOMATIC_DIR.iterdir()):
        if not participant_dir.is_dir() or participant_dir.name.startswith('.'):
            continue

        sessions = []
        for txt_file in participant_dir.rglob('*.txt'):
            match = re.search(r'(\d{4}-\d{2}-\d{2})\s*(\d{6})', txt_file.name)
            if match:
                date, time = match.group(1), match.group(2)
                dt = parse_datetime(date, time)
                sessions.append((dt, txt_file.name))

        groups = group_by_proximity(sessions)
        n_sessions = len(sessions)
        n_groups = len(groups)

        issues = []
        if n_sessions != SESSIONS_PER_PARTICIPANT:
            issues.append(f"{n_sessions} sessions")
        if n_groups != EXPECTED_VISITS and n_sessions >= SESSIONS_PER_VISIT:
            issues.append(f"{n_groups} visit(s)")

        bad_groups = [(i + 1, len(g)) for i, g in enumerate(groups) if len(g) != SESSIONS_PER_VISIT]
        if bad_groups:
            issues.append(f"visits with !={SESSIONS_PER_VISIT}: {bad_groups}")

        if issues:
            print(f"\n{participant_dir.name}: {', '.join(issues)}")
            for i, group in enumerate(groups):
                date = group[0][0].strftime("%Y-%m-%d")
                times = [dt.strftime("%H:%M") for dt, _ in group]
                print(f"  Visit {i + 1}: {date} [{' -> '.join(times)}] ({len(group)} sessions)")


if __name__ == '__main__':
    main()
