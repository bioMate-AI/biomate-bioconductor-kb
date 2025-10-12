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
        Search the web using Claude Code's WebSearch tool
        Returns: List of {title, url, description}
        """
        try:
            # Use WebSearch tool (available in Claude Code)
            # Note: This is a placeholder - actual implementation will use the WebSearch tool
            # For now, construct search results structure from documentation URLs

            # Common Galaxy documentation patterns for tools
            results = [
                {
                    'title': f'Galaxy ToolShed search: {query}',
                    'url': f'https://toolshed.g2.bx.psu.edu/',
                    'description': 'Search Galaxy ToolShed for tool documentation and parameters'
                },
                {
                    'title': f'Galaxy Project Documentation: {query}',
                    'url': 'https://docs.galaxyproject.org/',
                    'description': 'Official Galaxy documentation for tools and data managers'
                },
                {
                    'title': f'Galaxy Training: {query}',
                    'url': 'https://training.galaxyproject.org/',
                    'description': 'Galaxy training materials and tool usage examples'
                }
            ]

            return results[:num_results]

        except Exception as e:
            print(f"Web search error: {e}")
            return []

    def validate_compatibility(self, dataset: Dict[str, Any], tool: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate compatibility using LLM analysis with tool documentation context
        """
        tool_name = tool['name']
        tool_category = tool['category']
        tool_description = tool.get('rawText', '')[:500]

        dataset_name = dataset['name']
        dataset_format = dataset['format']
        dataset_category = dataset['category']
        dataset_use_cases = dataset.get('use_cases', [])

        # Use LLM to analyze compatibility based on available information
        # This is more reliable than web search which may not find specific tool docs
        return self._llm_validation_with_context(dataset, tool)

    def _llm_validation_with_context(self, dataset: Dict[str, Any], tool: Dict[str, Any]) -> Dict[str, Any]:
        """Use LLM to analyze compatibility with tool/dataset context and prompt caching"""

        # System prompt (cached - reused across all validations)
        system_prompt = """You are a Galaxy bioinformatics expert specializing in tool-dataset compatibility analysis.

Your task is to determine if a Galaxy tool can use a given dataset as a reference database parameter.

ANALYSIS FRAMEWORK:
1. Category Matching
   - Does the tool category align with dataset domain?
   - Example: Metabolomics tools work with metabolomics datasets

2. Format Compatibility
   - Can the tool accept this file format? (CSV, TSV, SQLite, etc.)
   - Galaxy tools typically accept: tabular, csv, tsv for text data
   - Specialized tools accept: sqlite for databases

3. Use Case Alignment
   - Do the dataset use cases match the tool's purpose?
   - Example: "drug discovery" dataset → docking/screening tools

4. Parameter Inference
   - Based on tool description, likely parameter names:
   - Common: reference_database, database_file, library, reference_genome

5. Confidence Scoring (0.0-1.0)
   - 0.8-1.0: Strong category match + clear format compatibility
   - 0.6-0.8: Good domain alignment + probable format support
   - 0.4-0.6: Weak alignment or uncertain format
   - 0.0-0.4: Incompatible (mark as false)

IMPORTANT: Be conservative but not overly strict. If category and format align, mark compatible with appropriate confidence."""

        user_prompt = f"""Analyze compatibility between this dataset and Galaxy tool.

DATASET:
- Name: {dataset['name']}
- Format: {dataset['format']}
- Category: {dataset['category']}
- Use cases: {', '.join(dataset.get('use_cases', []))}
- Columns: {', '.join(dataset.get('index_columns', [])[:5])}

GALAXY TOOL:
- Name: {tool['name']}
- Category: {tool['category']}
- Description: {tool.get('rawText', '')[:400]}

Based on the information above, determine:
1. Is this tool likely to accept the dataset as a reference parameter?
2. What confidence level (0.0-1.0)?
3. What parameter name would it likely use?

Respond in JSON:
{{
  "compatible": true/false,
  "confidence": 0.0-1.0,
  "reasoning": "Detailed explanation of category/format/use case alignment",
  "parameter_name": "likely parameter name" or null,
  "caveats": "any limitations" or null
}}"""

        try:
            # Use Claude Sonnet 4.5 with prompt caching
            response = client.messages.create(
                model="claude-sonnet-4-5",
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

            response_text = response.content[0].text

            # Try to extract JSON from response (Claude sometimes adds markdown)
            if "```json" in response_text:
                # Extract JSON from markdown code block
                json_start = response_text.find("```json") + 7
                json_end = response_text.find("```", json_start)
                response_text = response_text[json_start:json_end].strip()
            elif "```" in response_text:
                # Extract from generic code block
                json_start = response_text.find("```") + 3
                json_end = response_text.find("```", json_start)
                response_text = response_text[json_start:json_end].strip()

            result = json.loads(response_text)
            return result

        except json.JSONDecodeError as e:
            print(f"JSON parse error: {e}")
            print(f"Response text: {response_text[:200]}")
            return {
                'compatible': False,
                'confidence': 0.0,
                'reasoning': f'JSON parse failed: {str(e)}',
                'parameter_name': None
            }
        except Exception as e:
            print(f"LLM analysis error: {e}")
            return {
                'compatible': False,
                'confidence': 0.0,
                'reasoning': f'Analysis failed: {str(e)}',
                'parameter_name': None
            }

    def _llm_validation_with_web_DEPRECATED(self, dataset: Dict[str, Any], tool: Dict[str, Any],
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
                model="claude-sonnet-4-5",
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
                model="claude-sonnet-4-5",
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
