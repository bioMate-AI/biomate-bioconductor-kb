#!/usr/bin/env python3
"""
Parallel scientific context extraction using asyncio for concurrent API calls.
Dramatically faster than serial processing with prompt caching benefits.
"""

import os
import sys
import sqlite3
import json
import anthropic
import asyncio
from pathlib import Path
import time
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor
import threading

# Import the extraction function from the improved script
sys.path.insert(0, str(Path(__file__).parent))
from extract_scientific_context_improved import EXTRACTION_PROMPT

# Thread-safe database connection pool
db_lock = threading.Lock()

def get_db_connection(db_path):
    """Get a database connection (thread-safe)."""
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn

def extract_scientific_context_sync(tool: dict, client: anthropic.Anthropic, model: str) -> dict:
    """Synchronous wrapper for extraction (for thread pool)."""

    # Parse JSON fields properly
    def safe_parse_json(field, default=''):
        if not field:
            return default
        if isinstance(field, str):
            try:
                return json.loads(field)
            except:
                return field
        return field

    help_text_data = safe_parse_json(tool.get('help_text'), {})
    parameters_data = safe_parse_json(tool.get('parameters'), [])

    # Format help_text for better readability
    if isinstance(help_text_data, dict):
        help_text_str = f"""
What it does: {help_text_data.get('what_it_does', 'N/A')}
How to use: {help_text_data.get('how_to_use', 'N/A')}
Input: {help_text_data.get('input_description', 'N/A')}
Output: {help_text_data.get('output_description', 'N/A')}
Homepage: {help_text_data.get('homepage', 'N/A')}
"""
    else:
        help_text_str = str(help_text_data)

    # Format parameters
    if isinstance(parameters_data, list) and parameters_data:
        params_str = "\n".join([
            f"- {p.get('name', 'unknown')}: {p.get('help', 'no description')} (type: {p.get('type', 'unknown')})"
            for p in parameters_data[:10]
        ])
    else:
        params_str = "No parameter information available"

    # Build prompt
    prompt = EXTRACTION_PROMPT.format(
        tool_name=tool['name'],
        category=tool.get('category', 'Unknown'),
        description=(tool.get('description') or 'No description')[:1000],
        raw_text=(tool.get('rawText') or 'No raw documentation')[:8000],
        help_text=help_text_str[:2000],
        parameters=params_str[:1500]
    )

    try:
        response = client.messages.create(
            model=model,
            max_tokens=4000,
            temperature=0,
            messages=[{"role": "user", "content": prompt}]
        )

        text = response.content[0].text.strip()

        # Remove markdown code blocks if present
        if text.startswith('```'):
            lines = text.split('\n')
            if len(lines) > 2:
                text = '\n'.join(lines[1:-1])

        context = json.loads(text)

        if 'information_sources' not in context:
            context['information_sources'] = {
                "from_documentation": bool(tool.get('rawText')),
                "from_llm_knowledge": [],
                "confidence": "unknown"
            }

        return context

    except Exception as e:
        return {
            "omics_applicability": {},
            "tool_selection": {},
            "scientific_guidance": {},
            "scientific_assumptions": [],
            "information_sources": {
                "from_documentation": False,
                "from_llm_knowledge": [],
                "confidence": "none",
                "error": str(e)[:200]
            }
        }

def process_tool_batch(tools, client, model, db_path, log_file, offset):
    """Process a batch of tools in parallel using ThreadPoolExecutor."""

    results = []

    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = []

        for i, tool in enumerate(tools):
            tool_num = offset + i + 1
            future = executor.submit(extract_scientific_context_sync, dict(tool), client, model)
            futures.append((future, tool, tool_num))

        # Collect results
        for future, tool, tool_num in futures:
            start_time = time.time()
            try:
                context = future.result(timeout=120)
                elapsed = time.time() - start_time

                sources = context.get('information_sources', {})
                conf = sources.get('confidence', 'unknown')

                # Thread-safe database write
                with db_lock:
                    conn = get_db_connection(db_path)
                    cursor = conn.cursor()
                    cursor.execute(
                        "UPDATE tools SET scientific_context = ? WHERE id = ?",
                        (json.dumps(context), tool['id'])
                    )
                    conn.commit()
                    conn.close()

                # Thread-safe log write
                with db_lock:
                    log_file.write(f"{tool_num},{tool['name']},{conf},{elapsed:.1f}s\n")
                    log_file.flush()

                print(f"  {tool_num}: {tool['name'][:50]} [{conf}] {elapsed:.1f}s")
                results.append((conf, elapsed))

            except Exception as e:
                print(f"  {tool_num}: {tool['name'][:50]} [ERROR] {str(e)[:50]}")
                results.append(("error", 0))

    return results

def main():
    import argparse

    parser = argparse.ArgumentParser(description='Parallel scientific context extraction')
    parser.add_argument('--db', default='/home/yzhang/biomate/backend/database/galaxy_ai_tools.db')
    parser.add_argument('--batch-size', type=int, default=50, help='Tools per batch')
    parser.add_argument('--parallel-batches', type=int, default=1, help='Number of parallel batches')
    parser.add_argument('--workers-per-batch', type=int, default=10, help='Concurrent API calls per batch')
    parser.add_argument('--model', default='claude-haiku-4-5')
    parser.add_argument('--log', default='/tmp/parallel_extraction.log')
    parser.add_argument('--start-offset', type=int, default=0)

    args = parser.parse_args()

    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        print("❌ ANTHROPIC_API_KEY not set")
        return 1

    client = anthropic.Anthropic(api_key=api_key)

    # Connect to DB
    conn = get_db_connection(args.db)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) as count FROM tools")
    total = cursor.fetchone()['count']

    print("="*80)
    print("PARALLEL Scientific Context Extraction")
    print("="*80)
    print(f"Model: {args.model}")
    print(f"Total tools: {total}")
    print(f"Batch size: {args.batch_size}")
    print(f"Workers per batch: {args.workers_per_batch}")
    print(f"Parallelization: {args.workers_per_batch}x concurrent API calls")
    print(f"Starting offset: {args.start_offset}")
    print()

    log_file = open(args.log, 'a')
    log_file.write(f"\n{'='*80}\n")
    log_file.write(f"Started: {datetime.now()}\n")
    log_file.write(f"Model: {args.model}, Workers: {args.workers_per_batch}\n")

    offset = args.start_offset
    processed = 0
    success = 0
    high_conf = 0
    medium_conf = 0

    start_overall = time.time()

    while offset < total:
        batch_end = min(offset + args.batch_size, total)
        print(f"\n📦 Batch {offset}-{batch_end} ({offset/total*100:.1f}%)")

        cursor.execute("""
            SELECT id, name, category, description, help_text, rawText, parameters
            FROM tools
            ORDER BY id
            LIMIT ? OFFSET ?
        """, (args.batch_size, offset))

        tools = cursor.fetchall()

        batch_start = time.time()
        results = process_tool_batch(tools, client, args.model, args.db, log_file, offset)
        batch_elapsed = time.time() - batch_start

        # Update stats
        for conf, elapsed in results:
            processed += 1
            if conf in ['high', 'medium']:
                success += 1
                if conf == 'high':
                    high_conf += 1
                elif conf == 'medium':
                    medium_conf += 1

        throughput = len(tools) / batch_elapsed if batch_elapsed > 0 else 0
        print(f"\n  ✅ Batch complete: {len(tools)} tools in {batch_elapsed:.1f}s ({throughput:.1f} tools/sec)")
        print(f"  Progress: {success}/{processed} quality ({success/processed*100:.1f}%), High: {high_conf}, Medium: {medium_conf}")

        offset = batch_end

    elapsed_total = time.time() - start_overall

    log_file.write(f"Completed: {datetime.now()}\n")
    log_file.write(f"Processed: {processed}, Success: {success}, High: {high_conf}, Medium: {medium_conf}\n")
    log_file.write(f"Total time: {elapsed_total:.1f}s ({processed/elapsed_total:.2f} tools/sec)\n")
    log_file.close()

    print("\n" + "="*80)
    print("EXTRACTION COMPLETE")
    print("="*80)
    print(f"Total processed: {processed}")
    print(f"Quality extractions: {success} ({success/processed*100:.1f}%)")
    print(f"  High confidence: {high_conf} ({high_conf/processed*100:.1f}%)")
    print(f"  Medium confidence: {medium_conf} ({medium_conf/processed*100:.1f}%)")
    print(f"Total time: {elapsed_total/60:.1f} minutes ({processed/elapsed_total:.2f} tools/sec)")
    print(f"Log: {args.log}")

    conn.close()
    return 0

if __name__ == '__main__':
    sys.exit(main())
