#!/usr/bin/env python3
"""
LLM-powered deep extraction from nf-core workflows, subworkflows, and documentation.

This script uses Claude to analyze:
- Workflow README.md files
- Usage documentation
- Output documentation
- Parameter schemas
- Web documentation (nf-co.re)

Extracts:
- Detailed use cases with scientific scenarios
- Step-by-step workflow explanations
- Parameter recommendations with reasoning
- Data type and format requirements
- Common issues and troubleshooting
- Best practices from the community
- Performance and resource requirements
"""

import os
import json
import anthropic
from pathlib import Path
from typing import Dict, List, Optional
import time


WORKFLOW_EXTRACTION_PROMPT = """You are an expert bioinformatics workflow analyst. Analyze this nf-core workflow documentation and extract comprehensive knowledge.

Workflow: {workflow_name}

Documentation:
{documentation}

Extract detailed information in JSON format:

{{
  "workflow_overview": {{
    "name": "workflow name",
    "purpose": "what this workflow accomplishes",
    "scientific_domains": ["domain1", "domain2"],
    "typical_users": ["researcher type"],
    "key_features": ["unique capability 1", "unique capability 2"]
  }},
  "use_cases": [
    {{
      "scenario": "specific biological question or experiment type",
      "input_data": "what kind of data is needed",
      "expected_output": "what results you get",
      "when_to_use": "conditions where this workflow is appropriate",
      "example_study": "real-world example if mentioned"
    }}
  ],
  "workflow_steps": [
    {{
      "step_number": 1,
      "tool_name": "tool used",
      "purpose": "what this step does",
      "input": "what it takes",
      "output": "what it produces",
      "critical_parameters": ["param1", "param2"],
      "why_needed": "biological or technical reason"
    }}
  ],
  "data_requirements": {{
    "input_formats": ["format1", "format2"],
    "input_quality": "quality requirements",
    "minimum_samples": "how many samples needed",
    "recommended_depth": "sequencing depth or coverage",
    "file_organization": "how files should be organized"
  }},
  "parameter_guidance": {{
    "essential_parameters": [
      {{
        "name": "parameter name",
        "purpose": "what it controls",
        "recommended_value": "suggested setting",
        "when_to_adjust": "when to change from default",
        "impact": "what happens if changed"
      }}
    ],
    "performance_tuning": {{
      "compute_requirements": "CPU/memory needs",
      "runtime_estimates": "how long it takes",
      "cost_considerations": "cloud cost estimates if mentioned"
    }}
  }},
  "common_issues": [
    {{
      "problem": "issue users face",
      "cause": "why it happens",
      "solution": "how to fix it",
      "prevention": "how to avoid it"
    }}
  ],
  "best_practices": [
    "practice 1",
    "practice 2"
  ],
  "quality_control": {{
    "checkpoints": ["what to verify at each stage"],
    "quality_metrics": ["what metrics to monitor"],
    "red_flags": ["warning signs of problems"]
  }},
  "output_interpretation": {{
    "primary_outputs": [
      {{
        "file": "output file name/pattern",
        "content": "what's in it",
        "how_to_use": "next steps with this output"
      }}
    ],
    "quality_reports": "what QC reports are generated",
    "visualization": "what plots/graphs are created"
  }},
  "comparison_to_alternatives": {{
    "advantages": ["what this workflow does better"],
    "limitations": ["what it doesn't do well"],
    "when_to_use_alternatives": "scenarios where other tools are better"
  }},
  "citations": [
    {{
      "paper": "title",
      "doi": "DOI if available",
      "relevance": "why this citation matters"
    }}
  ],
  "community_notes": "any tips from the community or developers"
}}

CRITICAL INSTRUCTIONS:
1. Extract ONLY from provided documentation - no speculation
2. Be specific about biological/scientific context
3. Include actual parameter values when mentioned
4. Capture troubleshooting advice
5. Note performance characteristics if discussed
6. Empty arrays [] if no information found
7. Keep explanations clear and actionable
8. Focus on practical guidance for users

Return ONLY valid JSON, no additional text."""


SUBWORKFLOW_EXTRACTION_PROMPT = """You are an expert bioinformatics workflow analyst. Analyze this nf-core subworkflow documentation.

Subworkflow: {subworkflow_name}
Keywords: {keywords}
Components: {components}

Documentation:
{documentation}

Extract detailed information in JSON format:

{{
  "subworkflow_overview": {{
    "name": "subworkflow name",
    "purpose": "what this subworkflow accomplishes",
    "typical_position": "where in pipeline (start/middle/end)",
    "prerequisites": "what must happen before this"
  }},
  "component_tools": [
    {{
      "tool": "tool name",
      "role": "what it does in this subworkflow",
      "alternatives": ["alternative tools that could be used"],
      "why_chosen": "reason for using this specific tool"
    }}
  ],
  "data_flow": {{
    "input": "what comes in",
    "transformations": ["step 1", "step 2"],
    "output": "what comes out",
    "format_conversions": "any format changes"
  }},
  "use_patterns": [
    {{
      "scenario": "when this pattern is used",
      "upstream": "what typically comes before",
      "downstream": "what typically comes after",
      "variations": "common modifications"
    }}
  ],
  "parameter_interactions": [
    {{
      "parameter": "parameter name",
      "affects_which_tools": ["tool1", "tool2"],
      "interaction": "how tools interact based on this parameter"
    }}
  ],
  "quality_gates": {{
    "checks_performed": ["quality check 1", "quality check 2"],
    "failure_modes": ["what can go wrong"],
    "recovery_actions": ["how to handle failures"]
  }}
}}

Extract from documentation, be specific and practical.
Return ONLY valid JSON."""


def extract_workflow_knowledge(
    workflow_name: str,
    workflow_path: Path,
    api_key: str
) -> Optional[Dict]:
    """
    Extract comprehensive knowledge from a complete nf-core workflow.
    """
    print(f"\n{'='*80}")
    print(f"Analyzing workflow: {workflow_name}")
    print('='*80)

    # Gather all documentation
    docs = []

    # README - focus on intro and pipeline summary
    readme = workflow_path / "README.md"
    if readme.exists():
        with open(readme) as f:
            content = f.read()
            # Extract key sections only
            lines = content.split('\n')
            key_content = []
            capture = False
            for line in lines[:200]:  # First 200 lines
                if any(header in line for header in ['## Introduction', '## Quick Start', '## Pipeline Summary', '## Documentation']):
                    capture = True
                if capture and line.startswith('##') and 'Contributions' in line:
                    break
                if capture:
                    key_content.append(line)
            docs.append(f"=== README ===\n{chr(10).join(key_content[:25])}")
            print(f"  ✓ README.md ({len(content)} chars, using {len(key_content)} lines)")

    # Usage docs - main arguments only
    usage = workflow_path / "docs" / "usage.md"
    if usage.exists():
        with open(usage) as f:
            content = f.read()
            # Focus on main arguments and running the pipeline
            lines = content.split('\n')
            key_content = []
            capture = False
            for i, line in enumerate(lines[:100]):
                if '## Running the pipeline' in line or 'typical command' in line.lower():
                    capture = True
                    key_content.extend(lines[i:i+20])
                    break
            docs.append(f"=== USAGE ===\n{chr(10).join(key_content[:15])}")
            print(f"  ✓ usage.md ({len(content)} chars, extracted key sections)")

    # Output docs - summary only
    output = workflow_path / "docs" / "output.md"
    if output.exists():
        with open(output) as f:
            content = f.read()
            lines = content.split('\n')
            # Get pipeline overview and first few outputs
            docs.append(f"=== OUTPUT ===\n{chr(10).join(lines[:15])}")
            print(f"  ✓ output.md ({len(content)} chars, using first 15 lines)")

    # Parameters schema
    schema = workflow_path / "nextflow_schema.json"
    if schema.exists():
        try:
            with open(schema) as f:
                schema_data = json.load(f)
                # Extract parameter definitions
                if 'definitions' in schema_data:
                    param_summary = "=== PARAMETERS ===\n"
                    for def_name, def_data in list(schema_data['definitions'].items())[:3]:
                        if 'properties' in def_data:
                            param_summary += f"\n{def_name}:\n"
                            for param, spec in list(def_data['properties'].items())[:5]:
                                param_summary += f"  - {param}: {spec.get('description', '')[:100]}\n"
                    docs.append(param_summary[:1500])
                    print(f"  ✓ Parameters schema")
        except:
            pass

    if not docs:
        print("  ⚠️ No documentation found")
        return None

    combined_docs = "\n\n".join(docs)

    # Use Claude to extract with prompt caching
    try:
        print(f"  🤖 Analyzing with Claude Haiku 4.5 (with prompt caching)...")
        client = anthropic.Anthropic(api_key=api_key)

        # Split into cacheable system prompt and variable documentation
        system_prompt = WORKFLOW_EXTRACTION_PROMPT.split("{workflow_name}")[0].strip()

        message = client.messages.create(
            model="claude-haiku-4-5",
            max_tokens=8192,
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
                "content": f"Workflow: {workflow_name}\n\nDocumentation:\n{combined_docs}\n\n{WORKFLOW_EXTRACTION_PROMPT.split('{documentation}')[1]}"
            }]
        )

        response_text = message.content[0].text

        # Parse JSON
        if "```json" in response_text:
            response_text = response_text.split("```json")[1].split("```")[0]
        elif "```" in response_text:
            response_text = response_text.split("```")[1].split("```")[0]

        knowledge = json.loads(response_text.strip())
        print(f"  ✅ Extracted comprehensive knowledge")
        return knowledge

    except Exception as e:
        print(f"  ❌ Extraction failed: {str(e)[:100]}")
        return None


def extract_subworkflow_knowledge(
    subworkflow_name: str,
    subworkflow_meta: Dict,
    nf_core_subworkflows_path: Path,
    api_key: str
) -> Optional[Dict]:
    """
    Extract knowledge from subworkflow metadata and any additional documentation.
    """
    # Read main.nf for code context
    subworkflow_path = nf_core_subworkflows_path / subworkflow_name
    main_nf = subworkflow_path / "main.nf"

    docs = []
    docs.append(f"Keywords: {', '.join(subworkflow_meta.get('keywords', []))}")
    docs.append(f"Components: {', '.join(subworkflow_meta.get('components', []))}")
    docs.append(f"Description: {subworkflow_meta.get('description', '')}")

    if main_nf.exists():
        try:
            with open(main_nf) as f:
                code = f.read()[:4000]
                docs.append(f"=== CODE ===\n{code}")
        except:
            pass

    combined_docs = "\n\n".join(docs)

    try:
        client = anthropic.Anthropic(api_key=api_key)

        # Use prompt caching for the extraction template
        system_prompt = SUBWORKFLOW_EXTRACTION_PROMPT.split("{subworkflow_name}")[0].strip()

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
                "content": f"Subworkflow: {subworkflow_name}\nKeywords: {', '.join(subworkflow_meta.get('keywords', []))}\nComponents: {', '.join(subworkflow_meta.get('components', []))}\n\nDocumentation:\n{combined_docs}\n\n{SUBWORKFLOW_EXTRACTION_PROMPT.split('{documentation}')[1]}"
            }]
        )

        response_text = message.content[0].text

        if "```json" in response_text:
            response_text = response_text.split("```json")[1].split("```")[0]
        elif "```" in response_text:
            response_text = response_text.split("```")[1].split("```")[0]

        knowledge = json.loads(response_text.strip())
        return knowledge

    except Exception as e:
        return None


def main():
    """Main extraction function."""
    import argparse

    parser = argparse.ArgumentParser(description='LLM-powered nf-core workflow knowledge extraction')
    parser.add_argument('--workflows', help='Workflows directory',
                       default='/opt/biomate/backend/nf-core-workflows')
    parser.add_argument('--subworkflows', help='Subworkflows directory',
                       default='/opt/biomate/backend/nf-core-modules/subworkflows/nf-core')
    parser.add_argument('--output', help='Output JSON file',
                       default='/opt/biomate/backend/nfcore_workflow_knowledge.json')
    parser.add_argument('--limit-workflows', type=int, help='Limit workflows to process')
    parser.add_argument('--limit-subworkflows', type=int, help='Limit subworkflows to process')

    args = parser.parse_args()

    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        print("❌ Error: ANTHROPIC_API_KEY not set")
        return 1

    knowledge_base = {
        'workflows': {},
        'subworkflows': {},
        'extraction_date': time.strftime('%Y-%m-%d'),
        'statistics': {
            'workflows_processed': 0,
            'workflows_failed': 0,
            'subworkflows_processed': 0,
            'subworkflows_failed': 0
        }
    }

    print("=" * 80)
    print("LLM-Powered nf-core Workflow Knowledge Extraction")
    print("=" * 80)
    print()

    # Extract workflows
    workflows_path = Path(args.workflows)
    if workflows_path.exists():
        print("📊 Extracting Workflow Knowledge...")
        print()

        workflow_dirs = [d for d in workflows_path.iterdir() if d.is_dir() and not d.name.startswith('.')]
        if args.limit_workflows:
            workflow_dirs = workflow_dirs[:args.limit_workflows]

        for workflow_dir in workflow_dirs:
            knowledge = extract_workflow_knowledge(
                workflow_dir.name,
                workflow_dir,
                api_key
            )

            if knowledge:
                knowledge_base['workflows'][workflow_dir.name] = knowledge
                knowledge_base['statistics']['workflows_processed'] += 1
            else:
                knowledge_base['statistics']['workflows_failed'] += 1

            # Rate limiting
            time.sleep(2)

    # Extract subworkflows (selected important ones)
    subworkflows_path = Path(args.subworkflows)
    if subworkflows_path.exists():
        print()
        print("🔗 Extracting Subworkflow Knowledge...")
        print()

        # Read existing nfcore index to get subworkflow metadata
        index_file = Path('/opt/biomate/backend/nfcore_index.json')
        if index_file.exists():
            with open(index_file) as f:
                nfcore_index = json.load(f)

            subworkflows = list(nfcore_index.get('subworkflows', {}).items())
            if args.limit_subworkflows:
                subworkflows = subworkflows[:args.limit_subworkflows]

            for subworkflow_name, subworkflow_meta in subworkflows:
                print(f"  Analyzing: {subworkflow_name}")
                knowledge = extract_subworkflow_knowledge(
                    subworkflow_name,
                    subworkflow_meta,
                    subworkflows_path,
                    api_key
                )

                if knowledge:
                    knowledge_base['subworkflows'][subworkflow_name] = knowledge
                    knowledge_base['statistics']['subworkflows_processed'] += 1
                    print(f"    ✅ Extracted")
                else:
                    knowledge_base['statistics']['subworkflows_failed'] += 1
                    print(f"    ❌ Failed")

                time.sleep(1.5)

    # Save knowledge base
    output_file = Path(args.output)
    with open(output_file, 'w') as f:
        json.dump(knowledge_base, f, indent=2)

    print()
    print("=" * 80)
    print("✅ Knowledge Extraction Complete")
    print("=" * 80)
    print(f"   Workflows processed: {knowledge_base['statistics']['workflows_processed']}")
    print(f"   Workflows failed: {knowledge_base['statistics']['workflows_failed']}")
    print(f"   Subworkflows processed: {knowledge_base['statistics']['subworkflows_processed']}")
    print(f"   Subworkflows failed: {knowledge_base['statistics']['subworkflows_failed']}")
    print()
    print(f"💾 Knowledge base saved to: {output_file}")
    print()
    print("This knowledge base contains:")
    print("  • Detailed use cases with scientific scenarios")
    print("  • Step-by-step workflow explanations")
    print("  • Parameter recommendations with reasoning")
    print("  • Common issues and troubleshooting")
    print("  • Best practices from the community")
    print("  • Quality control checkpoints")
    print("  • Output interpretation guidance")

    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
