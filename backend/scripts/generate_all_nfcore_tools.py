#!/usr/bin/env python3
"""
Generate Galaxy tool wrappers for ALL nf-core modules that overlap with BioMni.
This expands beyond just LC-MS to cover genomics, single-cell, and other domains.
"""

import json
from pathlib import Path
from datetime import datetime

# All 23 tools from BioMni-nfcore crossover + additional high-priority tools
COMPREHENSIVE_TOOL_CONFIGS = {
    # Genomics & Alignment (High Priority)
    "samtools_sort": {"container": "biocontainers/samtools:1.19.2--h50ea8bc_1", "version": "1.19.2", "category": "genomics"},
    "samtools_index": {"container": "biocontainers/samtools:1.19.2--h50ea8bc_1", "version": "1.19.2", "category": "genomics"},
    "samtools_view": {"container": "biocontainers/samtools:1.19.2--h50ea8bc_1", "version": "1.19.2", "category": "genomics"},
    "samtools_flagstat": {"container": "biocontainers/samtools:1.19.2--h50ea8bc_1", "version": "1.19.2", "category": "genomics"},
    "bwa_mem": {"container": "biocontainers/bwa:0.7.17--he4a0461_11", "version": "0.7.17", "category": "genomics"},
    "bwa_index": {"container": "biocontainers/bwa:0.7.17--he4a0461_11", "version": "0.7.17", "category": "genomics"},
    "bowtie2_align": {"container": "biocontainers/bowtie2:2.5.3--hd9f7b48_0", "version": "2.5.3", "category": "genomics"},
    "bowtie2_build": {"container": "biocontainers/bowtie2:2.5.3--hd9f7b48_0", "version": "2.5.3", "category": "genomics"},

    # Bedtools Suite (22 modules)
    "bedtools_intersect": {"container": "biocontainers/bedtools:2.31.1--hf5e1c6e_1", "version": "2.31.1", "category": "genomics"},
    "bedtools_merge": {"container": "biocontainers/bedtools:2.31.1--hf5e1c6e_1", "version": "2.31.1", "category": "genomics"},
    "bedtools_sort": {"container": "biocontainers/bedtools:2.31.1--hf5e1c6e_1", "version": "2.31.1", "category": "genomics"},
    "bedtools_coverage": {"container": "biocontainers/bedtools:2.31.1--hf5e1c6e_1", "version": "2.31.1", "category": "genomics"},
    "bedtools_genomecov": {"container": "biocontainers/bedtools:2.31.1--hf5e1c6e_1", "version": "2.31.1", "category": "genomics"},

    # QC Tools
    "fastqc": {"container": "biocontainers/fastqc:0.12.1--hdfd78af_0", "version": "0.12.1", "category": "qc"},
    "trimmomatic": {"container": "biocontainers/trimmomatic:0.39--hdfd78af_2", "version": "0.39", "category": "qc"},

    # Single-cell & RNA-seq
    "scanpy_filter": {"container": "biocontainers/scanpy:1.9.6--pyhdfd78af_0", "version": "1.9.6", "category": "single_cell"},
    "scanpy_pca": {"container": "biocontainers/scanpy:1.9.6--pyhdfd78af_0", "version": "1.9.6", "category": "single_cell"},
    "deseq2_differential": {"container": "biocontainers/bioconductor-deseq2:1.42.0--r43hf17093f_0", "version": "1.42.0", "category": "rna_seq"},
    "limma_differential": {"container": "biocontainers/bioconductor-limma:3.58.1--r43hf17093f_0", "version": "3.58.1", "category": "rna_seq"},

    # Epigenomics
    "macs2_callpeak": {"container": "biocontainers/macs2:2.2.9.1--py310h4b81fae_0", "version": "2.2.9.1", "category": "epigenomics"},
    "homer_findpeaks": {"container": "biocontainers/homer:4.11--pl5321h2c4f38d_6", "version": "4.11", "category": "epigenomics"},
    "homer_annotatepeaks": {"container": "biocontainers/homer:4.11--pl5321h2c4f38d_6", "version": "4.11", "category": "epigenomics"},

    # Hi-C / Chromatin
    "cooler_balance": {"container": "biocontainers/cooler:0.9.3--pyh7cba7a3_0", "version": "0.9.3", "category": "hic"},
    "cooler_zoomify": {"container": "biocontainers/cooler:0.9.3--pyh7cba7a3_0", "version": "0.9.3", "category": "hic"},

    # Phylogenetics
    "fasttree": {"container": "biocontainers/fasttree:2.1.11--h031d066_3", "version": "2.1.11", "category": "phylogenetics"},
    "mafft_align": {"container": "biocontainers/mafft:7.520--h031d066_3", "version": "7.520", "category": "phylogenetics"},
    "iqtree": {"container": "biocontainers/iqtree:2.3.4--h21ec9f0_0", "version": "2.3.4", "category": "phylogenetics"},
    "muscle": {"container": "biocontainers/muscle:5.1.0--h4ac6f70_3", "version": "5.1.0", "category": "phylogenetics"},

    # Variant Analysis
    "plink2_vcf": {"container": "biocontainers/plink2:2.00a5--h4ac6f70_0", "version": "2.00a5", "category": "variants"},
    "plink2_pca": {"container": "biocontainers/plink2:2.00a5--h4ac6f70_0", "version": "2.00a5", "category": "variants"},

    # Format Conversion & Utilities
    "biomformat_convert": {"container": "biocontainers/biom-format:2.1.15--pyhdfd78af_0", "version": "2.1.15", "category": "utilities"},
    "anndata_barcodes": {"container": "biocontainers/anndata:0.10.5.post1--pyhdfd78af_0", "version": "0.10.5", "category": "single_cell"},

    # Image Analysis
    "cellpose": {"container": "biocontainers/cellpose:3.0.5--pyhdfd78af_0", "version": "3.0.5", "category": "imaging"},

    # CRISPR
    "mageck_count": {"container": "biocontainers/mageck:0.5.9.5--py39h1f90b4d_0", "version": "0.5.9.5", "category": "crispr"},
    "mageck_test": {"container": "biocontainers/mageck:0.5.9.5--py39h1f90b4d_0", "version": "0.5.9.5", "category": "crispr"},
}

def generate_generic_tool_xml(tool_id, config):
    """Generate generic Galaxy tool XML for any nf-core module"""
    tool_name = tool_id.replace('_', ' ').title()
    category = config['category']

    xml = f'''<tool id="{tool_id}" name="{tool_name}" version="{config['version']}">
    <description>nf-core {tool_id} module</description>

    <requirements>
        <container type="docker">{config['container']}</container>
    </requirements>

    <command detect_errors="exit_code"><![CDATA[
        {tool_id.split('_')[0]}
            #if $input
                -i '$input'
            #end if
            -o output
            #if $threads
                -t \\${{GALAXY_SLOTS:-$threads}}
            #end if
    ]]></command>

    <inputs>
        <param name="input" type="data" format="auto" label="Input File" optional="true"
               help="Input data file for processing"/>
        <param name="threads" type="integer" value="4" min="1" max="32" label="Number of Threads"
               help="Number of CPU threads to use"/>
    </inputs>

    <outputs>
        <data name="output" format="auto" from_work_dir="output*"
              label="${{tool.name}} on ${{on_string}}: Output"/>
    </outputs>

    <help><![CDATA[
**{tool_name} (nf-core module)**

Category: {category}

This is a Galaxy wrapper for the nf-core {tool_id} module.

**More Information:**
- nf-core modules: https://github.com/nf-core/modules
- Container: {config['container']}
    ]]></help>

    <citations>
        <citation type="bibtex">@misc{{nfcore,
            title = {{nf-core: Community curated bioinformatics pipelines}},
            url = {{https://nf-co.re}},
            year = {{2024}}
        }}</citation>
    </citations>
</tool>'''
    return xml

def main():
    """Generate all tool wrappers"""
    tools_dir = Path(__file__).parent.parent / "tools" / "nfcore_general"
    tools_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n{'='*70}")
    print(f"Generating {len(COMPREHENSIVE_TOOL_CONFIGS)} nf-core tool wrappers")
    print(f"{'='*70}\n")

    categories_count = {}
    for tool_id, config in COMPREHENSIVE_TOOL_CONFIGS.items():
        xml = generate_generic_tool_xml(tool_id, config)
        xml_path = tools_dir / f"{tool_id}.xml"
        xml_path.write_text(xml)

        category = config['category']
        categories_count[category] = categories_count.get(category, 0) + 1
        print(f"✓ Generated {xml_path.name} ({category})")

    print(f"\n{'='*70}")
    print("GENERATION COMPLETE")
    print(f"{'='*70}\n")
    print(f"Total tools generated: {len(COMPREHENSIVE_TOOL_CONFIGS)}")
    print(f"\nBy category:")
    for category, count in sorted(categories_count.items()):
        print(f"  {category}: {count} tools")

    print(f"\n✅ All tool wrappers saved to: {tools_dir}")

    return len(COMPREHENSIVE_TOOL_CONFIGS)

if __name__ == "__main__":
    count = main()
    print(f"\n🎉 Successfully generated {count} tool wrappers!")
