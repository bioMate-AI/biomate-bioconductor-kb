#!/usr/bin/env python3
"""
Biological Logic Detector - LLM-Based Subworkflow Detection

Uses LLM to identify biological logic groups in workflows by understanding:
1. Tool purpose and biological function
2. Data flow and dependencies
3. Common bioinformatics patterns
4. nf-core subworkflow structure

Author: BioMate Team
Date: 2025-11-24
"""

import json
from typing import Dict, List, Optional
from dataclasses import dataclass
import os


@dataclass
class BiologicalGroup:
    """Represents a detected biological logic group."""
    group_id: str
    name: str  # e.g., "FASTQ_ALIGN_DNA", "BAM_SORT_STATS"
    description: str
    steps: List[str]  # Step IDs
    biological_purpose: str
    inputs: List[str]
    outputs: List[str]


class BiologicalLogicDetector:
    """
    Uses LLM to detect biological logic groups in Galaxy workflows.

    Strategy:
    1. Extract workflow structure and tool information
    2. Build prompt with nf-core subworkflow examples
    3. Ask LLM to identify 5-10 logical groups
    4. Parse LLM response into structured groups
    """

    def __init__(self, gemini_api_key: Optional[str] = None):
        """Initialize detector with LLM client."""
        self.gemini_api_key = gemini_api_key or os.getenv('GEMINI_API_KEY')

        if not self.gemini_api_key:
            raise ValueError("GEMINI_API_KEY required")

        import google.generativeai as genai
        genai.configure(api_key=self.gemini_api_key)
        self.model = genai.GenerativeModel('gemini-2.0-flash-exp')

    def detect_biological_groups(self, galaxy_wf: Dict) -> List[BiologicalGroup]:
        """
        Detect biological logic groups using LLM.

        Args:
            galaxy_wf: Galaxy workflow definition

        Returns:
            List of detected biological groups (5-10 groups expected)
        """

        # Build analysis prompt
        prompt = self._build_detection_prompt(galaxy_wf)

        # Query LLM
        response = self.model.generate_content(prompt)

        # Parse response
        groups = self._parse_llm_response(response.text, galaxy_wf)

        return groups

    def _build_detection_prompt(self, galaxy_wf: Dict) -> str:
        """
        Build prompt for LLM with nf-core subworkflow context.

        The prompt includes:
        1. Explanation of biological logic grouping
        2. Examples from nf-core
        3. Workflow structure to analyze
        4. Request for 5-10 logical groups
        """

        steps = galaxy_wf.get('steps', {})
        workflow_name = galaxy_wf.get('name', 'UNNAMED')
        annotation = galaxy_wf.get('annotation', '')

        # Extract tool steps with connections
        tool_info = []
        for step_id, step in steps.items():
            if step.get('type') != 'tool':
                continue

            tool_id = step.get('tool_id', '')
            tool_name = step.get('name', tool_id)
            connections = step.get('input_connections', {})

            # Get input sources
            inputs_from = []
            for input_name, conn in connections.items():
                if isinstance(conn, dict):
                    source_id = str(conn.get('id'))
                    if source_id in steps:
                        source_name = steps[source_id].get('name', source_id)
                        inputs_from.append(f"{source_name} (step {source_id})")

            tool_info.append({
                'step_id': step_id,
                'tool': tool_name,
                'inputs_from': inputs_from
            })

        prompt = f"""You are an expert bioinformatician analyzing workflow structure.

TASK: Identify 5-10 biological logic groups in this Galaxy workflow.

BACKGROUND - nf-core Subworkflow Patterns:
nf-core organizes workflows into reusable subworkflows, each representing a cohesive biological step. Examples:

1. FASTQ_ALIGN_DNA:
   - Purpose: Align sequencing reads to reference
   - Tools: BWA/Bowtie2 (index + align) → SAMtools (sort)
   - Input: FASTQ reads, reference genome
   - Output: Sorted BAM

2. BAM_SORT_STATS:
   - Purpose: Sort alignment and generate statistics
   - Tools: SAMtools sort → SAMtools index → SAMtools stats
   - Input: Unsorted BAM
   - Output: Sorted BAM, index, statistics

3. FASTQ_FASTQC_UMITOOLS_FASTP:
   - Purpose: QC and read processing
   - Tools: FastQC → UMI-tools → fastp
   - Input: Raw FASTQ
   - Output: Processed FASTQ, QC reports

4. BAM_MARKDUPLICATES_PICARD:
   - Purpose: Mark PCR/optical duplicates
   - Tools: Picard MarkDuplicates → SAMtools index
   - Input: Sorted BAM
   - Output: Deduplicated BAM, metrics

WORKFLOW TO ANALYZE:
Name: {workflow_name}
Description: {annotation}
Total steps: {len(tool_info)}

TOOLS AND DEPENDENCIES:
{json.dumps(tool_info, indent=2)}

REQUIREMENTS:
1. Identify 5-10 logical groups (not 20+, not 1-2)
2. Each group should represent ONE biological purpose
3. Groups should follow natural data flow
4. Similar to nf-core subworkflow structure
5. Tools in a group should work together cohesively

OUTPUT FORMAT (JSON):
{{
  "groups": [
    {{
      "name": "FASTQ_ALIGN_DNA",
      "description": "Align sequencing reads to reference genome",
      "biological_purpose": "Sequence alignment",
      "steps": ["5", "6", "7"],
      "inputs": ["FASTQ reads", "Reference genome"],
      "outputs": ["Aligned BAM"]
    }},
    ...
  ]
}}

Analyze the workflow and provide 5-10 logical groups in JSON format."""

        return prompt

    def _parse_llm_response(self, response_text: str, galaxy_wf: Dict) -> List[BiologicalGroup]:
        """
        Parse LLM response into structured groups.

        Args:
            response_text: LLM response (expected JSON)
            galaxy_wf: Original workflow (for validation)

        Returns:
            List of BiologicalGroup objects
        """

        groups = []

        try:
            # Extract JSON from response (may have markdown code blocks)
            json_text = response_text
            if '```json' in response_text:
                json_text = response_text.split('```json')[1].split('```')[0]
            elif '```' in response_text:
                json_text = response_text.split('```')[1].split('```')[0]

            data = json.loads(json_text.strip())

            for i, group_data in enumerate(data.get('groups', [])):
                group = BiologicalGroup(
                    group_id=f"subworkflow_{i}",
                    name=group_data.get('name', f'GROUP_{i}'),
                    description=group_data.get('description', ''),
                    steps=group_data.get('steps', []),
                    biological_purpose=group_data.get('biological_purpose', ''),
                    inputs=group_data.get('inputs', []),
                    outputs=group_data.get('outputs', [])
                )
                groups.append(group)

        except Exception as e:
            print(f"Warning: Failed to parse LLM response as JSON: {e}")
            print(f"Response text: {response_text[:500]}")

        return groups


# ==============================================================================
# CLI for testing
# ==============================================================================

def main():
    """Test the biological logic detector."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: python biological_logic_detector.py <workflow.ga>")
        sys.exit(1)

    workflow_path = sys.argv[1]

    # Check for API key
    api_key = os.getenv('GEMINI_API_KEY')
    if not api_key:
        print("Error: GEMINI_API_KEY environment variable required")
        sys.exit(1)

    # Load workflow
    with open(workflow_path) as f:
        workflow = json.load(f)

    # Detect groups
    print(f"\n{'='*80}")
    print(f"Analyzing workflow: {workflow.get('name', 'UNNAMED')}")
    print(f"{'='*80}\n")

    detector = BiologicalLogicDetector(api_key)
    groups = detector.detect_biological_groups(workflow)

    print(f"Detected {len(groups)} biological logic groups:\n")

    for i, group in enumerate(groups, 1):
        print(f"{i}. {group.name}")
        print(f"   Purpose: {group.biological_purpose}")
        print(f"   Description: {group.description}")
        print(f"   Steps: {', '.join(group.steps)} ({len(group.steps)} steps)")
        print(f"   Inputs: {', '.join(group.inputs)}")
        print(f"   Outputs: {', '.join(group.outputs)}")
        print()


if __name__ == '__main__':
    main()
