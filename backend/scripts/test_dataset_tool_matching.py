#!/usr/bin/env python3
"""
Test if dataset-to-tool matching can be done with code alone or needs LLM reasoning.
"""
import json
import sqlite3
import re

# Test case 1: Simple keyword matching
def test_keyword_matching():
    """Can we match based on keywords alone?"""

    # Load sample dataset
    dataset = {
        'name': 'BindingDB_All_202409.tsv',
        'format': 'tsv',
        'category': 'drug_discovery',
        'description': 'Comprehensive database of measured binding affinities',
        'use_cases': ['drug target prediction', 'compound screening', 'pharmacology'],
        'index_columns': ['ligand', 'target', 'affinity', 'ki', 'kd', 'ic50']
    }

    # Load sample tools
    conn = sqlite3.connect('/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db')
    cursor = conn.cursor()

    # Simple keyword search
    keywords = ['drug', 'compound', 'ligand', 'binding', 'affinity', 'screening']
    keyword_pattern = '|'.join(keywords)

    cursor.execute(f"""
    SELECT tool_id, name, category, rawText
    FROM tools
    WHERE (category LIKE '%Computational chemistry%' OR category LIKE '%Drug%')
    AND rawText LIKE '%database%'
    LIMIT 10
    """)

    tools = cursor.fetchall()
    conn.close()

    print("=== TEST 1: KEYWORD MATCHING ===\n")
    print(f"Dataset: {dataset['name']}")
    print(f"Keywords to match: {keywords}\n")
    print(f"Found {len(tools)} tools by category + database mention\n")

    # Check if any match by keywords
    matches = []
    for tool_id, name, category, rawText in tools:
        text_lower = (rawText or '').lower()
        keyword_matches = [kw for kw in keywords if kw in text_lower]
        if keyword_matches:
            matches.append({
                'tool': name[:60],
                'category': category,
                'matched_keywords': keyword_matches
            })

    print(f"Tools matching keywords: {len(matches)}")
    for m in matches[:5]:
        print(f"  - {m['tool']} ({m['category']})")
        print(f"    Matched: {m['matched_keywords']}")

    print(f"\n✅ Conclusion: Keyword matching found {len(matches)} potential matches")
    print(f"❓ But are they truly compatible? We don't know without deeper analysis.\n")
    return matches

# Test case 2: Format compatibility
def test_format_matching():
    """Can we determine if tool accepts TSV format?"""

    print("\n=== TEST 2: FORMAT COMPATIBILITY ===\n")

    conn = sqlite3.connect('/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db')
    cursor = conn.cursor()

    # Find tools that mention tabular/tsv/csv
    cursor.execute("""
    SELECT name, category, rawText
    FROM tools
    WHERE rawText LIKE '%tabular%' OR rawText LIKE '%tsv%' OR rawText LIKE '%csv%'
    LIMIT 5
    """)

    tools = cursor.fetchall()
    conn.close()

    print("Sample tools mentioning tabular/tsv/csv:")
    for name, cat, rawText in tools:
        format_mentions = []
        if 'tabular' in rawText.lower():
            format_mentions.append('tabular')
        if 'tsv' in rawText.lower():
            format_mentions.append('tsv')
        if 'csv' in rawText.lower():
            format_mentions.append('csv')

        print(f"  - {name[:60]} ({cat})")
        print(f"    Formats: {format_mentions}")

    print("\n❓ Problem: Format mentions don't tell us if it's input, output, or parameter format")
    print("❓ We'd need to parse tool XML or parameter schema to know for sure.\n")

# Test case 3: Semantic matching challenge
def test_semantic_matching():
    """Cases where LLM would be clearly needed"""

    print("\n=== TEST 3: SEMANTIC MATCHING CHALLENGES ===\n")

    test_cases = [
        {
            'dataset': 'DepMap CRISPR Gene Dependency',
            'use_case': 'identify cancer drug targets',
            'tool_description': 'Perform enrichment analysis on gene lists',
            'question': 'Does the tool work with CRISPR dependency scores?',
            'answer': 'Maybe - enrichment tools work on gene lists, but do they understand dependency scores?'
        },
        {
            'dataset': 'MetaboAnalyst MS2ID database',
            'use_case': 'metabolite identification from MS/MS spectra',
            'tool_description': 'Annotate peaks from LC-MS data using spectral library',
            'question': 'Is this MS2ID database compatible with this tool?',
            'answer': 'Probably - both are about MS/MS, but need to check file format and API compatibility'
        },
        {
            'dataset': 'STRING protein interaction network',
            'use_case': 'network analysis',
            'tool_description': 'Calculate network centrality measures',
            'question': 'Can this tool use STRING network as input?',
            'answer': 'Maybe - depends on input format (edge list? adjacency matrix? specific schema?)'
        }
    ]

    for i, tc in enumerate(test_cases, 1):
        print(f"Case {i}:")
        print(f"  Dataset: {tc['dataset']}")
        print(f"  Dataset use case: {tc['use_case']}")
        print(f"  Tool description: {tc['tool_description']}")
        print(f"  ❓ {tc['question']}")
        print(f"  💭 {tc['answer']}")
        print()

    print("✅ Conclusion: These require semantic understanding and domain knowledge\n")

# Test case 4: What can code do?
def test_what_code_can_do():
    """Determine what's possible with code-only matching"""

    print("\n=== TEST 4: WHAT CODE CAN DO ===\n")

    strategies = {
        'Category matching': {
            'feasible': True,
            'confidence': 'Low',
            'reason': 'Metabolomics dataset → Metabolomics tools (but not all tools need databases)'
        },
        'Keyword matching': {
            'feasible': True,
            'confidence': 'Low-Medium',
            'reason': 'Match dataset keywords in tool description (many false positives)'
        },
        'Format validation': {
            'feasible': False,
            'confidence': 'N/A',
            'reason': 'Need tool XML schema to verify accepted formats'
        },
        'Column/schema matching': {
            'feasible': False,
            'confidence': 'N/A',
            'reason': 'Tools rarely document required column names'
        },
        'Use case alignment': {
            'feasible': False,
            'confidence': 'N/A',
            'reason': 'Requires semantic understanding (e.g., "drug discovery" → "docking" tools)'
        }
    }

    for strategy, details in strategies.items():
        print(f"{strategy}:")
        print(f"  Feasible: {'✅' if details['feasible'] else '❌'}")
        if details['feasible']:
            print(f"  Confidence: {details['confidence']}")
        print(f"  Reason: {details['reason']}")
        print()

# Test case 5: Proposed hybrid approach
def test_hybrid_approach():
    """What if we combine code filtering + LLM reasoning?"""

    print("\n=== TEST 5: HYBRID APPROACH (CODE + LLM) ===\n")

    print("Step 1: CODE FILTERING (fast, low precision)")
    print("  - Filter by category match (e.g., drug_discovery → Computational chemistry)")
    print("  - Filter by format mention (tsv/csv/tabular)")
    print("  - Filter by keyword overlap (binding, affinity, compound)")
    print("  - Result: ~50-200 candidate tools per dataset\n")

    print("Step 2: LLM REASONING (slow, high precision)")
    print("  - For each candidate, ask LLM:")
    print("    'Given this dataset: {dataset metadata}'")
    print("    'And this tool: {tool description}'")
    print("    'Is the dataset compatible as a reference database parameter?'")
    print("    'Respond: YES/NO/MAYBE with reasoning'")
    print("  - Result: 5-20 truly compatible tools per dataset\n")

    print("Step 3: MANUAL VALIDATION (human review)")
    print("  - Review LLM's 'MAYBE' cases")
    print("  - Test top matches in actual Galaxy workflows")
    print("  - Build ground truth for future model training\n")

    print("✅ This hybrid approach balances speed and accuracy\n")

if __name__ == '__main__':
    print("="*70)
    print("DATASET-TO-TOOL COMPATIBILITY MATCHING: CODE vs LLM")
    print("="*70 + "\n")

    test_keyword_matching()
    test_format_matching()
    test_semantic_matching()
    test_what_code_can_do()
    test_hybrid_approach()

    print("="*70)
    print("RECOMMENDATION")
    print("="*70)
    print("""
Use HYBRID APPROACH:

1. CODE FILTERING (automated):
   - Category: Exact or fuzzy category matching
   - Keywords: Dataset terms in tool description
   - Format hints: Mentions of csv/tsv/tabular
   - Reduce 6,295 tools → ~50-200 candidates per dataset

2. LLM REASONING (batch processing):
   - Provide dataset + tool metadata to LLM
   - Ask for compatibility assessment
   - Get confidence score + reasoning
   - Reduce candidates → 5-20 compatible tools per dataset

3. VALIDATION (sample testing):
   - Test top matches in Galaxy workflows
   - Build ground truth dataset
   - Iterate and improve filters

ESTIMATED TIME:
- Code filtering: 1 hour to implement
- LLM batch processing: ~6 hours for 115 datasets (15k API calls)
- Manual validation: 4 hours (test 20 dataset-tool pairs)
TOTAL: ~2 days
""")