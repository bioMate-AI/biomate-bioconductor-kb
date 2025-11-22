#!/usr/bin/env python3
"""
Blog Review Agent - Iteratively audits and improves blog posts

This agent:
1. Reviews generated blog posts for quality issues
2. Identifies specific problems and suggests fixes
3. Automatically improves the blog post
4. Decides when the blog is ready for manual review
5. Iterates until quality threshold is met (max 5 iterations)

Uses Claude Haiku 4.5 for fast, cost-effective review.

Usage:
    python blog_review_agent.py --blog-file auto_foldseek_blog.md --tool-id auto_foldseek
    python blog_review_agent.py --batch --blog-dir ./blog_posts
"""

import argparse
import json
import logging
import os
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import anthropic

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class BlogReviewAgent:
    """
    Autonomous agent that reviews and improves blog posts iteratively.
    """

    def __init__(self, db_path: Path, anthropic_api_key: str):
        self.db_path = db_path
        self.client = anthropic.Anthropic(api_key=anthropic_api_key)
        self.max_iterations = 5  # Prevent infinite loops

        # System prompt for review agent (with caching)
        self.review_system_prompt = [
            {
                "type": "text",
                "text": """You are a technical writing expert reviewing bioinformatics tool blog posts.

REVIEW CRITERIA:

1. **Clarity & Specificity**
   - Is the tool's purpose immediately clear?
   - Are input/output formats specific?
   - Are workflow examples realistic and detailed?
   - Avoid vague language like "can be used for" or "helps with"

2. **Technical Accuracy**
   - Are biological concepts explained correctly?
   - Are workflow integrations technically sound?
   - Are example commands/workflows executable?

3. **Audience Appropriateness**
   - Written for researchers (not beginners)
   - Assumes bioinformatics knowledge
   - Focuses on scientific value, not basic usage

4. **Completeness**
   - All sections present and substantive
   - Real examples, not generic placeholders
   - Specific use cases mentioned

5. **Engagement**
   - Compelling introduction
   - Clear value proposition
   - Practical workflow examples

REVIEW OUTPUT:

Return JSON with:
{
  "ready_for_review": true/false,
  "quality_score": 0.0-1.0,
  "issues": [
    {
      "section": "Introduction|Significance|Input/Output|Workflow|Overall",
      "severity": "critical|major|minor",
      "issue": "Specific problem description",
      "suggestion": "How to fix it"
    }
  ],
  "strengths": ["What the blog does well"],
  "decision_reason": "Why ready or not ready for manual review",
  "iteration_needed": true/false
}

**Decision Criteria:**
- quality_score >= 0.85 AND no critical issues → ready_for_review: true
- quality_score < 0.85 OR critical issues exist → ready_for_review: false
- If no improvements possible → ready_for_review: true (submit as-is)

Be strict but constructive. Focus on actionable improvements.""",
                "cache_control": {"type": "ephemeral"}
            }
        ]

        # System prompt for improvement agent
        self.improvement_system_prompt = [
            {
                "type": "text",
                "text": """You are a technical writing expert improving bioinformatics blog posts.

Given a blog post and review feedback, rewrite the blog to address all issues.

IMPROVEMENT GUIDELINES:

1. **Be Specific**
   - Replace vague descriptions with concrete examples
   - Add specific biological contexts
   - Include real workflow scenarios

2. **Enhance Technical Depth**
   - Explain biological significance
   - Detail input/output formats
   - Provide executable workflow examples

3. **Maintain Structure**
   - Keep the same section headings
   - Preserve markdown formatting
   - Keep Try Now links intact

4. **Add Value**
   - Include specific use cases
   - Mention related tools/datasets
   - Provide context for when to use this tool

OUTPUT FORMAT:
Return the complete improved blog post in markdown format.
Do NOT include explanations or meta-commentary.
Just return the improved markdown blog post.""",
                "cache_control": {"type": "ephemeral"}
            }
        ]

    def get_tool_metadata(self, tool_id: str) -> Optional[Dict]:
        """Get detailed tool metadata from database"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row

        cursor = conn.execute(
            """SELECT * FROM tools WHERE tool_id = ?""",
            (tool_id,)
        )
        row = cursor.fetchone()
        conn.close()

        return dict(row) if row else None

    def review_blog(self, blog_content: str, tool_metadata: Dict) -> Dict:
        """
        Review blog post and return quality assessment.

        Args:
            blog_content: Markdown content of blog post
            tool_metadata: Tool metadata from database

        Returns:
            Review result dictionary
        """
        review_prompt = f"""Review this bioinformatics tool blog post:

TOOL METADATA:
Name: {tool_metadata.get('name', 'Unknown')}
Category: {tool_metadata.get('category', 'Unknown')}
Description: {tool_metadata.get('description', 'No description')}
Stars: {tool_metadata.get('stars', 0)}

BLOG POST:
{blog_content}

Provide a detailed review based on the criteria above."""

        try:
            response = self.client.messages.create(
                model="claude-3-5-haiku-20241022",
                max_tokens=2048,
                system=self.review_system_prompt,
                messages=[
                    {"role": "user", "content": review_prompt}
                ]
            )

            response_text = response.content[0].text

            # Extract JSON from response
            start = response_text.find('{')
            end = response_text.rfind('}') + 1

            if start != -1 and end > start:
                result = json.loads(response_text[start:end])
            else:
                # Fallback
                result = {
                    "ready_for_review": False,
                    "quality_score": 0.5,
                    "issues": [{"section": "Overall", "severity": "major",
                               "issue": "Could not parse review",
                               "suggestion": "Retry review"}],
                    "strengths": [],
                    "decision_reason": "Review parsing failed",
                    "iteration_needed": True
                }

            # Log review results
            logger.info(f"Review Quality Score: {result.get('quality_score', 0):.2f}")
            logger.info(f"Ready for Review: {result.get('ready_for_review', False)}")
            logger.info(f"Issues Found: {len(result.get('issues', []))}")

            return result

        except Exception as e:
            logger.error(f"Error reviewing blog: {e}")
            return {
                "ready_for_review": False,
                "quality_score": 0.0,
                "issues": [{"section": "Overall", "severity": "critical",
                           "issue": f"Review error: {e}",
                           "suggestion": "Manual review required"}],
                "strengths": [],
                "decision_reason": f"Error: {e}",
                "iteration_needed": False
            }

    def improve_blog(self, blog_content: str, review_result: Dict, tool_metadata: Dict) -> str:
        """
        Improve blog post based on review feedback.

        Args:
            blog_content: Current blog markdown
            review_result: Review feedback
            tool_metadata: Tool metadata

        Returns:
            Improved blog markdown
        """
        # Format issues for the improvement prompt
        issues_text = "\n".join([
            f"- [{issue['severity'].upper()}] {issue['section']}: {issue['issue']}\n  → Suggested fix: {issue['suggestion']}"
            for issue in review_result.get('issues', [])
        ])

        improvement_prompt = f"""Improve this blog post based on the review feedback:

TOOL METADATA:
Name: {tool_metadata.get('name', 'Unknown')}
Category: {tool_metadata.get('category', 'Unknown')}
Description: {tool_metadata.get('description', 'No description')}
GitHub: {tool_metadata.get('github_url', 'N/A')}
Stars: {tool_metadata.get('stars', 0)}

CURRENT BLOG POST:
{blog_content}

REVIEW FEEDBACK:
Quality Score: {review_result.get('quality_score', 0):.2f}

Issues to Fix:
{issues_text}

Strengths to Preserve:
{', '.join(review_result.get('strengths', []))}

Rewrite the blog post addressing all issues while preserving strengths.
Return ONLY the improved markdown blog post."""

        try:
            response = self.client.messages.create(
                model="claude-3-5-haiku-20241022",
                max_tokens=4096,
                system=self.improvement_system_prompt,
                messages=[
                    {"role": "user", "content": improvement_prompt}
                ]
            )

            improved_content = response.content[0].text.strip()

            # Remove markdown code block markers if present
            if improved_content.startswith('```markdown'):
                improved_content = improved_content.replace('```markdown', '', 1)
            if improved_content.startswith('```'):
                improved_content = improved_content.replace('```', '', 1)
            if improved_content.endswith('```'):
                improved_content = improved_content.rsplit('```', 1)[0]

            improved_content = improved_content.strip()

            return improved_content

        except Exception as e:
            logger.error(f"Error improving blog: {e}")
            return blog_content  # Return original on error

    def iterative_review_and_improve(
        self,
        initial_blog: str,
        tool_id: str,
        tool_metadata: Dict,
        versions_dir: Path = None
    ) -> Tuple[str, List[Dict], bool]:
        """
        Iteratively review and improve blog until ready or max iterations reached.

        Args:
            initial_blog: Initial blog markdown
            tool_id: Tool identifier
            tool_metadata: Tool metadata from database
            versions_dir: Directory to save all intermediate versions

        Returns:
            Tuple of (final_blog, iteration_history, ready_for_review)
        """
        current_blog = initial_blog
        iteration_history = []

        # Create versions directory if provided
        if versions_dir:
            versions_dir.mkdir(parents=True, exist_ok=True)

            # Save initial version
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            initial_path = versions_dir / f"{tool_id}_v0_initial_{timestamp}.md"
            with open(initial_path, 'w') as f:
                f.write(initial_blog)
            logger.info(f"Saved initial version: {initial_path}")

        logger.info("="*80)
        logger.info(f"Starting Iterative Review for {tool_id}")
        logger.info("="*80)

        for iteration in range(1, self.max_iterations + 1):
            logger.info(f"\n--- Iteration {iteration}/{self.max_iterations} ---")

            # Review current blog
            review_result = self.review_blog(current_blog, tool_metadata)

            iteration_record = {
                "iteration": iteration,
                "quality_score": review_result.get("quality_score", 0),
                "ready_for_review": review_result.get("ready_for_review", False),
                "issues_found": len(review_result.get("issues", [])),
                "critical_issues": len([
                    i for i in review_result.get("issues", [])
                    if i.get("severity") == "critical"
                ]),
                "decision_reason": review_result.get("decision_reason", ""),
                "review_details": review_result
            }

            iteration_history.append(iteration_record)

            # Log iteration results
            logger.info(f"Quality Score: {iteration_record['quality_score']:.2f}")
            logger.info(f"Issues Found: {iteration_record['issues_found']} "
                       f"(Critical: {iteration_record['critical_issues']})")
            logger.info(f"Decision: {review_result.get('decision_reason', '')}")

            # Check if ready for manual review
            if review_result.get("ready_for_review", False):
                # Save final approved version
                if versions_dir:
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    final_path = versions_dir / f"{tool_id}_v{iteration}_final_approved_{timestamp}.md"
                    with open(final_path, 'w') as f:
                        f.write(current_blog)
                    logger.info(f"Saved final approved version: {final_path}")

                logger.info(f"\n✓ Blog ready for manual review after {iteration} iteration(s)")
                logger.info(f"  Final quality score: {iteration_record['quality_score']:.2f}")
                return current_blog, iteration_history, True

            # Check if we should continue iterating
            if not review_result.get("iteration_needed", True):
                logger.info(f"\n⚠ No further improvements possible after {iteration} iteration(s)")
                logger.info(f"  Submitting for manual review with score: {iteration_record['quality_score']:.2f}")
                return current_blog, iteration_history, False

            # Check if max iterations reached
            if iteration >= self.max_iterations:
                logger.info(f"\n⚠ Max iterations ({self.max_iterations}) reached")
                logger.info(f"  Submitting for manual review with score: {iteration_record['quality_score']:.2f}")
                return current_blog, iteration_history, False

            # Improve blog for next iteration
            logger.info(f"Improving blog post...")
            improved_blog = self.improve_blog(current_blog, review_result, tool_metadata)

            # Check if improvement actually changed the blog
            if improved_blog.strip() == current_blog.strip():
                logger.info(f"\n⚠ No changes made in improvement step")
                logger.info(f"  Submitting for manual review with score: {iteration_record['quality_score']:.2f}")
                return current_blog, iteration_history, False

            current_blog = improved_blog

            # Save improved version
            if versions_dir:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                phase = f"iteration_{iteration}"
                improved_path = versions_dir / f"{tool_id}_v{iteration}_{phase}_{timestamp}.md"
                with open(improved_path, 'w') as f:
                    f.write(improved_blog)
                logger.info(f"Saved {phase} version: {improved_path}")

                # Also save the review result
                review_path = versions_dir / f"{tool_id}_v{iteration}_{phase}_review_{timestamp}.json"
                with open(review_path, 'w') as f:
                    json.dump(review_result, f, indent=2)

            logger.info(f"✓ Blog improved, proceeding to iteration {iteration + 1}")

        # Should not reach here, but just in case
        return current_blog, iteration_history, False

    def process_blog(
        self,
        blog_path: Path,
        tool_id: str,
        output_dir: Path
    ) -> Dict:
        """
        Process a single blog post through iterative review.

        Args:
            blog_path: Path to initial blog markdown
            tool_id: Tool identifier
            output_dir: Directory for output files

        Returns:
            Processing summary dictionary
        """
        # Read initial blog
        with open(blog_path, 'r') as f:
            initial_blog = f.read()

        # Get tool metadata
        tool_metadata = self.get_tool_metadata(tool_id)
        if not tool_metadata:
            logger.error(f"Tool not found in database: {tool_id}")
            return {
                "success": False,
                "error": "Tool not found in database"
            }

        # Iterative review and improvement
        final_blog, iteration_history, ready = self.iterative_review_and_improve(
            initial_blog,
            tool_id,
            tool_metadata
        )

        # Save final blog
        output_dir.mkdir(parents=True, exist_ok=True)
        final_blog_path = output_dir / f"{tool_id}_blog_reviewed.md"

        with open(final_blog_path, 'w') as f:
            f.write(final_blog)

        # Save iteration history
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        history_path = output_dir / "review_history" / f"{tool_id}_review_{timestamp}.json"
        history_path.parent.mkdir(parents=True, exist_ok=True)

        review_summary = {
            "tool_id": tool_id,
            "tool_name": tool_metadata.get("name", "Unknown"),
            "timestamp": timestamp,
            "iterations": len(iteration_history),
            "final_quality_score": iteration_history[-1]["quality_score"] if iteration_history else 0,
            "ready_for_manual_review": ready,
            "initial_blog_path": str(blog_path),
            "final_blog_path": str(final_blog_path),
            "iteration_history": iteration_history
        }

        with open(history_path, 'w') as f:
            json.dump(review_summary, f, indent=2)

        logger.info(f"\n✓ Final blog saved: {final_blog_path}")
        logger.info(f"✓ Review history saved: {history_path}")

        return review_summary


def main():
    parser = argparse.ArgumentParser(
        description='Iteratively review and improve blog posts with AI'
    )

    parser.add_argument(
        '--blog-file',
        type=Path,
        help='Path to blog markdown file to review'
    )

    parser.add_argument(
        '--tool-id',
        help='Tool ID for the blog post'
    )

    parser.add_argument(
        '--batch',
        action='store_true',
        help='Process all blogs in a directory'
    )

    parser.add_argument(
        '--blog-dir',
        type=Path,
        default=Path('./blog_posts'),
        help='Directory containing blog posts (for batch mode)'
    )

    parser.add_argument(
        '--output',
        type=Path,
        default=Path('./blog_posts_reviewed'),
        help='Output directory for reviewed blogs'
    )

    parser.add_argument(
        '--db-path',
        type=Path,
        default=Path('/home/yzhang/biomate/backend/database/galaxy_ai_tools.db'),
        help='Path to Galaxy AI tools database'
    )

    parser.add_argument(
        '--anthropic-api-key',
        default=os.getenv('ANTHROPIC_API_KEY'),
        help='Anthropic API key'
    )

    args = parser.parse_args()

    if not args.anthropic_api_key:
        logger.error("Anthropic API key required")
        return 1

    # Initialize agent
    agent = BlogReviewAgent(args.db_path, args.anthropic_api_key)

    if args.batch:
        # Process all blogs in directory
        blog_files = list(args.blog_dir.glob("auto_*_blog.md"))
        logger.info(f"Found {len(blog_files)} blog files to review")

        summaries = []
        for blog_file in blog_files:
            # Extract tool_id from filename
            tool_id = blog_file.stem.replace('_blog', '')

            logger.info(f"\n{'='*80}")
            logger.info(f"Processing: {tool_id}")
            logger.info(f"{'='*80}")

            summary = agent.process_blog(blog_file, tool_id, args.output)
            summaries.append(summary)

        # Print summary
        print("\n" + "="*80)
        print("BATCH REVIEW SUMMARY")
        print("="*80)
        print(f"Total blogs processed: {len(summaries)}")

        ready_count = sum(1 for s in summaries if s.get('ready_for_manual_review', False))
        print(f"Ready for manual review: {ready_count}")
        print(f"Needs attention: {len(summaries) - ready_count}")

        avg_iterations = sum(s.get('iterations', 0) for s in summaries) / len(summaries) if summaries else 0
        print(f"Average iterations: {avg_iterations:.1f}")

        avg_quality = sum(s.get('final_quality_score', 0) for s in summaries) / len(summaries) if summaries else 0
        print(f"Average quality score: {avg_quality:.2f}")

    elif args.blog_file and args.tool_id:
        # Process single blog
        summary = agent.process_blog(args.blog_file, args.tool_id, args.output)
        print(json.dumps(summary, indent=2))

    else:
        parser.print_help()
        return 1

    return 0


if __name__ == '__main__':
    exit(main())
