#!/usr/bin/env python3
"""
Integrated Blog Post Generation Workflow with AI Review

This script:
1. Evaluates new tools using Claude Haiku 4.5 to filter general libraries
2. Generates blog posts only for approved specific tools
3. Iteratively reviews and improves blog posts using AI (until quality threshold met)
4. Saves evaluation and review results for final manual review before publishing

The review agent autonomously determines when a blog post is ready for manual review
based on quality score (>= 0.85) and absence of critical issues.

Usage:
    # Full workflow: evaluate, generate, and iteratively review blogs
    python generate_blogs_with_review.py --all-new --output ./blogs

    # Generate blogs for tools added since a specific date
    python generate_blogs_with_review.py --since 2025-11-01 --output ./blogs

    # Disable automatic review (generate only, no iterative improvement)
    python generate_blogs_with_review.py --all-new --output ./blogs --no-auto-review

    # Dry run (evaluate only, don't generate or review)
    python generate_blogs_with_review.py --all-new --dry-run
"""

import argparse
import json
import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List

from blog_worthiness_evaluator import BlogWorthinessEvaluator
from blog_post_generator import BlogPostGenerator
from blog_review_agent import BlogReviewAgent

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class IntegratedBlogWorkflow:
    """
    Integrated workflow for evaluating tools and generating blog posts.
    """

    def __init__(
        self,
        db_path: Path,
        output_dir: Path,
        anthropic_api_key: str,
        dry_run: bool = False,
        enable_auto_review: bool = True
    ):
        self.db_path = db_path
        self.output_dir = output_dir
        self.dry_run = dry_run
        self.enable_auto_review = enable_auto_review

        # Initialize components
        self.evaluator = BlogWorthinessEvaluator(db_path, anthropic_api_key)
        self.generator = BlogPostGenerator(db_path, output_dir)

        if enable_auto_review:
            self.review_agent = BlogReviewAgent(db_path, anthropic_api_key)
        else:
            self.review_agent = None

        # Create output directories
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.review_dir = output_dir / "review"
        self.review_dir.mkdir(parents=True, exist_ok=True)
        self.versions_dir = output_dir / "versions"  # For intermediate blog versions
        self.versions_dir.mkdir(parents=True, exist_ok=True)

    def process_tools(
        self,
        since_date: str = None,
        limit: int = None,
        tool_ids: List[str] = None
    ) -> Dict:
        """
        Process tools through evaluation and blog generation pipeline.

        Args:
            since_date: Only process tools added since this date (YYYY-MM-DD)
            limit: Limit number of tools to process
            tool_ids: Specific tool IDs to process

        Returns:
            Summary dictionary with statistics
        """
        logger.info("="*80)
        logger.info("INTEGRATED BLOG GENERATION WORKFLOW")
        logger.info("="*80)

        # Step 1: Evaluate tools
        logger.info("\nStep 1: Evaluating tools with Claude Haiku 4.5...")
        logger.info("-"*80)

        if tool_ids:
            evaluation_results = self.evaluator.evaluate_batch(tool_ids=tool_ids)
        else:
            evaluation_results = self.evaluator.evaluate_batch(limit=limit)

        # Save evaluation results for manual review
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        review_file = self.review_dir / f"evaluation_results_{timestamp}.json"

        with open(review_file, 'w') as f:
            json.dump(evaluation_results, f, indent=2)

        logger.info(f"\n✓ Evaluation results saved to: {review_file}")

        # Step 2: Filter approved tools
        approved_tools = [
            r for r in evaluation_results
            if r.get('recommended_action') == 'write_blog'
        ]

        skipped_tools = [
            r for r in evaluation_results
            if r.get('recommended_action') == 'skip'
        ]

        needs_review = [
            r for r in evaluation_results
            if r.get('recommended_action') == 'needs_review'
        ]

        logger.info("\n" + "="*80)
        logger.info("EVALUATION SUMMARY")
        logger.info("="*80)
        logger.info(f"Total tools evaluated: {len(evaluation_results)}")
        logger.info(f"✅ Approved for blog: {len(approved_tools)}")
        logger.info(f"❌ Skipped (general libraries): {len(skipped_tools)}")
        logger.info(f"⚠️  Needs manual review: {len(needs_review)}")

        # Print details
        if approved_tools:
            logger.info("\n✅ APPROVED FOR BLOG POSTS:")
            for tool in approved_tools:
                logger.info(f"   - {tool['tool_name']} ({tool['tool_id']}) - Confidence: {tool['confidence']:.2f}")
                logger.info(f"     Reason: {tool['reason']}")

        if skipped_tools:
            logger.info("\n❌ SKIPPED (General libraries):")
            for tool in skipped_tools:
                logger.info(f"   - {tool['tool_name']} ({tool['tool_id']})")
                logger.info(f"     Reason: {tool['reason']}")

        if needs_review:
            logger.info("\n⚠️  NEEDS MANUAL REVIEW:")
            for tool in needs_review:
                logger.info(f"   - {tool['tool_name']} ({tool['tool_id']})")

        # Step 3: Generate blog posts for approved tools
        review_summaries = []
        if not self.dry_run and approved_tools:
            logger.info("\n" + "="*80)
            logger.info("Step 2: Generating blog posts for approved tools...")
            logger.info("-"*80)

            self.generator.connect()
            try:
                for tool_result in approved_tools:
                    tool_id = tool_result['tool_id']
                    tool = self.generator.get_tool_by_id(tool_id)

                    if tool:
                        logger.info(f"Generating blog for: {tool['name']}")

                        blog_content = self.generator.generate_blog_post(tool)
                        blog_path = self.output_dir / f'{tool_id}_blog.md'
                        self.generator.save_blog_post(tool_id, blog_content)

                        logger.info(f"  ✓ Initial blog saved: {blog_path}")

                        # Step 4: Iterative review and improvement (if enabled)
                        if self.enable_auto_review and self.review_agent:
                            logger.info(f"\n  🔍 Starting iterative review for {tool_id}...")

                            tool_metadata = self.review_agent.get_tool_metadata(tool_id)
                            if tool_metadata:
                                # Create tool-specific versions directory
                                tool_versions_dir = self.versions_dir / tool_id
                                tool_versions_dir.mkdir(parents=True, exist_ok=True)

                                final_blog, iteration_history, ready = \
                                    self.review_agent.iterative_review_and_improve(
                                        blog_content, tool_id, tool_metadata, tool_versions_dir
                                    )

                                # Save reviewed blog
                                reviewed_path = self.output_dir / f'{tool_id}_blog_reviewed.md'
                                with open(reviewed_path, 'w') as f:
                                    f.write(final_blog)

                                # Track review summary
                                review_summary = {
                                    'tool_id': tool_id,
                                    'tool_name': tool['name'],
                                    'iterations': len(iteration_history),
                                    'final_quality_score': iteration_history[-1]['quality_score'] if iteration_history else 0,
                                    'ready_for_manual_review': ready,
                                    'iteration_history': iteration_history
                                }
                                review_summaries.append(review_summary)

                                logger.info(f"  ✓ Reviewed blog saved: {reviewed_path}")
                                logger.info(f"  ✓ Final quality score: {review_summary['final_quality_score']:.2f}")
                                logger.info(f"  ✓ Iterations: {review_summary['iterations']}")
                                logger.info(f"  ✓ Ready for manual review: {ready}")
                            else:
                                logger.warning(f"  ✗ Could not get metadata for review: {tool_id}")
                    else:
                        logger.warning(f"  ✗ Tool not found in database: {tool_id}")

            finally:
                self.generator.disconnect()

        elif self.dry_run:
            logger.info("\n🔍 DRY RUN MODE: Skipping blog generation and review")
            logger.info(f"   Would generate and review {len(approved_tools)} blog posts")

        # Create summary
        summary = {
            'timestamp': timestamp,
            'total_evaluated': len(evaluation_results),
            'approved': len(approved_tools),
            'skipped': len(skipped_tools),
            'needs_review': len(needs_review),
            'blogs_generated': len(approved_tools) if not self.dry_run else 0,
            'blogs_reviewed': len(review_summaries),
            'auto_review_enabled': self.enable_auto_review,
            'dry_run': self.dry_run,
            'review_file': str(review_file),
            'output_dir': str(self.output_dir),
            'approved_tools': [
                {
                    'tool_id': t['tool_id'],
                    'tool_name': t['tool_name'],
                    'confidence': t['confidence'],
                    'suggested_title': t.get('suggested_title')
                }
                for t in approved_tools
            ],
            'skipped_tools': [
                {
                    'tool_id': t['tool_id'],
                    'tool_name': t['tool_name'],
                    'reason': t['reason']
                }
                for t in skipped_tools
            ],
            'review_summaries': review_summaries
        }

        # Save summary
        summary_file = self.review_dir / f"workflow_summary_{timestamp}.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)

        logger.info("\n" + "="*80)
        logger.info("WORKFLOW COMPLETE")
        logger.info("="*80)
        logger.info(f"✓ Review file: {review_file}")
        logger.info(f"✓ Summary: {summary_file}")
        if not self.dry_run and approved_tools:
            logger.info(f"✓ Blog posts: {self.output_dir}")
        logger.info("\n⚠️  IMPORTANT: Review evaluation results before publishing blogs!")
        logger.info("="*80)

        return summary


def main():
    parser = argparse.ArgumentParser(
        description='Integrated workflow for evaluating and generating blog posts'
    )

    parser.add_argument(
        '--all-new',
        action='store_true',
        help='Process all new auto-discovered tools'
    )

    parser.add_argument(
        '--since',
        help='Only process tools added since this date (YYYY-MM-DD)'
    )

    parser.add_argument(
        '--limit',
        type=int,
        help='Limit number of tools to process'
    )

    parser.add_argument(
        '--tool-ids',
        nargs='+',
        help='Specific tool IDs to process'
    )

    parser.add_argument(
        '--db-path',
        type=Path,
        default=Path('/home/yzhang/biomate/backend/database/galaxy_ai_tools.db'),
        help='Path to Galaxy AI tools database'
    )

    parser.add_argument(
        '--output',
        type=Path,
        default=Path('./blog_posts'),
        help='Output directory for blog posts'
    )

    parser.add_argument(
        '--anthropic-api-key',
        default=os.getenv('ANTHROPIC_API_KEY'),
        help='Anthropic API key (or set ANTHROPIC_API_KEY env var)'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Evaluate tools but do not generate blog posts'
    )

    parser.add_argument(
        '--no-auto-review',
        action='store_true',
        help='Disable iterative AI review of blog posts (enabled by default)'
    )

    args = parser.parse_args()

    if not args.anthropic_api_key:
        logger.error("Anthropic API key required. Set ANTHROPIC_API_KEY env var or use --anthropic-api-key")
        return 1

    if not args.all_new and not args.tool_ids:
        parser.print_help()
        return 1

    # Initialize workflow
    workflow = IntegratedBlogWorkflow(
        db_path=args.db_path,
        output_dir=args.output,
        anthropic_api_key=args.anthropic_api_key,
        dry_run=args.dry_run,
        enable_auto_review=not args.no_auto_review
    )

    # Process tools
    summary = workflow.process_tools(
        since_date=args.since,
        limit=args.limit,
        tool_ids=args.tool_ids
    )

    return 0


if __name__ == '__main__':
    exit(main())
