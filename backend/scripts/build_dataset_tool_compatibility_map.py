#!/usr/bin/env python3
"""
Build dataset-to-tool compatibility mapping using hybrid approach:
1. Code filtering (fast, low precision)
2. LLM reasoning with web search (automated validation)
3. Confidence scoring and output

Strategy:
- For each dataset: Filter tools by category/keywords
- For each candidate: Use LLM + web search to validate compatibility
- Output: reference_data_complete.json updated with 'compatible_tools' field
"""
import json
import sqlite3
import os
import sys
from typing import List, Dict, Any
from pathlib import Path
import anthropic

# Import knowledge-based matcher
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from knowledge_based_matcher import KnowledgeBasedMatcher

# Configuration
GALAXY_TOOLS_DB = "/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db"
REFERENCE_DATA_JSON = "/Users/jingqiwang/biomate/backend/reference_data_complete.json"
OUTPUT_JSON = "/Users/jingqiwang/biomate/backend/reference_data_with_compatible_tools.json"
LOG_FILE = "/Users/jingqiwang/biomate/backend/logs/compatibility_mapping.log"

# LLM configuration
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
if not ANTHROPIC_API_KEY:
    print("Error: ANTHROPIC_API_KEY environment variable not set")
    sys.exit(1)

client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

# Category mapping (dataset category → tool categories)
# Using exact category names from Galaxy tool database
CATEGORY_MAPPING = {
    'drug_discovery': ['Computational chemistry'],
    'metabolomics': ['Metabolomics'],
    'proteomics': ['Proteomics'],
    'genomics': ['Sequence Analysis', 'Genome annotation'],
    'cancer_genomics': ['Sequence Analysis', 'Systems Biology', 'Genomic Interval Operations'],
    'transcriptomics': ['RNA'],
    'systems_biology': ['Systems Biology'],
    'protein_interactions': ['Proteomics', 'Systems Biology'],
    'pathway_analysis': ['Systems Biology', 'Metabolomics'],
}


class DatasetToolMatcher:
    """Match datasets to compatible Galaxy tools using knowledge-based approach"""

    def __init__(self):
        self.db_conn = sqlite3.connect(GALAXY_TOOLS_DB)
        self.log_entries = []
        self.knowledge_matcher = KnowledgeBasedMatcher()

    def log(self, message: str):
        """Log message to console and log file"""
        print(message, flush=True)
        self.log_entries.append(message)

    def filter_candidate_tools(self, dataset: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Step 1: Code-based filtering to get candidate tools
        Returns: List of candidate tool dicts
        """
        self.log(f"\n{'='*70}")
        self.log(f"Filtering candidates for: {dataset['name']}")
        self.log(f"Category: {dataset.get('category', 'unknown')}")
        self.log(f"Format: {dataset.get('format', 'unknown')}")

        # Get relevant categories for this dataset
        dataset_category = dataset.get('category', 'unknown')
        tool_categories = CATEGORY_MAPPING.get(dataset_category, [])

        # If no mapping, try to infer from use cases
        if not tool_categories:
            # Default to generic analysis categories
            tool_categories = ['Sequence Analysis', 'Systems Biology', 'Data Source']

        # Build category filter with EXACT match (not substring)
        category_conditions = " OR ".join([f"category = '{cat}'" for cat in tool_categories])

        # Extract keywords from dataset
        keywords = set()
        keywords.update(dataset['use_cases'])
        keywords.update(dataset.get('index_columns', []))
        keywords.add(dataset['category'])

        # Query database
        cursor = self.db_conn.cursor()
        query = f"""
        SELECT tool_id, name, category, rawText
        FROM tools
        WHERE ({category_conditions})
        AND (rawText LIKE '%database%' OR rawText LIKE '%reference%' OR rawText LIKE '%library%')
        """

        cursor.execute(query)
        results = cursor.fetchall()

        # Filter by keyword relevance
        candidates = []
        for tool_id, name, category, rawText in results:
            # Score by keyword matches
            text_lower = (rawText or '').lower()
            name_lower = (name or '').lower()

            # Check keyword matches in both rawText and name
            keyword_matches = [kw for kw in keywords if str(kw).lower() in text_lower or str(kw).lower() in name_lower]

            # Bonus points for format compatibility (not required)
            format_bonus = 0
            dataset_format = dataset.get('format', 'unknown')
            if dataset_format in ['csv', 'tsv', 'txt']:
                if 'tabular' in text_lower or 'csv' in text_lower or 'tsv' in text_lower:
                    format_bonus = 1
            elif dataset_format == 'parquet':
                if 'parquet' in text_lower:
                    format_bonus = 1
            elif dataset_format == 'sqlite':
                if 'sqlite' in text_lower or 'database' in text_lower:
                    format_bonus = 1

            # Include if has keyword matches OR mentions database/reference
            if keyword_matches or 'database' in text_lower or 'reference' in text_lower:
                candidates.append({
                    'tool_id': tool_id,
                    'name': name,
                    'category': category,
                    'rawText': rawText,
                    'keyword_matches': keyword_matches,
                    'relevance_score': len(keyword_matches) + format_bonus
                })

        # Sort by relevance
        candidates.sort(key=lambda x: x['relevance_score'], reverse=True)

        self.log(f"Found {len(candidates)} candidate tools")
        if candidates:
            self.log("Top 5 candidates:")
            for c in candidates[:5]:
                self.log(f"  - {c['name'][:60]} ({c['category']}) - Score: {c['relevance_score']}")

        return candidates[:50]  # Limit to top 50 candidates

    def validate_with_llm_and_web(self, dataset: Dict[str, Any], tool: Dict[str, Any]) -> Dict[str, Any]:
        """
        Step 2: Use LLM + web search to validate compatibility
        Returns: {
            'compatible': bool,
            'confidence': float (0-1),
            'reasoning': str,
            'web_validation': str
        }
        """
        # Prepare prompt for LLM with web search capability
        prompt = f"""You are a bioinformatics expert analyzing tool-dataset compatibility for Galaxy workflows.

DATASET:
Name: {dataset['name']}
Format: {dataset['format']}
Category: {dataset['category']}
Description: {dataset['description']}
Use cases: {', '.join(dataset['use_cases'])}
Columns: {', '.join(dataset.get('index_columns', []))}

GALAXY TOOL:
Name: {tool['name']}
Category: {tool['category']}
Description: {tool['rawText'][:500]}...

TASK:
Determine if this Galaxy tool can use this dataset as a reference database/library parameter.

SEARCH THE WEB for:
1. Documentation for this Galaxy tool (on toolshed.g2.bx.psu.edu or galaxyproject.org)
2. Examples of using this tool with similar databases
3. Tool parameter specifications and accepted formats

ANALYZE:
1. Does the tool accept database/reference file parameters?
2. Is the dataset format compatible with tool inputs?
3. Does the tool's scientific domain match the dataset's use cases?
4. Are there documented examples of similar usage?

RESPOND in JSON format:
{{
  "compatible": true/false,
  "confidence": 0.0-1.0,
  "reasoning": "Detailed explanation based on web search findings",
  "web_sources": ["list of URLs consulted"],
  "parameter_name": "name of the database parameter (if compatible)" or null
}}

Be conservative: Only mark as compatible if you find clear evidence.
"""

        try:
            # Use GPT-4 with web search (assuming you have web search enabled)
            # Note: This requires enabling web browsing/search in OpenAI API
            response = client.chat.completions.create(
                model="gpt-4o",  # Use GPT-4 for better reasoning
                messages=[
                    {"role": "system", "content": "You are a bioinformatics expert with access to web search. Use web search to validate your answers with documentation and examples."},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.1,  # Low temperature for consistent answers
                response_format={"type": "json_object"}
            )

            result = json.loads(response.choices[0].message.content)
            return result

        except Exception as e:
            self.log(f"  ERROR validating with LLM: {e}")
            return {
                'compatible': False,
                'confidence': 0.0,
                'reasoning': f'LLM validation failed: {str(e)}',
                'web_sources': [],
                'parameter_name': None
            }

    def validate_with_web_search_fallback(self, dataset: Dict[str, Any], tool: Dict[str, Any]) -> Dict[str, Any]:
        """
        Fallback: Use web search to find tool documentation and validate
        This doesn't require GPT-4 web browsing, instead uses WebFetch
        """
        # Extract tool repo from tool_id
        # Format: toolshed.g2.bx.psu.edu/repos/{owner}/{repo}/...
        tool_id = tool['tool_id']
        parts = tool_id.split('/')

        if len(parts) >= 5 and 'repos' in parts:
            repos_idx = parts.index('repos')
            owner = parts[repos_idx + 1]
            repo = parts[repos_idx + 2]

            # Construct ToolShed URL
            toolshed_url = f"https://toolshed.g2.bx.psu.edu/repos/{owner}/{repo}"

            # Use LLM to analyze tool documentation
            search_prompt = f"""Search for documentation about this Galaxy tool and determine database compatibility.

Tool: {tool['name']}
Category: {tool['category']}
ToolShed URL: {toolshed_url}

Dataset to check:
- Format: {dataset['format']}
- Category: {dataset['category']}
- Use case: {', '.join(dataset['use_cases'])}

Search strategy:
1. Look at ToolShed page for parameter descriptions
2. Search for "galaxy {tool['name']} database parameter"
3. Check if tool accepts tabular/CSV/TSV reference files

Respond in JSON:
{{
  "compatible": true/false,
  "confidence": 0.0-1.0,
  "reasoning": "explanation",
  "parameter_name": "database parameter name or null"
}}
"""

            try:
                # Use Claude Sonnet 4.5 for validation
                response = client.messages.create(
                    model="claude-sonnet-4-5",
                    max_tokens=1024,
                    temperature=0.1,
                    system="You are a Galaxy tool expert. Analyze tool documentation to determine database compatibility. Always respond with valid JSON.",
                    messages=[
                        {"role": "user", "content": search_prompt}
                    ]
                )

                return json.loads(response.content[0].text)

            except Exception as e:
                return {
                    'compatible': False,
                    'confidence': 0.0,
                    'reasoning': f'Validation failed: {str(e)}',
                    'parameter_name': None
                }

        return {
            'compatible': False,
            'confidence': 0.0,
            'reasoning': 'Could not parse tool ID',
            'parameter_name': None
        }

    def process_dataset(self, dataset_id: str, dataset: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process a single dataset: filter candidates and validate with LLM
        Returns: Updated dataset dict with 'compatible_tools' field
        """
        self.log(f"\n{'='*70}")
        self.log(f"PROCESSING: {dataset['name']}")
        self.log(f"{'='*70}")

        # Step 1: Code filtering
        candidates = self.filter_candidate_tools(dataset)

        if not candidates:
            self.log("No candidate tools found")
            return {**dataset, 'compatible_tools': []}

        # Step 2: LLM validation (limit to top 20 to save API costs)
        self.log(f"\nValidating top {min(20, len(candidates))} candidates with LLM...")

        compatible_tools = []

        for i, tool in enumerate(candidates[:20], 1):
            self.log(f"\n  [{i}/20] Validating: {tool['name'][:60]}")

            # Use knowledge-based matcher (analyzes existing tool metadata)
            validation = self.knowledge_matcher.analyze_compatibility(dataset, tool)

            # Log if web search was suggested
            if validation.get('needs_web_search'):
                self.log(f"    💡 Suggests web search: {validation.get('web_search_reason', 'N/A')}")

            if validation['compatible'] and validation['confidence'] >= 0.6:
                compatible_tools.append({
                    'tool_id': tool['tool_id'],
                    'tool_name': tool['name'],
                    'confidence': validation['confidence'],
                    'parameter_name': validation.get('parameter_name'),
                    'parameter_evidence': validation.get('parameter_evidence'),
                    'reasoning': validation['reasoning'],
                    'tool_params_found': validation.get('tool_params_found', 0)
                })
                self.log(f"    ✅ COMPATIBLE (confidence: {validation['confidence']:.2f})")
                self.log(f"    Parameter: {validation.get('parameter_name', 'N/A')}")
                self.log(f"    Reasoning: {validation['reasoning'][:120]}...")
            else:
                self.log(f"    ❌ Not compatible (confidence: {validation['confidence']:.2f})")

        self.log(f"\n✅ Found {len(compatible_tools)} compatible tools for {dataset['name']}")

        return {**dataset, 'compatible_tools': compatible_tools}

    def process_all_datasets(self, limit: int = None):
        """
        Process all datasets in reference_data_complete.json
        Args:
            limit: Process only first N datasets (for testing)
        """
        self.log("="*70)
        self.log("DATASET-TO-TOOL COMPATIBILITY MAPPING")
        self.log("="*70)

        # Load reference data
        with open(REFERENCE_DATA_JSON, 'r') as f:
            ref_data = json.load(f)

        datasets = ref_data['datasets']

        # Filter out API datasets - they should be wrapped as Data Source Tools, not get compatible_tools mapping
        local_datasets = {k: v for k, v in datasets.items() if v.get('access_method') == 'local_file'}
        api_datasets = {k: v for k, v in datasets.items() if v.get('access_method') == 'api'}

        dataset_ids = list(local_datasets.keys())

        if limit:
            dataset_ids = dataset_ids[:limit]
            self.log(f"\nProcessing {limit} datasets (test mode)")

        self.log(f"\nTotal datasets: {len(datasets)}")
        self.log(f"  - Local files (will process): {len(local_datasets)}")
        self.log(f"  - API endpoints (skipped - should be Data Source Tools): {len(api_datasets)}")
        self.log(f"\nProcessing {len(dataset_ids)} local datasets for compatible_tools mapping")

        # Process each dataset
        updated_datasets = {}
        for i, dataset_id in enumerate(dataset_ids, 1):
            self.log(f"\n\n{'='*70}")
            self.log(f"DATASET {i}/{len(dataset_ids)}")
            self.log(f"{'='*70}")

            dataset = datasets[dataset_id]
            updated_dataset = self.process_dataset(dataset_id, dataset)
            updated_datasets[dataset_id] = updated_dataset

        # Update reference data
        ref_data['datasets'] = {**datasets, **updated_datasets}

        # Save results
        with open(OUTPUT_JSON, 'w') as f:
            json.dump(ref_data, f, indent=2)

        self.log(f"\n\n{'='*70}")
        self.log("COMPLETED")
        self.log(f"{'='*70}")
        self.log(f"Output saved to: {OUTPUT_JSON}")

        # Save log
        Path(LOG_FILE).parent.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, 'w') as f:
            f.write('\n'.join(self.log_entries))

        self.log(f"Log saved to: {LOG_FILE}")

        # Print summary
        self.print_summary(updated_datasets)

    def print_summary(self, datasets: Dict[str, Dict[str, Any]]):
        """Print summary statistics"""
        total_datasets = len(datasets)
        datasets_with_tools = sum(1 for d in datasets.values() if d.get('compatible_tools'))
        total_tool_matches = sum(len(d.get('compatible_tools', [])) for d in datasets.values())

        self.log(f"\n{'='*70}")
        self.log("SUMMARY")
        self.log(f"{'='*70}")
        self.log(f"Total datasets processed: {total_datasets}")
        self.log(f"Datasets with compatible tools: {datasets_with_tools} ({datasets_with_tools/total_datasets*100:.1f}%)")
        self.log(f"Total tool-dataset matches: {total_tool_matches}")
        self.log(f"Average tools per dataset: {total_tool_matches/total_datasets:.1f}")

        # Top datasets by tool count
        sorted_datasets = sorted(
            datasets.items(),
            key=lambda x: len(x[1].get('compatible_tools', [])),
            reverse=True
        )

        self.log(f"\nTop 10 datasets by compatible tool count:")
        for i, (ds_id, ds) in enumerate(sorted_datasets[:10], 1):
            tool_count = len(ds.get('compatible_tools', []))
            self.log(f"  {i}. {ds['name']}: {tool_count} tools")

    def close(self):
        """Cleanup"""
        self.db_conn.close()


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Build dataset-to-tool compatibility mapping')
    parser.add_argument('--limit', type=int, help='Process only first N datasets (for testing)', default=None)
    parser.add_argument('--test', action='store_true', help='Test mode: process only 3 datasets')
    args = parser.parse_args()

    limit = args.limit if args.limit else (3 if args.test else None)

    matcher = DatasetToolMatcher()
    try:
        matcher.process_all_datasets(limit=limit)
    finally:
        matcher.close()

    return 0


if __name__ == '__main__':
    sys.exit(main())