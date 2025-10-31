#!/usr/bin/env python3
"""
Comprehensive tool information extraction from rawText and htmlContent.

This script extracts ALL valuable structured information from existing data:
- Input formats (SAM, BAM, FASTQ, VCF, GTF, GFF, etc.)
- Output formats
- File type requirements
- Dependencies/requirements (packages, versions)
- Citations and references
- EDAM ontology terms
- Compatible tools/integrations
- Version information
- Any other structured metadata
"""

import json
import sqlite3
import re
from pathlib import Path
from typing import Dict, List, Any, Set, Optional


# Common bioinformatics file formats to detect
FILE_FORMATS = {
    'sequence': ['fasta', 'fastq', 'fastq.gz', 'fasta.gz', 'fa', 'fq', 'fastqsanger', 'fastqillumina', 'fastqcssanger'],
    'alignment': ['sam', 'bam', 'cram', 'psl'],
    'variant': ['vcf', 'vcf.gz', 'bcf', 'bed', 'gff', 'gff3', 'gtf'],
    'tabular': ['tabular', 'tsv', 'csv', 'txt', 'tab'],
    'image': ['png', 'jpg', 'jpeg', 'pdf', 'svg'],
    'archive': ['zip', 'tar', 'tar.gz', 'tgz'],
    'markup': ['html', 'xml', 'json', 'yaml'],
    'other': ['h5', 'hdf5', 'rdata', 'rds', 'mzml', 'mzxml', 'mgf', 'feather']
}

ALL_FORMATS = set()
for formats in FILE_FORMATS.values():
    ALL_FORMATS.update(formats)


def extract_file_formats(text: str) -> Dict[str, List[str]]:
    """
    Extract input and output file formats from text.

    Looks for patterns like:
    - "Input file: SAM or BAM format"
    - "accepts FASTQ files"
    - "Output: VCF format"
    - "format='fastq'"
    """
    inputs = set()
    outputs = set()

    text_lower = text.lower()

    # Pattern 1: Explicit format mentions
    # "SAM format", "BAM or SAM", "FASTQ files"
    for fmt in ALL_FORMATS:
        # Input patterns
        input_patterns = [
            rf'\b(input|upload|read|import|accept|from|alignment|sequence).*?{fmt}\b',
            rf'\b{fmt}.*?(input|file|format|data)\b',
        ]
        for pattern in input_patterns:
            if re.search(pattern, text_lower):
                inputs.add(fmt)
                break

        # Output patterns
        output_patterns = [
            rf'\b(output|export|produce|generate|create|write).*?{fmt}\b',
            rf'\b{fmt}.*?(output|file|format|result)\b',
        ]
        for pattern in output_patterns:
            if re.search(pattern, text_lower):
                outputs.add(fmt)
                break

    # Pattern 2: Format lists
    # "SAM, BAM or CRAM format"
    # "accepts FASTQ, FASTA, or FastQC files"
    format_list_pattern = r'(?:format|file|accept|support|input|output)s?[:\s]+(?:from\s+)?([a-z0-9,/\s]+)'
    matches = re.findall(format_list_pattern, text_lower)
    for match in matches:
        for fmt in ALL_FORMATS:
            if fmt in match:
                # Determine if input or output based on context
                if 'input' in text_lower[max(0, text_lower.find(match)-100):text_lower.find(match)]:
                    inputs.add(fmt)
                elif 'output' in text_lower[max(0, text_lower.find(match)-100):text_lower.find(match)]:
                    outputs.add(fmt)
                else:
                    # Default to input if unclear
                    inputs.add(fmt)

    return {
        'inputs': sorted(list(inputs)),
        'outputs': sorted(list(outputs))
    }


def extract_requirements(text: str) -> List[Dict[str, str]]:
    """
    Extract software requirements and dependencies.

    Looks for:
    - Package names and versions
    - "Requires X version Y"
    - Tool dependencies
    """
    requirements = []
    seen = set()

    # Pattern 1: "Requires X version Y"
    # "requires R version 3.5"
    pattern1 = r'(?:require|need|depend|use)s?\s+([A-Za-z0-9\-\_]+)(?:\s+version\s+)?([0-9\.]+)?'
    matches = re.findall(pattern1, text, re.IGNORECASE)
    for pkg, version in matches:
        pkg = pkg.strip()
        if len(pkg) > 2 and pkg.lower() not in ['the', 'and', 'for', 'this']:
            key = f"{pkg}:{version}" if version else pkg
            if key not in seen:
                requirements.append({
                    'name': pkg,
                    'version': version if version else None,
                    'type': 'package'
                })
                seen.add(key)

    # Pattern 2: "Part of X package"
    # "FeatureCounts is part of the Subread package"
    pattern2 = r'(?:part of|from|in)\s+(?:the\s+)?([A-Z][A-Za-z0-9\-\_]+)\s+(?:package|suite|tool|library)'
    matches = re.findall(pattern2, text, re.IGNORECASE)
    for pkg in matches:
        pkg = pkg.strip()
        if pkg not in seen and len(pkg) > 2:
            requirements.append({
                'name': pkg,
                'version': None,
                'type': 'package'
            })
            seen.add(pkg)

    # Pattern 3: Common bioinformatics tools
    common_tools = [
        'samtools', 'bcftools', 'bedtools', 'bwa', 'bowtie', 'hisat2',
        'star', 'picard', 'gatk', 'fastqc', 'trimmomatic', 'cutadapt',
        'subread', 'featurecounts', 'deseq2', 'edger', 'limma'
    ]
    text_lower = text.lower()
    for tool in common_tools:
        if tool in text_lower and tool not in seen:
            # Extract version if present
            version_pattern = rf'{tool}[^\w]*(?:version\s+)?([0-9\.]+)'
            version_match = re.search(version_pattern, text_lower)
            version = version_match.group(1) if version_match else None

            requirements.append({
                'name': tool,
                'version': version,
                'type': 'tool'
            })
            seen.add(tool)

    return requirements


def extract_citations(text: str) -> List[Dict[str, str]]:
    """
    Extract citations and references.

    Looks for:
    - DOIs
    - PubMed IDs
    - URLs to papers
    - Author citations
    """
    citations = []
    seen = set()

    # Pattern 1: DOI
    doi_pattern = r'(?:doi[:\s]+|https?://doi\.org/)([0-9]{2}\.[0-9]{4,}/[^\s\)]+)'
    dois = re.findall(doi_pattern, text, re.IGNORECASE)
    for doi in dois:
        doi = doi.strip().rstrip('.,;')
        if doi not in seen:
            citations.append({
                'type': 'doi',
                'value': doi,
                'url': f'https://doi.org/{doi}'
            })
            seen.add(doi)

    # Pattern 2: PubMed ID
    pubmed_pattern = r'(?:pubmed|pmid)[:\s]+([0-9]{7,8})'
    pmids = re.findall(pubmed_pattern, text, re.IGNORECASE)
    for pmid in pmids:
        if pmid not in seen:
            citations.append({
                'type': 'pubmed',
                'value': pmid,
                'url': f'https://pubmed.ncbi.nlm.nih.gov/{pmid}/'
            })
            seen.add(pmid)

    # Pattern 3: Citation section
    citation_section = re.search(r'(?:citation|reference|paper|publication)s?[:\s]+(.*?)(?:\n\n|$)',
                                  text, re.IGNORECASE | re.DOTALL)
    if citation_section:
        citation_text = citation_section.group(1).strip()
        if len(citation_text) < 500 and citation_text not in seen:
            citations.append({
                'type': 'text',
                'value': citation_text[:300],
                'url': None
            })

    return citations


def extract_compatible_tools(text: str) -> List[str]:
    """
    Extract mentions of compatible/integrated tools.

    Looks for:
    - "compatible with X"
    - "integrates with Y"
    - "can be used with Z"
    """
    compatible = set()

    # Pattern: "compatible with X, Y and Z"
    pattern = r'(?:compatible|integrate|work|use)s?(?:\s+with)?[:\s]+(?:the\s+)?([A-Za-z0-9\-\_,\s]+?)(?:\s+(?:Galaxy\s+)?(?:wrapper|tool|package))'
    matches = re.findall(pattern, text, re.IGNORECASE)

    for match in matches:
        # Split on commas and 'and'
        tools = re.split(r',|\s+and\s+', match)
        for tool in tools:
            tool = tool.strip()
            if len(tool) > 2 and tool.lower() not in ['the', 'for', 'this', 'these']:
                compatible.add(tool)

    # Common integration mentions
    common_integrations = ['deseq2', 'edger', 'limma', 'voom', 'featurecounts', 'star', 'hisat2']
    text_lower = text.lower()
    for tool in common_integrations:
        if tool in text_lower:
            compatible.add(tool)

    return sorted(list(compatible))


def extract_version_info(text: str, tool_name: str) -> Optional[str]:
    """Extract tool version from text."""
    # Pattern 1: "ToolName (version X.Y.Z)"
    pattern1 = rf'{re.escape(tool_name)}\s*\(version\s+([0-9\.]+[^\)]*)\)'
    match = re.search(pattern1, text, re.IGNORECASE)
    if match:
        return match.group(1).strip()

    # Pattern 2: "version X.Y.Z"
    pattern2 = r'version\s+([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:\+galaxy[0-9]+)?)'
    match = re.search(pattern2, text, re.IGNORECASE)
    if match:
        return match.group(1).strip()

    return None


def extract_description(text: str) -> str:
    """
    Extract tool description from multiple possible sections.

    Looks for: Purpose, Overview, What it does, Summary, Description
    """
    # Try to find structured description sections
    description_patterns = [
        (r'(?:^|\n)Purpose[:\s]*\n+(.*?)(?=\n\n[A-Z]|\n\n$|\Z)', 'Purpose'),
        (r'(?:^|\n)Overview[:\s]*\n+(.*?)(?=\n\n[A-Z]|\n\n$|\Z)', 'Overview'),
        (r'(?:^|\n)What it does[:\s]*\n+(.*?)(?=\n\n[A-Z]|\n\n$|\Z)', 'What it does'),
        (r'(?:^|\n)Summary[:\s]*\n+(.*?)(?=\n\n[A-Z]|\n\n$|\Z)', 'Summary'),
        (r'(?:^|\n)Description[:\s]*\n+(.*?)(?=\n\n[A-Z]|\n\n$|\Z)', 'Description'),
    ]

    for pattern, section_name in description_patterns:
        match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
        if match:
            desc = match.group(1).strip()
            # Take first 500 chars of clean text
            desc = re.sub(r'\s+', ' ', desc)
            if len(desc) > 50:  # Must be substantial
                return desc[:500]

    # Fallback: extract first substantial paragraph after tool name
    lines = text.split('\n')
    for i, line in enumerate(lines):
        if i > 5 and len(line) > 100 and not line.isupper():
            # Clean and return
            return re.sub(r'\s+', ' ', line.strip())[:500]

    return ""


def extract_examples(text: str) -> List[str]:
    """
    Extract usage examples and code snippets.

    Looks for:
    - Example sections
    - Code blocks
    - Usage instructions
    - Sample commands
    """
    examples = []

    # Pattern 1: Example sections
    example_patterns = [
        r'(?:^|\n)Example[s]?[:\s]*\n+(.*?)(?=\n\n[A-Z]|\Z)',
        r'(?:^|\n)Usage[:\s]*\n+(.*?)(?=\n\n[A-Z]|\Z)',
        r'(?:^|\n)Sample[s]?[:\s]*\n+(.*?)(?=\n\n[A-Z]|\Z)',
        r'(?:^|\n)Tutorial[:\s]*\n+(.*?)(?=\n\n[A-Z]|\Z)',
        r'(?:^|\n)How to use[:\s]*\n+(.*?)(?=\n\n[A-Z]|\Z)',
    ]

    for pattern in example_patterns:
        matches = re.findall(pattern, text, re.IGNORECASE | re.DOTALL)
        for match in matches:
            example = match.strip()
            if len(example) > 20:
                examples.append(example[:1000])  # Keep substantial examples

    # Pattern 2: Code blocks (indented or in backticks)
    code_blocks = re.findall(r'```(.*?)```', text, re.DOTALL)
    for code in code_blocks:
        code = code.strip()
        if len(code) > 10:
            examples.append(code[:500])

    # Pattern 3: Command examples (lines starting with $, >, or tool name)
    command_pattern = r'(?:^|\n)\s*(?:\$|>)(.{10,100})(?:\n|$)'
    commands = re.findall(command_pattern, text, re.MULTILINE)
    if commands and len(examples) < 3:
        examples.extend(commands[:3])

    return examples[:5]  # Return up to 5 examples


def extract_usage_guide(text: str) -> str:
    """
    Extract usage instructions and tutorial information.

    Looks for: Tutorial, How to, Usage, Instructions, Guide
    """
    usage_patterns = [
        r'(?:^|\n)Tutorial[:\s]*\n+(.*?)(?=\n\n[A-Z]|\Z)',
        r'(?:^|\n)How to(?: use)?[:\s]*\n+(.*?)(?=\n\n[A-Z]|\Z)',
        r'(?:^|\n)Instructions[:\s]*\n+(.*?)(?=\n\n[A-Z]|\Z)',
        r'(?:^|\n)Guide[:\s]*\n+(.*?)(?=\n\n[A-Z]|\Z)',
        r'(?:^|\n)Usage[:\s]*\n+(.*?)(?=\n\n[A-Z]|\Z)',
    ]

    for pattern in usage_patterns:
        match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
        if match:
            usage = match.group(1).strip()
            # Clean and limit
            usage = re.sub(r'\s+', ' ', usage)
            if len(usage) > 50:
                return usage[:1000]

    return ""


def extract_edam_terms(text: str) -> Dict[str, List[str]]:
    """
    Extract EDAM ontology terms if mentioned.

    EDAM (EMBRACE Data and Methods) provides terms for:
    - Operations (what the tool does)
    - Topics (scientific domain)
    - Data types
    """
    edam = {
        'operations': [],
        'topics': [],
        'data': []
    }

    # Pattern: EDAM terms usually appear as "EDAM:operation_XXXX"
    edam_pattern = r'EDAM:(operation|topic|data)_([0-9]{4})'
    matches = re.findall(edam_pattern, text, re.IGNORECASE)

    for term_type, term_id in matches:
        edam[f'{term_type.lower()}s'].append(f'EDAM:{term_type}_{term_id}')

    return edam


def extract_comprehensive_info(tool_id: str, name: str, raw_text: str, html_content: str) -> Dict[str, Any]:
    """
    Extract ALL valuable information from tool rawText and htmlContent.
    """
    combined_text = f"{raw_text}\n{html_content}"

    # Extract all information
    description = extract_description(combined_text)
    examples = extract_examples(combined_text)
    usage_guide = extract_usage_guide(combined_text)
    formats = extract_file_formats(combined_text)
    requirements = extract_requirements(combined_text)
    citations = extract_citations(combined_text)
    compatible_tools = extract_compatible_tools(combined_text)
    version = extract_version_info(combined_text, name)
    edam = extract_edam_terms(combined_text)

    return {
        'tool_id': tool_id,
        'name': name,
        'description': description,
        'examples': examples,
        'usage_guide': usage_guide,
        'version': version,
        'inputs': formats['inputs'],
        'outputs': formats['outputs'],
        'requirements': requirements,
        'citations': citations,
        'compatible_tools': compatible_tools,
        'edam_operations': edam['operations'],
        'edam_topics': edam['topics'],
        'edam_data': edam['data']
    }


def update_database(db_path: str, batch_size: int = 100):
    """Update database with comprehensive extracted information."""

    print(f"Opening database: {db_path}")
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Get total count
    cursor.execute("SELECT COUNT(*) FROM tools WHERE rawText IS NOT NULL AND rawText != ''")
    total = cursor.fetchone()[0]

    print(f"Processing {total} tools...")
    print("="*80)

    # Statistics
    stats = {
        'processed': 0,
        'with_description': 0,
        'with_examples': 0,
        'with_usage_guide': 0,
        'with_inputs': 0,
        'with_outputs': 0,
        'with_requirements': 0,
        'with_citations': 0,
        'with_compatible': 0,
        'with_edam': 0,
        'with_version': 0
    }

    # Fetch all tools
    cursor.execute("""
        SELECT tool_id, name, rawText, htmlContent
        FROM tools
        WHERE rawText IS NOT NULL AND rawText != ''
    """)
    all_tools = cursor.fetchall()

    batch = []
    for row in all_tools:
        tool_id = row['tool_id']
        name = row['name']
        raw_text = row['rawText'] or ''
        html_content = row['htmlContent'] or ''

        # Extract comprehensive information
        info = extract_comprehensive_info(tool_id, name, raw_text, html_content)

        # Update statistics
        if info['description']:
            stats['with_description'] += 1
        if info['examples']:
            stats['with_examples'] += 1
        if info['usage_guide']:
            stats['with_usage_guide'] += 1
        if info['inputs']:
            stats['with_inputs'] += 1
        if info['outputs']:
            stats['with_outputs'] += 1
        if info['requirements']:
            stats['with_requirements'] += 1
        if info['citations']:
            stats['with_citations'] += 1
        if info['compatible_tools']:
            stats['with_compatible'] += 1
        if info['edam_operations'] or info['edam_topics']:
            stats['with_edam'] += 1
        if info['version']:
            stats['with_version'] += 1

        batch.append((
            info['description'],
            json.dumps(info['examples']),
            info['usage_guide'],
            json.dumps(info['inputs']),
            json.dumps(info['outputs']),
            json.dumps(info['requirements']),
            json.dumps(info['citations']),
            info['version'],
            json.dumps(info['edam_operations'] + info['edam_topics']),  # Combined EDAM
            json.dumps(info['compatible_tools']),
            tool_id
        ))

        stats['processed'] += 1

        # Update in batches
        if len(batch) >= batch_size:
            update_cursor = conn.cursor()
            update_cursor.executemany('''
                UPDATE tools
                SET description = ?,
                    examples = ?,
                    usage_guide = ?,
                    inputs = ?,
                    outputs = ?,
                    requirements = ?,
                    citations = ?,
                    version = ?,
                    edam_operations = ?,
                    tags = ?
                WHERE tool_id = ?
            ''', batch)
            update_cursor.close()
            conn.commit()
            batch = []

            if stats['processed'] % 500 == 0:
                print(f"  Processed {stats['processed']}/{total} tools...")
                print(f"    Inputs: {stats['with_inputs']}, Outputs: {stats['with_outputs']}, "
                      f"Requirements: {stats['with_requirements']}, Citations: {stats['with_citations']}")

    # Final batch
    if batch:
        update_cursor = conn.cursor()
        update_cursor.executemany('''
            UPDATE tools
            SET description = ?,
                examples = ?,
                usage_guide = ?,
                inputs = ?,
                outputs = ?,
                requirements = ?,
                citations = ?,
                version = ?,
                edam_operations = ?,
                tags = ?
            WHERE tool_id = ?
        ''', batch)
        update_cursor.close()
        conn.commit()

    conn.close()

    print("="*80)
    print(f"✅ Comprehensive extraction complete:")
    print(f"   Total processed: {stats['processed']}")
    print(f"   With description: {stats['with_description']} ({stats['with_description']/stats['processed']*100:.1f}%)")
    print(f"   With examples: {stats['with_examples']} ({stats['with_examples']/stats['processed']*100:.1f}%)")
    print(f"   With usage guide: {stats['with_usage_guide']} ({stats['with_usage_guide']/stats['processed']*100:.1f}%)")
    print(f"   With input formats: {stats['with_inputs']} ({stats['with_inputs']/stats['processed']*100:.1f}%)")
    print(f"   With output formats: {stats['with_outputs']} ({stats['with_outputs']/stats['processed']*100:.1f}%)")
    print(f"   With requirements: {stats['with_requirements']} ({stats['with_requirements']/stats['processed']*100:.1f}%)")
    print(f"   With citations: {stats['with_citations']} ({stats['with_citations']/stats['processed']*100:.1f}%)")
    print(f"   With compatible tools: {stats['with_compatible']} ({stats['with_compatible']/stats['processed']*100:.1f}%)")
    print(f"   With EDAM terms: {stats['with_edam']} ({stats['with_edam']/stats['processed']*100:.1f}%)")
    print(f"   With version info: {stats['with_version']} ({stats['with_version']/stats['processed']*100:.1f}%)")

    return stats


def main():
    """Main function."""
    db_path = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return 1

    print("="*80)
    print("Galaxy AI Tools - Comprehensive Information Extraction")
    print("="*80)
    print(f"Database: {db_path}")
    print(f"Size: {db_path.stat().st_size / (1024*1024):.1f} MB")
    print()
    print("Extracting:")
    print("  • Input/Output file formats")
    print("  • Software requirements and dependencies")
    print("  • Citations and references")
    print("  • Compatible tool integrations")
    print("  • Version information")
    print("  • EDAM ontology terms")
    print()

    try:
        stats = update_database(str(db_path))

        print()
        print("="*80)
        print("✅ EXTRACTION COMPLETE")
        print("="*80)
        print()
        print("Database now contains:")
        print(f"  • {stats['with_description']} tools with descriptions")
        print(f"  • {stats['with_examples']} tools with examples")
        print(f"  • {stats['with_usage_guide']} tools with usage guides")
        print(f"  • {stats['with_inputs']} tools with input formats")
        print(f"  • {stats['with_outputs']} tools with output formats")
        print(f"  • {stats['with_requirements']} tools with requirements")
        print(f"  • {stats['with_citations']} tools with citations")
        print(f"  • {stats['with_compatible']} tools with compatible tool info")
        print(f"  • {stats['with_version']} tools with version info")
        print()
        print("Next steps:")
        print("  1. Restart Galaxy backend to use updated database")
        print("  2. Test schema endpoints with complete information")
        print("  3. Verify frontend displays descriptions and examples")

        return 0

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
