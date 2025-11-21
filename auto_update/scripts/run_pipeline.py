#!/usr/bin/env python3
"""
End-to-End Auto-Update Pipeline

Orchestrates the complete pipeline:
1. Detect tools from GitHub
2. Fetch documentation
3. Generate wrappers
4. Validate wrappers
5. Test execution
6. Integrate into Galaxy

Usage:
    python run_pipeline.py --mode full --days 30 --min-stars 50
    python run_pipeline.py --mode test --discovery data/discoveries/latest.json --limit 5
    python run_pipeline.py --mode integrate --wrappers data/wrappers --validate --test
"""

import argparse
import json
import logging
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

# Import pipeline components
sys.path.insert(0, str(Path(__file__).parent))

from detect_github_tools import GitHubDetector, load_config
from documentation_fetcher import DocumentationFetcher
from galaxy_wrapper_generator import GalaxyWrapperGenerator
from api_wrapper_generator import APIWrapperGenerator
from validate_wrapper import WrapperValidator
from test_tool_execution import ToolExecutor
from integrate_tools import ToolIntegrator, DatabaseIntegrator
from quality_enhancement_step import QualityEnhancementStep
from feasibility_checker import FeasibilityChecker
from api_detector import APIDetector
try:
    from llm_feasibility_checker import HybridFeasibilityChecker
    HAS_LLM_CHECKER = True
except ImportError:
    HAS_LLM_CHECKER = False

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class PipelineStats:
    """
    Track pipeline execution statistics.
    """

    def __init__(self):
        self.stats = {
            'detected': 0,
            'feasibility_passed': 0,
            'feasibility_rejected': 0,
            'skipped_duplicate': 0,
            'skipped_has_api': 0,
            'skipped_too_large': 0,
            'docs_fetched': 0,
            'wrappers_generated': 0,
            'api_wrappers_generated': 0,
            'wrappers_validated': 0,
            'tests_passed': 0,
            'tests_failed': 0,
            'integrated': 0,
            'errors': []
        }

    def add(self, key: str, count: int = 1):
        """Add to counter"""
        if key in self.stats:
            self.stats[key] += count

    def add_error(self, error: str):
        """Add error message"""
        self.stats['errors'].append(error)

    def summary(self) -> str:
        """Generate summary report"""
        lines = [
            "="*60,
            "Pipeline Execution Summary",
            "="*60,
            f"Tools detected: {self.stats['detected']}",
            f"Feasibility passed: {self.stats['feasibility_passed']}",
            f"Feasibility rejected: {self.stats['feasibility_rejected']}",
            f"Skipped (duplicate): {self.stats['skipped_duplicate']}",
            f"Skipped (has API): {self.stats['skipped_has_api']}",
            f"Skipped (too large): {self.stats['skipped_too_large']}",
            f"Documentation fetched: {self.stats['docs_fetched']}",
            f"Wrappers generated: {self.stats['wrappers_generated']}",
            f"  ├─ API wrappers: {self.stats['api_wrappers_generated']}",
            f"  └─ Docker wrappers: {self.stats['wrappers_generated'] - self.stats['api_wrappers_generated']}",
            f"Wrappers validated: {self.stats['wrappers_validated']}",
            f"Tests passed: {self.stats['tests_passed']}",
            f"Tests failed: {self.stats['tests_failed']}",
            f"Tools integrated: {self.stats['integrated']}",
            ""
        ]

        if self.stats['errors']:
            lines.append("ERRORS:")
            for error in self.stats['errors'][:10]:  # Show first 10
                lines.append(f"  - {error}")
            if len(self.stats['errors']) > 10:
                lines.append(f"  ... and {len(self.stats['errors']) - 10} more")
            lines.append("")

        lines.append("="*60)
        return "\n".join(lines)

    def save(self, output_file: Path):
        """Save stats to JSON file"""
        with open(output_file, 'w') as f:
            json.dump(self.stats, f, indent=2)


class AutoUpdatePipeline:
    """
    Main pipeline orchestrator.
    """

    def __init__(self, config_dir: Path, data_dir: Path):
        self.config_dir = config_dir
        self.data_dir = data_dir
        self.stats = PipelineStats()

        # Load configuration
        self.config = load_config(config_dir)

        # Set paths for database and tools directory
        self.db_path = Path(__file__).parent.parent.parent / 'backend' / 'database' / 'galaxy_ai_tools.db'
        self.tools_dir = Path(__file__).parent.parent.parent / 'backend' / 'tools'

    def run_full_pipeline(
        self,
        days: int = 90,
        min_stars: int = 50,
        limit: Optional[int] = None,
        validate: bool = True,
        test: bool = True
    ) -> bool:
        """
        Run complete pipeline from detection to integration.

        Args:
            days: Look back N days for tools
            min_stars: Minimum stars threshold
            limit: Limit number of tools to process
            validate: Run validation step
            test: Run testing step

        Returns:
            True if pipeline completed successfully
        """
        logger.info("Starting full auto-update pipeline")
        logger.info(f"Parameters: days={days}, min_stars={min_stars}, limit={limit}")

        # Stage 1: Detection
        discoveries = self._run_detection(days, min_stars, limit)
        if not discoveries:
            logger.error("No tools discovered")
            return False

        # Stage 2-6: Process each discovered tool
        for discovery in discoveries:
            try:
                self._process_tool(discovery, validate, test)
            except Exception as e:
                error_msg = f"Error processing {discovery.get('name')}: {e}"
                logger.error(error_msg)
                self.stats.add_error(error_msg)
                continue

        # Print summary
        print(self.stats.summary())

        # Save stats
        stats_file = self.data_dir / f"pipeline_stats_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        self.stats.save(stats_file)
        logger.info(f"Stats saved to: {stats_file}")

        return self.stats.stats['integrated'] > 0

    def _run_detection(
        self,
        days: int,
        min_stars: int,
        limit: Optional[int]
    ) -> List[Dict]:
        """
        Stage 1: Detect tools from GitHub.
        """
        logger.info("="*60)
        logger.info("STAGE 1: Detection")
        logger.info("="*60)

        # Get GitHub token
        token = self.config.get('credentials', {}).get('github', {}).get('token')
        if not token:
            logger.error("GitHub token not configured")
            return []

        # Get topics from config
        topics = self.config.get('sources', {}).get('github', {}).get('topics', [])

        # Initialize detector
        detector = GitHubDetector(token, self.config)

        # Run detection with early termination if limit specified
        # Request 2-3x limit to account for duplicates and filtering
        max_high_quality = (limit * 3) if limit else None

        discoveries = detector.search_repos(
            topics=topics,
            min_stars=min_stars,
            days_back=days,
            max_high_quality=max_high_quality
        )

        # Filter high-quality only
        high_quality = [d for d in discoveries if d.get('classification') == 'high']

        logger.info(f"Found {len(discoveries)} tools, {len(high_quality)} high-quality")

        # Apply limit
        if limit:
            high_quality = high_quality[:limit]
            logger.info(f"Limited to {len(high_quality)} tools")

        self.stats.add('detected', len(high_quality))

        # Save discoveries
        discoveries_file = self.data_dir / 'discoveries' / f"github_tools_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        discoveries_file.parent.mkdir(parents=True, exist_ok=True)
        with open(discoveries_file, 'w') as f:
            json.dump(high_quality, f, indent=2)

        return high_quality

    def _process_tool(
        self,
        discovery: Dict,
        validate: bool,
        test: bool
    ):
        """
        Process a single tool through all pipeline stages.
        """
        tool_name = discovery.get('name')
        repo_full_name = discovery.get('full_name')

        logger.info(f"\nProcessing tool: {tool_name}")

        # Stage 1.5: Feasibility check (filter unsuitable tools early)
        # Use LLM-based checker if available for better generalization
        api_key = os.getenv('ANTHROPIC_API_KEY')
        if HAS_LLM_CHECKER and api_key:
            checker = HybridFeasibilityChecker(api_key)
            feasible, reason, confidence, tool_type = checker.check(discovery)
        else:
            checker = FeasibilityChecker()
            feasible, reason, confidence = checker.check(discovery)
            tool_type = "unknown"

        if not feasible:
            logger.info(f"  [SKIP] Not feasible ({tool_type}): {reason} (confidence: {confidence:.0%})")
            self.stats.add('feasibility_rejected')
            return

        self.stats.add('feasibility_passed')
        logger.info(f"  [1/6] Feasibility check passed ({tool_type}): {reason}")

        # Stage 1.6: Check for duplicates in database
        tool_id = f"auto_{tool_name.lower().replace('-', '_')}"
        db_integrator = DatabaseIntegrator(self.db_path)
        db_integrator.connect()
        if db_integrator.tool_exists(tool_id):
            logger.info(f"  [SKIP] Tool {tool_id} already exists in database")
            self.stats.add('skipped_duplicate')
            db_integrator.close()
            return
        db_integrator.close()

        # Stage 1.7: Check for API availability (prefer API over local installation)
        api_detector = APIDetector()
        has_api, api_info = api_detector.check(discovery)
        if has_api and api_info:
            confidence = api_info.get('confidence', 0)
            if confidence > 0.7:
                indicators = ', '.join(api_info.get('indicators', [])[:2])
                logger.info(f"  [SKIP] Tool has API (confidence: {confidence:.0%}): {indicators}")
                logger.info(f"    Suggestion: Use API instead of local installation")
                self.stats.add('skipped_has_api')
                return

        # Stage 2: Fetch documentation
        documentation = self._fetch_documentation(repo_full_name)
        if not documentation:
            self.stats.add_error(f"{tool_name}: Failed to fetch documentation")
            return

        # Stage 3: Generate wrapper
        wrapper_path = self._generate_wrapper(discovery, documentation)
        if not wrapper_path:
            self.stats.add_error(f"{tool_name}: Failed to generate wrapper")
            return

        # Stage 4: Validate wrapper
        if validate:
            is_valid = self._validate_wrapper(wrapper_path)
            if not is_valid:
                self.stats.add_error(f"{tool_name}: Validation failed")
                return

        # Stage 5: Test execution
        test_result = None
        if test:
            test_passed = self._test_execution(wrapper_path, discovery)
            if not test_passed:
                self.stats.add_error(f"{tool_name}: Test failed")
                # Continue to integration even if test failed (for now)
                test_result = {'success': False}
            else:
                test_result = {'success': True}

        # Stage 6: Integrate with complete metadata extraction
        result = self._integrate_tool(wrapper_path, discovery, documentation, test_result)
        if result == "success":
            logger.info(f"✓ Successfully integrated {tool_name}")
        elif result == "duplicate":
            logger.info(f"⊘ {tool_name} skipped (already exists or duplicate)")
        else:
            self.stats.add_error(f"{tool_name}: Integration failed")

    def _fetch_documentation(self, repo_full_name: str) -> Optional[Dict]:
        """
        Stage 2: Fetch documentation.
        """
        logger.info(f"  [2/6] Fetching documentation...")

        try:
            token = self.config.get('credentials', {}).get('github', {}).get('token')
            fetcher = DocumentationFetcher(token)
            docs = fetcher.fetch_documentation(repo_full_name)

            self.stats.add('docs_fetched')
            return docs

        except Exception as e:
            logger.error(f"Documentation fetch error: {e}")
            return None

    def _generate_wrapper(
        self,
        metadata: Dict,
        documentation: Dict
    ) -> Optional[Path]:
        """
        Stage 3: Generate Galaxy wrapper (Docker or API-based).

        Smart wrapper selection:
        - Checks Docker image size first
        - If > 2GB and API available, generates API wrapper instead
        - Otherwise generates standard Docker wrapper
        """
        logger.info(f"  [3/6] Generating wrapper...")

        try:
            # First, try standard Docker wrapper generation
            generator = GalaxyWrapperGenerator()
            wrapper_xml = generator.generate_wrapper(metadata, documentation)

            # Extract Docker image from wrapper (if present)
            docker_image = self._extract_docker_image(wrapper_xml)

            # Check if we should use API instead
            if docker_image:
                use_api = self._should_use_api_wrapper(
                    docker_image,
                    metadata,
                    documentation
                )

                if use_api:
                    # Generate API wrapper instead
                    api_detector = APIDetector()
                    has_api, api_info = api_detector.check(metadata)

                    if has_api and api_info:
                        logger.info(f"    → Converting to API wrapper (Docker image too large)")
                        api_generator = APIWrapperGenerator()
                        wrapper_xml = api_generator.generate_api_wrapper(
                            metadata,
                            api_info,
                            documentation
                        )
                        self.stats.add('api_wrappers_generated')
                    else:
                        logger.warning(f"    Docker too large but no API found, using Docker anyway")

            # Save wrapper
            tool_name = metadata.get('name')
            wrapper_path = self.data_dir / 'wrappers' / f"{tool_name}.xml"
            wrapper_path.parent.mkdir(parents=True, exist_ok=True)

            with open(wrapper_path, 'w') as f:
                f.write(wrapper_xml)

            self.stats.add('wrappers_generated')
            logger.info(f"    Saved to: {wrapper_path}")
            return wrapper_path

        except Exception as e:
            logger.error(f"Wrapper generation error: {e}")
            return None

    def _extract_docker_image(self, wrapper_xml: str) -> Optional[str]:
        """Extract Docker image name from wrapper XML."""
        import re
        match = re.search(r'<container type="docker">([^<]+)</container>', wrapper_xml)
        return match.group(1) if match else None

    def _should_use_api_wrapper(
        self,
        docker_image: str,
        metadata: Dict,
        documentation: Dict
    ) -> bool:
        """
        Determine if we should use API wrapper instead of Docker.

        Returns True if:
        - Docker image is > 2GB
        - Tool has a usable API
        """
        try:
            # Import here to avoid circular dependency
            from test_tool_execution import ContainerManager

            container_mgr = ContainerManager()
            size_mb = container_mgr.get_image_size(docker_image)

            if size_mb and size_mb > 2000:  # 2GB threshold
                logger.info(f"    Docker image is large: {size_mb}MB")

                # Check for API
                api_detector = APIDetector()
                has_api, api_info = api_detector.check(metadata)

                if has_api and api_info:
                    confidence = api_info.get('confidence', 0)
                    logger.info(f"    API available (confidence: {confidence:.0%})")

                    # Use API if confidence is reasonably high
                    return confidence > 0.6

            return False

        except Exception as e:
            logger.warning(f"    Error checking Docker size: {e}")
            return False

    def _validate_wrapper(self, wrapper_path: Path) -> bool:
        """
        Stage 4: Validate wrapper.
        """
        logger.info(f"  [4/6] Validating wrapper...")

        try:
            validator = WrapperValidator()
            result = validator.validate(wrapper_path)

            if result.is_valid():
                self.stats.add('wrappers_validated')
                logger.info(f"    ✓ Validation passed")
                return True
            else:
                logger.warning(f"    ✗ Validation failed: {len(result.errors)} errors")
                for error in result.errors[:3]:
                    logger.warning(f"      - {error}")
                return False

        except Exception as e:
            logger.error(f"Validation error: {e}")
            return False

    def _test_execution(self, wrapper_path: Path, metadata: Dict) -> bool:
        """
        Stage 5: Test tool execution with real test data from repository.
        """
        logger.info(f"  [5/6] Testing execution...")

        try:
            # Get GitHub token from config
            github_token = self.config.get('credentials', {}).get('github', {}).get('token')

            # Create executor with real test data fetcher
            executor = ToolExecutor(github_token=github_token, tool_metadata=metadata)
            result = executor.execute_tool(wrapper_path)

            if result.success:
                self.stats.add('tests_passed')
                logger.info(f"    ✓ Test passed ({result.execution_time:.1f}s)")
                return True
            else:
                # Check if failure was due to image size
                if result.errors:
                    for error in result.errors:
                        if 'Image too large' in error or 'too large' in error:
                            self.stats.add('skipped_too_large')
                            logger.warning(f"    ✗ {error}")
                            return False

                self.stats.add('tests_failed')
                logger.warning(f"    ✗ Test failed")
                if result.errors:
                    for error in result.errors[:2]:
                        logger.warning(f"      - {error}")
                return False

        except Exception as e:
            logger.error(f"Test execution error: {e}")
            self.stats.add('tests_failed')
            return False

    def _integrate_tool(
        self,
        wrapper_path: Path,
        metadata: Dict,
        documentation: Dict,
        test_result: Optional[Dict] = None
    ) -> bool:
        """
        Stage 6: Integrate tool into Galaxy with complete metadata extraction.
        """
        logger.info(f"  [6/6] Integrating tool with complete metadata...")

        try:
            # Initialize integrator with comprehensive metadata extractor
            db_path = Path(__file__).parent.parent.parent / 'backend' / 'database' / 'galaxy_ai_tools.db'
            tools_dir = Path(__file__).parent.parent.parent / 'backend' / 'tools'

            # Get GitHub token from config
            github_token = self.config.get('credentials', {}).get('github', {}).get('token')

            integrator = ToolIntegrator(
                db_path=db_path,
                tools_dir=tools_dir,
                enable_llm=False,  # Set to True for production with anthropic_api_key
                anthropic_api_key=None,
                github_token=github_token
            )

            # Integrate with complete metadata (38 fields)
            result = integrator.integrate_tool(
                wrapper_path=wrapper_path,
                metadata=metadata,
                documentation=documentation,
                test_result=test_result
            )

            if result == "success" or result == True:
                self.stats.add('integrated')
                logger.info(f"    ✓ Integration complete with all metadata fields")
                return "success"
            elif result == "duplicate":
                self.stats.add('skipped_duplicate')
                logger.info(f"    ⊘ Skipped (duplicate)")
                return "duplicate"
            else:
                logger.warning(f"    ✗ Integration failed")
                return "error"

        except Exception as e:
            logger.error(f"Integration error: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return False


def main():
    parser = argparse.ArgumentParser(
        description='Auto-update pipeline for Galaxy tools'
    )
    parser.add_argument(
        '--mode',
        choices=['full', 'test', 'integrate'],
        default='full',
        help='Pipeline mode (default: full)'
    )
    parser.add_argument(
        '--days',
        type=int,
        default=90,
        help='Look back N days for tools (default: 90)'
    )
    parser.add_argument(
        '--min-stars',
        type=int,
        default=50,
        help='Minimum stars threshold (default: 50)'
    )
    parser.add_argument(
        '--limit',
        type=int,
        help='Limit number of tools to process'
    )
    parser.add_argument(
        '--no-validate',
        action='store_true',
        help='Skip validation step'
    )
    parser.add_argument(
        '--no-test',
        action='store_true',
        help='Skip testing step'
    )
    parser.add_argument(
        '--config-dir',
        type=str,
        default='config',
        help='Configuration directory (default: config)'
    )
    parser.add_argument(
        '--data-dir',
        type=str,
        default='data',
        help='Data directory (default: data)'
    )

    args = parser.parse_args()

    # Initialize pipeline
    script_dir = Path(__file__).parent.parent
    config_dir = script_dir / args.config_dir
    data_dir = script_dir / args.data_dir

    pipeline = AutoUpdatePipeline(config_dir, data_dir)

    # Run pipeline
    start_time = datetime.now()
    logger.info(f"Starting pipeline at {start_time}")

    if args.mode == 'full':
        success = pipeline.run_full_pipeline(
            days=args.days,
            min_stars=args.min_stars,
            limit=args.limit,
            validate=not args.no_validate,
            test=not args.no_test
        )

        # Post-processing: Quality Enhancement
        if success:
            logger.info("\n" + "=" * 70)
            logger.info("POST-PROCESSING: Quality Enhancement")
            logger.info("=" * 70)

            try:
                import os
                db_path = Path(__file__).parent.parent.parent / 'backend' / 'database' / 'galaxy_ai_tools.db'
                anthropic_key = os.getenv('ANTHROPIC_API_KEY')

                enhancer = QualityEnhancementStep(db_path, anthropic_key)
                results = enhancer.process_recent_tools(enhance=bool(anthropic_key))
                report = enhancer.generate_report(results)
                print(report)

                # Log summary
                workflow_ready = sum(1 for r in results if r.get('workflow_ready'))
                logger.info(f"\nQuality Enhancement: {workflow_ready}/{len(results)} tools workflow-ready")

            except Exception as e:
                logger.warning(f"Quality enhancement failed: {e}")
                import traceback
                logger.debug(traceback.format_exc())
    else:
        logger.error(f"Mode '{args.mode}' not yet implemented")
        return 1

    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()

    logger.info(f"\nPipeline completed in {duration:.1f}s")

    return 0 if success else 1


if __name__ == '__main__':
    exit(main())
