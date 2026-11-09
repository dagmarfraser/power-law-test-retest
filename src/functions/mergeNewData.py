#!/usr/bin/env python3
"""
Process NEW .eml files only, merging into existing data/raw/automatic/.
Skips already-extracted emails and reports what's new.

Usage:
    python3 mergeNewData.py --dry-run   # Preview what would be extracted
    python3 mergeNewData.py             # Extract new data
    python3 mergeNewData.py --summary   # Just show current state

Adapted from analysis_2025/data2025/mergeNewData.py. Logic unchanged;
paths updated for Analysis_2026's clean layout, and the "complete"
session count pulled out to SESSIONS_PER_PARTICIPANT below.
"""

import os
import re
import email
from email import policy
from pathlib import Path
import argparse
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[2]
EML_DIR = ROOT / 'data' / 'raw' / 'eml'
AUTOMATIC_DIR = ROOT / 'data' / 'raw' / 'automatic'

# analysis_2025 design: 3 sessions/visit x 2 visits = 6. If the k=3 design
# from docs/DesignNotes.md is adopted for this cohort, update this to 9
# (3 sessions/visit x 3 visits) -- nothing else in this script needs to change.
SESSIONS_PER_PARTICIPANT = 6


def extract_rps_id(filename, subject):
    """Extract RPS ID from filename or subject."""
    patterns = [
        r'(?i:participant|pp)[\s\-]*(\d{3})\b',  # 2026 cohort: "Participant-201", "PP318", "PARTICIPANT 304"
        r'RPS ID[:\-\s]+(\d{6})',
        r'^(\d{6})\s+',
        r'[Ii][Dd][:\-\s]*(\d{6})',
        r'\bid\s*(\d{6})',
    ]
    for text in [filename, subject]:
        for pattern in patterns:
            match = re.search(pattern, text)
            if match:
                return match.group(1)
    return None


def extract_session_datetime(filename):
    """Extract datetime from filename like 'betaTestv002 2025-12-05 161540.txt'"""
    match = re.search(r'(\d{4}-\d{2}-\d{2})\s*(\d{6})', filename)
    if match:
        return f"{match.group(1)} {match.group(2)}"
    return None


def decode_attachments(eml_path):
    """Extract all attachments from .eml file."""
    with open(eml_path, 'rb') as f:
        msg = email.message_from_binary_file(f, policy=policy.default)

    subject = msg.get('Subject', '')
    attachments = []

    for part in msg.walk():
        filename = part.get_filename()
        if filename:
            payload = part.get_payload(decode=True)
            if payload:
                attachments.append((filename, payload))

    return subject, attachments


def get_existing_sessions(automatic_dir):
    """Scan automatic/ folder and return dict of {ID: set of session datetimes}"""
    existing = defaultdict(set)

    if not automatic_dir.exists():
        return existing

    for participant_dir in automatic_dir.iterdir():
        if not participant_dir.is_dir() or participant_dir.name.startswith('.'):
            continue

        participant_id = participant_dir.name  # e.g., "ID121546"

        for txt_file in participant_dir.glob('*.txt'):
            session_dt = extract_session_datetime(txt_file.name)
            if session_dt:
                existing[participant_id].add(session_dt)

    return existing


def check_if_already_extracted(eml_path, automatic_dir, existing_sessions):
    """Check if this .eml's session already exists in automatic/"""
    subject, attachments = decode_attachments(eml_path)

    if not attachments:
        return None, None, "no_attachments"

    rps_id = extract_rps_id(eml_path.name, subject)
    if not rps_id:
        return None, None, "no_rps_id"

    participant_id = f"ID{rps_id}"

    for att_name, _ in attachments:
        session_dt = extract_session_datetime(att_name)
        if session_dt and session_dt in existing_sessions.get(participant_id, set()):
            return participant_id, session_dt, "already_exists"

    for att_name, _ in attachments:
        if att_name.endswith('.txt'):
            session_dt = extract_session_datetime(att_name)
            return participant_id, session_dt, "new"

    return participant_id, None, "no_txt_attachment"


def process_eml(eml_path, automatic_dir):
    """Extract attachments from .eml to automatic/ID{RPS_ID}/"""
    subject, attachments = decode_attachments(eml_path)

    rps_id = extract_rps_id(eml_path.name, subject)
    if rps_id:
        output_dir = automatic_dir / f"ID{rps_id}"
    else:
        output_dir = automatic_dir / eml_path.stem

    os.makedirs(output_dir, exist_ok=True)

    for att_name, att_content in attachments:
        out_path = output_dir / att_name
        with open(out_path, 'wb') as f:
            f.write(att_content)

    return output_dir, len(attachments)


def print_summary(automatic_dir):
    """Print summary of current state."""
    existing = get_existing_sessions(automatic_dir)

    complete = []
    incomplete = defaultdict(list)

    for participant_id, sessions in sorted(existing.items()):
        n = len(sessions)
        if n == SESSIONS_PER_PARTICIPANT:
            complete.append(participant_id)
        else:
            incomplete[n].append(participant_id)

    print(f"\n{'=' * 60}")
    print("CURRENT STATE SUMMARY")
    print(f"{'=' * 60}")
    print(f"\nComplete ({SESSIONS_PER_PARTICIPANT} sessions): {len(complete)}")

    for count in sorted(incomplete.keys(), reverse=True):
        ids = incomplete[count]
        print(f"{count} sessions: {len(ids)} participants")
        if len(ids) <= 10:
            print(f"  -> {', '.join(ids)}")

    print(f"\nTotal participants: {len(existing)}")
    print(f"Total sessions: {sum(len(s) for s in existing.values())}")


def main():
    parser = argparse.ArgumentParser(description='Process new .eml files only')
    parser.add_argument('--dry-run', action='store_true', help='Preview without extracting')
    parser.add_argument('--summary', action='store_true', help='Show current state only')
    args = parser.parse_args()

    if args.summary:
        print_summary(AUTOMATIC_DIR)
        return

    existing_sessions = get_existing_sessions(AUTOMATIC_DIR)
    existing_participants = set(existing_sessions.keys())

    print(f"Existing: {len(existing_participants)} participants, "
          f"{sum(len(s) for s in existing_sessions.values())} sessions")

    if not EML_DIR.exists():
        print(f"ERROR: {EML_DIR} does not exist. Create it and place .eml files there.")
        return

    eml_files = list(EML_DIR.glob('*.eml'))
    print(f"Found: {len(eml_files)} .eml files\n")

    if not eml_files:
        print("No .eml files to process.")
        print_summary(AUTOMATIC_DIR)
        return

    new_emails = []
    skipped_existing = []
    errors = []

    for eml_path in sorted(eml_files):
        if eml_path.name.startswith('.'):
            continue

        participant_id, session_dt, status = check_if_already_extracted(
            eml_path, AUTOMATIC_DIR, existing_sessions
        )

        if status == "new":
            new_emails.append((eml_path, participant_id, session_dt))
        elif status == "already_exists":
            skipped_existing.append((eml_path.name, participant_id, session_dt))
        else:
            errors.append((eml_path.name, status))

    print(f"{'=' * 60}")
    print("ANALYSIS")
    print(f"{'=' * 60}")
    print(f"New emails to process: {len(new_emails)}")
    print(f"Already extracted (skipping): {len(skipped_existing)}")
    print(f"Errors: {len(errors)}")

    if errors:
        print("\nErrors:")
        for name, err in errors:
            print(f"  {name}: {err}")

    if not new_emails:
        print("\nNo new emails to process!")
        print_summary(AUTOMATIC_DIR)
        return

    new_participants = defaultdict(list)
    additional_sessions = defaultdict(list)

    for eml_path, participant_id, session_dt in new_emails:
        if participant_id in existing_participants:
            additional_sessions[participant_id].append((eml_path, session_dt))
        else:
            new_participants[participant_id].append((eml_path, session_dt))

    print(f"\n{'=' * 60}")
    print("NEW DATA BREAKDOWN")
    print(f"{'=' * 60}")

    if new_participants:
        print(f"\nNEW PARTICIPANTS ({len(new_participants)}):")
        for pid in sorted(new_participants.keys()):
            sessions = new_participants[pid]
            print(f"  {pid}: {len(sessions)} session(s)")

    if additional_sessions:
        print(f"\nADDITIONAL SESSIONS for existing participants ({len(additional_sessions)}):")
        for pid in sorted(additional_sessions.keys()):
            sessions = additional_sessions[pid]
            existing_count = len(existing_sessions.get(pid, set()))
            new_count = existing_count + len(sessions)
            status = "-> COMPLETE!" if new_count == SESSIONS_PER_PARTICIPANT else ""
            print(f"  {pid}: {existing_count} -> {new_count} sessions {status}")

    if args.dry_run:
        print(f"\n{'=' * 60}")
        print("DRY RUN - Would extract:")
        print(f"{'=' * 60}")
        for eml_path, participant_id, session_dt in new_emails:
            print(f"  {eml_path.name} -> {participant_id}/")
        print("\nRun without --dry-run to extract.")
    else:
        print(f"\n{'=' * 60}")
        print("EXTRACTING")
        print(f"{'=' * 60}")
        success = 0
        for eml_path, participant_id, session_dt in new_emails:
            output_dir, n_files = process_eml(eml_path, AUTOMATIC_DIR)
            print(f"  OK {eml_path.name} -> {output_dir.name}/ ({n_files} files)")
            success += 1

        print(f"\nExtracted: {success} emails")
        print_summary(AUTOMATIC_DIR)


if __name__ == '__main__':
    main()
