#!/usr/bin/env python3
"""
Batch LLM extraction with optimizations:
- Parallel processing with rate limiting
- Resume from interruptions
- Priority categories first
- Progress tracking
"""

import os
import sqlite3
import json
import time
from pathlib import Path
from typing import Dict, Optional
import anthropic
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading


# Global rate limiter
class RateLimiter:
    def __init__(self, calls_per_minute=50):
        self.calls_per_minute = calls_per_minute
        self.min_interval = 60.0 / calls_per_minute
        self.last_call = 0
        self.lock = threading.Lock()

    def wait(self):
        with self.lock:
            now = time.time()
            time_since_last = now - self.last_call
            if time_since_last < self.min_interval:
                time.sleep(self.min_interval - time_since_last)
            self.last_call = time.time()


EXTRACTION_PROMPT = """You are a scientific tool metadata expert. Analyze this tool's documentation and extract comprehensive scientific context in structured JSON format.

Tool Name: {tool_name}
Category: {category}

Documentation:
{documentation}

Extract in this exact JSON structure (ONLY include fields where you have information):

{{
  "data_type_compatibility": {{
    "supported_data_types": ["specific data types/formats"],
    "not_supported_data_types": ["incompatible types"],
    "notes": "compatibility details"
  }},
  "use_cases": [
    {{
      "scenario": "specific use case",
      "when_to_use": "conditions",
      "typical_workflow": "pipeline position"
    }}
  ],
  "common_mistakes": [
    {{
      "mistake": "what users do wrong",
      "why_wrong": "why it's a problem",
      "correct_approach": "correct way"
    }}
  ],
  "prerequisites": {{
    "required_inputs": ["input types"],
    "required_software": ["dependencies"],
    "recommended_data_quality": "quality requirements"
  }},
  "parameter_guidance": {{
    "essential_parameters": ["must configure"],
    "recommended_defaults": {{"param": "value with reason"}},
    "common_adjustments": ["when to change defaults"]
  }},
  "strengths": ["what tool excels at"],
  "limitations": ["what tool cannot do"],
  "alternatives": ["when to use other tools"],
  "scientific_notes": "domain knowledge"
}}

CRITICAL RULES:
1. Extract ONLY from provided documentation - no speculation
2. For proteomics: distinguish DDA/DIA, label-free/labeled, targeted/untargeted
3. For genomics: distinguish WGS/WES/RNA-seq, single-cell/bulk
4. Be specific and concise
5. Empty arrays [] if no info found
6. Return ONLY valid JSON"""


def extract_with_llm_safe(
    tool_id: int,
    tool_name: str,
    category: str,
    documentation: str,
    api_key: str,
    rate_limiter: RateLimiter
) -> Optional[Dict]:
    """Thread-safe LLM extraction with rate limiting."""

    # Truncate documentation
    if len(documentation) > 10000:
        documentation = documentation[:10000] + "\n[...truncated...]"

    try:
        # Rate limiting
        rate_limiter.wait()

        # Use prompt caching for the extraction template
        system_prompt = EXTRACTION_PROMPT.split("{tool_name}")[0].strip()

        client = anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-haiku-4-5",
            max_tokens=4096,
            temperature=0,
            system=[
                {
                    "type": "text",
                    "text": system_prompt,
                    "cache_control": {"type": "ephemeral"}
                }
            ],
            messages=[{
                "role": "user",
                "content": f"Tool Name: {tool_name}\nCategory: {category or 'Unknown'}\n\nDocumentation:\n{documentation}\n\n{EXTRACTION_PROMPT.split('{documentation}')[1]}"
            }]
        )

        response_text = message.content[0].text

        # Parse JSON
        if "```json" in response_text:
            response_text = response_text.split("```json")[1].split("```")[0]
        elif "```" in response_text:
            response_text = response_text.split("```")[1].split("```")[0]

        context = json.loads(response_text.strip())
        return {'id': tool_id, 'context': context, 'success': True}

    except Exception as e:
        return {'id': tool_id, 'error': str(e)[:200], 'success': False}


def batch_process(
    db_path: str,
    api_key: str,
    category_filter: Optional[str] = None,
    limit: Optional[int] = None,
    workers: int = 5,
    resume: bool = True
):
    """Batch process tools with parallel workers."""

    print("=" * 80)
    print("Batch LLM-Powered Scientific Context Extraction")
    print("=" * 80)
    print(f"Workers: {workers}")
    print(f"Rate limit: ~{50//workers} calls/min per worker")
    print()

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Build query
    query = """
        SELECT id, tool_id, name, version, category, description, rawText, help_text, scientific_context
        FROM tools
        WHERE (rawText IS NOT NULL AND rawText != '') OR (description IS NOT NULL AND description != '')
    """

    params = []
    if category_filter:
        query += " AND category = ?"
        params.append(category_filter)

    if resume:
        # Skip tools that already have rich context
        query += """ AND (
            scientific_context IS NULL
            OR scientific_context = ''
            OR scientific_context = '{}'
            OR json_extract(scientific_context, '$.data_type_compatibility') IS NULL
        )"""

    query += " ORDER BY CASE category "
    query += " WHEN 'Proteomics' THEN 1"
    query += " WHEN 'Transcriptomics' THEN 2"
    query += " WHEN 'Metabolomics' THEN 3"
    query += " WHEN 'Genomics' THEN 4"
    query += " ELSE 5 END, name"

    if limit:
        query += f" LIMIT {limit}"

    cursor.execute(query, params)
    tools = cursor.fetchall()
    conn.close()

    print(f"📊 Found {len(tools)} tools to process")
    if category_filter:
        print(f"   Category: {category_filter}")
    if resume:
        print(f"   Resume mode: skipping tools with existing context")
    print()

    # Prepare work items
    work_items = []
    for tool in tools:
        doc_parts = []
        if tool['description']:
            doc_parts.append(f"Description: {tool['description']}")
        if tool['rawText']:
            doc_parts.append(f"Documentation: {tool['rawText']}")
        if tool['help_text']:
            try:
                help_obj = json.loads(tool['help_text'])
                if isinstance(help_obj, dict):
                    doc_parts.extend([f"{k}: {v}" for k, v in help_obj.items() if v])
            except:
                pass

        documentation = "\n\n".join(doc_parts)
        if len(documentation) >= 50:
            work_items.append({
                'id': tool['id'],
                'name': tool['name'],
                'category': tool['category'],
                'documentation': documentation
            })

    print(f"📝 {len(work_items)} tools have sufficient documentation")
    print()

    # Process with thread pool
    rate_limiter = RateLimiter(calls_per_minute=50)
    stats = {
        'processed': 0,
        'successful': 0,
        'failed': 0,
        'by_category': {}
    }

    start_time = time.time()

    # Open connection for updates
    update_conn = sqlite3.connect(db_path, check_same_thread=False)
    update_lock = threading.Lock()

    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(
                extract_with_llm_safe,
                item['id'],
                item['name'],
                item['category'],
                item['documentation'],
                api_key,
                rate_limiter
            ): item for item in work_items
        }

        for i, future in enumerate(as_completed(futures), 1):
            item = futures[future]
            result = future.result()

            category = item['category'] or 'Unknown'
            if category not in stats['by_category']:
                stats['by_category'][category] = {'successful': 0, 'failed': 0}

            if result['success']:
                # Update database
                with update_lock:
                    cursor = update_conn.cursor()
                    cursor.execute(
                        "UPDATE tools SET scientific_context = ? WHERE id = ?",
                        (json.dumps(result['context']), result['id'])
                    )
                    update_conn.commit()

                stats['successful'] += 1
                stats['by_category'][category]['successful'] += 1
                status = "✅"
            else:
                stats['failed'] += 1
                stats['by_category'][category]['failed'] += 1
                status = "❌"

            stats['processed'] += 1

            # Progress
            if i % 10 == 0 or i == len(work_items):
                elapsed = time.time() - start_time
                rate = stats['processed'] / elapsed * 60 if elapsed > 0 else 0
                remaining = (len(work_items) - i) / (stats['processed'] / elapsed) if stats['processed'] > 0 else 0

                print(f"[{i}/{len(work_items)}] {status} {item['name'][:50]:50} | "
                      f"Success: {stats['successful']}/{stats['processed']} | "
                      f"Rate: {rate:.1f}/min | ETA: {remaining/60:.1f}h")

    update_conn.close()

    # Summary
    elapsed = time.time() - start_time
    print()
    print("=" * 80)
    print("✅ Batch Extraction Complete")
    print("=" * 80)
    print(f"   Processed: {stats['processed']}")
    print(f"   Successful: {stats['successful']} ({stats['successful']/stats['processed']*100:.1f}%)")
    print(f"   Failed: {stats['failed']}")
    print(f"   Time: {elapsed/3600:.2f} hours")
    print(f"   Rate: {stats['processed']/elapsed*60:.1f} tools/minute")
    print()
    print("📊 By Category (top 10):")
    sorted_cats = sorted(stats['by_category'].items(), key=lambda x: x[1]['successful'], reverse=True)
    for cat, cat_stats in sorted_cats[:10]:
        total = cat_stats['successful'] + cat_stats['failed']
        print(f"   {cat:30} {cat_stats['successful']:4}/{total:4} successful")


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Batch LLM extraction with parallel processing')
    parser.add_argument('--category', help='Filter by category')
    parser.add_argument('--limit', type=int, help='Limit number of tools')
    parser.add_argument('--workers', type=int, default=5, help='Number of parallel workers (default: 5)')
    parser.add_argument('--no-resume', action='store_true', help='Reprocess all tools')
    parser.add_argument('--db', help='Database path')

    args = parser.parse_args()

    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        print("❌ Error: ANTHROPIC_API_KEY not set")
        return 1

    db_path = args.db if args.db else Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

    if not Path(db_path).exists():
        print(f"❌ Database not found: {db_path}")
        return 1

    try:
        batch_process(
            db_path=str(db_path),
            api_key=api_key,
            category_filter=args.category,
            limit=args.limit,
            workers=args.workers,
            resume=not args.no_resume
        )
        return 0
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted. Progress saved.")
        return 1
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
