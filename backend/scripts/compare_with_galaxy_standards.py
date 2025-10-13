#!/usr/bin/env python3
"""
Compare our nf-core tools with Galaxy ToolShed standards.
Identify missing information that should be added from nf-core meta.yml files.
"""

import xml.etree.ElementTree as ET
from pathlib import Path
import yaml
from collections import defaultdict

class GalaxyStandardsComparison:
    def __init__(self, tools_dir: str = "tools/nfcore_generated",
                 modules_dir: str = "/tmp/nfcore-modules/modules/nf-core"):
        self.tools_dir = Path(tools_dir)
        self.modules_dir = Path(modules_dir)
        self.missing_info = defaultdict(list)

    def extract_meta_yml_info(self, module_path: Path):
        """Extract rich metadata from nf-core meta.yml file."""
        meta_file = module_path / "meta.yml"
        if not meta_file.exists():
            return None

        try:
            with open(meta_file) as f:
                meta_data = yaml.safe_load(f)

            info = {
                'name': meta_data.get('name', ''),
                'description': meta_data.get('description', ''),
                'keywords': meta_data.get('keywords', []),
                'tools': meta_data.get('tools', {}),
                'input': meta_data.get('input', []),
                'output': meta_data.get('output', {}),
                'authors': meta_data.get('authors', []),
                'maintainers': meta_data.get('maintainers', [])
            }

            # Extract tool-specific info
            if info['tools']:
                tool_name = list(info['tools'].keys())[0]
                tool_info = info['tools'][tool_name]
                info['tool_description'] = tool_info.get('description', '')
                info['homepage'] = tool_info.get('homepage', '')
                info['documentation'] = tool_info.get('documentation', '')
                info['licence'] = tool_info.get('licence', [])
                info['identifier'] = tool_info.get('identifier', '')

            return info
        except Exception as e:
            print(f"Error reading meta.yml: {e}")
            return None

    def analyze_tool(self, xml_file: Path):
        """Analyze a tool XML against Galaxy standards."""
        try:
            tree = ET.parse(xml_file)
            root = tree.getroot()

            # Extract tool ID to find corresponding nf-core module
            tool_id = root.get('id', '')
            if not tool_id.startswith('nfcore_'):
                return None

            module_name = tool_id.replace('nfcore_', '')
            module_path = self.modules_dir / module_name.replace('/', '/')

            if not module_path.exists():
                return None

            # Get meta.yml info
            meta_info = self.extract_meta_yml_info(module_path)
            if not meta_info:
                return None

            # Analyze what's missing from XML
            issues = []

            # Check description richness
            xml_desc = root.find('description')
            if xml_desc is not None and xml_desc.text:
                if len(xml_desc.text) < 50 and meta_info.get('tool_description'):
                    issues.append({
                        'type': 'SHORT_DESCRIPTION',
                        'current': xml_desc.text,
                        'available': meta_info['tool_description'][:100]
                    })

            # Check for missing elements
            if root.find('edam_topics') is None and meta_info.get('keywords'):
                issues.append({
                    'type': 'MISSING_EDAM_TOPICS',
                    'available': meta_info['keywords']
                })

            if root.find('xrefs') is None and meta_info.get('identifier'):
                issues.append({
                    'type': 'MISSING_XREFS',
                    'available': meta_info['identifier']
                })

            # Check help section richness
            help_elem = root.find('help')
            if help_elem is not None and help_elem.text:
                help_text = help_elem.text.strip()
                has_homepage = meta_info.get('homepage', '') in help_text
                has_documentation = meta_info.get('documentation', '') in help_text

                if not has_homepage and meta_info.get('homepage'):
                    issues.append({
                        'type': 'MISSING_HOMEPAGE',
                        'available': meta_info['homepage']
                    })

                if not has_documentation and meta_info.get('documentation'):
                    issues.append({
                        'type': 'MISSING_DOCUMENTATION',
                        'available': meta_info['documentation']
                    })

            # Check for detailed input/output descriptions
            inputs_elem = root.find('inputs')
            if inputs_elem is not None:
                params = inputs_elem.findall('param')
                if len(params) <= 3:  # Only generic params
                    if meta_info.get('input'):
                        issues.append({
                            'type': 'GENERIC_INPUTS',
                            'available': f"{len(meta_info['input'])} detailed input specs"
                        })

            outputs_elem = root.find('outputs')
            if outputs_elem is not None:
                outputs = outputs_elem.findall('data')
                if len(outputs) <= 1:  # Only generic output
                    if meta_info.get('output'):
                        issues.append({
                            'type': 'GENERIC_OUTPUTS',
                            'available': f"{len(meta_info['output'])} detailed output specs"
                        })

            # Check for stdio/error handling
            if root.find('stdio') is None:
                issues.append({
                    'type': 'MISSING_STDIO',
                    'available': 'Should add error code handling'
                })

            # Check for version command
            if root.find('version_command') is None:
                issues.append({
                    'type': 'MISSING_VERSION_COMMAND',
                    'available': 'Should add version detection'
                })

            return {
                'tool_id': tool_id,
                'module_name': module_name,
                'issues': issues,
                'meta_info': meta_info
            }

        except Exception as e:
            print(f"Error analyzing {xml_file}: {e}")
            return None

    def run(self):
        """Run comparison analysis."""
        print("=" * 80)
        print("COMPARISON WITH GALAXY TOOLSHED STANDARDS")
        print("=" * 80)
        print()

        all_issues = defaultdict(list)
        tools_analyzed = 0

        for xml_file in sorted(self.tools_dir.glob("*.xml"))[:50]:  # Sample first 50
            result = self.analyze_tool(xml_file)
            if result and result['issues']:
                tools_analyzed += 1
                for issue in result['issues']:
                    all_issues[issue['type']].append({
                        'tool': result['module_name'],
                        'details': issue
                    })

        print(f"Analyzed {tools_analyzed} tools with nf-core metadata\n")

        print("=" * 80)
        print("MISSING INFORMATION SUMMARY")
        print("=" * 80)
        print()

        for issue_type, occurrences in sorted(all_issues.items(),
                                              key=lambda x: len(x[1]), reverse=True):
            print(f"\n{issue_type}: {len(occurrences)} tools")
            print("-" * 80)

            # Show examples
            for example in occurrences[:3]:
                print(f"\nTool: {example['tool']}")
                if 'current' in example['details']:
                    print(f"  Current: {example['details']['current']}")
                print(f"  Available: {example['details']['available']}")

        print("\n" + "=" * 80)
        print("RECOMMENDATIONS")
        print("=" * 80)
        print()

        recommendations = []

        if 'SHORT_DESCRIPTION' in all_issues:
            recommendations.append(
                f"1. ENHANCE DESCRIPTIONS: {len(all_issues['SHORT_DESCRIPTION'])} tools "
                "have brief descriptions. Use detailed descriptions from meta.yml."
            )

        if 'MISSING_HOMEPAGE' in all_issues:
            recommendations.append(
                f"2. ADD HOMEPAGE LINKS: {len(all_issues['MISSING_HOMEPAGE'])} tools "
                "missing homepage in help section."
            )

        if 'MISSING_DOCUMENTATION' in all_issues:
            recommendations.append(
                f"3. ADD DOCUMENTATION LINKS: {len(all_issues['MISSING_DOCUMENTATION'])} tools "
                "missing documentation links in help section."
            )

        if 'MISSING_EDAM_TOPICS' in all_issues:
            recommendations.append(
                f"4. ADD EDAM ANNOTATIONS: {len(all_issues['MISSING_EDAM_TOPICS'])} tools "
                "missing EDAM topics/operations. Use keywords from meta.yml."
            )

        if 'MISSING_XREFS' in all_issues:
            recommendations.append(
                f"5. ADD CROSS-REFERENCES: {len(all_issues['MISSING_XREFS'])} tools "
                "missing xrefs (bio.tools identifiers)."
            )

        if 'GENERIC_INPUTS' in all_issues:
            recommendations.append(
                f"6. DETAILED INPUT PARAMETERS: {len(all_issues['GENERIC_INPUTS'])} tools "
                "use generic inputs. Map from meta.yml input specifications."
            )

        if 'GENERIC_OUTPUTS' in all_issues:
            recommendations.append(
                f"7. DETAILED OUTPUT FILES: {len(all_issues['GENERIC_OUTPUTS'])} tools "
                "use generic outputs. Map from meta.yml output specifications."
            )

        if 'MISSING_STDIO' in all_issues:
            recommendations.append(
                f"8. ADD ERROR HANDLING: {len(all_issues['MISSING_STDIO'])} tools "
                "missing stdio section for error code handling."
            )

        if 'MISSING_VERSION_COMMAND' in all_issues:
            recommendations.append(
                f"9. ADD VERSION DETECTION: {len(all_issues['MISSING_VERSION_COMMAND'])} tools "
                "missing version_command element."
            )

        for i, rec in enumerate(recommendations, 1):
            print(rec)
            print()

if __name__ == "__main__":
    comparator = GalaxyStandardsComparison()
    comparator.run()
