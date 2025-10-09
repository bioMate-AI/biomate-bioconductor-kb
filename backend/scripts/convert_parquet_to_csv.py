#!/usr/bin/env python3
"""
Convert all Parquet files in biomni_data_lake to CSV format for Galaxy compatibility
"""
import pandas as pd
import glob
import os
import sys
from pathlib import Path
from datetime import datetime

SOURCE_DIR = "/Users/jingqiwang/Biomni/knowledge_data/biomni_data_lake"
LOG_FILE = "/Users/jingqiwang/biomate/backend/logs/parquet_conversion.log"

def log(message: str):
    """Write to log file and print to console"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_message = f"[{timestamp}] {message}"
    print(log_message)

    with open(LOG_FILE, 'a') as f:
        f.write(log_message + '\n')

def convert_parquet_to_csv(parquet_file: str) -> bool:
    """Convert single parquet file to CSV"""
    basename = os.path.basename(parquet_file)

    try:
        log(f"Converting {basename}...")

        # Read parquet
        df = pd.read_parquet(parquet_file)

        # Generate CSV filename
        csv_file = parquet_file.replace('.parquet', '.csv')

        # Write CSV
        df.to_csv(csv_file, index=False)

        # Get file sizes
        parquet_size = os.path.getsize(parquet_file) / (1024**3)  # GB
        csv_size = os.path.getsize(csv_file) / (1024**3)  # GB

        log(f"  ✓ Success: {basename}")
        log(f"    Rows: {len(df):,} | Columns: {len(df.columns)}")
        log(f"    Parquet: {parquet_size:.2f} GB → CSV: {csv_size:.2f} GB")

        return True

    except Exception as e:
        log(f"  ✗ FAILED: {basename}")
        log(f"    Error: {str(e)}")
        return False

def main():
    # Initialize log
    log("="*70)
    log("Parquet to CSV Conversion Script")
    log("="*70)

    # Find all parquet files
    parquet_files = sorted(glob.glob(f"{SOURCE_DIR}/*.parquet"))
    log(f"\nFound {len(parquet_files)} Parquet files in {SOURCE_DIR}\n")

    if len(parquet_files) == 0:
        log("No Parquet files found. Exiting.")
        return 0

    # Convert each file
    success_count = 0
    failure_count = 0
    failed_files = []

    for i, parquet_file in enumerate(parquet_files, 1):
        log(f"\n[{i}/{len(parquet_files)}] Processing...")
        if convert_parquet_to_csv(parquet_file):
            success_count += 1
        else:
            failure_count += 1
            failed_files.append(os.path.basename(parquet_file))

    # Summary
    log("\n" + "="*70)
    log("CONVERSION SUMMARY")
    log("="*70)
    log(f"Total files processed: {len(parquet_files)}")
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
