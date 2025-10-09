#!/usr/bin/env python3
"""
Add XCMS and other important LC-MS tools to the tool_search_index.db

This script adds missing XCMS tools and other essential LC-MS tools
that were not in the original curated database.
"""

import sqlite3
import sys
from pathlib import Path

# Path to database
DB_PATH = Path(__file__).parent.parent / "database" / "tool_search_index.db"

# Essential LC-MS tools to add (manually curated from ToolShed)
TOOLS_TO_ADD = [
    # XCMS Core Tools (lecorguille)
    {
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_xcmsset/xcms_xcmsset',
        'name': 'xcms xcmsSet',
        'description': '[Metabolomics][W4M][LC-MS] XCMS R Package - Preprocessing - peaks calling in NetCDF/mzXML files',
        'version': '4.0.4+galaxy0',
        'category': 'Metabolomics',
        'repo_name': 'xcms_xcmsset',
        'repo_owner': 'lecorguille',
        'changeset_revision': 'b02d1992a43a',  # Latest stable
        'tool_shed': 'https://toolshed.g2.bx.psu.edu',
    },
    {
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_group/xcms_group',
        'name': 'xcms findChromPeaks (groupChromPeaks)',
        'description': '[Metabolomics][W4M][LC-MS] XCMS R Package - Preprocessing - Group peaks from different samples together',
        'version': '4.0.4+galaxy0',
        'category': 'Metabolomics',
        'repo_name': 'xcms_group',
        'repo_owner': 'lecorguille',
        'changeset_revision': 'f8c80659ed76',
        'tool_shed': 'https://toolshed.g2.bx.psu.edu',
    },
    {
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_retcor/xcms_retcor',
        'name': 'xcms adjustRtime (retcor)',
        'description': '[Metabolomics][W4M][LC-MS] XCMS R Package - Preprocessing - Correct retention time deviation',
        'version': '4.0.4+galaxy0',
        'category': 'Metabolomics',
        'repo_name': 'xcms_retcor',
        'repo_owner': 'lecorguille',
        'changeset_revision': '01c2fa7e6938',
        'tool_shed': 'https://toolshed.g2.bx.psu.edu',
    },
    {
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_fillpeaks/xcms_fillpeaks',
        'name': 'xcms fillChromPeaks (fillPeaks)',
        'description': '[Metabolomics][W4M][LC-MS] XCMS R Package - Preprocessing - Integrate areas of missing peaks',
        'version': '4.0.4+galaxy0',
        'category': 'Metabolomics',
        'repo_name': 'xcms_fillpeaks',
        'repo_owner': 'lecorguille',
        'changeset_revision': '26d77e8ee99f',
        'tool_shed': 'https://toolshed.g2.bx.psu.edu',
    },
    {
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_merge/xcms_merge',
        'name': 'xcms process Merge',
        'description': '[Metabolomics][W4M][LC-MS] XCMS R Package - Preprocessing - Merge individual xcms datasets',
        'version': '4.0.4+galaxy0',
        'category': 'Metabolomics',
        'repo_name': 'xcms_merge',
        'repo_owner': 'lecorguille',
        'changeset_revision': '18309b8c0b8f',
        'tool_shed': 'https://toolshed.g2.bx.psu.edu',
    },
    {
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_plot_chromatogram/xcms_plot_chromatogram',
        'name': 'xcms plot chromatogram',
        'description': '[Metabolomics][W4M][LC-MS] XCMS R Package - Preprocessing - Plot base peak intensity chromatogram',
        'version': '4.0.4+galaxy0',
        'category': 'Metabolomics',
        'repo_name': 'xcms_plot_chromatogram',
        'repo_owner': 'lecorguille',
        'changeset_revision': '49c41eb07f52',
        'tool_shed': 'https://toolshed.g2.bx.psu.edu',
    },
    {
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_summary/xcms_summary',
        'name': 'xcms process Summary',
        'description': '[Metabolomics][W4M][LC-MS] XCMS R Package - Preprocessing - HTML Summary for XCMS and CAMERA',
        'version': '4.0.4+galaxy0',
        'category': 'Metabolomics',
        'repo_name': 'xcms_summary',
        'repo_owner': 'lecorguille',
        'changeset_revision': '4c5694b98e8c',
        'tool_shed': 'https://toolshed.g2.bx.psu.edu',
    },
    {
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/lecorguille/msnbase_readmsdata/msnbase_readmsdata',
        'name': 'MSnbase readMSData',
        'description': '[Metabolomics][W4M][LC-MS] MSnbase R Package - Preprocessing - Imports Mass-Spectrometry Data Files',
        'version': '2.32.0+galaxy0',
        'category': 'Metabolomics',
        'repo_name': 'msnbase_readmsdata',
        'repo_owner': 'lecorguille',
        'changeset_revision': 'd81f0090a5df',
        'tool_shed': 'https://toolshed.g2.bx.psu.edu',
    },
    # Additional XCMS tools (workflow4metabolomics)
    {
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/workflow4metabolomics/xcms_plot_raw/xcms_plot_raw',
        'name': 'Plot raw mzml file',
        'description': 'Plot raw mzml file content with xcms',
        'version': '1.0.0',
        'category': 'Metabolomics',
        'repo_name': 'xcms_plot_raw',
        'repo_owner': 'workflow4metabolomics',
        'changeset_revision': '5c247fb4fb0f',
        'tool_shed': 'https://toolshed.g2.bx.psu.edu',
    },
    {
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/workflow4metabolomics/xcms_refine/xcms_refine',
        'name': 'xcms refine',
        'description': '[Metabolomics][W4M][LC-MS] XCMS R Package - Preprocessing - Refine choice of peaks',
        'version': '1.0.0',
        'category': 'Metabolomics',
        'repo_name': 'xcms_refine',
        'repo_owner': 'workflow4metabolomics',
        'changeset_revision': 'fcd6426f53e3',
        'tool_shed': 'https://toolshed.g2.bx.psu.edu',
    },
]


def add_tools_to_db(db_path: Path):
    """Add tools to the database"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    added = 0
    skipped = 0

    for tool in TOOLS_TO_ADD:
        # Check if tool already exists
        cursor.execute('SELECT COUNT(*) FROM tools WHERE tool_id = ?', (tool['tool_id'],))
        if cursor.fetchone()[0] > 0:
            print(f"⏭️  Skipped (already exists): {tool['name']}")
            skipped += 1
            continue

        # Insert tool
        cursor.execute('''
            INSERT INTO tools (
                tool_id, name, description, version, category,
                repo_name, repo_owner, changeset_revision, tool_shed,
                is_installed, install_status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 'not_installed')
        ''', (
            tool['tool_id'],
            tool['name'],
            tool['description'],
            tool['version'],
            tool['category'],
            tool['repo_name'],
            tool['repo_owner'],
            tool['changeset_revision'],
            tool['tool_shed']
        ))

        # Get the row id for FTS5 insert
        row_id = cursor.lastrowid

        # Insert into FTS5 index
        cursor.execute('''
            INSERT INTO tools_fts (rowid, name, description, keywords)
            VALUES (?, ?, ?, ?)
        ''', (
            row_id,
            tool['name'],
            tool['description'],
            'xcms lcms metabolomics preprocessing'
        ))

        print(f"✅ Added: {tool['name']} ({tool['repo_owner']}/{tool['repo_name']})")
        added += 1

    conn.commit()
    conn.close()

    print(f"\n{'='*70}")
    print(f"Summary:")
    print(f"  ✅ Added: {added}")
    print(f"  ⏭️  Skipped: {skipped}")
    print(f"  📊 Total: {added + skipped}")
    print(f"{'='*70}")

    return added, skipped


def main():
    """Main entry point"""
    if not DB_PATH.exists():
        print(f"❌ Error: Database not found at {DB_PATH}")
        sys.exit(1)

    print("="*70)
    print("Adding XCMS and Essential LC-MS Tools to Database")
    print("="*70)
    print(f"\nDatabase: {DB_PATH}")
    print(f"Tools to add: {len(TOOLS_TO_ADD)}\n")

    added, skipped = add_tools_to_db(DB_PATH)

    if added > 0:
        print(f"\n✅ Successfully added {added} XCMS tools to the database!")
        print(f"   You can now search for XCMS tools in the tool index.")
    else:
        print(f"\n⚠️  No new tools were added (all tools already exist)")


if __name__ == '__main__':
    main()
