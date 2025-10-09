#!/usr/bin/env python3
"""
Convert all PKL files in biomni_data_lake to CSV format for Galaxy compatibility
Handles different data structures (dict, list, DataFrame)
"""
import pickle
import pandas as pd
import glob
import os
import sys
from datetime import datetime

SOURCE_DIR = "/Users/jingqiwang/Biomni/knowledge_data/biomni_data_lake"
LOG_FILE = "/Users/jingqiwang/biomate/backend/logs/pkl_conversion.log"

def log(message: str):
    """Write to log file and print to console"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_message = f"[{timestamp}] {message}"
    print(log_message)

    with open(LOG_FILE, 'a') as f:
        f.write(log_message + '\n')

def inspect_pkl_structure(pkl_file: str):
    """Inspect PKL file structure"""
    with open(pkl_file, 'rb') as f:
        data = pickle.load(f)

    data_type = type(data).__name__

    if isinstance(data, pd.DataFrame):
        return f"DataFrame ({len(data)} rows, {len(data.columns)} cols)"
    elif isinstance(data, dict):
        sample_key = next(iter(data.keys())) if len(data) > 0 else None
        sample_value = next(iter(data.values())) if len(data) > 0 else None
        return f"Dict ({len(data)} entries, key type: {type(sample_key).__name__}, value type: {type(sample_value).__name__})"
    elif isinstance(data, list):
        sample_item = data[0] if len(data) > 0 else None
        return f"List ({len(data)} items, item type: {type(sample_item).__name__})"
    else:
        return f"{data_type} (size: {sys.getsizeof(data)} bytes)"

def convert_pkl_to_csv(pkl_file: str) -> bool:
    """Convert single PKL file to CSV based on data structure"""
    basename = os.path.basename(pkl_file)

    try:
        log(f"Converting {basename}...")

        # Load pickle
        with open(pkl_file, 'rb') as f:
            data = pickle.load(f)

        log(f"  Structure: {inspect_pkl_structure(pkl_file)}")

        # Convert to DataFrame based on type
        if isinstance(data, pd.DataFrame):
            df = data
            log(f"  Direct DataFrame conversion")

        elif isinstance(data, dict):
            # Try to infer structure
            if len(data) > 0:
                first_value = next(iter(data.values()))

                if isinstance(first_value, (dict, list)):
                    # Dict of dicts/lists → each key becomes a row
                    df = pd.DataFrame.from_dict(data, orient='index')
                    log(f"  Dict → DataFrame (from_dict, orient='index')")
                else:
                    # Simple key-value pairs
                    df = pd.DataFrame(list(data.items()), columns=['key', 'value'])
                    log(f"  Dict → DataFrame (key-value pairs)")
            else:
                df = pd.DataFrame()
                log(f"  Empty dict → Empty DataFrame")

        elif isinstance(data, list):
            # List of items → each item becomes a row
            df = pd.DataFrame(data)
            log(f"  List → DataFrame")

        else:
            # Try generic conversion
            df = pd.DataFrame(data)
            log(f"  Generic conversion to DataFrame")

        # Generate CSV filename
        csv_file = pkl_file.replace('.pkl', '.csv')

        # Write CSV
        df.to_csv(csv_file, index=True)

        # Get file sizes
        pkl_size = os.path.getsize(pkl_file) / (1024**2)  # MB
        csv_size = os.path.getsize(csv_file) / (1024**2)  # MB

        log(f"  ✓ Success: {basename}")
        log(f"    Rows: {len(df):,} | Columns: {len(df.columns)}")
        log(f"    PKL: {pkl_size:.2f} MB → CSV: {csv_size:.2f} MB")

        return True

    except Exception as e:
        log(f"  ✗ FAILED: {basename}")
        log(f"    Error: {str(e)}")
        return False

def main():
    # Initialize log
    log("="*70)
    log("PKL to CSV Conversion Script")
    log("="*70)

    # Find all PKL files
    pkl_files = sorted(glob.glob(f"{SOURCE_DIR}/*.pkl"))
    log(f"\nFound {len(pkl_files)} PKL files in {SOURCE_DIR}\n")

    if len(pkl_files) == 0:
        log("No PKL files found. Exiting.")
        return 0

    # Convert each file
    success_count = 0
    failure_count = 0
    failed_files = []

    for i, pkl_file in enumerate(pkl_files, 1):
        log(f"\n[{i}/{len(pkl_files)}] Processing...")
        if convert_pkl_to_csv(pkl_file):
            success_count += 1
        else:
            failure_count += 1
            failed_files.append(os.path.basename(pkl_file))

    # Summary
    log("\n" + "="*70)
    log("CONVERSION SUMMARY")
    log("="*70)
    log(f"Total files processed: {len(pkl_files)}")
    log(f"  ✓ Successful: {success_count}")
    log(f"  ✗ Failed: {failure_count}")

    if failed_files:
        log("\nFailed files:")
        for fname in failed_files:
            log(f"  - {fname}")

    log(f"\nLog file: {LOG_FILE}")
    log("="*70)

    return 0 if failure_count == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
