#!/usr/bin/env python3
"""
Web search-based validation for dataset-tool compatibility.
Uses Brave Search API or similar to find actual documentation and examples.
"""
import os
import json
import requests
from typing import Dict, Any, List
import anthropic

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
BRAVE_API_KEY = os.getenv("BRAVE_API_KEY")  # Get from https://brave.com/search/api/

client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)


class WebSearchValidator:
    """Validate tool-dataset compatibility using web search"""

    def __init__(self):
        self.brave_api_key = BRAVE_API_KEY

    def search_web(self, query: str, num_results: int = 5) -> List[Dict[str, str]]:
        """
        Search the web using Brave Search API
        Returns: List of {title, url, description}
        """
        if not self.brave_api_key:
            print("Warning: BRAVE_API_KEY not set, skipping web search")
            return []

        try:
            headers = {
                "Accept": "application/json",
                "X-Subscription-Token": self.brave_api_key
            }

            params = {
                "q": query,
                "count": num_results
            }

            response = requests.get(
                "https://api.search.brave.com/res/v1/web/search",
                headers=headers,
                params=params,
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                results = []

                for item in data.get('web', {}).get('results', []):
                    results.append({
                        'title': item.get('title', ''),
                        'url': item.get('url', ''),
                        'description': item.get('description', '')
                    })

                return results
            else:
                print(f"Web search failed: {response.status_code}")
                return []

        except Exception as e:
            print(f"Web search error: {e}")
            return []

    def validate_compatibility(self, dataset: Dict[str, Any], tool: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate compatibility using web search + LLM analysis
        """
        tool_name = tool['name']
        dataset_name = dataset['name']
        dataset_format = dataset['format']

        # Step 1: Search for tool documentation
        doc_query = f"galaxy {tool_name} toolshed documentation parameters"
        doc_results = self.search_web(doc_query, num_results=3)

        # Step 2: Search for usage examples
        example_query = f"galaxy {tool_name} database reference file example"
        example_results = self.search_web(example_query, num_results=3)

        # Step 3: Search for format compatibility
        format_query = f"galaxy {tool_name} {dataset_format} input format"
        format_results = self.search_web(format_query, num_results=2)

        # Combine search results
        all_results = doc_results + example_results + format_results

        if not all_results:
            # Fallback: Use LLM without web search
            return self._llm_validation_no_web(dataset, tool)

        # Step 4: Use LLM to analyze search results
        return self._llm_validation_with_web(dataset, tool, all_results)

    def _llm_validation_with_web(self, dataset: Dict[str, Any], tool: Dict[str, Any],
                                  search_results: List[Dict[str, str]]) -> Dict[str, Any]:
        """Use LLM to analyze web search results with prompt caching"""

        # Format search results for LLM
        search_context = "\n\n".join([
            f"[{i+1}] {r['title']}\nURL: {r['url']}\n{r['description']}"
            for i, r in enumerate(search_results)
        ])

        # System prompt (cached - reused across all validations)
        system_prompt = """You are a Galaxy bioinformatics expert specializing in tool-dataset compatibility analysis.

Your task is to determine if a Galaxy tool can use a given dataset as a reference database parameter.

ANALYSIS FRAMEWORK:
1. Evidence Quality Assessment
   - Look for explicit mentions of database/reference parameters
   - Check for format compatibility (CSV, TSV, SQLite, etc.)
   - Verify scientific domain alignment
   - Identify parameter names from documentation

2. Confidence Scoring (0.0-1.0)
   - 0.9-1.0: Explicit documentation with parameter names
   - 0.7-0.9: Clear evidence from examples/tutorials
   - 0.5-0.7: Indirect evidence, format compatibility unclear
   - 0.0-0.5: Insufficient evidence (mark incompatible)

3. Response Format
   Always respond in JSON with:
   - compatible: true/false
   - confidence: 0.0-1.0
   - reasoning: detailed explanation citing search results
   - evidence_urls: list of supporting URLs
   - parameter_name: exact parameter name if found
   - caveats: any limitations or requirements

IMPORTANT: Base your analysis ONLY on the provided search results. Be conservative - only mark compatible if clear evidence exists."""

        user_prompt = f"""Analyze whether this Galaxy tool can use this dataset as a reference database.

DATASET:
- Name: {dataset['name']}
- Format: {dataset['format']}
- Category: {dataset['category']}
- Use cases: {', '.join(dataset['use_cases'])}
- Columns: {', '.join(dataset.get('index_columns', []))}

GALAXY TOOL:
- Name: {tool['name']}
- Category: {tool['category']}

WEB SEARCH RESULTS (from Galaxy documentation and examples):
{search_context}

Provide your analysis in JSON format."""

        try:
            # Use Claude Sonnet 4.5 with prompt caching
            response = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=1024,
                temperature=0.1,
                system=[
                    {
                        "type": "text",
                        "text": system_prompt,
                        "cache_control": {"type": "ephemeral"}  # Cache system prompt - saves 90%!
                    }
                ],
                messages=[
                    {"role": "user", "content": user_prompt}
                ]
            )

            result = json.loads(response.content[0].text)
            return result

        except Exception as e:
            print(f"LLM analysis error: {e}")
            return {
                'compatible': False,
                'confidence': 0.0,
                'reasoning': f'Analysis failed: {str(e)}',
                'evidence_urls': [],
                'parameter_name': None
            }

    def _llm_validation_no_web(self, dataset: Dict[str, Any], tool: Dict[str, Any]) -> Dict[str, Any]:
        """Fallback: LLM validation without web search with prompt caching"""

        system_prompt = """You are a Galaxy bioinformatics expert with deep knowledge of Galaxy tools and their parameters.

Your task is to assess tool-dataset compatibility based on your knowledge when web search is unavailable.

IMPORTANT LIMITATIONS:
- Without documentation, confidence must be LOW (max 0.5)
- Only mark compatible if you have strong prior knowledge
- Be conservative - prefer false negatives over false positives

Response format: JSON with compatible, confidence, reasoning, parameter_name"""

        user_prompt = f"""Based on your knowledge of Galaxy tools, assess this compatibility.

DATASET:
- Name: {dataset['name']}
- Format: {dataset['format']}
- Category: {dataset['category']}
- Description: {dataset['description']}

TOOL:
- Name: {tool['name']}
- Category: {tool['category']}
- Description: {tool['rawText'][:300]}...

Respond in JSON:
{{
  "compatible": true/false,
  "confidence": 0.0-1.0,
  "reasoning": "explanation",
  "parameter_name": null  // Cannot determine without documentation
}}

Note: Without web search, confidence should be low (max 0.5) unless you have strong prior knowledge.
"""

        try:
            # Use Claude Sonnet 4.5 with prompt caching
            response = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=1024,
                temperature=0.1,
                system=[
                    {
                        "type": "text",
                        "text": system_prompt,
                        "cache_control": {"type": "ephemeral"}  # Cache system prompt
                    }
                ],
                messages=[
                    {"role": "user", "content": user_prompt}
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


# Example usage
if __name__ == '__main__':
    validator = WebSearchValidator()

    # Test with a sample dataset and tool
    test_dataset = {
        'name': 'BindingDB_All_202409.tsv',
        'format': 'tsv',
        'category': 'drug_discovery',
        'description': 'Comprehensive database of measured binding affinities',
        'use_cases': ['drug target prediction', 'compound screening'],
        'index_columns': ['ligand', 'target', 'affinity']
    }

    test_tool = {
        'name': 'Search ChEMBL database',
        'category': 'Computational chemistry',
        'rawText': 'Tool for searching ChEMBL database...',
        'tool_id': 'toolshed.g2.bx.psu.edu/repos/bgruening/chembl/Search_ChEMBL_database'
    }

    print("Testing web search validation...")
    result = validator.validate_compatibility(test_dataset, test_tool)

    print("\nResult:")
    print(json.dumps(result, indent=2))
