#!/usr/bin/env python3
"""
LLM-powered scientific context extraction for tool metadata.

Uses Claude to deeply analyze tool documentation and extract:
- Complete data type compatibility
- Detailed use cases with examples
- Common mistakes with explanations
- Prerequisites and dependencies
- Best practices
- Parameter guidance
- Compatibility notes
- Scientific domain knowledge
"""

import os
import sqlite3
import json
import time
from pathlib import Path
from typing import Dict, List, Optional
import anthropic


# Expected structured output schema
SCIENTIFIC_CONTEXT_SCHEMA = {
    "data_type_compatibility": {
        "supported_data_types": [],  # e.g., ["DIA", "SWATH-MS", "label-free DIA"]
        "not_supported_data_types": [],  # e.g., ["DDA", "data-dependent acquisition"]
        "notes": ""  # Additional compatibility notes
    },
    "use_cases": [
        {
            "scenario": "",  # e.g., "Bottom-up DIA proteomics with spectral library"
            "when_to_use": "",  # Conditions for this use case
            "typical_workflow": ""  # Where this fits in a workflow
        }
    ],
    "common_mistakes": [
        {
            "mistake": "",  # What users commonly do wrong
            "why_wrong": "",  # Why it's a problem
            "correct_approach": ""  # What to do instead
        }
    ],
    "prerequisites": {
        "required_inputs": [],  # e.g., ["mzML files", "FASTA database"]
        "required_software": [],  # e.g., ["Thermo MS File Reader"]
        "recommended_data_quality": ""  # Quality requirements
    },
    "parameter_guidance": {
        "essential_parameters": [],  # Parameters users must set
        "recommended_defaults": {},  # key: parameter, value: recommended value
        "common_adjustments": []  # When to change from defaults
    },
    "strengths": [],  # What this tool excels at
    "limitations": [],  # What this tool cannot do or does poorly
    "alternatives": [],  # When to use other tools instead
    "scientific_notes": ""  # Domain-specific knowledge
}


EXTRACTION_PROMPT = """You are a scientific tool metadata expert. Analyze this tool's documentation and extract comprehensive scientific context in structured JSON format.

Tool Name: {tool_name}
Category: {category}
Version: {version}

Documentation:
{documentation}

Extract the following information in JSON format:

{{
    "data_type_compatibility": {{
        "supported_data_types": [list of explicitly supported data acquisition types, formats, or experimental methods],
        "not_supported_data_types": [list of explicitly incompatible or not recommended data types],
        "notes": "any additional compatibility details"
    }},
    "use_cases": [
        {{
            "scenario": "specific scientific scenario",
            "when_to_use": "conditions where this tool is appropriate",
            "typical_workflow": "where this fits in analysis pipeline"
        }}
    ],
    "common_mistakes": [
        {{
            "mistake": "what users commonly do wrong",
            "why_wrong": "why this causes problems",
            "correct_approach": "what to do instead"
        }}
    ],
    "prerequisites": {{
        "required_inputs": [list of required input file types or data],
        "required_software": [list of dependencies or prerequisite software],
        "recommended_data_quality": "quality requirements or recommendations"
    }},
    "parameter_guidance": {{
        "essential_parameters": [parameters that users must configure],
        "recommended_defaults": {{"parameter_name": "recommended_value with explanation"}},
        "common_adjustments": [when and how to adjust from defaults]
    }},
    "strengths": [what this tool excels at],
    "limitations": [what this tool cannot do or does poorly],
    "alternatives": [when to consider using different tools],
    "scientific_notes": "domain-specific knowledge or important scientific context"
}}

IMPORTANT INSTRUCTIONS:
1. Extract ONLY information that is explicitly stated or clearly implied in the documentation
2. For proteomics tools: distinguish DDA vs DIA, label-free vs labeled, targeted vs untargeted
3. For genomics tools: distinguish WGS vs WES vs RNA-seq, single-cell vs bulk
4. Be specific: instead of "quality control", say "read quality assessment for NGS data"
5. Empty arrays if no information found - DO NOT guess or infer without evidence
6. Keep explanations concise but informative (1-2 sentences)
7. Focus on scientific accuracy over completeness

Return ONLY valid JSON, no additional text."""


def extract_with_llm(
    tool_name: str,
    category: str,
    version: str,
    documentation: str,
    api_key: str
) -> Optional[Dict]:
    """
    Use Claude to extract scientific context from tool documentation.

    Args:
        tool_name: Name of the tool
        category: Tool category
        version: Tool version
        documentation: Combined documentation text
        api_key: Anthropic API key

    Returns:
        Extracted context as dictionary, or None if extraction fails
    """
    client = anthropic.Anthropic(api_key=api_key)

    # Truncate documentation if too long (keep first 8000 chars)
    if len(documentation) > 8000:
        documentation = documentation[:8000] + "\n\n[... documentation truncated ...]"

    # Split prompt into system (cacheable) and user parts
    system_prompt = """You are a scientific tool metadata expert. Analyze tool documentation and extract comprehensive scientific context in structured JSON format.

Extract the following information in JSON format:

{
    "data_type_compatibility": {
        "supported_data_types": [list of explicitly supported data acquisition types, formats, or experimental methods],
        "not_supported_data_types": [list of explicitly incompatible or not recommended data types],
        "notes": "any additional compatibility details"
    },
    "use_cases": [
        {
            "scenario": "specific scientific scenario",
            "description": "detailed use case",
            "example": "example if available"
        }
    ],
    "research_context": {
        "fields": [list of research fields where this tool is used],
        "methods": [list of methods/techniques this tool supports],
        "experimental_designs": [types of experiments this tool is suited for]
    },
    "limitations": {
        "technical": [list of technical limitations],
        "biological": [list of biological/experimental limitations],
        "computational": [list of computational requirements or constraints]
    },
    "best_practices": [list of recommended usage patterns or guidelines],
    "citations_context": "how the tool should be cited and its academic impact"
}

Be specific and extract only information explicitly mentioned in the documentation."""

    user_content = f"""Tool Name: {tool_name}
Category: {category}
Version: {version}

Documentation:
{documentation}"""

    try:
        message = client.messages.create(
            model="claude-haiku-4-5",  # Upgraded to Haiku 4.5
            max_tokens=4096,
            temperature=0,
            system=[
                {
                    "type": "text",
                    "text": system_prompt,
                    "cache_control": {"type": "ephemeral"}  # Enable prompt caching
                }
            ],
            messages=[{"role": "user", "content": user_content}]
        )

        response_text = message.content[0].text

        # Parse JSON response
        # Remove markdown code blocks if present
        if "```json" in response_text:
            response_text = response_text.split("```json")[1].split("```")[0]
        elif "```" in response_text:
            response_text = response_text.split("```")[1].split("```")[0]

        context = json.loads(response_text.strip())
        return context

    except Exception as e:
        print(f"    ⚠️  LLM extraction failed for {tool_name}: {str(e)[:100]}")
        return None


def process_tools_with_llm(
    db_path: str,
    api_key: str,
    category_filter: Optional[str] = None,
    limit: Optional[int] = None,
    skip_existing: bool = True
):
    """
    Process all tools using LLM extraction.

    Args:
        db_path: Path to database
        api_key: Anthropic API key
        category_filter: Only process tools in this category (e.g., "Proteomics")
        limit: Maximum number of tools to process
        skip_existing: Skip tools that already have scientific_context
    """
    print("=" * 80)
    print("LLM-Powered Scientific Context Extraction")
    print("=" * 80)
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

    if skip_existing:
        query += " AND (scientific_context IS NULL OR scientific_context = '' OR scientific_context = '{}')"

    query += " ORDER BY category, name"

    if limit:
        query += f" LIMIT {limit}"

    cursor.execute(query, params)
    tools = cursor.fetchall()

    print(f"📊 Found {len(tools)} tools to process")
    if category_filter:
        print(f"   Filtered by category: {category_filter}")
    if limit:
        print(f"   Limited to: {limit} tools")
    print()

    stats = {
        'total': len(tools),
        'processed': 0,
        'successful': 0,
        'failed': 0,
        'skipped': 0,
        'by_category': {}
    }

    start_time = time.time()

    for i, tool in enumerate(tools, 1):
        category = tool['category'] or 'Unknown'

        # Initialize category stats
        if category not in stats['by_category']:
            stats['by_category'][category] = {'processed': 0, 'successful': 0}

        # Prepare documentation
        documentation_parts = []
        if tool['description']:
            documentation_parts.append(f"Description: {tool['description']}")
        if tool['rawText']:
            documentation_parts.append(f"Documentation: {tool['rawText']}")
        if tool['help_text']:
            try:
                help_obj = json.loads(tool['help_text'])
                if isinstance(help_obj, dict):
                    for key, value in help_obj.items():
                        if value:
                            documentation_parts.append(f"{key}: {value}")
            except:
                documentation_parts.append(f"Help: {tool['help_text']}")

        documentation = "\n\n".join(documentation_parts)

        if not documentation or len(documentation) < 50:
            stats['skipped'] += 1
            continue

        print(f"[{i}/{len(tools)}] Processing: {tool['name']} ({category})")

        # Extract with LLM
        context = extract_with_llm(
            tool_name=tool['name'],
            category=category,
            version=tool['version'] or 'unknown',
            documentation=documentation,
            api_key=api_key
        )

        if context:
            # Update database
            cursor.execute(
                "UPDATE tools SET scientific_context = ? WHERE id = ?",
                (json.dumps(context), tool['id'])
            )
            conn.commit()

            stats['successful'] += 1
            stats['by_category'][category]['successful'] += 1
            print(f"    ✅ Extracted rich context")
        else:
            stats['failed'] += 1
            print(f"    ❌ Extraction failed")

        stats['processed'] += 1
        stats['by_category'][category]['processed'] += 1

        # Progress update every 10 tools
        if i % 10 == 0:
            elapsed = time.time() - start_time
            rate = stats['processed'] / elapsed
            remaining = (len(tools) - i) / rate if rate > 0 else 0
            print(f"    Progress: {stats['successful']}/{stats['processed']} successful | Rate: {rate:.1f} tools/min | ETA: {remaining/60:.1f} min")
            print()

        # Rate limiting: Claude has rate limits
        time.sleep(1)  # 1 second between requests

    conn.close()

    # Print summary
    elapsed = time.time() - start_time
    print()
    print("=" * 80)
    print("✅ LLM Extraction Complete")
    print("=" * 80)
    print(f"   Total tools: {stats['total']}")
    print(f"   Processed: {stats['processed']}")
    print(f"   Successful: {stats['successful']} ({stats['successful']/stats['processed']*100:.1f}%)")
    print(f"   Failed: {stats['failed']}")
    print(f"   Skipped (insufficient docs): {stats['skipped']}")
    print(f"   Time elapsed: {elapsed/60:.1f} minutes")
    print(f"   Rate: {stats['processed']/elapsed*60:.1f} tools/minute")
    print()

    print("📊 By Category:")
    sorted_categories = sorted(
        stats['by_category'].items(),
        key=lambda x: x[1]['successful'],
        reverse=True
    )
    for cat, cat_stats in sorted_categories[:10]:
        print(f"   {cat:30} {cat_stats['successful']:4}/{cat_stats['processed']:4} successful")

    return stats


def show_extracted_examples(db_path: str, category: str = "Proteomics", limit: int = 3):
    """Show examples of extracted context."""
    print()
    print("=" * 80)
    print(f"Example Extracted Context ({category})")
    print("=" * 80)

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("""
        SELECT name, category, scientific_context
        FROM tools
        WHERE category = ?
        AND scientific_context IS NOT NULL
        AND scientific_context != ''
        AND scientific_context != '{}'
        ORDER BY name
        LIMIT ?
    """, (category, limit))

    tools = cursor.fetchall()

    for tool in tools:
        print()
        print(f"🔧 {tool['name']}")
        print("-" * 80)

        try:
            context = json.loads(tool['scientific_context'])

            # Data types
            if context.get('data_type_compatibility', {}).get('supported_data_types'):
                print(f"   ✅ Supports: {', '.join(context['data_type_compatibility']['supported_data_types'])}")
            if context.get('data_type_compatibility', {}).get('not_supported_data_types'):
                print(f"   ❌ Not for: {', '.join(context['data_type_compatibility']['not_supported_data_types'])}")

            # Use cases
            if context.get('use_cases'):
                print(f"   📋 Use Cases:")
                for uc in context['use_cases'][:2]:
                    print(f"      • {uc.get('scenario', 'N/A')}")

            # Strengths
            if context.get('strengths'):
                print(f"   ⭐ Strengths:")
                for strength in context['strengths'][:2]:
                    print(f"      • {strength}")

            # Common mistakes
            if context.get('common_mistakes'):
                print(f"   ⚠️  Common Mistakes:")
                for mistake in context['common_mistakes'][:2]:
                    print(f"      • {mistake.get('mistake', 'N/A')}")

            # Prerequisites
            if context.get('prerequisites', {}).get('required_inputs'):
                print(f"   📥 Required Inputs: {', '.join(context['prerequisites']['required_inputs'][:3])}")

        except Exception as e:
            print(f"   ⚠️  Error parsing context: {str(e)}")

    conn.close()


def main():
    """Main function."""
    import argparse

    parser = argparse.ArgumentParser(
        description='LLM-powered scientific context extraction'
    )
    parser.add_argument(
        '--category',
        type=str,
        help='Only process tools in this category (e.g., Proteomics)'
    )
    parser.add_argument(
        '--limit',
        type=int,
        help='Maximum number of tools to process (for testing)'
    )
    parser.add_argument(
        '--examples',
        action='store_true',
        help='Show example extractions after processing'
    )
    parser.add_argument(
        '--force',
        action='store_true',
        help='Reprocess tools that already have context'
    )
    parser.add_argument(
        '--db',
        type=str,
        help='Path to database'
    )

    args = parser.parse_args()

    # Get API key
    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        print("❌ Error: ANTHROPIC_API_KEY environment variable not set")
        print()
        print("Set it with:")
        print("  export ANTHROPIC_API_KEY='your-api-key'")
        return 1

    # Determine database path
    if args.db:
        db_path = Path(args.db)
    else:
        db_path = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return 1

    print(f"📁 Database: {db_path}")
    print()

    try:
        # Process tools
        stats = process_tools_with_llm(
            db_path=str(db_path),
            api_key=api_key,
            category_filter=args.category,
            limit=args.limit,
            skip_existing=not args.force
        )

        # Show examples
        if args.examples and stats['successful'] > 0:
            category = args.category or "Proteomics"
            show_extracted_examples(str(db_path), category=category)

        print()
        print("✅ Done! Tools now have rich, LLM-extracted scientific context.")
        print()
        print("This enables:")
        print("  • Accurate data type compatibility checking")
        print("  • Detailed use case matching")
        print("  • Proactive mistake prevention")
        print("  • Parameter recommendation")
        print("  • Workflow optimization")

        return 0

    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user. Progress has been saved.")
        return 1
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
