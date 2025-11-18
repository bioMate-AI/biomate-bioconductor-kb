#!/usr/bin/env python3
"""
Tool Quality Validator

Validates that tools have sufficient structured information for:
- Workflow configuration and implementation
- Process/input/output interpretation
- Resource scheduling and deployment

This acts as a quality gate before tools are added to the production index.

Usage:
    # Validate a specific tool
    python tool_quality_validator.py --tool-id auto_foldseek

    # Validate all auto-discovered tools
    python tool_quality_validator.py --all-auto-discovered

    # Generate quality report
    python tool_quality_validator.py --all-auto-discovered --report quality_report.json

    # Check if tool meets minimum quality
    python tool_quality_validator.py --tool-id auto_foldseek --min-score 0.7
"""

import argparse
import json
import logging
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ToolQualityValidator:
    """
    Validates tool metadata quality for workflow implementation.
    """

    # Minimum quality thresholds
    MIN_QUALITY_SCORE = 0.70  # Minimum overall score
    MIN_WORKFLOW_READY_SCORE = 0.85  # Score for production-ready workflows

    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.conn = None

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

    def validate_tool(self, tool: Dict) -> Dict:
        """
        Comprehensive tool validation.

        Returns:
            Validation result with scores, issues, and recommendations
        """
        result = {
            'tool_id': tool['tool_id'],
            'tool_name': tool['name'],
            'validated_at': datetime.now().isoformat(),
            'category_scores': {},
            'overall_score': 0.0,
            'grade': '',
            'issues': [],
            'warnings': [],
            'recommendations': [],
            'workflow_ready': False,
            'blocking_issues': []
        }

        # Validate each category
        result['category_scores']['basic_metadata'] = self._validate_basic_metadata(tool, result)
        result['category_scores']['parameters'] = self._validate_parameters(tool, result)
        result['category_scores']['requirements'] = self._validate_requirements(tool, result)
        result['category_scores']['inputs_outputs'] = self._validate_inputs_outputs(tool, result)
        result['category_scores']['usage_documentation'] = self._validate_usage_documentation(tool, result)
        result['category_scores']['scientific_context'] = self._validate_scientific_context(tool, result)

        # Calculate overall score (weighted average)
        weights = {
            'basic_metadata': 0.15,
            'parameters': 0.35,  # Most critical for workflows
            'requirements': 0.20,  # Critical for deployment
            'inputs_outputs': 0.15,
            'usage_documentation': 0.10,
            'scientific_context': 0.05
        }

        result['overall_score'] = sum(
            result['category_scores'][cat] * weight
            for cat, weight in weights.items()
        )

        # Assign grade
        result['grade'] = self._assign_grade(result['overall_score'])

        # Determine workflow readiness
        result['workflow_ready'] = (
            result['overall_score'] >= self.MIN_WORKFLOW_READY_SCORE and
            len(result['blocking_issues']) == 0
        )

        return result

    def _validate_basic_metadata(self, tool: Dict, result: Dict) -> float:
        """Validate basic metadata (name, description, etc.)"""
        score = 1.0
        required_fields = ['tool_id', 'name', 'description', 'github_url']

        for field in required_fields:
            if not tool.get(field):
                score -= 0.25
                result['issues'].append({
                    'category': 'basic_metadata',
                    'severity': 'critical',
                    'field': field,
                    'issue': f"Missing required field: {field}"
                })
                result['blocking_issues'].append(f"Missing {field}")

        # Check description quality
        description = tool.get('description', '')
        if description and len(description) < 20:
            score -= 0.1
            result['warnings'].append({
                'category': 'basic_metadata',
                'field': 'description',
                'issue': f"Description too short ({len(description)} chars)",
                'recommendation': "Provide detailed description (50+ chars)"
            })

        return max(0.0, score)

    def _validate_parameters(self, tool: Dict, result: Dict) -> float:
        """
        Validate tool parameters - CRITICAL for workflow configuration.
        """
        score = 0.0
        parameters_str = tool.get('parameters', '[]')

        try:
            parameters = json.loads(parameters_str) if parameters_str else []
        except json.JSONDecodeError:
            result['issues'].append({
                'category': 'parameters',
                'severity': 'critical',
                'field': 'parameters',
                'issue': "Invalid JSON in parameters field"
            })
            result['blocking_issues'].append("Invalid parameters JSON")
            return 0.0

        if not parameters or parameters == []:
            result['issues'].append({
                'category': 'parameters',
                'severity': 'critical',
                'field': 'parameters',
                'issue': "No parameters defined - cannot generate workflow forms",
                'impact': "Users cannot configure tool through UI"
            })
            result['blocking_issues'].append("No parameters defined")
            result['recommendations'].append({
                'category': 'parameters',
                'action': 'extract_from_help',
                'details': "Run tool with --help and parse parameter definitions"
            })
            return 0.0

        # Check if parameters are dummy placeholders
        dummy_indicators = ['help', 'h', 'm', 'Parameter for']
        dummy_count = sum(
            1 for p in parameters
            if p.get('name', '').lower() in dummy_indicators or
            'Parameter for' in p.get('help', '')
        )

        if dummy_count > 0:
            score = 0.2  # Some structure but useless
            result['issues'].append({
                'category': 'parameters',
                'severity': 'critical',
                'field': 'parameters',
                'issue': f"Contains {dummy_count} dummy/placeholder parameters",
                'examples': [p.get('name') for p in parameters[:3]],
                'impact': "Cannot generate meaningful workflow forms"
            })
            result['blocking_issues'].append("Dummy parameters detected")
            return score

        # Validate parameter quality
        score = 1.0
        for i, param in enumerate(parameters):
            # Check required fields
            if not param.get('name'):
                score -= 0.1
                result['warnings'].append({
                    'category': 'parameters',
                    'issue': f"Parameter {i} missing 'name' field"
                })

            if not param.get('type'):
                score -= 0.05
                result['warnings'].append({
                    'category': 'parameters',
                    'issue': f"Parameter '{param.get('name')}' missing 'type'"
                })

            # Check for good types
            valid_types = ['text', 'integer', 'float', 'boolean', 'select', 'data']
            if param.get('type') not in valid_types:
                score -= 0.05
                result['warnings'].append({
                    'category': 'parameters',
                    'issue': f"Parameter '{param.get('name')}' has unusual type: {param.get('type')}"
                })

        return max(0.0, score)

    def _validate_requirements(self, tool: Dict, result: Dict) -> float:
        """
        Validate requirements - CRITICAL for deployment and resource scheduling.
        """
        score = 0.0
        requirements_str = tool.get('requirements', '[]')

        try:
            requirements = json.loads(requirements_str) if requirements_str else []
        except json.JSONDecodeError:
            result['issues'].append({
                'category': 'requirements',
                'severity': 'major',
                'field': 'requirements',
                'issue': "Invalid JSON in requirements field"
            })
            return 0.0

        if not requirements:
            result['issues'].append({
                'category': 'requirements',
                'severity': 'critical',
                'field': 'requirements',
                'issue': "No requirements defined",
                'impact': "Cannot deploy tool, no container/package info"
            })
            result['blocking_issues'].append("No requirements defined")
            return 0.0

        # Check for Docker container (most important)
        has_docker = any(r.get('type') == 'docker' for r in requirements)
        if has_docker:
            score = 0.6  # Base score for having Docker
            docker_req = next(r for r in requirements if r.get('type') == 'docker')

            # Validate Docker container name
            container_name = docker_req.get('name', '')
            if not container_name:
                score -= 0.2
                result['warnings'].append({
                    'category': 'requirements',
                    'issue': "Docker requirement missing container name"
                })
        else:
            result['warnings'].append({
                'category': 'requirements',
                'issue': "No Docker container specified - may be harder to deploy"
            })
            score = 0.3

        # Check for structured resource requirements
        # (CPU, GPU, memory - currently in unstructured text)
        usage_guide = tool.get('usage_guide', '')
        has_gpu_info = 'GPU' in usage_guide or 'gpu' in usage_guide.lower()
        has_cpu_info = 'AVX' in usage_guide or 'SSE' in usage_guide or 'CPU' in usage_guide
        has_memory_info = 'memory' in usage_guide.lower() or 'RAM' in usage_guide or 'GB' in usage_guide

        if has_gpu_info or has_cpu_info:
            score += 0.2
            result['warnings'].append({
                'category': 'requirements',
                'issue': "CPU/GPU requirements exist but unstructured",
                'recommendation': "Parse usage_guide to extract structured requirements"
            })
        else:
            result['recommendations'].append({
                'category': 'requirements',
                'action': 'add_resource_requirements',
                'details': "Add CPU, GPU, and memory requirements for proper scheduling"
            })

        # Check for system prerequisites
        if has_cpu_info or has_gpu_info or has_memory_info:
            score += 0.2

        return min(1.0, score)

    def _validate_inputs_outputs(self, tool: Dict, result: Dict) -> float:
        """Validate input/output specifications."""
        score = 1.0

        # Check inputs
        inputs_str = tool.get('inputs', '[]')
        try:
            inputs = json.loads(inputs_str) if inputs_str else []
        except:
            inputs = []
            score -= 0.3
            result['warnings'].append({
                'category': 'inputs_outputs',
                'issue': "Invalid JSON in inputs field"
            })

        if not inputs:
            score -= 0.3
            result['warnings'].append({
                'category': 'inputs_outputs',
                'issue': "No input formats defined"
            })
        elif isinstance(inputs, list) and inputs:
            # Check if it's just file extensions or detailed specs
            if isinstance(inputs[0], str):
                # Just extensions like ["fasta", "fa"]
                score -= 0.2
                result['recommendations'].append({
                    'category': 'inputs_outputs',
                    'action': 'enhance_input_specs',
                    'details': "Provide detailed input specifications with descriptions"
                })

        # Check outputs
        outputs_str = tool.get('outputs', '[]')
        try:
            outputs = json.loads(outputs_str) if outputs_str else []
        except:
            outputs = []
            score -= 0.3
            result['warnings'].append({
                'category': 'inputs_outputs',
                'issue': "Invalid JSON in outputs field"
            })

        if not outputs:
            score -= 0.3
            result['warnings'].append({
                'category': 'inputs_outputs',
                'issue': "No output formats defined"
            })
        elif isinstance(outputs, list) and outputs:
            if isinstance(outputs[0], str):
                score -= 0.2
                result['recommendations'].append({
                    'category': 'inputs_outputs',
                    'action': 'enhance_output_specs',
                    'details': "Provide detailed output specifications with descriptions"
                })

        return max(0.0, score)

    def _validate_usage_documentation(self, tool: Dict, result: Dict) -> float:
        """Validate usage guide and examples."""
        score = 1.0

        # Check usage_guide
        usage_guide = tool.get('usage_guide', '')
        if not usage_guide or len(usage_guide) < 100:
            score -= 0.4
            result['warnings'].append({
                'category': 'usage_documentation',
                'issue': f"Usage guide too short or missing ({len(usage_guide)} chars)"
            })
        else:
            # Good length
            if len(usage_guide) > 1000:
                score += 0.1  # Bonus for detailed guide

        # Check examples
        examples_str = tool.get('examples', '[]')
        try:
            examples = json.loads(examples_str) if examples_str else []
        except:
            examples = []

        if not examples:
            score -= 0.3
            result['warnings'].append({
                'category': 'usage_documentation',
                'issue': "No usage examples provided"
            })
        elif len(examples) >= 2:
            score += 0.1  # Bonus for multiple examples

        # Check citations
        citations_str = tool.get('citations', '[]')
        try:
            citations = json.loads(citations_str) if citations_str else []
        except:
            citations = []

        if citations and len(citations) > 0:
            score += 0.1  # Bonus for having citations

        return min(1.0, max(0.0, score))

    def _validate_scientific_context(self, tool: Dict, result: Dict) -> float:
        """Validate scientific context and use cases."""
        score = 0.5  # Neutral base score (not critical)

        sci_context_str = tool.get('scientific_context', '{}')
        try:
            sci_context = json.loads(sci_context_str) if sci_context_str else {}
        except:
            return 0.5

        # Check if populated
        use_cases = sci_context.get('use_cases', [])
        if use_cases and len(use_cases) > 0:
            score = 1.0
        else:
            result['recommendations'].append({
                'category': 'scientific_context',
                'action': 'add_use_cases',
                'details': "Add typical scientific use cases for better discoverability"
            })

        return score

    def _assign_grade(self, score: float) -> str:
        """Assign letter grade based on score."""
        if score >= 0.95:
            return 'A+'
        elif score >= 0.90:
            return 'A'
        elif score >= 0.85:
            return 'A-'
        elif score >= 0.80:
            return 'B+'
        elif score >= 0.75:
            return 'B'
        elif score >= 0.70:
            return 'B-'
        elif score >= 0.65:
            return 'C+'
        elif score >= 0.60:
            return 'C'
        elif score >= 0.50:
            return 'D'
        else:
            return 'F'

    def generate_report(self, validation_results: List[Dict]) -> Dict:
        """Generate summary report from multiple validation results."""
        report = {
            'generated_at': datetime.now().isoformat(),
            'total_tools': len(validation_results),
            'summary': {
                'workflow_ready': 0,
                'needs_improvement': 0,
                'blocking_issues': 0
            },
            'grade_distribution': {},
            'common_issues': {},
            'tools': validation_results
        }

        # Calculate statistics
        for result in validation_results:
            if result['workflow_ready']:
                report['summary']['workflow_ready'] += 1
            if result['blocking_issues']:
                report['summary']['blocking_issues'] += 1
            else:
                report['summary']['needs_improvement'] += 1

            # Grade distribution
            grade = result['grade']
            report['grade_distribution'][grade] = report['grade_distribution'].get(grade, 0) + 1

            # Collect common issues
            for issue in result['issues']:
                issue_key = f"{issue['category']}:{issue['field']}"
                if issue_key not in report['common_issues']:
                    report['common_issues'][issue_key] = {
                        'category': issue['category'],
                        'field': issue['field'],
                        'count': 0,
                        'example': issue['issue']
                    }
                report['common_issues'][issue_key]['count'] += 1

        # Sort common issues by frequency
        report['common_issues'] = dict(
            sorted(
                report['common_issues'].items(),
                key=lambda x: x[1]['count'],
                reverse=True
            )
        )

        return report


def main():
    parser = argparse.ArgumentParser(
        description='Validate tool quality for workflow implementation'
    )

    parser.add_argument(
        '--tool-id',
        help='Specific tool ID to validate'
    )

    parser.add_argument(
        '--all-auto-discovered',
        action='store_true',
        help='Validate all auto-discovered tools'
    )

    parser.add_argument(
        '--db-path',
        type=Path,
        default=Path('/home/yzhang/biomate/backend/database/galaxy_ai_tools.db'),
        help='Path to database'
    )

    parser.add_argument(
        '--report',
        type=Path,
        help='Output path for JSON report'
    )

    parser.add_argument(
        '--min-score',
        type=float,
        default=0.0,
        help='Minimum quality score required (exits with error if below)'
    )

    parser.add_argument(
        '--block-on-issues',
        action='store_true',
        help='Exit with error if blocking issues found'
    )

    args = parser.parse_args()

    validator = ToolQualityValidator(args.db_path)
    validator.connect()

    try:
        validation_results = []

        if args.tool_id:
            # Validate single tool
            tool = validator.get_tool(args.tool_id)
            if not tool:
                logger.error(f"Tool not found: {args.tool_id}")
                return 1

            result = validator.validate_tool(tool)
            validation_results.append(result)

            # Print result
            print("="*80)
            print(f"QUALITY VALIDATION: {result['tool_name']} ({result['tool_id']})")
            print("="*80)
            print(f"\nOverall Score: {result['overall_score']:.2f} (Grade: {result['grade']})")
            print(f"Workflow Ready: {'✅ YES' if result['workflow_ready'] else '❌ NO'}")

            print(f"\n📊 Category Scores:")
            for category, score in result['category_scores'].items():
                print(f"  {category:25s}: {score:.2f}")

            if result['blocking_issues']:
                print(f"\n🔴 Blocking Issues ({len(result['blocking_issues'])}):")
                for issue in result['blocking_issues']:
                    print(f"  - {issue}")

            if result['issues']:
                print(f"\n⚠️  Issues ({len(result['issues'])}):")
                for issue in result['issues'][:5]:  # Show first 5
                    print(f"  [{issue['severity']}] {issue['category']}: {issue['issue']}")

            if result['recommendations']:
                print(f"\n💡 Recommendations ({len(result['recommendations'])}):")
                for rec in result['recommendations'][:5]:
                    if isinstance(rec, dict):
                        print(f"  - {rec['category']}: {rec.get('details', rec.get('action'))}")
                    else:
                        print(f"  - {rec}")

        elif args.all_auto_discovered:
            # Validate all auto-discovered tools
            cursor = validator.conn.execute(
                "SELECT * FROM tools WHERE auto_discovered = 1"
            )
            tools = [dict(row) for row in cursor.fetchall()]

            print(f"Validating {len(tools)} auto-discovered tools...")
            print("="*80)

            for tool in tools:
                result = validator.validate_tool(tool)
                validation_results.append(result)

                # Print summary line
                status = "✅" if result['workflow_ready'] else "❌"
                print(f"{status} {tool['tool_id']:20s} | Score: {result['overall_score']:.2f} ({result['grade']}) | Blocking: {len(result['blocking_issues'])}")

            # Generate report
            report = validator.generate_report(validation_results)

            print("\n" + "="*80)
            print("SUMMARY REPORT")
            print("="*80)
            print(f"Total tools: {report['total_tools']}")
            print(f"✅ Workflow ready: {report['summary']['workflow_ready']}")
            print(f"⚠️  Needs improvement: {report['summary']['needs_improvement']}")
            print(f"🔴 Has blocking issues: {report['summary']['blocking_issues']}")

            print(f"\n📊 Grade Distribution:")
            for grade, count in sorted(report['grade_distribution'].items()):
                print(f"  {grade}: {count} tools")

            print(f"\n🔴 Most Common Issues:")
            for issue_key, issue_data in list(report['common_issues'].items())[:5]:
                print(f"  {issue_data['count']}x - {issue_data['category']}.{issue_data['field']}: {issue_data['example'][:60]}...")

            # Save report if requested
            if args.report:
                with open(args.report, 'w') as f:
                    json.dump(report, f, indent=2)
                print(f"\n✅ Full report saved to: {args.report}")
        else:
            parser.print_help()
            return 1

        # Check thresholds
        if validation_results:
            min_score_result = min(validation_results, key=lambda x: x['overall_score'])

            if args.min_score > 0 and min_score_result['overall_score'] < args.min_score:
                logger.error(f"\n❌ FAILED: Minimum score {args.min_score} not met")
                logger.error(f"   Lowest score: {min_score_result['overall_score']:.2f} ({min_score_result['tool_id']})")
                return 1

            if args.block_on_issues:
                tools_with_blocking = [r for r in validation_results if r['blocking_issues']]
                if tools_with_blocking:
                    logger.error(f"\n❌ FAILED: {len(tools_with_blocking)} tools have blocking issues")
                    for result in tools_with_blocking:
                        logger.error(f"   - {result['tool_id']}: {len(result['blocking_issues'])} blocking issues")
                    return 1

        return 0

    finally:
        validator.disconnect()


if __name__ == '__main__':
    exit(main())
