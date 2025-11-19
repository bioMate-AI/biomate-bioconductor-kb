#!/usr/bin/env python3
"""
Quality Enhancement Step - Post-processing for auto-discovered tools

Integrates into the pipeline to:
1. Validate tool quality after integration
2. Enhance metadata using Claude API if score < threshold
3. Mark tools as workflow-ready or add to enhancement queue

Usage:
    # As standalone post-processor
    python quality_enhancement_step.py --all-recent

    # For specific tools
    python quality_enhancement_step.py --tool-ids auto_foldseek auto_mmseqs2

    # With quality threshold
    python quality_enhancement_step.py --all-recent --min-score 0.85

Can be called from run_pipeline.py as a post-integration step.
"""

import argparse
import json
import logging
import os
import sqlite3
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

# Import our quality tools
sys.path.insert(0, str(Path(__file__).parent))

from tool_quality_validator import ToolQualityValidator
from unified_metadata_extractor import UnifiedMetadataExtractor
from cleanup_dummy_parameters import DummyParameterCleaner

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


class QualityEnhancementStep:
    """
    Post-integration quality enhancement for auto-discovered tools.
    """

    MIN_WORKFLOW_READY_SCORE = 0.85
    MIN_PREVIEW_MODE_SCORE = 0.60

    def __init__(
        self,
        db_path: Path,
        anthropic_api_key: str = None
    ):
        self.db_path = db_path
        self.anthropic_api_key = anthropic_api_key or os.getenv('ANTHROPIC_API_KEY')

        # Initialize components
        self.validator = ToolQualityValidator(db_path)
        self.cleaner = DummyParameterCleaner(db_path)

        if self.anthropic_api_key:
            self.extractor = UnifiedMetadataExtractor(db_path, self.anthropic_api_key)
        else:
            self.extractor = None
            logger.warning("No Anthropic API key - metadata enhancement disabled")

    def process_tool(self, tool_id: str, enhance: bool = True) -> Dict:
        """
        Process a single tool through quality enhancement.

        Steps:
        1. Clean up dummy parameters
        2. Validate current quality
        3. If score < threshold and enhance=True, run enhancement
        4. Re-validate
        5. Return quality status

        Returns:
            Dict with quality results and enhancement status
        """
        result = {
            'tool_id': tool_id,
            'initial_score': None,
            'final_score': None,
            'enhanced': False,
            'workflow_ready': False,
            'grade': None,
            'issues': []
        }

        # Step 1: Get tool data and validate initial quality
        tool = self._get_tool(tool_id)
        if not tool:
            result['issues'].append(f"Tool not found: {tool_id}")
            return result

        initial_validation = self.validator.validate_tool(tool)
        result['initial_score'] = initial_validation['overall_score']

        logger.info(f"{tool_id}: Initial score {initial_validation['overall_score']:.2f} ({initial_validation['grade']})")

        # Step 2: Clean up dummy parameters if present
        self.cleaner.connect()
        try:
            # Cleaner expects parsed parameters, create a copy with parsed JSON
            tool_for_cleaner = dict(tool)
            try:
                tool_for_cleaner['parameters'] = json.loads(tool.get('parameters', '[]') or '[]')
            except (json.JSONDecodeError, TypeError):
                tool_for_cleaner['parameters'] = []

            cleanup_result = self.cleaner.cleanup_tool(tool_for_cleaner, apply=True)
            if cleanup_result['removed_count'] > 0:
                logger.info(f"  Cleaned {cleanup_result['removed_count']} dummy parameters")
                # Re-fetch tool after cleanup
                tool = self._get_tool(tool_id)
        finally:
            self.cleaner.close()

        # Step 3: Enhance metadata if score is low and enhancement is enabled
        if enhance and self.extractor and initial_validation['overall_score'] < self.MIN_WORKFLOW_READY_SCORE:
            logger.info(f"  Enhancing metadata (score < {self.MIN_WORKFLOW_READY_SCORE})...")
            try:
                # Get tool with parsed JSON for extractor
                tool_for_extractor = dict(tool)
                for json_field in ['parameters', 'inputs', 'outputs', 'use_cases', 'citations']:
                    if tool_for_extractor.get(json_field):
                        try:
                            tool_for_extractor[json_field] = json.loads(tool_for_extractor[json_field])
                        except (json.JSONDecodeError, TypeError):
                            tool_for_extractor[json_field] = []

                # Extract metadata using Claude
                extraction_result = self.extractor.extract_all_metadata(tool_for_extractor)

                # Update database with extracted metadata
                if extraction_result.get('success') and extraction_result.get('extracted_metadata'):
                    extracted = extraction_result['extracted_metadata']
                    # Connect extractor to database for update
                    self.extractor.connect()
                    try:
                        success = self.extractor.update_database(tool_id, extracted)
                        if success:
                            result['enhanced'] = True
                            params_added = len(extracted.get('parameters', []))
                            logger.info(f"  Enhanced: +{params_added} params")
                            # Re-fetch tool after enhancement
                            tool = self._get_tool(tool_id)
                    finally:
                        self.extractor.disconnect()
            except Exception as e:
                logger.warning(f"  Enhancement failed: {e}")
                result['issues'].append(f"Enhancement failed: {str(e)}")

        # Step 4: Final validation
        final_validation = self.validator.validate_tool(tool)
        result['final_score'] = final_validation['overall_score']
        result['grade'] = final_validation['grade']
        result['workflow_ready'] = final_validation['workflow_ready']
        result['blocking_issues'] = final_validation.get('blocking_issues', [])

        # Log improvement
        improvement = result['final_score'] - result['initial_score']
        if improvement > 0:
            logger.info(f"  Final: {result['final_score']:.2f} ({result['grade']}) [+{improvement:.2f}]")
        else:
            logger.info(f"  Final: {result['final_score']:.2f} ({result['grade']})")

        if result['workflow_ready']:
            logger.info(f"  ✅ Workflow Ready")
        elif result['final_score'] >= self.MIN_PREVIEW_MODE_SCORE:
            logger.info(f"  ⚠️  Preview Mode")
        else:
            logger.info(f"  ❌ Blocked")

        return result

    def process_recent_tools(
        self,
        hours: int = 24,
        enhance: bool = True
    ) -> List[Dict]:
        """
        Process all tools added/updated in the last N hours.
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Find recently added/updated auto-discovered tools
        cursor.execute("""
            SELECT tool_id FROM tools
            WHERE tool_id LIKE 'auto_%'
            ORDER BY tool_id
        """)

        tool_ids = [row[0] for row in cursor.fetchall()]
        conn.close()

        logger.info(f"Processing {len(tool_ids)} auto-discovered tools")

        results = []
        for tool_id in tool_ids:
            result = self.process_tool(tool_id, enhance)
            results.append(result)

        return results

    def process_tool_list(
        self,
        tool_ids: List[str],
        enhance: bool = True
    ) -> List[Dict]:
        """
        Process a specific list of tools.
        """
        results = []
        for tool_id in tool_ids:
            result = self.process_tool(tool_id, enhance)
            results.append(result)
        return results

    def _get_tool(self, tool_id: str) -> Optional[Dict]:
        """Get tool data from database (raw, without JSON parsing)."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        cursor.execute("""
            SELECT * FROM tools WHERE tool_id = ?
        """, (tool_id,))

        row = cursor.fetchone()
        conn.close()

        if not row:
            return None

        # Return raw dict without parsing JSON fields
        # (validator expects strings for JSON fields)
        return dict(row)

    def generate_report(self, results: List[Dict]) -> str:
        """Generate summary report of enhancement results."""
        lines = [
            "=" * 70,
            "QUALITY ENHANCEMENT REPORT",
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            "=" * 70,
            ""
        ]

        # Summary stats
        total = len(results)
        workflow_ready = sum(1 for r in results if r.get('workflow_ready'))
        enhanced = sum(1 for r in results if r.get('enhanced'))
        improved = sum(1 for r in results if r.get('final_score', 0) > r.get('initial_score', 0))

        lines.extend([
            f"Total tools processed: {total}",
            f"Workflow ready: {workflow_ready} ({100*workflow_ready/total:.0f}%)" if total else "Workflow ready: 0",
            f"Enhanced: {enhanced}",
            f"Improved: {improved}",
            ""
        ])

        # Tool details
        lines.append("TOOL DETAILS:")
        lines.append("-" * 70)

        for r in sorted(results, key=lambda x: x.get('final_score', 0), reverse=True):
            status = "✅" if r.get('workflow_ready') else "❌"
            enhanced_mark = " [E]" if r.get('enhanced') else ""
            lines.append(
                f"{status} {r['tool_id']}: "
                f"{r.get('initial_score', 0):.2f} → {r.get('final_score', 0):.2f} "
                f"({r.get('grade', '?')}){enhanced_mark}"
            )

        lines.extend(["", "=" * 70])

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Quality enhancement step for auto-discovered tools'
    )
    parser.add_argument(
        '--db-path',
        type=Path,
        default=Path('/home/yzhang/biomate/backend/database/galaxy_ai_tools.db'),
        help='Path to database'
    )
    parser.add_argument(
        '--tool-ids',
        nargs='+',
        help='Specific tool IDs to process'
    )
    parser.add_argument(
        '--all-recent',
        action='store_true',
        help='Process all recent auto-discovered tools'
    )
    parser.add_argument(
        '--no-enhance',
        action='store_true',
        help='Skip metadata enhancement (validation only)'
    )
    parser.add_argument(
        '--output',
        type=Path,
        help='Output file for results JSON'
    )

    args = parser.parse_args()

    # Initialize
    enhancer = QualityEnhancementStep(args.db_path)

    # Process tools
    if args.tool_ids:
        results = enhancer.process_tool_list(args.tool_ids, enhance=not args.no_enhance)
    elif args.all_recent:
        results = enhancer.process_recent_tools(enhance=not args.no_enhance)
    else:
        parser.print_help()
        return 1

    # Generate report
    report = enhancer.generate_report(results)
    print(report)

    # Save results
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        logger.info(f"Results saved to: {args.output}")

    # Return success based on workflow ready count
    workflow_ready = sum(1 for r in results if r.get('workflow_ready'))
    return 0 if workflow_ready > 0 else 1


if __name__ == '__main__':
    exit(main())
