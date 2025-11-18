#!/usr/bin/env python3
"""
Unified Metadata Extractor - Extract ALL missing metadata using Claude API

Extracts from existing usage_guide and examples fields:
1. Parameters (35% of quality score)
2. Resource requirements - CPU/GPU/memory (20% of score)
3. Enhanced I/O specifications (15% of score)
4. Scientific use cases (5% of score)

Single Claude API call per tool for efficiency.

Usage:
    # Extract metadata for one tool
    python unified_metadata_extractor.py --tool-id auto_foldseek

    # Process all tools with low quality scores
    python unified_metadata_extractor.py --all-low-quality

    # Update database with extracted metadata
    python unified_metadata_extractor.py --tool-id auto_foldseek --update-db

    # Batch process and update
    python unified_metadata_extractor.py --all-low-quality --update-db
"""

import argparse
import json
import logging
import os
import re
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import anthropic

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


class UnifiedMetadataExtractor:
    """
    Extracts comprehensive structured metadata from existing text fields.
    """

    def __init__(self, db_path: Path, anthropic_api_key: str = None):
        self.db_path = db_path
        self.conn = None
        self.anthropic_api_key = anthropic_api_key or os.getenv('ANTHROPIC_API_KEY')

        if not self.anthropic_api_key:
            raise ValueError("Anthropic API key required. Set ANTHROPIC_API_KEY env var or pass --anthropic-api-key")

        self.client = anthropic.Anthropic(api_key=self.anthropic_api_key)

    def connect(self):
        """Connect to database"""
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row

    def disconnect(self):
        """Disconnect from database"""
        if self.conn:
            self.conn.close()

    def get_tool(self, tool_id: str) -> Optional[Dict]:
        """Get tool metadata"""
        cursor = self.conn.execute(
            "SELECT * FROM tools WHERE tool_id = ?",
            (tool_id,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None

    def extract_all_metadata(self, tool: Dict) -> Dict:
        """
        Extract all metadata categories in a single Claude API call.

        Returns:
            Extraction result with all enhanced metadata
        """
        result = {
            'tool_id': tool['tool_id'],
            'tool_name': tool['name'],
            'extracted_at': datetime.now().isoformat(),
            'success': False,
            'error': None,
            'extracted_metadata': {}
        }

        # Prepare source data
        usage_guide = tool.get('usage_guide', '') or ''
        examples_str = tool.get('examples', '[]')
        try:
            examples = json.loads(examples_str) if examples_str else []
            examples_text = '\n\n'.join(examples) if isinstance(examples, list) else str(examples)
        except:
            examples_text = str(examples_str)

        description = tool.get('description', '') or ''

        # Build extraction prompt
        prompt = self._build_extraction_prompt(
            tool_name=tool['name'],
            description=description,
            usage_guide=usage_guide,
            examples=examples_text
        )

        try:
            logger.info(f"Extracting metadata for {tool['tool_id']} using Claude API...")

            response = self.client.messages.create(
                model="claude-sonnet-4-5-20250929",  # Use Sonnet 4.5 for better accuracy
                max_tokens=8192,
                temperature=0,  # Deterministic output
                messages=[
                    {"role": "user", "content": prompt}
                ]
            )

            response_text = response.content[0].text.strip()

            # Remove markdown code blocks if present
            if '```json' in response_text:
                response_text = re.search(r'```json\s*\n(.*?)\n```', response_text, re.DOTALL)
                if response_text:
                    response_text = response_text.group(1)
            elif '```' in response_text:
                response_text = re.sub(r'^```\s*', '', response_text)
                response_text = re.sub(r'\s*```$', '', response_text)

            # Parse JSON
            extracted = json.loads(response_text)

            result['extracted_metadata'] = extracted
            result['success'] = True

            # Log summary
            param_count = len(extracted.get('parameters', []))
            has_reqs = bool(extracted.get('compute_requirements', {}).get('cpu') or
                          extracted.get('compute_requirements', {}).get('gpu'))
            input_count = len(extracted.get('inputs', []))
            output_count = len(extracted.get('outputs', []))

            logger.info(f"✅ Extracted for {tool['tool_id']}:")
            logger.info(f"   - Parameters: {param_count}")
            logger.info(f"   - CPU/GPU Requirements: {'Yes' if has_reqs else 'No'}")
            logger.info(f"   - Inputs: {input_count}, Outputs: {output_count}")

        except json.JSONDecodeError as e:
            result['error'] = f"Failed to parse JSON: {e}"
            result['raw_response'] = response_text[:500]
            logger.error(f"❌ JSON parse error for {tool['tool_id']}: {e}")
            logger.error(f"   Response preview: {response_text[:200]}...")

        except Exception as e:
            result['error'] = str(e)
            logger.error(f"❌ Extraction failed for {tool['tool_id']}: {e}")

        return result

    def _build_extraction_prompt(self, tool_name: str, description: str,
                                 usage_guide: str, examples: str) -> str:
        """Build comprehensive extraction prompt."""

        # Truncate if needed (keep most important parts)
        usage_guide_excerpt = usage_guide[:4000] if len(usage_guide) > 4000 else usage_guide
        examples_excerpt = examples[:2000] if len(examples) > 2000 else examples

        prompt = f"""Extract structured metadata from this bioinformatics tool documentation.

**Tool Name**: {tool_name}
**Description**: {description}

**Usage Guide**:
{usage_guide_excerpt}

**Example Commands**:
{examples_excerpt}

---

Extract and return a JSON object with these fields:

1. **parameters** (array): Command-line parameters
   For each parameter:
   - name: parameter name (alphanumeric_underscores, e.g., "threads", "gpu", "sensitivity")
   - flag: command-line flag (e.g., "--threads", "--gpu", "-s")
   - type: one of: "boolean", "integer", "float", "string", "select", "data"
   - label: human-readable label (e.g., "Number of Threads")
   - help: description of what the parameter does
   - default: default value if mentioned (omit if not specified)
   - required: true if required, false if optional
   - min: minimum value for numeric types (if specified)
   - max: maximum value for numeric types (if specified)
   - options: array of valid values for select type (if specified)

2. **compute_requirements** (object):
   - cpu (object or null):
     - instruction_sets: array of required CPU features (e.g., ["AVX2", "SSE4.1"])
     - architectures: array of supported architectures (e.g., ["x86_64", "ARM64"])
     - minimum_cores: minimum cores if specified
     - recommended_cores: recommended cores if specified
   - gpu (object or null):
     - optional: true if GPU is optional, false if required
     - provider: e.g., "NVIDIA", "AMD"
     - generations: array of supported GPU generations (e.g., ["Ampere", "Turing"])
     - driver_minimum: minimum driver version if specified
     - cuda_version: CUDA version if specified
     - performance_notes: any performance comparisons mentioned (e.g., "4x faster than CPU")
   - memory (object or null):
     - minimum_gb: minimum RAM in GB
     - recommended_gb: recommended RAM in GB
     - notes: any memory scaling notes
   - system (object or null):
     - glibc_minimum: minimum glibc version if specified
     - other_requirements: array of other system requirements

3. **inputs** (array): Enhanced input specifications
   For each input:
   - name: input name (e.g., "query_structure", "target_database")
   - formats: array of file formats (e.g., ["pdb", "cif", "mmcif"])
   - description: what this input is
   - required: true if required
   - multiple: true if multiple files allowed

4. **outputs** (array): Enhanced output specifications
   For each output:
   - name: output name (e.g., "alignments", "clusters")
   - format: file format (e.g., "m8", "tsv", "pdb")
   - description: what this output contains
   - optional: true if optional output

5. **use_cases** (array): Scientific use cases
   For each use case:
   - name: brief name (e.g., "Protein Evolution Analysis")
   - description: what it's used for
   - typical_scale: typical data size (e.g., "100-10000 proteins")

**Important Guidelines**:
- Extract ONLY information that is explicitly stated or strongly implied
- For parameters: look for --flag patterns in examples and their descriptions in the guide
- For requirements: look for CPU features (AVX2, SSE), GPU info (NVIDIA, Ampere), memory sizes (GB, RAM)
- For inputs/outputs: infer from examples and descriptions
- Use null for sections where no information is available
- Ensure all JSON is valid and properly formatted
- Be conservative - if unsure, omit rather than guess

Return ONLY the JSON object, no additional text or markdown formatting.
"""

        return prompt

    def update_database(self, tool_id: str, extracted_metadata: Dict) -> bool:
        """Update database with extracted metadata."""
        try:
            updates = []

            # Update parameters if extracted
            if extracted_metadata.get('parameters'):
                parameters_json = json.dumps(extracted_metadata['parameters'])
                updates.append(('parameters', parameters_json))

            # Update or merge requirements
            if extracted_metadata.get('compute_requirements'):
                # Get existing requirements
                tool = self.get_tool(tool_id)
                existing_reqs_str = tool.get('requirements', '[]')
                try:
                    existing_reqs = json.loads(existing_reqs_str) if existing_reqs_str else []
                except:
                    existing_reqs = []

                # Add compute_requirements as new entries
                compute_reqs = extracted_metadata['compute_requirements']

                # Add CPU requirements
                if compute_reqs.get('cpu'):
                    cpu_req = {
                        'type': 'cpu_requirements',
                        'data': compute_reqs['cpu']
                    }
                    existing_reqs.append(cpu_req)

                # Add GPU requirements
                if compute_reqs.get('gpu'):
                    gpu_req = {
                        'type': 'gpu_requirements',
                        'data': compute_reqs['gpu']
                    }
                    existing_reqs.append(gpu_req)

                # Add memory requirements
                if compute_reqs.get('memory'):
                    mem_req = {
                        'type': 'memory_requirements',
                        'data': compute_reqs['memory']
                    }
                    existing_reqs.append(mem_req)

                # Add system requirements
                if compute_reqs.get('system'):
                    sys_req = {
                        'type': 'system_requirements',
                        'data': compute_reqs['system']
                    }
                    existing_reqs.append(sys_req)

                requirements_json = json.dumps(existing_reqs)
                updates.append(('requirements', requirements_json))

            # Update inputs if extracted
            if extracted_metadata.get('inputs'):
                inputs_json = json.dumps(extracted_metadata['inputs'])
                updates.append(('inputs', inputs_json))

            # Update outputs if extracted
            if extracted_metadata.get('outputs'):
                outputs_json = json.dumps(extracted_metadata['outputs'])
                updates.append(('outputs', outputs_json))

            # Update scientific_context if use_cases extracted
            if extracted_metadata.get('use_cases'):
                tool = self.get_tool(tool_id)
                sci_context_str = tool.get('scientific_context', '{}')
                try:
                    sci_context = json.loads(sci_context_str) if sci_context_str else {}
                except:
                    sci_context = {}

                sci_context['use_cases'] = extracted_metadata['use_cases']
                sci_context_json = json.dumps(sci_context)
                updates.append(('scientific_context', sci_context_json))

            # Perform updates
            if updates:
                set_clause = ', '.join(f"{field} = ?" for field, _ in updates)
                values = [value for _, value in updates]
                values.append(datetime.now().isoformat())
                values.append(tool_id)

                query = f"""
                    UPDATE tools
                    SET {set_clause}, updated_at = ?
                    WHERE tool_id = ?
                """

                self.conn.execute(query, values)
                self.conn.commit()

                logger.info(f"✅ Updated database for {tool_id}: {len(updates)} fields")
                return True
            else:
                logger.warning(f"⚠️  No updates for {tool_id} (no metadata extracted)")
                return False

        except Exception as e:
            logger.error(f"❌ Database update failed for {tool_id}: {e}")
            return False


def main():
    parser = argparse.ArgumentParser(
        description='Extract comprehensive metadata using Claude API'
    )

    parser.add_argument(
        '--tool-id',
        help='Specific tool ID to process'
    )

    parser.add_argument(
        '--all-low-quality',
        action='store_true',
        help='Process all auto-discovered tools with quality score < 0.85'
    )

    parser.add_argument(
        '--all-auto-discovered',
        action='store_true',
        help='Process all auto-discovered tools'
    )

    parser.add_argument(
        '--db-path',
        type=Path,
        default=Path('/home/yzhang/biomate/backend/database/galaxy_ai_tools.db'),
        help='Path to database'
    )

    parser.add_argument(
        '--anthropic-api-key',
        default=os.getenv('ANTHROPIC_API_KEY'),
        help='Anthropic API key'
    )

    parser.add_argument(
        '--update-db',
        action='store_true',
        help='Update database with extracted metadata'
    )

    parser.add_argument(
        '--output',
        type=Path,
        help='Save extraction results to JSON file'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Extract but do not update database'
    )

    args = parser.parse_args()

    # Check for API key
    if not args.anthropic_api_key:
        logger.error("❌ Anthropic API key required. Set ANTHROPIC_API_KEY env var or use --anthropic-api-key")
        return 1

    extractor = UnifiedMetadataExtractor(args.db_path, args.anthropic_api_key)
    extractor.connect()

    try:
        results = []
        tools_to_process = []

        if args.tool_id:
            # Process single tool
            tool = extractor.get_tool(args.tool_id)
            if not tool:
                logger.error(f"❌ Tool not found: {args.tool_id}")
                return 1
            tools_to_process = [tool]

        elif args.all_low_quality:
            # Process tools with low quality scores
            cursor = extractor.conn.execute("""
                SELECT * FROM tools
                WHERE auto_discovered = 1
                AND (quality_score IS NULL OR quality_score < 0.85)
            """)
            tools_to_process = [dict(row) for row in cursor.fetchall()]
            logger.info(f"Found {len(tools_to_process)} tools with quality score < 0.85")

        elif args.all_auto_discovered:
            # Process all auto-discovered tools
            cursor = extractor.conn.execute("""
                SELECT * FROM tools
                WHERE auto_discovered = 1
            """)
            tools_to_process = [dict(row) for row in cursor.fetchall()]
            logger.info(f"Found {len(tools_to_process)} auto-discovered tools")

        else:
            parser.print_help()
            return 1

        # Process tools
        print("="*80)
        print(f"PROCESSING {len(tools_to_process)} TOOLS")
        print("="*80)

        for i, tool in enumerate(tools_to_process, 1):
            print(f"\n[{i}/{len(tools_to_process)}] {tool['tool_id']} ({tool['name']})")
            print("-"*80)

            result = extractor.extract_all_metadata(tool)
            results.append(result)

            if result['success']:
                metadata = result['extracted_metadata']

                print(f"✅ Extraction successful:")
                print(f"   Parameters: {len(metadata.get('parameters', []))}")

                comp_reqs = metadata.get('compute_requirements', {})
                print(f"   CPU requirements: {'Yes' if comp_reqs.get('cpu') else 'No'}")
                print(f"   GPU requirements: {'Yes' if comp_reqs.get('gpu') else 'No'}")
                print(f"   Memory requirements: {'Yes' if comp_reqs.get('memory') else 'No'}")

                print(f"   Enhanced inputs: {len(metadata.get('inputs', []))}")
                print(f"   Enhanced outputs: {len(metadata.get('outputs', []))}")
                print(f"   Use cases: {len(metadata.get('use_cases', []))}")

                # Update database if requested
                if args.update_db and not args.dry_run:
                    success = extractor.update_database(tool['tool_id'], metadata)
                    if success:
                        print(f"   ✅ Database updated")
                elif args.dry_run:
                    print(f"   ⚠️  Dry run - database not updated")

            else:
                print(f"❌ Extraction failed: {result.get('error', 'Unknown error')}")

        # Summary
        print("\n" + "="*80)
        print("SUMMARY")
        print("="*80)

        successful = [r for r in results if r['success']]
        failed = [r for r in results if not r['success']]

        print(f"Total tools processed: {len(results)}")
        print(f"✅ Successful: {len(successful)} ({len(successful)*100//len(results) if results else 0}%)")
        print(f"❌ Failed: {len(failed)}")

        if successful:
            total_params = sum(len(r['extracted_metadata'].get('parameters', [])) for r in successful)
            tools_with_cpu = sum(1 for r in successful if r['extracted_metadata'].get('compute_requirements', {}).get('cpu'))
            tools_with_gpu = sum(1 for r in successful if r['extracted_metadata'].get('compute_requirements', {}).get('gpu'))

            print(f"\n📊 Extraction Statistics:")
            print(f"   Total parameters: {total_params}")
            print(f"   Average per tool: {total_params / len(successful):.1f}")
            print(f"   Tools with CPU requirements: {tools_with_cpu}")
            print(f"   Tools with GPU requirements: {tools_with_gpu}")

        if args.update_db and not args.dry_run:
            print(f"\n✅ Database updated for {len(successful)} tools")
        elif args.dry_run:
            print(f"\n⚠️  Dry run mode - no database changes made")

        # Save results if requested
        if args.output:
            output_data = {
                'extracted_at': datetime.now().isoformat(),
                'total_tools': len(results),
                'successful': len(successful),
                'failed': len(failed),
                'results': results
            }
            with open(args.output, 'w') as f:
                json.dump(output_data, f, indent=2)
            print(f"\n✅ Results saved to: {args.output}")

        return 0 if len(failed) == 0 else 1

    finally:
        extractor.disconnect()


if __name__ == '__main__':
    exit(main())
