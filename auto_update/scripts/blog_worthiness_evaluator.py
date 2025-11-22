#!/usr/bin/env python3
"""
Blog Worthiness Evaluator - Uses Claude Haiku 4.5 to determine if a tool deserves a blog post

Evaluates tools based on:
- Specificity (reject general libraries like biopython)
- Biological meaningfulness
- Novel functionality
- Research impact potential

Uses prompt caching for efficiency when processing multiple tools.

Usage:
    python blog_worthiness_evaluator.py --tool-id auto_deepvariant
    python blog_worthiness_evaluator.py --batch --limit 10
"""

import argparse
import json
import logging
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import anthropic
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class BlogWorthinessEvaluator:
    """
    Evaluates whether a tool is worthy of a blog post using Claude.
    """

    def __init__(self, db_path: Path, anthropic_api_key: str):
        self.db_path = db_path
        self.conn = None
        self.client = anthropic.Anthropic(api_key=anthropic_api_key)

        # System prompt for evaluation (will be cached)
        self.system_prompt = [
            {
                "type": "text",
                "text": """You are a bioinformatics expert evaluating whether newly added tools deserve detailed blog posts.

EVALUATION CRITERIA:

✅ BLOG-WORTHY TOOLS:
- Specific, focused bioinformatics tools (e.g., DeepVariant for variant calling)
- Novel computational models (e.g., AlphaFold for structure prediction)
- Specialized datasets with clear biological purpose
- Tools solving specific research problems
- Methods with peer-reviewed publications
- Tools with clear input/output and biological workflow

❌ NOT BLOG-WORTHY:
- General programming libraries (e.g., Biopython, NumPy, Pandas)
- Generic containers or frameworks
- Low-level utilities without biological context
- Tools that are just wrappers around other tools
- Deprecated or unmaintained tools
- Tools with unclear biological purpose

EVALUATION OUTPUT:
Return JSON with:
{
  "worthy": true/false,
  "confidence": 0.0-1.0,
  "reason": "Brief explanation",
  "tool_type": "specific_tool|general_library|model|dataset|utility",
  "biological_focus": "clear|unclear|none",
  "recommended_action": "write_blog|skip|needs_review",
  "suggested_title": "Blog title if worthy, null otherwise"
}

Be strict: Only recommend blogs for tools that provide clear, specific biological value.""",
                "cache_control": {"type": "ephemeral"}
            }
        ]

    def connect(self):
        """Connect to database"""
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row

    def disconnect(self):
        """Disconnect from database"""
        if self.conn:
            self.conn.close()

    def get_tool(self, tool_id: str) -> Optional[Dict]:
        """Get tool data from database"""
        cursor = self.conn.execute(
            """SELECT tool_id, name, description, category,
               github_url, stars, quality_score, citations,
               edam_operations, scientific_context, language,
               inputs, outputs, help_text
            FROM tools WHERE tool_id = ?""",
            (tool_id,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None

    def get_new_tools(self, limit: Optional[int] = None) -> List[Dict]:
        """Get newly added tools"""
        query = """
            SELECT tool_id, name, description, category,
                   github_url, stars, quality_score
            FROM tools
            WHERE auto_discovered = 1
            ORDER BY discovery_date DESC
        """

        if limit:
            query += f" LIMIT {limit}"

        cursor = self.conn.execute(query)
        return [dict(row) for row in cursor.fetchall()]

    def evaluate_tool(self, tool: Dict) -> Dict:
        """
        Evaluate if tool is worthy of a blog post using Claude Haiku 4.5.

        Args:
            tool: Tool dictionary from database

        Returns:
            Evaluation result dictionary
        """
        # Prepare tool information for Claude
        tool_info = f"""
TOOL TO EVALUATE:

Name: {tool['name']}
Tool ID: {tool['tool_id']}
Description: {tool.get('description', 'No description')}
Category: {tool.get('category', 'Unknown')}
GitHub: {tool.get('github_url', 'N/A')}
Stars: {tool.get('stars', 0)}
Quality Score: {tool.get('quality_score', 0)}

Language: {tool.get('language', 'Unknown')}

Help Text:
{tool.get('help_text', 'No help text available')[:500]}

Citations: {tool.get('citations', 'None')}
EDAM Operations: {tool.get('edam_operations', 'None')}
Scientific Context: {tool.get('scientific_context', 'None')}

Inputs: {tool.get('inputs', 'Not specified')}
Outputs: {tool.get('outputs', 'Not specified')}

Based on this information, is this tool worthy of a detailed blog post?
"""

        try:
            # Call Claude Haiku 4.5 with prompt caching
            response = self.client.messages.create(
                model="claude-3-5-haiku-20241022",
                max_tokens=1024,
                system=self.system_prompt,
                messages=[
                    {
                        "role": "user",
                        "content": tool_info
                    }
                ]
            )

            # Parse response
            response_text = response.content[0].text

            # Extract JSON from response
            try:
                # Try to find JSON in response
                start = response_text.find('{')
                end = response_text.rfind('}') + 1
                if start != -1 and end > start:
                    result = json.loads(response_text[start:end])
                else:
                    # Fallback parsing
                    result = self._parse_fallback(response_text)

                # Add metadata
                result['tool_id'] = tool['tool_id']
                result['tool_name'] = tool['name']
                result['evaluated_at'] = datetime.now().isoformat()

                # Log cache performance
                usage = response.usage
                logger.info(f"Tool: {tool['name']}")
                logger.info(f"  Worthy: {result.get('worthy', False)}")
                logger.info(f"  Confidence: {result.get('confidence', 0):.2f}")
                logger.info(f"  Cache read tokens: {getattr(usage, 'cache_read_input_tokens', 0)}")
                logger.info(f"  Cache creation tokens: {getattr(usage, 'cache_creation_input_tokens', 0)}")
                logger.info(f"  Input tokens: {usage.input_tokens}")

                return result

            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse JSON from Claude response: {e}")
                return self._create_error_result(tool, "JSON parse error")

        except Exception as e:
            logger.error(f"Error evaluating tool {tool['tool_id']}: {e}")
            return self._create_error_result(tool, str(e))

    def _parse_fallback(self, text: str) -> Dict:
        """Fallback parser if JSON extraction fails"""
        worthy = "blog-worthy" in text.lower() or "recommend" in text.lower()

        return {
            "worthy": worthy,
            "confidence": 0.5,
            "reason": "Fallback parsing from text response",
            "tool_type": "unknown",
            "biological_focus": "unknown",
            "recommended_action": "needs_review",
            "suggested_title": None
        }

    def _create_error_result(self, tool: Dict, error: str) -> Dict:
        """Create error result"""
        return {
            "tool_id": tool['tool_id'],
            "tool_name": tool['name'],
            "worthy": False,
            "confidence": 0.0,
            "reason": f"Error: {error}",
            "tool_type": "error",
            "biological_focus": "unknown",
            "recommended_action": "needs_review",
            "suggested_title": None
        }

    def evaluate_batch(self, tool_ids: Optional[List[str]] = None, limit: Optional[int] = None) -> List[Dict]:
        """
        Evaluate multiple tools.

        Args:
            tool_ids: Specific tool IDs to evaluate
            limit: Limit number of tools to evaluate

        Returns:
            List of evaluation results
        """
        self.connect()

        try:
            if tool_ids:
                tools = [self.get_tool(tid) for tid in tool_ids]
                tools = [t for t in tools if t is not None]
            else:
                tools = self.get_new_tools(limit)

            results = []

            for tool in tools:
                logger.info(f"Evaluating: {tool['name']} ({tool['tool_id']})")
                result = self.evaluate_tool(tool)
                results.append(result)

            return results

        finally:
            self.disconnect()

    def save_results(self, results: List[Dict], output_path: Path):
        """Save evaluation results to JSON"""
        with open(output_path, 'w') as f:
            json.dump(results, f, indent=2)

        logger.info(f"Results saved to: {output_path}")

    def print_summary(self, results: List[Dict]):
        """Print evaluation summary"""
        worthy_count = sum(1 for r in results if r.get('worthy', False))
        skip_count = sum(1 for r in results if r.get('recommended_action') == 'skip')
        review_count = sum(1 for r in results if r.get('recommended_action') == 'needs_review')

        print("\n" + "="*80)
        print("BLOG WORTHINESS EVALUATION SUMMARY")
        print("="*80)
        print(f"Total tools evaluated: {len(results)}")
        print(f"Worthy of blog post: {worthy_count}")
        print(f"Should skip: {skip_count}")
        print(f"Needs manual review: {review_count}")
        print()

        if worthy_count > 0:
            print("RECOMMENDED FOR BLOG POSTS:")
            print("-" * 80)
            for r in results:
                if r.get('worthy'):
                    print(f"✅ {r['tool_name']} ({r['tool_id']})")
                    print(f"   Confidence: {r.get('confidence', 0):.2f}")
                    print(f"   Type: {r.get('tool_type', 'unknown')}")
                    print(f"   Reason: {r.get('reason', 'N/A')}")
                    if r.get('suggested_title'):
                        print(f"   Suggested Title: {r['suggested_title']}")
                    print()

        if skip_count > 0:
            print("SHOULD SKIP (General libraries, not specific tools):")
            print("-" * 80)
            for r in results:
                if r.get('recommended_action') == 'skip':
                    print(f"❌ {r['tool_name']} ({r['tool_id']})")
                    print(f"   Reason: {r.get('reason', 'N/A')}")
                    print()


def main():
    parser = argparse.ArgumentParser(
        description='Evaluate tools for blog worthiness using Claude Haiku 4.5'
    )

    parser.add_argument(
        '--tool-id',
        help='Evaluate specific tool'
    )

    parser.add_argument(
        '--batch',
        action='store_true',
        help='Evaluate multiple tools'
    )

    parser.add_argument(
        '--limit',
        type=int,
        default=10,
        help='Limit number of tools to evaluate (default: 10)'
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
        default=Path('./blog_worthiness_results.json'),
        help='Output file for evaluation results'
    )

    parser.add_argument(
        '--anthropic-api-key',
        default=os.getenv('ANTHROPIC_API_KEY'),
        help='Anthropic API key (or set ANTHROPIC_API_KEY env var)'
    )

    args = parser.parse_args()

    if not args.anthropic_api_key:
        logger.error("Anthropic API key required. Set ANTHROPIC_API_KEY env var or use --anthropic-api-key")
        return 1

    # Initialize evaluator
    evaluator = BlogWorthinessEvaluator(args.db_path, args.anthropic_api_key)

    if args.tool_id:
        # Evaluate single tool
        evaluator.connect()
        tool = evaluator.get_tool(args.tool_id)
        evaluator.disconnect()

        if not tool:
            logger.error(f"Tool not found: {args.tool_id}")
            return 1

        result = evaluator.evaluate_tool(tool)
        evaluator.save_results([result], args.output)
        evaluator.print_summary([result])

    elif args.batch:
        # Evaluate batch
        results = evaluator.evaluate_batch(limit=args.limit)
        evaluator.save_results(results, args.output)
        evaluator.print_summary(results)

    else:
        parser.print_help()

    return 0


if __name__ == '__main__':
    exit(main())
