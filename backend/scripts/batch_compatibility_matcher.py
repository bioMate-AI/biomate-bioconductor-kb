#!/usr/bin/env python3
"""
Batch compatibility matcher - evaluates ALL candidate tools in ONE API call.
Much faster than sequential evaluation.
"""
import json
import time
from typing import Dict, Any, List
import anthropic
import os

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)


class BatchCompatibilityMatcher:
    """Evaluate all candidate tools in a single batch API call"""

    def analyze_batch(self, dataset: Dict[str, Any], tools: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Analyze ALL tools at once for compatibility with dataset.
        Returns list of compatible tools with confidence scores.
        """

        # Build tool list for prompt
        tools_list = []
        for i, tool in enumerate(tools):
            tools_list.append(f"""
[Tool {i+1}]
- Name: {tool['name']}
- Category: {tool['category']}
- Description: {tool.get('rawText', '')[:300]}...
""")

        tools_text = "\n".join(tools_list)

        system_prompt = """You are a Galaxy bioinformatics expert specializing in tool-dataset compatibility analysis.

Your task is to evaluate MULTIPLE Galaxy tools at once and determine which ones can accept a given dataset as a reference database parameter.

ANALYSIS FRAMEWORK:
1. Category Matching - Does tool category align with dataset domain?
2. Format Compatibility - Can the tool accept this file format?
3. Use Case Alignment - Do dataset use cases match tool's purpose?
4. Parameter Inference - Based on tool description, does it need reference data?

CONFIDENCE SCORING (0.0-1.0):
- 0.8-1.0: Strong category match + clear format compatibility
- 0.6-0.8: Good domain alignment + probable format support
- Below 0.6: Mark as incompatible

IMPORTANT: Be efficient but thorough. Only mark tools as compatible if there's clear evidence."""

        user_prompt = f"""Analyze which of these {len(tools)} Galaxy tools can use this dataset as a reference parameter.

DATASET:
- Name: {dataset['name']}
- Format: {dataset.get('format', 'unknown')}
- Category: {dataset.get('category', 'unknown')}
- Use Cases: {', '.join(dataset.get('use_cases', [])[:5])}
- Columns: {', '.join(dataset.get('index_columns', [])[:10])}

CANDIDATE TOOLS:
{tools_text}

For EACH tool, determine compatibility. Respond with a JSON array:
[
  {{
    "tool_index": 1,
    "tool_name": "tool name",
    "compatible": true/false,
    "confidence": 0.0-1.0,
    "reasoning": "brief explanation",
    "parameter_name": "likely parameter name" or null
  }},
  ...
]

ONLY include tools where compatible=true AND confidence >= 0.6 in your response."""

        # Retry with exponential backoff
        max_retries = 5
        base_delay = 2

        for attempt in range(max_retries):
            try:
                response = client.messages.create(
                    model="claude-sonnet-4-5",
                    max_tokens=8000,  # Larger for batch response
                    temperature=0.1,
                    system=[
                        {
                            "type": "text",
                            "text": system_prompt,
                            "cache_control": {"type": "ephemeral"}
                        }
                    ],
                    messages=[
                        {"role": "user", "content": user_prompt}
                    ]
                )

                response_text = response.content[0].text
                break  # Success

            except Exception as api_error:
                if "rate_limit" in str(api_error) and attempt < max_retries - 1:
                    wait_time = base_delay * (2 ** attempt)
                    print(f"Rate limit hit, retrying in {wait_time}s... (attempt {attempt + 1}/{max_retries})")
                    time.sleep(wait_time)
                    continue
                else:
                    raise api_error

        try:
            # Extract JSON from response
            if "```json" in response_text:
                json_start = response_text.find("```json") + 7
                json_end = response_text.find("```", json_start)
                response_text = response_text[json_start:json_end].strip()
            elif "```" in response_text:
                json_start = response_text.find("```") + 3
                json_end = response_text.find("```", json_start)
                response_text = response_text[json_start:json_end].strip()

            # Handle case where response is just "[]" for no matches
            if response_text.strip() == "[]":
                return []

            results = json.loads(response_text)

            # Map back to original tools
            compatible_tools = []
            for result in results:
                if result.get('compatible', False) and result.get('confidence', 0) >= 0.6:
                    tool_idx = result['tool_index'] - 1  # Convert to 0-indexed
                    if 0 <= tool_idx < len(tools):
                        compatible_tools.append({
                            'tool_id': tools[tool_idx]['tool_id'],
                            'name': tools[tool_idx]['name'],
                            'category': tools[tool_idx]['category'],
                            'confidence': result['confidence'],
                            'reasoning': result.get('reasoning', ''),
                            'parameter_name': result.get('parameter_name')
                        })

            return compatible_tools

        except json.JSONDecodeError as e:
            print(f"JSON parse error: {e}")
            print(f"Response text: {response_text[:500]}")
            return []
        except Exception as e:
            print(f"Batch analysis error: {e}")
            return []


# Test
if __name__ == '__main__':
    matcher = BatchCompatibilityMatcher()

    test_dataset = {
        'name': 'BindingDB_All_202409.tsv',
        'format': 'tsv',
        'category': 'drug_discovery',
        'use_cases': ['drug target prediction', 'compound screening'],
        'index_columns': ['ligand', 'target', 'affinity']
    }

    test_tools = [
        {
            'tool_id': 'tool1',
            'name': 'ChemBL Search',
            'category': 'Computational chemistry',
            'rawText': 'Search chemical database for compounds and targets'
        },
        {
            'tool_id': 'tool2',
            'name': 'BLAST',
            'category': 'Sequence Analysis',
            'rawText': 'Basic Local Alignment Search Tool for sequences'
        }
    ]

    print("Testing batch matcher...")
    results = matcher.analyze_batch(test_dataset, test_tools)
    print(f"\nFound {len(results)} compatible tools:")
    for r in results:
        print(f"  - {r['name']} (confidence: {r['confidence']})")
