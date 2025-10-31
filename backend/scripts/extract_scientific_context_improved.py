#!/usr/bin/env python3
"""
IMPROVED Scientific Context Extraction - Uses Full Source Data
Key improvements:
1. Uses rawText (richer than help_text)
2. Parses help_text JSON properly
3. Includes parameter details
4. Higher token limits for detailed documentation
5. Better confidence tracking
"""

import os
import sys
import sqlite3
import json
import anthropic
from pathlib import Path
import time
from datetime import datetime

# Enhanced extraction prompt with full context
EXTRACTION_PROMPT = """You are a bioinformatics expert extracting scientific decision-making information about Galaxy tools.

CONTEXT ABOUT THE TOOL DATABASE:
The database already has these fields (DO NOT duplicate):
- description: Tool overview
- help_text: Documentation (JSON structure)
- parameters: Technical specs with types/defaults
- inputs/outputs: File formats
- citations: References

YOUR TASK: Extract UNIQUE scientific context for tool selection and workflow decisions.

INFORMATION SOURCES - ALL CLAIMS NEED EVIDENCE:
1. **Tool documentation** (below): Extract URLs, DOIs, paper citations mentioned
2. **Published papers**: Provide DOI or URL (search if needed: "tool name bioinformatics paper")
3. **Benchmarks/comparisons**: Find comparison papers, tutorials, community benchmarks
4. **Best practices**: Link to tutorials, protocol papers, or method papers

CRITICAL: Do NOT make unsupported claims. Every claim must have:
- A verifiable URL (DOI, GitHub, documentation, paper, tutorial)
- OR be directly quoted from the tool documentation provided
- If you know something but can't find evidence, mark it as "needs_verification" with search query

OUTPUT SCHEMA:
{{
  "omics_applicability": {{
    "primary_omics": ["proteomics", "transcriptomics", etc.],
    "suitable_designs": ["experimental designs this works for"],
    "not_suitable": ["when not to use this tool"],
    "data_requirements": {{
      "min_samples": <number or null>,
      "min_replicates": <number or null>,
      "notes": "sample size requirements"
    }},
    "evidence": [
      {{
        "claim": "specific claim being made",
        "source": "tool documentation / published paper / tutorial / needs verification",
        "url": "https://... or DOI (REQUIRED - find it or mark needs_verification)",
        "quote": "relevant excerpt if from documentation",
        "search_query": "if needs_verification, what to search for"
      }}
    ]
  }},

  "tool_selection": {{
    "best_for": ["specific scenarios where this excels"],
    "not_recommended_for": ["contexts where alternatives better"],
    "alternatives": [
      {{
        "tool": "alternative name",
        "when_to_prefer_this": "current tool better when...",
        "when_to_prefer_alternative": "alternative better when...",
        "evidence_url": "comparison paper/benchmark URL (REQUIRED - search for tool comparison papers)"
      }}
    ],
    "evidence": [
      {{
        "claim": "why this tool excels in certain scenarios",
        "source": "benchmark paper / tool publication / community discussion / needs verification",
        "url": "https://... or DOI (REQUIRED)",
        "search_query": "if needs_verification, search query to find evidence"
      }}
    ]
  }},

  "scientific_guidance": {{
    "common_pitfalls": [
      {{
        "mistake": "what users do wrong",
        "consequence": "what happens",
        "recommendation": "correct approach",
        "evidence_url": "tutorial/paper/forum discussion URL (REQUIRED - search for it)"
      }}
    ],
    "key_parameters": [
      {{
        "parameter": "parameter name",
        "scientific_meaning": "what it controls scientifically",
        "typical_values": "common ranges",
        "context_guidance": {{"scenario": "recommended value"}},
        "evidence_url": "paper/documentation URL (REQUIRED - find method paper or docs)"
      }}
    ],
    "result_interpretation": [
      {{
        "guidance": "How to interpret outputs or what to validate",
        "evidence_url": "documentation/paper URL (REQUIRED - find tutorial or method paper)",
        "search_query": "if URL not found, what to search for"
      }}
    ]
  }},

  "scientific_assumptions": [
    {{
      "assumption": "Biological or statistical assumption",
      "violation_context": "When this may be violated",
      "evidence_url": "paper/documentation URL (REQUIRED - find method paper)",
      "search_query": "if URL not found"
    }}
  ],

  "information_sources": {{
    "tool_homepage": "official tool website URL (extract from documentation)",
    "tool_documentation": "documentation URL (extract from rawText/help_text)",
    "key_publications": ["DOI or URL (extract from citations or documentation)"],
    "evidence_quality": "complete/partial/needs_verification",
    "missing_evidence_for": ["list what needs verification with search queries"],
    "confidence": "high (all evidence found) / medium (some evidence) / low (needs verification)"
  }}
}}

RULES:
1. Be specific - no generic "Alignment" or "Visualization" terms
2. Complete sentences only
3. **EVIDENCE REQUIRED**: For EVERY claim, extract verifiable URL from documentation:
   - Extract URLs from rawText, help_text (homepage, GitHub, papers, DOIs)
   - Look for phrases like "homepage:", "see paper:", "doi:", "github.com", "bioconductor.org"
   - Extract citation URLs if papers are mentioned
   - DO NOT use memorized URLs - only extract from provided documentation
   - If URL not found in documentation, mark as "needs_verification" with search_query
4. Mark confidence based on evidence completeness:
   - high: all claims have URLs extracted from documentation
   - medium: most claims have URLs, some need verification
   - low: many claims need verification
5. Only extract from provided documentation - do not fabricate or use memorized URLs

TOOL INFORMATION:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Tool: {tool_name}
Category: {category}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Description:
{description}

Documentation (rawText - most comprehensive):
{raw_text}

Structured Help:
{help_text}

Parameters:
{parameters}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Extract now. Return ONLY valid JSON.
"""


def extract_scientific_context(tool: dict, client: anthropic.Anthropic, model: str) -> dict:
    """Extract scientific context using Claude with comprehensive source data."""

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
            for p in parameters_data[:10]  # First 10 parameters
        ])
    else:
        params_str = "No parameter information available"

    # Build prompt with comprehensive data
    prompt = EXTRACTION_PROMPT.format(
        tool_name=tool['name'],
        category=tool.get('category', 'Unknown'),
        description=(tool.get('description') or 'No description')[:1000],
        raw_text=(tool.get('rawText') or 'No raw documentation')[:8000],  # Up to 8KB
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

        # Parse response
        text = response.content[0].text.strip()

        # Remove markdown code blocks if present
        if text.startswith('```'):
            lines = text.split('\n')
            if len(lines) > 2:
                text = '\n'.join(lines[1:-1])

        context = json.loads(text)

        # Ensure information_sources exists
        if 'information_sources' not in context:
            context['information_sources'] = {
                "from_documentation": bool(tool.get('rawText')),
                "from_llm_knowledge": [],
                "confidence": "unknown"
            }

        return context

    except Exception as e:
        print(f"    ⚠️  Error: {str(e)[:100]}")
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


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Extract scientific context with FULL source data')
    parser.add_argument('--db', default='/home/yzhang/biomate/backend/database/galaxy_ai_tools.db')
    parser.add_argument('--batch-size', type=int, default=50, help='Process in batches')
    parser.add_argument('--start-offset', type=int, default=0, help='Resume from offset')
    parser.add_argument('--model', default='claude-haiku-4-5')
    parser.add_argument('--log', default='/tmp/improved_extraction.log')
    parser.add_argument('--test', type=int, help='Test mode: only process N tools')

    args = parser.parse_args()

    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        print("❌ ANTHROPIC_API_KEY not set")
        return 1

    client = anthropic.Anthropic(api_key=api_key)

    # Connect to DB
    conn = sqlite3.connect(args.db)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Get total count
    cursor.execute("SELECT COUNT(*) as count FROM tools")
    total = cursor.fetchone()['count']

    if args.test:
        total = min(args.test, total)

    print("="*80)
    print("IMPROVED Scientific Context Extraction")
    print("="*80)
    print(f"Model: {args.model}")
    print(f"Total tools: {total}")
    print(f"Batch size: {args.batch_size}")
    print(f"Starting offset: {args.start_offset}")
    print(f"Log file: {args.log}")
    if args.test:
        print(f"TEST MODE: Only processing {args.test} tools")
    print()
    print("KEY IMPROVEMENTS:")
    print("✓ Uses rawText (up to 8KB) - richer than help_text")
    print("✓ Parses help_text JSON properly")
    print("✓ Includes parameter details")
    print("✓ Higher context limits for full documentation")
    print()

    # Process in batches
    offset = args.start_offset
    processed = 0
    success = 0
    high_conf = 0
    medium_conf = 0

    log_file = open(args.log, 'a')
    log_file.write(f"\n{'='*80}\n")
    log_file.write(f"Started: {datetime.now()}\n")
    log_file.write(f"Model: {args.model}, Offset: {offset}\n")

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

        for i, tool in enumerate(tools, 1):
            tool_num = offset + i
            print(f"  {tool_num}/{total}: {tool['name'][:50]} ", end='', flush=True)

            start_time = time.time()
            context = extract_scientific_context(dict(tool), client, args.model)
            elapsed = time.time() - start_time

            # Assess quality
            sources = context.get('information_sources', {})
            conf = sources.get('confidence', 'unknown')

            if conf in ['high', 'medium']:
                success += 1
                if conf == 'high':
                    high_conf += 1
                elif conf == 'medium':
                    medium_conf += 1

            # Save to database
            cursor.execute(
                "UPDATE tools SET scientific_context = ? WHERE id = ?",
                (json.dumps(context), tool['id'])
            )
            conn.commit()

            processed += 1

            # Log
            log_entry = f"{tool_num},{tool['name']},{conf},{elapsed:.1f}s\n"
            log_file.write(log_entry)
            log_file.flush()

            print(f"[{conf}] {elapsed:.1f}s")

            # Progress summary every 10 tools
            if processed % 10 == 0:
                success_rate = success/processed*100 if processed > 0 else 0
                print(f"    Progress: {success}/{processed} quality ({success_rate:.1f}%), High: {high_conf}, Medium: {medium_conf}")

        offset = batch_end

        # Summary after each batch
        print(f"\n  ✅ Batch complete: {processed} processed, {success} quality, {high_conf} high, {medium_conf} medium")

        if args.test and processed >= args.test:
            break

    log_file.write(f"Completed: {datetime.now()}\n")
    log_file.write(f"Processed: {processed}, Success: {success}, High: {high_conf}, Medium: {medium_conf}\n")
    log_file.close()

    print("\n" + "="*80)
    print("EXTRACTION COMPLETE")
    print("="*80)
    print(f"Total processed: {processed}")
    print(f"Quality extractions: {success} ({success/processed*100:.1f}%)")
    print(f"  High confidence: {high_conf} ({high_conf/processed*100:.1f}%)")
    print(f"  Medium confidence: {medium_conf} ({medium_conf/processed*100:.1f}%)")
    print(f"Log: {args.log}")

    conn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
