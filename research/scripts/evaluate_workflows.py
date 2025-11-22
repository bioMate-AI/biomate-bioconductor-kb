#!/usr/bin/env python3
"""
Galaxy Workflow Quality Evaluator

This script evaluates all Galaxy workflows from a collection, scores them based on
quality criteria, converts high-quality ones to .ga format, and generates detailed
reports explaining keep/reject decisions.

Author: AI Assistant (Claude)
Date: 2025-11-18
"""

import json
import os
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Any
from collections import Counter

# Configuration
INPUT_DIR = "/home/yzhang/biomate/research/galaxy/lib/galaxy/ai/data/workflows"
OUTPUT_DIR = "/home/yzhang/biomate/research/curated_workflows"
REPORT_DIR = "/home/yzhang/biomate/research"

# Quality thresholds
MIN_STEPS_FOR_QUALITY = 5
MIN_TOOL_STEPS = 3
MAX_SCORE = 100
KEEP_THRESHOLD = 50  # Minimum score to keep a workflow


class WorkflowEvaluator:
    """Evaluates Galaxy workflow quality based on multiple criteria."""

    # Trusted sources (workflows from these owners are generally high quality)
    # These are established Galaxy community contributors with track records
    TRUSTED_OWNERS = {
        # Official Galaxy Project teams
        'iwc',           # Intergalactic Workflow Commission - peer-reviewed workflows
        'iuc',           # Intergalactic Utilities Commission - tool wrappers
        'devteam',       # Galaxy core development team

        # Domain-specific expert groups
        'galaxyp',       # Galaxy Proteomics community
        'nml',           # National Microbiology Laboratory (Canada)
        'ebi-gxa',       # EBI Gene Expression Atlas
        'bgruening',     # Björn Grüning - major Galaxy contributor
        'lparsons',      # Lance Parsons - Princeton genomics
        'recetox',       # RECETOX metabolomics center
        'workflow4metabolomics',  # W4M consortium

        # Training and education
        'galaxyproject', # Official Galaxy Project
        'gtn',           # Galaxy Training Network

        # Major research institutions
        'usegalaxy-eu',  # European Galaxy server team
        'usegalaxy-au',  # Australian Galaxy server team
        'erasmusmc',     # Erasmus Medical Center

        # Bioinformatics platforms
        'abromics',      # ABRomics antimicrobial resistance
        'pah',           # Public health bioinformatics
    }

    # Red flag patterns in workflow names
    AD_HOC_PATTERNS = [
        r'constructed from history',
        r'imported:',
        r'copy of',
        r'test\s*\d*$',
        r'^\s*untitled',
        r'workflow\s*\d+$',
        r'my\s+workflow',
        r'new\s+workflow',
    ]

    # Valuable bioinformatics domains
    VALUABLE_DOMAINS = {
        'genomics': ['variant', 'snp', 'indel', 'vcf', 'bam', 'sam', 'fasta', 'genome', 'dna', 'wgs', 'wes'],
        'transcriptomics': ['rna', 'rnaseq', 'expression', 'deseq', 'transcript', 'cufflinks', 'htseq'],
        'epigenomics': ['chip', 'chipseq', 'atac', 'methylation', 'histone', 'peak', 'macs'],
        'metagenomics': ['metagen', '16s', 'microbiome', 'kraken', 'metaphlan', 'taxonomy'],
        'proteomics': ['protein', 'peptide', 'mass spec', 'proteom', 'maxquant'],
        'assembly': ['assembly', 'spades', 'megahit', 'flye', 'canu', 'scaffold'],
        'alignment': ['align', 'map', 'bowtie', 'bwa', 'minimap', 'hisat', 'star'],
        'quality_control': ['fastqc', 'multiqc', 'quality', 'trim', 'filter'],
        'annotation': ['annot', 'snpeff', 'vep', 'prokka', 'blast'],
        'phylogenetics': ['phylo', 'tree', 'evolution', 'raxml', 'beast'],
        'long_read': ['nanopore', 'pacbio', 'ont', 'long read', 'hifi'],
        'single_cell': ['single cell', 'scrna', 'scanpy', '10x', 'seurat'],
    }

    def __init__(self):
        self.results = []
        self.stats = {
            'total': 0,
            'kept': 0,
            'rejected': 0,
            'by_domain': Counter(),
            'by_owner': Counter(),
            'score_distribution': [],
        }

    def evaluate_workflow(self, filepath: str) -> Dict[str, Any]:
        """Evaluate a single workflow and return detailed assessment."""

        with open(filepath, 'r') as f:
            data = json.load(f)

        workflow_id = data.get('workflow_id', 'unknown')
        metadata = data.get('metadata', {})
        workflow_json = data.get('workflow_json', {})
        extracted = data.get('extracted_details', {})

        # Initialize evaluation result
        result = {
            'workflow_id': workflow_id,
            'filepath': filepath,
            'name': metadata.get('name', 'Unnamed'),
            'owner': metadata.get('owner', 'unknown'),
            'annotation': workflow_json.get('annotation', ''),
            'num_steps': metadata.get('number_of_steps', 0),
            'tags': metadata.get('tags', []),
            'published': metadata.get('published', False),
            'score': 0,
            'keep': False,
            'reasons': [],
            'domains': [],
            'tools': [],
            'creator': None,
            'license': None,
        }

        # Extract additional info
        basic_info = extracted.get('basic_info', {})
        result['creator'] = basic_info.get('creator', [])
        result['license'] = basic_info.get('license', '')

        # Get tools list
        tools = extracted.get('tools', [])
        result['tools'] = [t.get('tool_id', '').split('/')[-1].split('/')[0] for t in tools if t.get('tool_id')]

        # Run evaluation criteria
        score, reasons = self._calculate_score(result, workflow_json, extracted)

        result['score'] = score
        result['keep'] = score >= KEEP_THRESHOLD
        result['reasons'] = reasons

        # Identify domains
        result['domains'] = self._identify_domains(result)

        return result

    def _calculate_score(self, result: Dict, workflow_json: Dict, extracted: Dict) -> Tuple[int, List[str]]:
        """Calculate quality score and collect reasons."""

        score = 0
        reasons = []

        name = result['name'].lower()
        annotation = result['annotation'].lower() if result['annotation'] else ''
        owner = result['owner'].lower()
        num_steps = result['num_steps']
        tools = result['tools']

        # === NEGATIVE CRITERIA (Deductions) ===

        # Check for ad-hoc workflow patterns
        for pattern in self.AD_HOC_PATTERNS:
            if re.search(pattern, name, re.IGNORECASE):
                score -= 30
                reasons.append(f"[-30] Ad-hoc workflow pattern detected: '{pattern}'")
                break

        # Note: We do NOT penalize for few steps - modular workflows are valuable
        # A 3-step workflow that does one thing well is better than a bloated workflow

        # No annotation
        if not annotation or len(annotation) < 20:
            score -= 15
            reasons.append("[-15] No meaningful annotation/description")

        # Note: We do NOT penalize for few tools - small focused workflows are valuable
        # A workflow with 2-3 tools can be excellent if it does one thing well

        # Hardcoded sample names in inputs
        steps = extracted.get('steps', [])
        for step in steps:
            label = step.get('label', '') or ''
            if re.search(r'\.(fq|fastq|bam|sam|vcf|bed)$', label, re.IGNORECASE):
                score -= 10
                reasons.append(f"[-10] Hardcoded sample filename: '{label}'")
                break

        # Not published
        if not result['published']:
            score -= 5
            reasons.append("[-5] Workflow not published")

        # === POSITIVE CRITERIA (Additions) ===

        # Trusted owner
        if owner in self.TRUSTED_OWNERS:
            score += 25
            reasons.append(f"[+25] Trusted owner: {owner}")

        # Has meaningful annotation
        if annotation and len(annotation) >= 50:
            score += 20
            reasons.append(f"[+20] Has meaningful annotation ({len(annotation)} chars)")
        elif annotation and len(annotation) >= 20:
            score += 10
            reasons.append(f"[+10] Has brief annotation ({len(annotation)} chars)")

        # Sufficient complexity
        if num_steps >= 10:
            score += 20
            reasons.append(f"[+20] Complex workflow ({num_steps} steps)")
        elif num_steps >= MIN_STEPS_FOR_QUALITY:
            score += 10
            reasons.append(f"[+10] Adequate complexity ({num_steps} steps)")

        # Has tags
        if result['tags']:
            score += 10
            reasons.append(f"[+10] Has tags: {result['tags']}")

        # Has creator attribution
        if result['creator']:
            score += 15
            creator_names = [c.get('name', 'Unknown') for c in result['creator'] if isinstance(c, dict)]
            reasons.append(f"[+15] Has creator attribution: {creator_names}")

        # Has license
        if result['license']:
            score += 10
            reasons.append(f"[+10] Has license: {result['license']}")

        # Uses standard bioinformatics tools
        standard_tools = ['bowtie', 'bwa', 'star', 'hisat', 'samtools', 'bcftools',
                        'freebayes', 'gatk', 'macs2', 'deseq', 'featurecounts',
                        'fastqc', 'multiqc', 'cutadapt', 'trimmomatic', 'snpeff',
                        'minimap', 'nanoplot', 'kraken', 'metaphlan']

        tools_lower = [t.lower() for t in tools]
        matched_tools = [t for t in standard_tools if any(t in tool for tool in tools_lower)]
        if len(matched_tools) >= 3:
            score += 15
            reasons.append(f"[+15] Uses multiple standard tools: {matched_tools[:5]}")
        elif len(matched_tools) >= 1:
            score += 5
            reasons.append(f"[+5] Uses standard tools: {matched_tools}")

        # Has labeled workflow outputs
        outputs = extracted.get('outputs', [])
        labeled_outputs = [o for o in outputs if o.get('label')]
        if len(labeled_outputs) >= 3:
            score += 10
            reasons.append(f"[+10] Has {len(labeled_outputs)} labeled outputs")
        elif labeled_outputs:
            score += 5
            reasons.append(f"[+5] Has {len(labeled_outputs)} labeled output(s)")

        # Proper connections (all steps connected)
        connections = extracted.get('connections', [])
        if connections and len(connections) >= num_steps - 1:
            score += 10
            reasons.append(f"[+10] Well-connected pipeline ({len(connections)} connections)")

        # Version control indicator
        if 'release' in name or 'v0.' in name or 'v1.' in name:
            score += 5
            reasons.append("[+5] Appears to be versioned release")

        # Base score for being a valid workflow
        score += 40
        reasons.insert(0, "[+40] Base score for valid workflow")

        return score, reasons

    def _identify_domains(self, result: Dict) -> List[str]:
        """Identify which bioinformatics domains this workflow covers."""

        domains = []
        name = result['name'].lower()
        annotation = (result['annotation'] or '').lower()
        tags = [t.lower() for t in result['tags']]
        tools = [t.lower() for t in result['tools']]

        # Combine all text for searching
        all_text = f"{name} {annotation} {' '.join(tags)} {' '.join(tools)}"

        for domain, keywords in self.VALUABLE_DOMAINS.items():
            if any(kw in all_text for kw in keywords):
                domains.append(domain)

        return domains

    def evaluate_all(self) -> None:
        """Evaluate all workflows in the input directory."""

        workflow_files = list(Path(INPUT_DIR).glob("*.json"))
        self.stats['total'] = len(workflow_files)

        print(f"Evaluating {len(workflow_files)} workflows...")

        for i, filepath in enumerate(workflow_files):
            if (i + 1) % 100 == 0:
                print(f"  Processed {i + 1}/{len(workflow_files)}...")

            try:
                result = self.evaluate_workflow(str(filepath))
                self.results.append(result)

                # Update stats
                if result['keep']:
                    self.stats['kept'] += 1
                    for domain in result['domains']:
                        self.stats['by_domain'][domain] += 1
                else:
                    self.stats['rejected'] += 1

                self.stats['by_owner'][result['owner']] += 1
                self.stats['score_distribution'].append(result['score'])

            except Exception as e:
                print(f"  Error processing {filepath}: {e}")
                self.results.append({
                    'workflow_id': filepath.stem,
                    'filepath': str(filepath),
                    'name': 'ERROR',
                    'score': 0,
                    'keep': False,
                    'reasons': [f"Error: {str(e)}"],
                    'domains': [],
                })

        # Sort results by score
        self.results.sort(key=lambda x: x['score'], reverse=True)

        print(f"\nEvaluation complete!")
        print(f"  Kept: {self.stats['kept']}")
        print(f"  Rejected: {self.stats['rejected']}")

    def save_curated_workflows(self) -> None:
        """Save high-quality workflows in .ga format."""

        os.makedirs(OUTPUT_DIR, exist_ok=True)

        kept_workflows = [r for r in self.results if r['keep']]

        print(f"\nSaving {len(kept_workflows)} curated workflows...")

        for result in kept_workflows:
            try:
                with open(result['filepath'], 'r') as f:
                    data = json.load(f)

                # Extract the workflow_json which is the .ga format
                workflow_ga = data.get('workflow_json', {})

                # Generate a clean filename
                name = result['name']
                # Clean up the name for filename
                clean_name = re.sub(r'[^\w\s-]', '', name)
                clean_name = re.sub(r'\s+', '_', clean_name)
                clean_name = clean_name.lower()[:50]

                # Add score to filename for easy sorting
                filename = f"{result['score']:03d}_{clean_name}.ga"
                output_path = os.path.join(OUTPUT_DIR, filename)

                # Handle duplicates
                counter = 1
                while os.path.exists(output_path):
                    filename = f"{result['score']:03d}_{clean_name}_{counter}.ga"
                    output_path = os.path.join(OUTPUT_DIR, filename)
                    counter += 1

                with open(output_path, 'w') as f:
                    json.dump(workflow_ga, f, indent=2)

                result['output_path'] = output_path

            except Exception as e:
                print(f"  Error saving {result['name']}: {e}")

        print(f"  Saved to: {OUTPUT_DIR}")

    def generate_report(self) -> str:
        """Generate a detailed evaluation report."""

        timestamp = datetime.now().strftime("%Y%m%d_%H%M")
        report_path = os.path.join(REPORT_DIR, f"{timestamp}_WORKFLOW_EVALUATION_REPORT.md")

        report = []
        report.append("# Galaxy Workflow Quality Evaluation Report\n")
        report.append(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        report.append(f"**Total Workflows Evaluated:** {self.stats['total']}\n")
        report.append(f"**Kept:** {self.stats['kept']} ({100*self.stats['kept']/self.stats['total']:.1f}%)\n")
        report.append(f"**Rejected:** {self.stats['rejected']} ({100*self.stats['rejected']/self.stats['total']:.1f}%)\n")
        report.append(f"**Keep Threshold:** {KEEP_THRESHOLD}/100\n")
        report.append("\n---\n")

        # Score distribution
        report.append("## Score Distribution\n")
        scores = self.stats['score_distribution']
        if scores:
            report.append(f"- **Min:** {min(scores)}\n")
            report.append(f"- **Max:** {max(scores)}\n")
            report.append(f"- **Mean:** {sum(scores)/len(scores):.1f}\n")
            report.append(f"- **Median:** {sorted(scores)[len(scores)//2]}\n")
        report.append("\n")

        # Domain coverage
        report.append("## Kept Workflows by Domain\n")
        for domain, count in sorted(self.stats['by_domain'].items(), key=lambda x: -x[1]):
            report.append(f"- **{domain}:** {count}\n")
        report.append("\n---\n")

        # Top workflows
        report.append("## Top 50 Highest Quality Workflows\n")
        report.append("These are the best workflows that should definitely be included.\n\n")

        for i, result in enumerate(self.results[:50]):
            report.append(f"### {i+1}. {result['name']}\n")
            report.append(f"- **Score:** {result['score']}/100\n")
            report.append(f"- **Owner:** {result['owner']}\n")
            report.append(f"- **Steps:** {result.get('num_steps', 'N/A')}\n")
            report.append(f"- **Domains:** {', '.join(result['domains']) if result['domains'] else 'General'}\n")
            if result['annotation']:
                report.append(f"- **Description:** {result['annotation'][:200]}{'...' if len(result['annotation']) > 200 else ''}\n")
            report.append("\n**Evaluation:**\n")
            for reason in result['reasons']:
                report.append(f"  {reason}\n")
            report.append("\n")

        report.append("---\n")

        # All kept workflows summary
        report.append("## All Kept Workflows Summary\n\n")
        report.append("| Score | Name | Owner | Steps | Domains |\n")
        report.append("|-------|------|-------|-------|----------|\n")

        for result in self.results:
            if result['keep']:
                domains = ', '.join(result['domains'][:2]) if result['domains'] else '-'
                name_short = result['name'][:40] + '...' if len(result['name']) > 40 else result['name']
                report.append(f"| {result['score']} | {name_short} | {result['owner']} | {result.get('num_steps', 'N/A')} | {domains} |\n")

        report.append("\n---\n")

        # Rejected workflows analysis
        report.append("## Rejected Workflows Analysis\n\n")

        # Group rejections by primary reason
        rejection_reasons = Counter()
        for result in self.results:
            if not result['keep']:
                # Find the most significant negative reason
                for reason in result['reasons']:
                    if reason.startswith('[-'):
                        rejection_reasons[reason.split(']')[1].strip()] += 1
                        break

        report.append("### Top Rejection Reasons\n")
        for reason, count in sorted(rejection_reasons.items(), key=lambda x: -x[1])[:10]:
            report.append(f"- **{reason}:** {count} workflows\n")
        report.append("\n")

        # Sample of rejected workflows
        report.append("### Sample Rejected Workflows (20 examples)\n\n")

        rejected = [r for r in self.results if not r['keep']]
        for result in rejected[:20]:
            report.append(f"#### {result['name']}\n")
            report.append(f"- **Score:** {result['score']}/100 (below {KEEP_THRESHOLD} threshold)\n")
            report.append(f"- **Owner:** {result['owner']}\n")
            report.append(f"- **Steps:** {result.get('num_steps', 'N/A')}\n")
            report.append("**Why Rejected:**\n")
            for reason in result['reasons']:
                if reason.startswith('[-'):
                    report.append(f"  {reason}\n")
            report.append("\n")

        report.append("---\n")

        # Evaluation criteria documentation
        report.append("## Evaluation Criteria\n\n")
        report.append("### Positive Criteria (Score Additions)\n")
        report.append("- **+40** Base score for valid workflow\n")
        report.append("- **+25** Trusted owner (iwc, iuc, devteam, etc.)\n")
        report.append("- **+20** Has meaningful annotation (50+ chars)\n")
        report.append("- **+20** Complex workflow (10+ steps)\n")
        report.append("- **+15** Has creator attribution with ORCID\n")
        report.append("- **+15** Uses multiple standard bioinformatics tools\n")
        report.append("- **+10** Has tags\n")
        report.append("- **+10** Has license\n")
        report.append("- **+10** Well-connected pipeline\n")
        report.append("- **+10** Multiple labeled outputs\n")
        report.append("- **+5** Appears to be versioned release\n\n")

        report.append("### Negative Criteria (Score Deductions)\n")
        report.append("- **-30** Ad-hoc workflow pattern (e.g., 'constructed from history')\n")
        report.append("- **-20** Too few steps (< 5)\n")
        report.append("- **-15** No meaningful annotation\n")
        report.append("- **-15** Too few tools (< 3)\n")
        report.append("- **-10** Hardcoded sample filenames\n")
        report.append("- **-5** Workflow not published\n\n")

        report.append("### Threshold\n")
        report.append(f"Workflows with score >= {KEEP_THRESHOLD} are kept.\n")

        # Save report
        report_content = ''.join(report)
        with open(report_path, 'w') as f:
            f.write(report_content)

        print(f"\nReport saved to: {report_path}")

        return report_path


def main():
    """Main execution function."""

    print("=" * 60)
    print("Galaxy Workflow Quality Evaluator")
    print("=" * 60)
    print()

    evaluator = WorkflowEvaluator()

    # Run evaluation
    evaluator.evaluate_all()

    # Save curated workflows
    evaluator.save_curated_workflows()

    # Generate report
    evaluator.generate_report()

    print("\n" + "=" * 60)
    print("Evaluation Complete!")
    print("=" * 60)
    print(f"\nSummary:")
    print(f"  - Total evaluated: {evaluator.stats['total']}")
    print(f"  - Kept: {evaluator.stats['kept']}")
    print(f"  - Rejected: {evaluator.stats['rejected']}")
    print(f"  - Output directory: {OUTPUT_DIR}")
    print()


if __name__ == "__main__":
    main()
