#!/usr/bin/env python3
"""
Knowledge-based tool-dataset compatibility matcher.
Uses existing tool metadata (parameters, descriptions) for matching.
LLM orchestrates the matching process and decides when web search is needed.
"""
import json
import re
import time
from typing import Dict, Any, List, Optional
import anthropic
import os

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)


class ToolParameterExtractor:
    """Extract parameter information from tool metadata"""

    @staticmethod
    def extract_parameters_from_rawtext(rawtext: str) -> List[Dict[str, str]]:
        """
        Extract parameter information from tool rawText field.
        Returns list of {name, type, description}
        """
        parameters = []

        # Common parameter patterns in Galaxy tool descriptions
        # Pattern 1: "Parameter Name: description"
        param_pattern = r'([A-Z][a-zA-Z\s]+):\s*([^\n]+)'
        matches = re.findall(param_pattern, rawtext)

        for name, description in matches:
            name = name.strip()
            description = description.strip()

            # Identify database/reference parameters
            is_database_param = any(kw in name.lower() or kw in description.lower()
                                   for kw in ['database', 'reference', 'library', 'index',
                                             'genome', 'annotation', 'background'])

            if is_database_param:
                parameters.append({
                    'name': name,
                    'description': description,
                    'is_database_param': True
                })

        return parameters

    @staticmethod
    def extract_file_format_requirements(rawtext: str) -> List[str]:
        """Extract supported file formats from tool description"""
        formats = []

        # Look for format mentions
        format_keywords = ['csv', 'tsv', 'tabular', 'txt', 'parquet', 'sqlite',
                          'fasta', 'fastq', 'bam', 'sam', 'vcf', 'gff']

        text_lower = rawtext.lower()
        for fmt in format_keywords:
            if fmt in text_lower:
                formats.append(fmt)

        return list(set(formats))


class KnowledgeBasedMatcher:
    """Match datasets to tools using existing knowledge + LLM orchestration"""

    def __init__(self):
        self.param_extractor = ToolParameterExtractor()

    def analyze_compatibility(self, dataset: Dict[str, Any], tool: Dict[str, Any]) -> Dict[str, Any]:
        """
        Use LLM to orchestrate the matching process:
        1. Analyze tool parameters from rawText
        2. Match with dataset characteristics
        3. Decide if web search is needed for confirmation
        4. Return compatibility assessment
        """

        # Extract tool parameters
        tool_params = self.param_extractor.extract_parameters_from_rawtext(tool.get('rawText', ''))
        tool_formats = self.param_extractor.extract_file_format_requirements(tool.get('rawText', ''))

        # Build analysis prompt with cached system instructions
        system_prompt = """You are a Galaxy bioinformatics tool compatibility expert.

Your task: Determine if a Galaxy tool can accept a dataset as a reference/database parameter.

AVAILABLE INFORMATION:
- Tool metadata: name, category, description, extracted parameters
- Dataset metadata: name, format, category, use cases, columns

ANALYSIS WORKFLOW:
1. Parameter Analysis
   - Review extracted parameters from tool description
   - Identify database/reference parameters
   - Check parameter types and descriptions

2. Category & Domain Matching
   - Does tool category align with dataset domain?
   - Do use cases match tool purpose?

3. Format Compatibility
   - Can tool accept dataset format?
   - Check extracted format requirements

4. Confidence Assessment
   - High (0.8-1.0): Clear parameter match + format compatible + domain aligned
   - Medium (0.5-0.8): Likely compatible but some uncertainty
   - Low (0.0-0.5): Incompatible or insufficient evidence

5. Web Search Decision
   - If high confidence: No web search needed
   - If medium confidence with unclear parameters: Suggest web search
   - If low confidence: Mark incompatible, no web search

IMPORTANT:
- Base analysis on PROVIDED tool metadata first
- Only suggest web search if genuinely uncertain about parameters
- Be conservative but not overly strict"""

        # Prepare tool and dataset info
        user_prompt = f"""Analyze compatibility between this dataset and tool using available metadata.

DATASET:
- Name: {dataset['name']}
- Format: {dataset.get('format', 'unknown')}
- Category: {dataset.get('category', 'unknown')}
- Use Cases: {', '.join(dataset.get('use_cases', [])[:5])}
- Columns: {', '.join(dataset.get('index_columns', [])[:10])}

TOOL:
- Name: {tool['name']}
- Category: {tool['category']}
- Description: {tool.get('rawText', '')[:800]}

EXTRACTED TOOL PARAMETERS (database/reference):
{json.dumps(tool_params, indent=2) if tool_params else 'No database parameters clearly identified'}

DETECTED FORMAT SUPPORT:
{', '.join(tool_formats) if tool_formats else 'Format requirements unclear'}

Based on this information:
1. Can this tool accept the dataset as a parameter?
2. What's your confidence level?
3. What parameter name would it use (if compatible)?
4. Do you need web search to confirm?

Respond in JSON:
{{
  "compatible": true/false,
  "confidence": 0.0-1.0,
  "reasoning": "Detailed analysis based on extracted parameters and metadata",
  "parameter_name": "likely parameter name" or null,
  "parameter_evidence": "which tool parameter description suggests this" or null,
  "needs_web_search": true/false,
  "web_search_reason": "why web search would help" or null
}}"""

        # Retry with exponential backoff for rate limits
        max_retries = 5
        base_delay = 2

        for attempt in range(max_retries):
            try:
                # Use Claude with prompt caching
                response = client.messages.create(
                    model="claude-sonnet-4-5",
                    max_tokens=512,  # Reduced from 1024 - responses are short JSON
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

                response_text = response.content[0].text
                break  # Success, exit retry loop

            except Exception as api_error:
                if "rate_limit" in str(api_error) and attempt < max_retries - 1:
                    # Exponential backoff: 2s, 4s, 8s, 16s, 32s
                    wait_time = base_delay * (2 ** attempt)
                    print(f"Rate limit hit, retrying in {wait_time}s... (attempt {attempt + 1}/{max_retries})")
                    time.sleep(wait_time)
                    continue
                else:
                    # Not a rate limit or final attempt - raise the error
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

            result = json.loads(response_text)

            # Add metadata about the analysis
            result['tool_params_found'] = len(tool_params)
            result['formats_detected'] = tool_formats

            return result

        except json.JSONDecodeError as e:
            print(f"JSON parse error: {e}")
            print(f"Response: {response_text[:300]}")
            return {
                'compatible': False,
                'confidence': 0.0,
                'reasoning': f'Analysis failed: JSON parse error',
                'parameter_name': None,
                'needs_web_search': False
            }
        except Exception as e:
            print(f"Analysis error: {e}")
            return {
                'compatible': False,
                'confidence': 0.0,
                'reasoning': f'Analysis failed: {str(e)}',
                'parameter_name': None,
                'needs_web_search': False
            }

    def web_search_confirmation(self, dataset: Dict[str, Any], tool: Dict[str, Any],
                               preliminary_result: Dict[str, Any]) -> Dict[str, Any]:
        """
        Use web search to confirm compatibility when LLM requests it.
        This is auxiliary - only called when needs_web_search=True
        """
        # TODO: Implement web search using WebFetch tool if needed
        # For now, just return preliminary result with note
        preliminary_result['web_search_performed'] = False
        preliminary_result['web_search_note'] = 'Web search not yet implemented'
        return preliminary_result


# Test function
if __name__ == '__main__':
    matcher = KnowledgeBasedMatcher()

    # Test with a sample
    test_dataset = {
        'name': 'BindingDB_All_202409.tsv',
        'format': 'tsv',
        'category': 'drug_discovery',
        'use_cases': ['drug target prediction', 'compound screening', 'affinity analysis'],
        'index_columns': ['ligand', 'target', 'affinity', 'IC50', 'Ki']
    }

    test_tool = {
        'name': 'Spectrophores search',
        'category': 'Computational chemistry',
        'rawText': '''Spectrophores search
Tool for searching molecular databases using spectrophore descriptors.

Reference database: Database of molecules to search against (tabular format with SMILES)
Query molecule: Input molecule in SMILES or SDF format
Similarity threshold: Minimum similarity score (0.0-1.0)
Output format: Format for results (CSV, TSV, or tabular)

This tool searches a reference database of molecules and returns similar compounds based on spectrophore descriptors.'''
    }

    print("Testing knowledge-based matcher...")
    print("="*70)
    result = matcher.analyze_compatibility(test_dataset, test_tool)
    print(json.dumps(result, indent=2))
