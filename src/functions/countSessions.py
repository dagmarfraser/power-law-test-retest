#!/usr/bin/env python3
"""
Count sessions per participant in data/raw/automatic/.

Adapted from analysis_2025/data2025/countSessions.py. The manual/ vs
automatic/ distinction from analysis_2025 (manual/ held deprecated
hand-processed legacy data) has been dropped here -- Analysis_2026 has
no legacy data, so there is only one folder to check.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUTOMATIC_DIR = ROOT / 'data' / 'raw' / 'automatic'

# See mergeNewData.py for the same constant -- keep both in sync if the
# k=2 vs k=3 design decision (docs/DesignNotes.md) changes this.
SESSIONS_PER_PARTICIPANT = 6


def main():
    if not AUTOMATIC_DIR.exists():
        print(f"ERROR: {AUTOMATIC_DIR} does not exist. Run processEmails.py or mergeNewData.py first.")
        return

    print(f"\n{'=' * 50}")
    print("AUTOMATIC")
    print(f"{'=' * 50}")

    incomplete = []
    complete = []

    for participant_dir in sorted(AUTOMATIC_DIR.iterdir()):
        if not participant_dir.is_dir() or participant_dir.name.startswith('.'):
            continue

        txt_files = list(participant_dir.rglob('*.txt'))
        n_sessions = len(txt_files)

        if n_sessions != SESSIONS_PER_PARTICIPANT:
            incomplete.append((participant_dir.name, n_sessions))
        else:
            complete.append(participant_dir.name)

    print(f"Complete ({SESSIONS_PER_PARTICIPANT} sessions): {len(complete)}")
    print(f"Incomplete: {len(incomplete)}")

    if incomplete:
        print("\nIncomplete participants:")
        for name, count in incomplete:
            print(f"  {name}: {count} sessions")


if __name__ == '__main__':
    main()
