#!/usr/bin/env python3
"""
Process .eml files from Outlook to extract all 4 attachments per session.
Creates: data/raw/automatic/ID{RPS_ID}/{session files}

First-time / full extraction. For subsequent batches use mergeNewData.py
instead (skips already-extracted emails).

Usage: python3 processEmails.py [--dry-run]

Adapted from analysis_2025/data2025/processEmails.py. Logic unchanged;
only paths updated for the Analysis_2026 clean layout (data/raw/eml/,
data/raw/automatic/ instead of script-adjacent directories).
"""

import os
import re
import email
from email import policy
from pathlib import Path
import argparse

# Project layout: this file lives at src/functions/processEmails.py
ROOT = Path(__file__).resolve().parents[2]
EML_DIR = ROOT / 'data' / 'raw' / 'eml'
AUTOMATIC_DIR = ROOT / 'data' / 'raw' / 'automatic'


def extract_rps_id(filename, subject):
    """Extract RPS ID from filename or subject."""
    patterns = [
        r'(?i:participant|pp)[\s\-]*(\d{3})\b',  # 2026 cohort: "Participant-201", "PP318", "PARTICIPANT 304"
        r'RPS ID[:\-\.\s]+(\d{6})',
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


def decode_attachments(eml_path):
    """Extract all attachments from .eml file. Returns (subject, [(filename, content), ...])"""
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


def process_eml(eml_path, automatic_dir, dry_run=False):
    """Process a single .eml file. Outputs to automatic/ID{RPS_ID}/."""
    filename = eml_path.name
    if filename.startswith('.'):
        return None, "Skipped"

    subject, attachments = decode_attachments(eml_path)
    if not attachments:
        return None, "EMPTY - no attachments"

    rps_id = extract_rps_id(filename, subject)
    if not rps_id:
        return None, "NO_ID - could not parse RPS ID"

    output_dir = automatic_dir / f"ID{rps_id}"

    existing = []
    new_atts = []
    for att_name, att_content in attachments:
        out_path = output_dir / att_name
        if out_path.exists():
            existing.append(att_name)
        else:
            new_atts.append((att_name, att_content))

    if dry_run:
        if existing and not new_atts:
            return output_dir, f"SKIP - all {len(existing)} files already exist"
        elif existing:
            return output_dir, f"Would extract {len(new_atts)} new, skip {len(existing)} existing"
        else:
            return output_dir, f"Would extract {len(attachments)} files"

    if not new_atts:
        return output_dir, f"SKIP - all {len(existing)} files already exist"

    os.makedirs(output_dir, exist_ok=True)

    for att_name, att_content in new_atts:
        out_path = output_dir / att_name
        with open(out_path, 'wb') as f:
            f.write(att_content)

    skipped = f", skipped {len(existing)} existing" if existing else ""
    return output_dir, f"{len(new_atts)} new files{skipped}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    if not EML_DIR.exists():
        print(f"ERROR: {EML_DIR} does not exist. Create it and place .eml files there.")
        return

    eml_files = list(EML_DIR.glob('*.eml'))

    print(f"Found {len(eml_files)} .eml files in {EML_DIR}")
    print(f"Output: {AUTOMATIC_DIR}/\n")

    success, errors = 0, []
    for eml_path in sorted(eml_files):
        result, status = process_eml(eml_path, AUTOMATIC_DIR, args.dry_run)
        if result:
            print(f"OK  {eml_path.name} -> {result.name}/ ({status})")
            success += 1
        else:
            errors.append((eml_path.name, status))

    print(f"\n{'=' * 60}")
    print(f"Processed: {success}/{len(eml_files)}")
    if errors:
        empty = [(n, e) for n, e in errors if 'EMPTY' in e]
        no_id = [(n, e) for n, e in errors if 'NO_ID' in e]
        other = [(n, e) for n, e in errors if 'EMPTY' not in e and 'NO_ID' not in e]
        if empty:
            print(f"\nEMPTY emails ({len(empty)}) - no attachments:")
            for name, _ in empty:
                print(f"  {name}")
        if no_id:
            print(f"\nNO ID parsed ({len(no_id)}):")
            for name, _ in no_id:
                print(f"  {name}")
        if other:
            print(f"\nOther ({len(other)}):")
            for name, err in other:
                print(f"  {name}: {err}")


if __name__ == '__main__':
    main()
