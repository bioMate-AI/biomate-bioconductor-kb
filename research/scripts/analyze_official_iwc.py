#!/usr/bin/env python3
"""
Analyze official IWC workflows for BioMate.

Creates a comprehensive quality report of the official IWC workflows.
"""

import json
import os
from pathlib import Path
from collections import defaultdict
from datetime import datetime

WORKFLOWS_DIR = "/home/yzhang/biomate/backend/galaxy_workflows_official_iwc"
OUTPUT_DIR = "/home/yzhang/biomate/research"


def analyze_workflows():
    """Analyze all official IWC workflows."""

    results = []
    domains = defaultdict(list)
    tools_used = defaultdict(int)

    for ga_file in Path(WORKFLOWS_DIR).rglob("*.ga"):
        try:
            with open(ga_file, 'r') as f:
                workflow = json.load(f)

            # Extract metadata
            name = workflow.get('name', ga_file.stem)
            annotation = workflow.get('annotation', '')
            license_info = workflow.get('license', 'None')
            creator = workflow.get('creator', [])
            release = workflow.get('release', 'None')

            # Extract domain from path
            rel_path = ga_file.relative_to(WORKFLOWS_DIR)
            domain = str(rel_path.parts[0]) if len(rel_path.parts) > 1 else 'general'

            # Analyze steps
            steps = workflow.get('steps', {})
            num_steps = len(steps)

            input_steps = 0
            tool_steps = 0
            labeled_inputs = 0
            labeled_outputs = 0
            tools = []

            for step_id, step in steps.items():
                step_type = step.get('type', '')

                if step_type in ['data_input', 'data_collection_input', 'parameter_input']:
                    input_steps += 1
                    if step.get('label'):
                        labeled_inputs += 1
                elif step_type == 'tool':
                    tool_steps += 1
                    tool_id = step.get('tool_id', '')
                    if tool_id:
                        tools.append(tool_id)
                        tools_used[tool_id] += 1

                    # Check workflow outputs
                    outputs = step.get('workflow_outputs', [])
                    if outputs:
                        for output in outputs:
                            if output.get('label'):
                                labeled_outputs += 1

            # Check creator has ORCID
            has_orcid = any(
                'orcid.org' in str(c.get('identifier', ''))
                for c in creator
            )

            # Quality score
            quality_score = 0
            if license_info and license_info != 'None':
                quality_score += 20
            if has_orcid:
                quality_score += 20
            if annotation and len(annotation) > 50:
                quality_score += 20
            if labeled_inputs == input_steps and input_steps > 0:
                quality_score += 20
            if labeled_outputs > 0:
                quality_score += 20

            result = {
                'name': name,
                'file': str(ga_file.relative_to(WORKFLOWS_DIR)),
                'domain': domain,
                'annotation': annotation[:200] + '...' if len(annotation) > 200 else annotation,
                'license': license_info,
                'creator': [c.get('name', 'Unknown') for c in creator],
                'has_orcid': has_orcid,
                'release': release,
                'num_steps': num_steps,
                'input_steps': input_steps,
                'tool_steps': tool_steps,
                'labeled_inputs': labeled_inputs,
                'labeled_outputs': labeled_outputs,
                'tools': tools,
                'quality_score': quality_score
            }

            results.append(result)
            domains[domain].append(result)

        except Exception as e:
            print(f"Error analyzing {ga_file}: {e}")

    return results, domains, tools_used


def generate_report(results, domains, tools_used):
    """Generate comprehensive quality report."""

    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    report_path = f"{OUTPUT_DIR}/{timestamp}_OFFICIAL_IWC_QUALITY_REPORT.md"

    # Sort by quality
    results.sort(key=lambda x: (-x['quality_score'], x['name']))

    with open(report_path, 'w') as f:
        f.write("# Official IWC Workflows Quality Report\n\n")
        f.write(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"**Total Workflows:** {len(results)}\n")
        f.write(f"**Location:** `/home/yzhang/biomate/backend/galaxy_workflows_official_iwc/`\n\n")

        # Quality summary
        high_quality = sum(1 for r in results if r['quality_score'] >= 80)
        good_quality = sum(1 for r in results if 60 <= r['quality_score'] < 80)
        needs_work = sum(1 for r in results if r['quality_score'] < 60)

        f.write("## Quality Summary\n\n")
        f.write(f"- **High Quality (80+):** {high_quality} workflows\n")
        f.write(f"- **Good Quality (60-79):** {good_quality} workflows\n")
        f.write(f"- **Needs Improvement (<60):** {needs_work} workflows\n\n")

        avg_score = sum(r['quality_score'] for r in results) / len(results)
        f.write(f"**Average Quality Score:** {avg_score:.1f}/100\n\n")

        # Domain coverage
        f.write("---\n\n## Domain Coverage\n\n")
        f.write("| Domain | Workflows | Avg Quality |\n")
        f.write("|--------|-----------|-------------|\n")

        for domain in sorted(domains.keys()):
            workflows = domains[domain]
            avg = sum(w['quality_score'] for w in workflows) / len(workflows)
            f.write(f"| {domain} | {len(workflows)} | {avg:.0f} |\n")

        # Top quality workflows
        f.write("\n---\n\n## Top Quality Workflows (Score 100)\n\n")
        perfect = [r for r in results if r['quality_score'] == 100]
        for r in perfect[:20]:
            f.write(f"### {r['name']}\n\n")
            f.write(f"- **Domain:** {r['domain']}\n")
            f.write(f"- **License:** {r['license']}\n")
            f.write(f"- **Creator:** {', '.join(r['creator'])}\n")
            f.write(f"- **Steps:** {r['tool_steps']} tools, {r['input_steps']} inputs\n")
            f.write(f"- **Description:** {r['annotation']}\n\n")

        if len(perfect) > 20:
            f.write(f"... and {len(perfect) - 20} more\n\n")

        # Tools analysis
        f.write("---\n\n## Most Used Tools\n\n")
        top_tools = sorted(tools_used.items(), key=lambda x: -x[1])[:30]
        for tool_id, count in top_tools:
            # Extract tool name
            if 'toolshed.g2.bx.psu.edu' in tool_id:
                parts = tool_id.split('/')
                if len(parts) >= 5:
                    tool_name = f"{parts[4]}/{parts[5]}"
                else:
                    tool_name = tool_id
            else:
                tool_name = tool_id
            f.write(f"- `{tool_name}` ({count}x)\n")

        # All workflows by domain
        f.write("\n---\n\n## Complete Workflow List by Domain\n\n")
        for domain in sorted(domains.keys()):
            workflows = sorted(domains[domain], key=lambda x: -x['quality_score'])
            f.write(f"### {domain.replace('-', ' ').title()} ({len(workflows)} workflows)\n\n")

            for w in workflows:
                score_icon = "★" if w['quality_score'] >= 80 else "○"
                f.write(f"- {score_icon} **{w['name']}** (Score: {w['quality_score']})\n")
                f.write(f"  - Tools: {w['tool_steps']}, Inputs: {w['input_steps']}\n")
            f.write("\n")

        # Quality criteria explanation
        f.write("---\n\n## Quality Scoring Criteria\n\n")
        f.write("Each workflow is scored on these criteria (20 points each):\n\n")
        f.write("1. **License** - Has a proper license (e.g., MIT)\n")
        f.write("2. **Creator ORCID** - Creator has ORCID identifier\n")
        f.write("3. **Annotation** - Meaningful description (>50 chars)\n")
        f.write("4. **Labeled Inputs** - All inputs have labels\n")
        f.write("5. **Labeled Outputs** - Workflow outputs are labeled\n\n")

    print(f"Report saved to: {report_path}")

    # Also save JSON data
    json_path = f"{OUTPUT_DIR}/{timestamp}_OFFICIAL_IWC_INVENTORY.json"
    with open(json_path, 'w') as f:
        json.dump({
            'workflows': results,
            'tools': dict(tools_used),
            'domains': {k: len(v) for k, v in domains.items()}
        }, f, indent=2)

    print(f"JSON data saved to: {json_path}")

    return report_path


def main():
    print("=" * 60)
    print("Official IWC Workflow Analysis")
    print("=" * 60)
    print()

    results, domains, tools_used = analyze_workflows()

    print(f"Analyzed {len(results)} workflows")
    print(f"Across {len(domains)} domains")
    print(f"Using {len(tools_used)} unique tools")
    print()

    report_path = generate_report(results, domains, tools_used)

    # Print summary
    high_quality = sum(1 for r in results if r['quality_score'] >= 80)
    print(f"\nHigh quality workflows (80+): {high_quality}/{len(results)}")


if __name__ == "__main__":
    main()
