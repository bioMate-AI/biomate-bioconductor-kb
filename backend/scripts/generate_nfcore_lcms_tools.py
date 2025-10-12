#!/usr/bin/env python3
"""
Generate Galaxy tool wrappers for all remaining nf-core LC-MS modules.
This script automates the creation of tool XMLs based on nf-core specifications.
"""

import json
from pathlib import Path
from datetime import datetime

# Tool configurations with essential parameters
TOOL_CONFIGS = {
    "sageproteomics_sage": {
        "name": "Sage Peptide Search",
        "version": "0.14.7",
        "container": "biocontainers/sage-proteomics:0.14.7--h031d066_0",
        "description": "Ultra-fast peptide search engine for proteomics",
        "citation": "10.1021/acs.jproteome.3c00486",
        "tier": 1
    },
    "openms_peakpickerhires": {
        "name": "OpenMS PeakPickerHiRes",
        "version": "3.1.0",
        "container": "biocontainers/openms:3.1.0--h8964181_1",
        "description": "High-resolution peak detection for LC-MS data",
        "citation": "10.1038/nmeth.3959",
        "tier": 2
    },
    "openms_peptideindexer": {
        "name": "OpenMS PeptideIndexer",
        "version": "3.1.0",
        "container": "biocontainers/openms:3.1.0--h8964181_1",
        "description": "Index peptides in protein databases for efficient searching",
        "citation": "10.1038/nmeth.3959",
        "tier": 2
    },
    "openms_decoydatabase": {
        "name": "OpenMS DecoyDatabase",
        "version": "3.1.0",
        "container": "biocontainers/openms:3.1.0--h8964181_1",
        "description": "Generate decoy protein sequences for FDR control",
        "citation": "10.1038/nmeth.3959",
        "tier": 2
    },
    "openms_filefilter": {
        "name": "OpenMS FileFilter",
        "version": "3.1.0",
        "container": "biocontainers/openms:3.1.0--h8964181_1",
        "description": "Filter and preprocess MS data files",
        "citation": "10.1038/nmeth.3959",
        "tier": 2
    },
    "openms_idfilter": {
        "name": "OpenMS IDFilter",
        "version": "3.1.0",
        "container": "biocontainers/openms:3.1.0--h8964181_1",
        "description": "Filter peptide and protein identifications",
        "citation": "10.1038/nmeth.3959",
        "tier": 2
    },
    "openms_idmerger": {
        "name": "OpenMS IDMerger",
        "version": "3.1.0",
        "container": "biocontainers/openms:3.1.0--h8964181_1",
        "description": "Merge identification results from multiple runs",
        "citation": "10.1038/nmeth.3959",
        "tier": 2
    },
    "openms_idscoreswitcher": {
        "name": "OpenMS IDScoreSwitcher",
        "version": "3.1.0",
        "container": "biocontainers/openms:3.1.0--h8964181_1",
        "description": "Switch between different scoring schemes",
        "citation": "10.1038/nmeth.3959",
        "tier": 2
    },
    "openms_idripper": {
        "name": "OpenMS IDRipper",
        "version": "3.1.0",
        "container": "biocontainers/openms:3.1.0--h8964181_1",
        "description": "Split identification files by protein/peptide",
        "citation": "10.1038/nmeth.3959",
        "tier": 2
    },
    "openms_idmassaccuracy": {
        "name": "OpenMS IDMassAccuracy",
        "version": "3.1.0",
        "container": "biocontainers/openms:3.1.0--h8964181_1",
        "description": "Calculate and assess mass accuracy of identifications",
        "citation": "10.1038/nmeth.3959",
        "tier": 2
    },
    "maxquant_lfq": {
        "name": "MaxQuant LFQ",
        "version": "2.4.3.0",
        "container": "biocontainers/maxquant:2.4.3.0--hdfd78af_1",
        "description": "Label-free quantification for proteomics",
        "citation": "10.1038/nbt.1511",
        "tier": 3
    }
}

def generate_sage_xml():
    """Generate Sage peptide search tool XML"""
    xml = '''<tool id="sageproteomics_sage" name="Sage Peptide Search" version="0.14.7">
    <description>Ultra-fast peptide search engine for proteomics</description>

    <requirements>
        <container type="docker">biocontainers/sage-proteomics:0.14.7--h031d066_0</container>
    </requirements>

    <command detect_errors="exit_code"><![CDATA[
        export RAYON_NUM_THREADS=\${GALAXY_SLOTS:-4} &&

        sage '$config_json'
            --disable-telemetry-i-dont-want-to-improve-sage
            --fasta '$fasta_input'
            --write-pin
            '$mzml_input'
    ]]></command>

    <inputs>
        <param name="mzml_input" type="data" format="mzml" label="mzML Input File"
               help="Mass spectrometry data in mzML format"/>

        <param name="fasta_input" type="data" format="fasta" label="Protein Database (FASTA)"
               help="Protein sequence database for peptide searching"/>

        <param name="config_json" type="data" format="json" label="Sage Configuration JSON"
               help="Configuration file for Sage search parameters"/>
    </inputs>

    <outputs>
        <data name="results_tsv" format="tsv" from_work_dir="results.sage.tsv"
              label="${tool.name} on ${on_string}: Results TSV"/>
        <data name="results_json" format="json" from_work_dir="results.json"
              label="${tool.name} on ${on_string}: Results JSON"/>
        <data name="results_pin" format="txt" from_work_dir="results.sage.pin"
              label="${tool.name} on ${on_string}: PIN format"/>
    </outputs>

    <help><![CDATA[
**Sage: Ultra-Fast Peptide Search Engine**

Sage is a modern peptide search engine written in Rust, offering 10-100x speedup compared to traditional search engines while maintaining or exceeding sensitivity.

**Key Features:**
- Blazing fast: Rust-based implementation with parallel processing
- High sensitivity: Matches or exceeds traditional search engines
- Memory efficient: Handles large databases with minimal RAM
- Open source: MIT license, fully transparent algorithm

**Inputs:**
- **mzML**: Mass spectrometry data in open mzML format
- **FASTA**: Protein database for searching
- **Config JSON**: Search parameters (mass tolerance, modifications, etc.)

**Outputs:**
- **TSV**: Tab-separated results with peptide identifications
- **JSON**: Structured results for programmatic access
- **PIN**: Percolator input format for FDR control

**Citation:** Lazear MR. Sage: An Open-Source Tool for Fast Proteomics Searching and Quantification at Scale. J Proteome Res. 2023 Sep 1;22(9):3652-3659. doi: 10.1021/acs.jproteome.3c00486
    ]]></help>

    <citations>
        <citation type="doi">10.1021/acs.jproteome.3c00486</citation>
    </citations>
</tool>'''
    return xml

def generate_openms_xml(tool_id, config):
    """Generate generic OpenMS tool XML"""
    command = tool_id.split('_')[1].upper()  # Extract OpenMS command name

    xml = f'''<tool id="{tool_id}" name="{config['name']}" version="{config['version']}">
    <description>{config['description']}</description>

    <requirements>
        <container type="docker">{config['container']}</container>
    </requirements>

    <command detect_errors="exit_code"><![CDATA[
        {command}
            -in '$input'
            -out output.${{output_format}}
            -threads \\${{GALAXY_SLOTS:-4}}
    ]]></command>

    <inputs>
        <param name="input" type="data" format="mzml,mzxml" label="Input File"
               help="Input mass spectrometry data or identification file"/>

        <param name="output_format" type="select" label="Output Format">
            <option value="mzML" selected="true">mzML</option>
            <option value="idXML">idXML</option>
        </param>
    </inputs>

    <outputs>
        <data name="output" format_source="output_format" from_work_dir="output.*"
              label="${{tool.name}} on ${{on_string}}: Output"/>
    </outputs>

    <help><![CDATA[
**OpenMS {command}**

{config['description']}

OpenMS is a comprehensive open-source framework for LC-MS data analysis, providing modular tools for complete proteomics and metabolomics workflows.

**Citation:** Röst HL, Sachsenberg T, Aiche S, et al. OpenMS: a flexible open-source software platform for mass spectrometry data analysis. Nat Methods. 2016 Sep;13(9):741-8. doi: {config['citation']}
    ]]></help>

    <citations>
        <citation type="doi">{config['citation']}</citation>
    </citations>
</tool>'''
    return xml

def generate_maxquant_xml():
    """Generate MaxQuant LFQ tool XML"""
    xml = '''<tool id="maxquant_lfq" name="MaxQuant LFQ" version="2.4.3.0">
    <description>Label-free quantification for proteomics</description>

    <requirements>
        <container type="docker">biocontainers/maxquant:2.4.3.0--hdfd78af_1</container>
    </requirements>

    <command detect_errors="exit_code"><![CDATA[
        maxquant '$mqpar_xml'
    ]]></command>

    <inputs>
        <param name="mqpar_xml" type="data" format="xml" label="MaxQuant Parameter File (mqpar.xml)"
               help="MaxQuant configuration file specifying all analysis parameters"/>
    </inputs>

    <outputs>
        <collection name="output_tables" type="list" label="${tool.name} on ${on_string}: Output Tables">
            <discover_datasets pattern="(?P&lt;designation&gt;.+)\\.txt$" directory="combined/txt" format="tabular"/>
        </collection>
    </outputs>

    <help><![CDATA[
**MaxQuant Label-Free Quantification**

MaxQuant is the gold standard for label-free quantification in proteomics, providing accurate protein quantification with advanced algorithms for peak detection, alignment, and FDR control.

**Key Features:**
- Industry-standard LFQ algorithm
- Match-between-runs for improved coverage
- Advanced peak detection and quantification
- Built-in FDR control at peptide and protein level

**Input:**
- **mqpar.xml**: MaxQuant parameter file (generated using MaxQuant GUI or programmatically)

**Outputs:**
- **proteinGroups.txt**: Protein-level quantification results
- **peptides.txt**: Peptide-level results
- **evidence.txt**: MS/MS evidence table
- **summary.txt**: Run summary statistics

**Citation:** Cox J, Mann M. MaxQuant enables high peptide identification rates, individualized p.p.b.-range mass accuracies and proteome-wide protein quantification. Nat Biotechnol. 2008 Dec;26(12):1367-72. doi: 10.1038/nbt.1511
    ]]></help>

    <citations>
        <citation type="doi">10.1038/nbt.1511</citation>
    </citations>
</tool>'''
    return xml

def main():
    """Generate all tool XMLs and update index"""
    tools_dir = Path(__file__).parent.parent / "tools" / "nfcore_lcms"
    tools_dir.mkdir(parents=True, exist_ok=True)

    print(f"Generating nf-core LC-MS tool wrappers in {tools_dir}...")

    # Generate Sage
    sage_xml = generate_sage_xml()
    sage_path = tools_dir / "sageproteomics_sage.xml"
    sage_path.write_text(sage_xml)
    print(f"✓ Generated {sage_path.name}")

    # Generate OpenMS tools
    for tool_id, config in TOOL_CONFIGS.items():
        if tool_id.startswith("openms_"):
            xml = generate_openms_xml(tool_id, config)
            xml_path = tools_dir / f"{tool_id}.xml"
            xml_path.write_text(xml)
            print(f"✓ Generated {xml_path.name}")

    # Generate MaxQuant
    maxquant_xml = generate_maxquant_xml()
    maxquant_path = tools_dir / "maxquant_lfq.xml"
    maxquant_path.write_text(maxquant_xml)
    print(f"✓ Generated {maxquant_path.name}")

    print(f"\n✅ Generated {len(TOOL_CONFIGS)} tool wrappers")
    print(f"   Tools directory: {tools_dir}")

    return len(TOOL_CONFIGS)

if __name__ == "__main__":
    count = main()
    print(f"\nTotal tools generated: {count}")
