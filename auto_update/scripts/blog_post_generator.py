#!/usr/bin/env python3
"""
Blog Post Generator for Auto-Discovered Tools

Generates engaging blog posts for newly added bioinformatics tools, including:
- Concise introduction and significance
- Input/output descriptions
- Workflow integration suggestions
- Direct workflow link with authentication check

Usage:
    python blog_post_generator.py --tool-id auto_biopython --output blog_posts/
    python blog_post_generator.py --all-new --since 2025-11-01
"""

import argparse
import json
import logging
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class BlogPostGenerator:
    """
    Generates blog posts for bioinformatics tools.
    """

    def __init__(self, db_path: Path, output_dir: Path):
        self.db_path = db_path
        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.conn = None

    def connect(self):
        """Connect to database"""
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row

    def disconnect(self):
        """Disconnect from database"""
        if self.conn:
            self.conn.close()

    def get_new_tools(self, since_date: Optional[str] = None) -> List[Dict]:
        """
        Get newly added tools.

        Args:
            since_date: ISO date string (e.g., '2025-11-01')

        Returns:
            List of tool dictionaries
        """
        query = """
            SELECT *
            FROM tools
            WHERE auto_discovered = 1
        """

        if since_date:
            query += f" AND discovery_date >= '{since_date}'"

        query += " ORDER BY discovery_date DESC"

        cursor = self.conn.execute(query)
        tools = [dict(row) for row in cursor.fetchall()]

        logger.info(f"Found {len(tools)} new tools")
        return tools

    def get_tool_by_id(self, tool_id: str) -> Optional[Dict]:
        """Get tool by ID"""
        cursor = self.conn.execute(
            "SELECT * FROM tools WHERE tool_id = ?",
            (tool_id,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None

    def _parse_inputs(self, inputs_json: Optional[str]) -> List[Dict]:
        """Parse inputs from JSON"""
        if not inputs_json:
            return []

        try:
            inputs = json.loads(inputs_json)
            if isinstance(inputs, list):
                # Handle both list of dicts and list of strings
                return [
                    inp if isinstance(inp, dict) else {'name': inp, 'format': 'Any', 'optional': False}
                    for inp in inputs
                ]
            return []
        except:
            return []

    def _parse_outputs(self, outputs_json: Optional[str]) -> List[Dict]:
        """Parse outputs from JSON"""
        if not outputs_json:
            return []

        try:
            outputs = json.loads(outputs_json)
            if isinstance(outputs, list):
                # Handle both list of dicts and list of strings
                return [
                    out if isinstance(out, dict) else {'name': out, 'format': 'Any'}
                    for out in outputs
                ]
            return []
        except:
            return []

    def _generate_introduction(self, tool: Dict) -> str:
        """Generate introduction section"""
        name = tool['name']
        description = tool.get('description', 'A bioinformatics tool')
        category = tool.get('category', 'Analysis')
        github_url = tool.get('github_url', '')
        stars = tool.get('stars', 0)

        intro = f"# {name}\n\n"
        intro += f"**Category**: {category}\n\n"

        if github_url:
            intro += f"**Source**: [GitHub Repository]({github_url})"
            if stars:
                intro += f" ⭐ {stars} stars"
            intro += "\n\n"

        intro += f"## Introduction\n\n{description}\n\n"

        return intro

    def _generate_significance(self, tool: Dict) -> str:
        """Generate significance section"""
        significance = "## Why This Tool Matters\n\n"

        # Use scientific context if available
        scientific_context = tool.get('scientific_context', '')
        if scientific_context:
            try:
                context = json.loads(scientific_context)
                if isinstance(context, dict):
                    if 'biological_domain' in context:
                        significance += f"**Biological Domain**: {context['biological_domain']}\n\n"
                    if 'research_areas' in context:
                        areas = ', '.join(context['research_areas'])
                        significance += f"**Research Applications**: {areas}\n\n"
            except:
                pass

        # Add quality score if high
        quality_score = tool.get('quality_score')
        if quality_score and quality_score >= 0.7:
            significance += f"**Quality Score**: {quality_score:.2f}/1.00 - Highly vetted and well-maintained\n\n"

        # Add EDAM operations
        edam_ops = tool.get('edam_operations', '')
        if edam_ops:
            try:
                ops = json.loads(edam_ops)
                if ops:
                    ops_list = ', '.join(ops)
                    significance += f"**EDAM Operations**: {ops_list}\n\n"
            except:
                pass

        # Add citations if available
        citations = tool.get('citations', '')
        if citations:
            try:
                cites = json.loads(citations)
                if cites and len(cites) > 0:
                    significance += f"**Peer-Reviewed**: {len(cites)} scientific publication(s)\n\n"
            except:
                pass

        return significance

    def _generate_io_section(self, tool: Dict) -> str:
        """Generate input/output section"""
        section = "## Input and Output\n\n"

        # Parse inputs
        inputs = self._parse_inputs(tool.get('inputs'))
        if inputs:
            section += "### Inputs\n\n"
            for inp in inputs:
                name = inp.get('name', 'Unknown')
                format_type = inp.get('format', 'Any')
                optional = inp.get('optional', False)
                req = "Optional" if optional else "Required"

                section += f"- **{name}** ({format_type}) - {req}\n"

                if 'description' in inp:
                    section += f"  - {inp['description']}\n"

            section += "\n"

        # Parse outputs
        outputs = self._parse_outputs(tool.get('outputs'))
        if outputs:
            section += "### Outputs\n\n"
            for out in outputs:
                name = out.get('name', 'Unknown')
                format_type = out.get('format', 'Any')

                section += f"- **{name}** ({format_type})\n"

                if 'description' in out:
                    section += f"  - {out['description']}\n"

            section += "\n"

        return section

    def _suggest_workflow_integrations(self, tool: Dict) -> str:
        """Suggest workflow integrations"""
        section = "## Workflow Integration\n\n"

        category = tool.get('category', '')
        tool_name = tool['name']

        # Category-based suggestions
        if 'quality' in category.lower() or 'qc' in category.lower():
            section += f"{tool_name} works seamlessly in quality control pipelines:\n\n"
            section += "1. **Pre-processing Stage**: Run after data import to validate input quality\n"
            section += "2. **Multi-QC Integration**: Combine with MultiQC for comprehensive reports\n"
            section += "3. **Filtering Pipeline**: Use QC results to filter low-quality samples\n\n"

        elif 'variant' in category.lower():
            section += f"{tool_name} integrates into variant calling workflows:\n\n"
            section += "1. **Alignment → Variant Calling**: Connect with aligners like BWA or Bowtie2\n"
            section += "2. **Annotation Pipeline**: Chain with variant annotation tools (VEP, SnpEff)\n"
            section += "3. **Filtering → Analysis**: Export to downstream statistical analysis\n\n"

        elif 'sequence' in category.lower() or 'alignment' in category.lower():
            section += f"{tool_name} fits into sequence analysis workflows:\n\n"
            section += "1. **QC → Alignment → Analysis**: Standard NGS pipeline integration\n"
            section += "2. **Multi-Sample Processing**: Batch process multiple datasets in parallel\n"
            section += "3. **Format Conversion**: Use as intermediate step for format compatibility\n\n"

        elif 'rna' in category.lower() or 'expression' in category.lower():
            section += f"{tool_name} enhances RNA-seq workflows:\n\n"
            section += "1. **Quantification Pipeline**: Connect with mapping and counting tools\n"
            section += "2. **Differential Expression**: Feed results into DESeq2 or edgeR\n"
            section += "3. **Visualization**: Export for plotting with R or Python tools\n\n"

        else:
            section += f"{tool_name} can be integrated into various workflows:\n\n"
            section += "1. **Data Preparation**: Use in preprocessing stages\n"
            section += "2. **Analysis Pipeline**: Connect with complementary tools\n"
            section += "3. **Results Processing**: Chain with downstream analysis steps\n\n"

        # Add example workflow
        section += "### Example Workflow\n\n"
        section += "```\n"
        section += "Input Data → Quality Control → " + tool_name + " → Downstream Analysis → Visualization\n"
        section += "```\n\n"

        return section

    def _generate_try_link(self, tool: Dict) -> str:
        """Generate try now section with workflow link"""
        tool_id = tool['tool_id']
        tool_name = tool['name']

        section = "## Try It Now\n\n"
        section += f"Ready to explore {tool_name}? Click the button below to launch an interactive workflow:\n\n"

        # Generate workflow link (will be handled by frontend)
        section += f"[🚀 Try {tool_name} Now](/workflow/try/{tool_id})\n\n"

        section += "*Note: You'll be redirected to the workflow builder with this tool pre-loaded. "
        section += "Login required for full access.*\n\n"

        return section

    def generate_blog_post(self, tool: Dict) -> str:
        """
        Generate complete blog post for a tool.

        Args:
            tool: Tool dictionary from database

        Returns:
            Markdown blog post
        """
        blog_post = ""

        # Header
        blog_post += self._generate_introduction(tool)

        # Significance
        blog_post += self._generate_significance(tool)

        # Input/Output
        blog_post += self._generate_io_section(tool)

        # Workflow Integration
        blog_post += self._suggest_workflow_integrations(tool)

        # Try Now Link
        blog_post += self._generate_try_link(tool)

        # Footer
        blog_post += "---\n\n"
        blog_post += f"*Tool added on {tool.get('discovery_date', 'N/A')}*\n"
        blog_post += f"*Blog post auto-generated from tool metadata*\n"

        return blog_post

    def save_blog_post(self, tool_id: str, content: str, format: str = 'md'):
        """Save blog post to file"""
        filename = f"{tool_id}_blog.{format}"
        output_path = self.output_dir / filename

        with open(output_path, 'w') as f:
            f.write(content)

        logger.info(f"Blog post saved: {output_path}")

        # Also save as JSON for API consumption
        json_path = self.output_dir / f"{tool_id}_blog.json"
        blog_data = {
            'tool_id': tool_id,
            'content': content,
            'format': format,
            'generated_at': datetime.now().isoformat()
        }

        with open(json_path, 'w') as f:
            json.dump(blog_data, f, indent=2)

    def generate_all_new_tools(self, since_date: Optional[str] = None):
        """Generate blog posts for all new tools"""
        self.connect()

        try:
            tools = self.get_new_tools(since_date)

            for tool in tools:
                logger.info(f"Generating blog post for: {tool['tool_id']}")

                blog_content = self.generate_blog_post(tool)
                self.save_blog_post(tool['tool_id'], blog_content)

            logger.info(f"Generated {len(tools)} blog posts")

        finally:
            self.disconnect()

    def generate_single_tool(self, tool_id: str):
        """Generate blog post for a single tool"""
        self.connect()

        try:
            tool = self.get_tool_by_id(tool_id)

            if not tool:
                logger.error(f"Tool not found: {tool_id}")
                return

            logger.info(f"Generating blog post for: {tool_id}")

            blog_content = self.generate_blog_post(tool)
            self.save_blog_post(tool_id, blog_content)

        finally:
            self.disconnect()


def main():
    parser = argparse.ArgumentParser(
        description='Generate blog posts for auto-discovered tools'
    )

    parser.add_argument(
        '--tool-id',
        help='Generate blog post for specific tool'
    )

    parser.add_argument(
        '--all-new',
        action='store_true',
        help='Generate blog posts for all new tools'
    )

    parser.add_argument(
        '--since',
        help='Only include tools added since this date (YYYY-MM-DD)'
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

    args = parser.parse_args()

    # Initialize generator
    generator = BlogPostGenerator(args.db_path, args.output)

    if args.tool_id:
        generator.generate_single_tool(args.tool_id)
    elif args.all_new:
        generator.generate_all_new_tools(args.since)
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
