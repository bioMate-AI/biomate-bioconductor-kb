#!/usr/bin/env python3
"""
Generate comprehensive Excel file with all workflows from Biomni, Galaxy IWC, and nf-core.
"""

import sqlite3
import json
import re
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter
from datetime import datetime

# Define nf-core pipelines based on official list
NFCORE_PIPELINES = [
    # RNA-seq & Transcriptomics
    {"name": "rnaseq", "category": "RNA-seq", "tools": "STAR, HISAT2, salmon, kallisto, featureCounts, DESeq2, edgeR", "subworkflows": "FASTQ_FASTQC_UMITOOLS_TRIMGALORE, ALIGN_STAR, QUANTIFY_RSEM"},
    {"name": "rnafusion", "category": "RNA-seq", "tools": "STAR-Fusion, Arriba, FusionCatcher, squid", "subworkflows": "ALIGN_STAR, BAM_SORT_STATS_SAMTOOLS"},
    {"name": "riboseq", "category": "RNA-seq", "tools": "STAR, bowtie2, samtools, ORFquant", "subworkflows": "FASTQ_TRIM_FASTP_FASTQC"},
    {"name": "scrnaseq", "category": "Single-Cell", "tools": "CellRanger, STARsolo, kallisto-bustools, alevin-fry", "subworkflows": "FASTQ_FASTQC_UMITOOLS_TRIMGALORE"},
    {"name": "scdownstream", "category": "Single-Cell", "tools": "Scanpy, Seurat, CellTypist, scVI", "subworkflows": "H5AD_REMOVEBACKGROUND_BARCODES_CELLBENDER_ANNDATA"},

    # Variant Calling
    {"name": "sarek", "category": "Variant Calling", "tools": "BWA, GATK, Mutect2, Strelka2, FreeBayes, DeepVariant, VEP, SnpEff", "subworkflows": "FASTQ_ALIGN_BWA, BAM_VARIANT_CALLING_GATK, VCF_ANNOTATE_ENSEMBLVEP"},
    {"name": "raredisease", "category": "Variant Calling", "tools": "BWA, GATK, DeepVariant, ExpansionHunter, VEP", "subworkflows": "FASTQ_ALIGN_BWA, BAM_VARIANT_CALLING_DEEPVARIANT"},
    {"name": "variantbenchmarking", "category": "Variant Calling", "tools": "hap.py, Truvari, vcfeval", "subworkflows": "VCF_QC_BCFTOOLS_VCFTOOLS"},

    # Metagenomics
    {"name": "ampliseq", "category": "Metagenomics", "tools": "DADA2, QIIME2, Cutadapt, Kraken2", "subworkflows": "FASTQ_TRIM_FASTP_FASTQC"},
    {"name": "mag", "category": "Metagenomics", "tools": "MEGAHIT, SPAdes, MetaBAT2, MaxBin2, GTDB-Tk", "subworkflows": "FASTA_BINNING_CONCOCT"},
    {"name": "taxprofiler", "category": "Metagenomics", "tools": "Kraken2, Bracken, MetaPhlAn, Centrifuge, DIAMOND, mOTUs", "subworkflows": "FASTQ_EXTRACT_KRAKEN_KRAKENTOOLS"},
    {"name": "funcscan", "category": "Metagenomics", "tools": "Prodigal, ABRicate, AMRFinderPlus, DeepARG", "subworkflows": "FAA_SEQFU_SEQKIT"},

    # Epigenetics
    {"name": "chipseq", "category": "Epigenetics", "tools": "BWA, bowtie2, MACS2, deepTools, HOMER", "subworkflows": "FASTQ_ALIGN_BWA, BAM_MARKDUPLICATES_PICARD"},
    {"name": "atacseq", "category": "Epigenetics", "tools": "BWA, bowtie2, MACS2, deepTools, HOMER, ATACseqQC", "subworkflows": "FASTQ_ALIGN_BWA, BAM_MARKDUPLICATES_PICARD"},
    {"name": "cutandrun", "category": "Epigenetics", "tools": "bowtie2, SEACR, MACS2, deepTools", "subworkflows": "FASTQ_ALIGN_BOWTIE2"},
    {"name": "methylseq", "category": "Epigenetics", "tools": "Bismark, bwa-meth, MethylDackel", "subworkflows": "FASTQ_ALIGN_DEDUP_BISMARK, FASTQ_ALIGN_DEDUP_BWAMETH"},
    {"name": "hic", "category": "Epigenetics", "tools": "HiCUP, cooler, HiCExplorer, Juicer", "subworkflows": "BAM_SORT_STATS_SAMTOOLS"},

    # Genome Assembly
    {"name": "genomeassembler", "category": "Assembly", "tools": "Hifiasm, Flye, Verkko, Shasta, BUSCO", "subworkflows": "FASTA_GXF_BUSCO_PLOT"},
    {"name": "genomeannotator", "category": "Assembly", "tools": "BRAKER, MAKER, Funannotate, RepeatModeler", "subworkflows": "FASTA_HMMSEARCH_RANK_FASTAS"},
    {"name": "bacass", "category": "Assembly", "tools": "Unicycler, SPAdes, Prokka, Quast", "subworkflows": "BAM_SORT_STATS_SAMTOOLS"},

    # Long-read Sequencing
    {"name": "nanoseq", "category": "Long-read", "tools": "minimap2, NanoPlot, pycoQC, Medaka", "subworkflows": "BAM_SORT_STATS_SAMTOOLS"},
    {"name": "longread", "category": "Long-read", "tools": "minimap2, Dorado, Guppy, Medaka", "subworkflows": "BAM_SORT_STATS_SAMTOOLS"},

    # Proteomics
    {"name": "quantms", "category": "Proteomics", "tools": "OpenMS, Comet, MSFragger, MaxQuant", "subworkflows": "DIA_PROTEOMICS_ANALYSIS"},
    {"name": "mhcquant", "category": "Proteomics", "tools": "OpenMS, Comet, Percolator", "subworkflows": ""},

    # Other domains
    {"name": "fetchngs", "category": "Data Fetching", "tools": "SRA-tools, ENA downloader", "subworkflows": "FASTQ_DOWNLOAD_PREFETCH_FASTERQDUMP_SRATOOLS"},
    {"name": "demultiplex", "category": "Pre-processing", "tools": "bcl2fastq, bcl-convert", "subworkflows": "BCL_DEMULTIPLEX"},
    {"name": "smrnaseq", "category": "Small RNA", "tools": "bowtie, miRDeep2, miRTop", "subworkflows": "FASTQ_FIND_MIRNA_MIRDEEP2"},
    {"name": "eager", "category": "Ancient DNA", "tools": "BWA, MapDamage2, DamageProfiler", "subworkflows": "FASTQ_ALIGN_BWAALN"},
    {"name": "spatialvi", "category": "Spatial", "tools": "Space Ranger, Scanpy, Squidpy", "subworkflows": "TIFF_SEGMENTATION_VPT"},
    {"name": "molkart", "category": "Imaging", "tools": "Cellpose, Mesmer, Stardist", "subworkflows": "TIFF_SEGMENTATION_VPT"},
    {"name": "viralrecon", "category": "Virology", "tools": "BWA, iVar, Pangolin, Nextclade", "subworkflows": "FASTQ_TRIM_FASTP_FASTQC, BAM_VARIANT_DEMIX_BOOT_FREYJA"},
    {"name": "pangenome", "category": "Pangenomics", "tools": "PGGB, VG, Minigraph-Cactus", "subworkflows": ""},
    {"name": "epitopeprediction", "category": "Immunoinformatics", "tools": "MHCflurry, MHCnuggets, NetMHC", "subworkflows": ""},
    {"name": "differentialabundance", "category": "Transcriptomics", "tools": "DESeq2, edgeR, limma", "subworkflows": "DIFFERENTIAL_FUNCTIONAL_ENRICHMENT"},
    {"name": "circdna", "category": "Genomics", "tools": "Circle-Map, CIRCexplorer2", "subworkflows": "BAM_SORT_STATS_SAMTOOLS"},
    {"name": "phageannotator", "category": "Virology", "tools": "VIBRANT, VirSorter2, CheckV", "subworkflows": ""},
    {"name": "crisprseq", "category": "CRISPR", "tools": "MAGeCK, CRISPResso2", "subworkflows": ""},
    {"name": "airrflow", "category": "Immunology", "tools": "IgBLAST, pRESTO, Change-O", "subworkflows": ""},
    {"name": "bamtofastq", "category": "Utilities", "tools": "samtools, picard", "subworkflows": "BAM_CONVERT_SAMTOOLS"},
    {"name": "createpanelrefs", "category": "Variant Calling", "tools": "GATK CreateSomaticPanelOfNormals", "subworkflows": "BAM_CREATE_SOM_PON_GATK"},
    {"name": "denovohybrid", "category": "Assembly", "tools": "Unicycler, SPAdes, Flye", "subworkflows": ""},
    {"name": "detaxizer", "category": "Metagenomics", "tools": "Kraken2, BLAST, BWA", "subworkflows": "FASTQ_CONTAM_SEQTK_KRAKEN"},
    {"name": "isoseq", "category": "Long-read", "tools": "IsoSeq3, SQANTI3, CPAT", "subworkflows": ""},
    {"name": "multiplesequencealign", "category": "Phylogenetics", "tools": "MAFFT, Clustal Omega, MUSCLE, T-Coffee", "subworkflows": ""},
    {"name": "nascent", "category": "Transcriptomics", "tools": "BWA, HOMER, Tfit", "subworkflows": "HOMER_GROSEQ"},
    {"name": "nanostring", "category": "Expression", "tools": "NanoStringQCPro, nacho", "subworkflows": ""},
    {"name": "neutronstar", "category": "Long-read", "tools": "Supernova, Longranger", "subworkflows": ""},
    {"name": "phyloplace", "category": "Phylogenetics", "tools": "EPA-ng, GAPPA, RAxML", "subworkflows": "FASTA_NEWICK_EPANG_GAPPA"},
    {"name": "proteinfold", "category": "Structural", "tools": "AlphaFold, ESMFold, ColabFold", "subworkflows": ""},
    {"name": "radseq", "category": "Population Genetics", "tools": "Stacks, dDocent, ipyrad", "subworkflows": ""},
    {"name": "reportho", "category": "Comparative", "tools": "OrthoFinder, BLAST", "subworkflows": ""},
    {"name": "rnasplice", "category": "RNA-seq", "tools": "rMATS, SUPPA2, Leafcutter", "subworkflows": "ALIGN_STAR"},
    {"name": "scflow", "category": "Single-Cell", "tools": "Scanpy, scVI, CellBender", "subworkflows": ""},
    {"name": "spinningjenny", "category": "Metagenomics", "tools": "Kraken2, GTDB-Tk", "subworkflows": ""},
    {"name": "ssds", "category": "Epigenetics", "tools": "BWA, MACS2, deepTools", "subworkflows": ""},
    {"name": "taxpasta", "category": "Metagenomics", "tools": "taxpasta, pandas", "subworkflows": ""},
    {"name": "variantcatalogue", "category": "Variant Calling", "tools": "GATK, VEP, gnomAD", "subworkflows": ""},
]

# Define Biomni functions/tools
BIOMNI_FUNCTIONS = [
    # Scanpy functions
    {"name": "scanpy.read_h5ad", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.pp.filter_cells", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.pp.filter_genes", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.pp.normalize_total", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.pp.log1p", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.pp.highly_variable_genes", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.tl.pca", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.pp.neighbors", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.tl.umap", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.tl.leiden", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.tl.rank_genes_groups", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},
    {"name": "scanpy.pl.umap", "category": "Single-Cell", "tools": "Scanpy", "type": "Python function"},

    # gget functions
    {"name": "gget.ref", "category": "Data Retrieval", "tools": "gget", "type": "Python function"},
    {"name": "gget.search", "category": "Data Retrieval", "tools": "gget", "type": "Python function"},
    {"name": "gget.info", "category": "Data Retrieval", "tools": "gget", "type": "Python function"},
    {"name": "gget.seq", "category": "Data Retrieval", "tools": "gget", "type": "Python function"},
    {"name": "gget.blast", "category": "Sequence Analysis", "tools": "gget", "type": "Python function"},
    {"name": "gget.enrichr", "category": "Functional Analysis", "tools": "gget", "type": "Python function"},
    {"name": "gget.archs4", "category": "Expression", "tools": "gget", "type": "Python function"},
    {"name": "gget.alphafold", "category": "Structural", "tools": "gget", "type": "Python function"},
    {"name": "gget.pdb", "category": "Structural", "tools": "gget", "type": "Python function"},

    # Biopython functions
    {"name": "Bio.SeqIO.parse", "category": "Sequence I/O", "tools": "Biopython", "type": "Python function"},
    {"name": "Bio.SeqIO.read", "category": "Sequence I/O", "tools": "Biopython", "type": "Python function"},
    {"name": "Bio.SeqIO.write", "category": "Sequence I/O", "tools": "Biopython", "type": "Python function"},
    {"name": "Bio.Blast.NCBIWWW.qblast", "category": "Sequence Analysis", "tools": "Biopython", "type": "Python function"},
    {"name": "Bio.AlignIO.read", "category": "Alignment", "tools": "Biopython", "type": "Python function"},
    {"name": "Bio.Phylo.read", "category": "Phylogenetics", "tools": "Biopython", "type": "Python function"},

    # Pandas/analysis functions
    {"name": "pandas.read_csv", "category": "Data I/O", "tools": "Pandas", "type": "Python function"},
    {"name": "pandas.DataFrame.merge", "category": "Data Processing", "tools": "Pandas", "type": "Python function"},
    {"name": "pandas.DataFrame.groupby", "category": "Data Processing", "tools": "Pandas", "type": "Python function"},

    # CLI tools via subprocess
    {"name": "samtools_view", "category": "BAM Processing", "tools": "samtools", "type": "CLI wrapper"},
    {"name": "samtools_sort", "category": "BAM Processing", "tools": "samtools", "type": "CLI wrapper"},
    {"name": "samtools_index", "category": "BAM Processing", "tools": "samtools", "type": "CLI wrapper"},
    {"name": "bwa_mem", "category": "Alignment", "tools": "BWA", "type": "CLI wrapper"},
    {"name": "star_align", "category": "Alignment", "tools": "STAR", "type": "CLI wrapper"},
    {"name": "hisat2_align", "category": "Alignment", "tools": "HISAT2", "type": "CLI wrapper"},
    {"name": "salmon_quant", "category": "Quantification", "tools": "salmon", "type": "CLI wrapper"},
    {"name": "kallisto_quant", "category": "Quantification", "tools": "kallisto", "type": "CLI wrapper"},
    {"name": "fastqc", "category": "QC", "tools": "FastQC", "type": "CLI wrapper"},
    {"name": "fastp_trim", "category": "QC", "tools": "fastp", "type": "CLI wrapper"},
    {"name": "multiqc", "category": "QC", "tools": "MultiQC", "type": "CLI wrapper"},
    {"name": "bcftools_call", "category": "Variant Calling", "tools": "bcftools", "type": "CLI wrapper"},
    {"name": "bedtools_intersect", "category": "Genomic Intervals", "tools": "bedtools", "type": "CLI wrapper"},
    {"name": "seqkit_stats", "category": "Sequence Analysis", "tools": "seqkit", "type": "CLI wrapper"},
    {"name": "mafft_align", "category": "Alignment", "tools": "MAFFT", "type": "CLI wrapper"},
    {"name": "blast_search", "category": "Sequence Analysis", "tools": "BLAST", "type": "CLI wrapper"},
]


def get_galaxy_workflows(db_path):
    """Get Galaxy IWC workflows from database."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT id, name, domain, tools_used FROM workflows ORDER BY id")
    rows = cursor.fetchall()
    conn.close()

    workflows = []
    for row in rows:
        wf_id, name, domain, tools_json = row

        # Determine source based on workflow name pattern
        if name.isupper() or "_" in name and name.split("_")[0].isupper():
            source = "nf-core"
        else:
            source = "Galaxy IWC"

        # Parse tools
        tools = []
        if tools_json:
            try:
                tool_list = json.loads(tools_json)
                for t in tool_list:
                    # Extract tool name from toolshed path
                    if "Repository_Actions_" in t:
                        tool_name = t.split("Repository_Actions_")[-1].replace("_", " ")
                        tools.append(tool_name)
                    elif "/" in t:
                        tool_name = t.split("/")[-1]
                        tools.append(tool_name)
                    else:
                        tools.append(t)
            except:
                tools = []

        # Categorize based on domain or name
        category = domain or "General"
        if "RNA" in name.upper() or "RNASEQ" in name.upper():
            category = "RNA-seq"
        elif "CHIP" in name.upper() or "ATAC" in name.upper():
            category = "Epigenetics"
        elif "VARIANT" in name.upper() or "VCF" in name.upper() or "COVID" in name.upper():
            category = "Variant Calling"
        elif "SINGLE" in name.upper() or "SCANPY" in name.upper():
            category = "Single-Cell"
        elif "METAG" in name.upper() or "QIIME" in name.upper() or "MGNIFY" in name.upper():
            category = "Metagenomics"
        elif "ALIGN" in name.upper() or "BWA" in name.upper() or "STAR" in name.upper():
            category = "Alignment"
        elif "ASSEMBLY" in name.upper() or "VGP" in name.upper():
            category = "Assembly"
        elif "HI-C" in name.upper() or "HIC" in name.upper():
            category = "Epigenetics"
        elif "PROTEOM" in name.upper():
            category = "Proteomics"

        workflows.append({
            "name": name,
            "source": source,
            "category": category,
            "tools": ", ".join(list(set(tools))[:10]),  # Limit to 10 unique tools
            "subworkflows": ""
        })

    return workflows


def create_excel(output_path, db_path):
    """Create comprehensive Excel file."""

    wb = Workbook()
    ws = wb.active
    ws.title = "All Workflows"

    # Define headers
    headers = [
        "ID", "Workflow Name", "Source", "Category",
        "Tools Used", "Subworkflows/Functions", "Notes"
    ]

    # Style definitions
    header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
    header_font = Font(bold=True, color="FFFFFF")
    border = Border(
        left=Side(style='thin'),
        right=Side(style='thin'),
        top=Side(style='thin'),
        bottom=Side(style='thin')
    )

    galaxy_fill = PatternFill(start_color="E2EFDA", end_color="E2EFDA", fill_type="solid")
    nfcore_fill = PatternFill(start_color="FCE4D6", end_color="FCE4D6", fill_type="solid")
    biomni_fill = PatternFill(start_color="DEEBF7", end_color="DEEBF7", fill_type="solid")

    # Write headers
    for col, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col, value=header)
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(horizontal='center', vertical='center')
        cell.border = border

    # Get Galaxy workflows from database
    galaxy_workflows = get_galaxy_workflows(db_path)

    # Combine all data
    all_rows = []
    row_id = 1

    # Add Galaxy IWC workflows
    for wf in galaxy_workflows:
        if wf["source"] == "Galaxy IWC":
            all_rows.append({
                "id": row_id,
                "name": wf["name"],
                "source": "Galaxy IWC",
                "category": wf["category"],
                "tools": wf["tools"],
                "subworkflows": "",
                "notes": "From Galaxy IWC repository"
            })
            row_id += 1

    # Add nf-core pipelines from database (uppercase names)
    for wf in galaxy_workflows:
        if wf["source"] == "nf-core":
            all_rows.append({
                "id": row_id,
                "name": wf["name"],
                "source": "nf-core (subworkflow)",
                "category": wf["category"],
                "tools": wf["tools"],
                "subworkflows": wf["name"],
                "notes": "nf-core subworkflow/module"
            })
            row_id += 1

    # Add nf-core pipelines from curated list
    for pipeline in NFCORE_PIPELINES:
        all_rows.append({
            "id": row_id,
            "name": f"nf-core/{pipeline['name']}",
            "source": "nf-core (pipeline)",
            "category": pipeline["category"],
            "tools": pipeline["tools"],
            "subworkflows": pipeline["subworkflows"],
            "notes": "Main nf-core pipeline"
        })
        row_id += 1

    # Add Biomni functions
    for func in BIOMNI_FUNCTIONS:
        all_rows.append({
            "id": row_id,
            "name": func["name"],
            "source": "Biomni",
            "category": func["category"],
            "tools": func["tools"],
            "subworkflows": "",
            "notes": func["type"]
        })
        row_id += 1

    # Write data rows
    for row_num, row_data in enumerate(all_rows, 2):
        ws.cell(row=row_num, column=1, value=row_data["id"]).border = border
        ws.cell(row=row_num, column=2, value=row_data["name"]).border = border
        ws.cell(row=row_num, column=3, value=row_data["source"]).border = border
        ws.cell(row=row_num, column=4, value=row_data["category"]).border = border
        ws.cell(row=row_num, column=5, value=row_data["tools"]).border = border
        ws.cell(row=row_num, column=6, value=row_data["subworkflows"]).border = border
        ws.cell(row=row_num, column=7, value=row_data["notes"]).border = border

        # Apply source-based coloring
        if "Galaxy" in row_data["source"]:
            fill = galaxy_fill
        elif "nf-core" in row_data["source"]:
            fill = nfcore_fill
        elif "Biomni" in row_data["source"]:
            fill = biomni_fill
        else:
            fill = None

        if fill:
            for col in range(1, 8):
                ws.cell(row=row_num, column=col).fill = fill

    # Adjust column widths
    column_widths = [8, 60, 20, 20, 80, 50, 30]
    for col, width in enumerate(column_widths, 1):
        ws.column_dimensions[get_column_letter(col)].width = width

    # Create summary sheet
    ws_summary = wb.create_sheet("Summary")

    summary_data = [
        ["Source", "Count"],
        ["Galaxy IWC", len([r for r in all_rows if "Galaxy" in r["source"]])],
        ["nf-core (pipelines)", len(NFCORE_PIPELINES)],
        ["nf-core (subworkflows)", len([r for r in all_rows if "nf-core (subworkflow)" in r["source"]])],
        ["Biomni", len(BIOMNI_FUNCTIONS)],
        ["", ""],
        ["Total Entries", len(all_rows)],
    ]

    for row_num, row_data in enumerate(summary_data, 1):
        for col_num, value in enumerate(row_data, 1):
            cell = ws_summary.cell(row=row_num, column=col_num, value=value)
            if row_num == 1:
                cell.fill = header_fill
                cell.font = header_font
            cell.border = border

    ws_summary.column_dimensions['A'].width = 25
    ws_summary.column_dimensions['B'].width = 15

    # Create category breakdown sheet
    ws_cats = wb.create_sheet("By Category")

    # Count by category
    cat_counts = {}
    for row in all_rows:
        cat = row["category"]
        if cat not in cat_counts:
            cat_counts[cat] = {"Galaxy": 0, "nf-core": 0, "Biomni": 0}
        if "Galaxy" in row["source"]:
            cat_counts[cat]["Galaxy"] += 1
        elif "nf-core" in row["source"]:
            cat_counts[cat]["nf-core"] += 1
        elif "Biomni" in row["source"]:
            cat_counts[cat]["Biomni"] += 1

    cat_headers = ["Category", "Galaxy IWC", "nf-core", "Biomni", "Total"]
    for col, header in enumerate(cat_headers, 1):
        cell = ws_cats.cell(row=1, column=col, value=header)
        cell.fill = header_fill
        cell.font = header_font
        cell.border = border

    for row_num, (cat, counts) in enumerate(sorted(cat_counts.items()), 2):
        total = sum(counts.values())
        ws_cats.cell(row=row_num, column=1, value=cat).border = border
        ws_cats.cell(row=row_num, column=2, value=counts["Galaxy"]).border = border
        ws_cats.cell(row=row_num, column=3, value=counts["nf-core"]).border = border
        ws_cats.cell(row=row_num, column=4, value=counts["Biomni"]).border = border
        ws_cats.cell(row=row_num, column=5, value=total).border = border

    ws_cats.column_dimensions['A'].width = 25
    ws_cats.column_dimensions['B'].width = 15
    ws_cats.column_dimensions['C'].width = 12
    ws_cats.column_dimensions['D'].width = 12
    ws_cats.column_dimensions['E'].width = 10

    # Save workbook
    wb.save(output_path)
    print(f"Excel file created: {output_path}")

    return len(all_rows)


if __name__ == "__main__":
    db_path = "/home/yzhang/biomate/backend/galaxy_ai_tools.db"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    output_path = f"/home/yzhang/biomate/backend/{timestamp}_COMPREHENSIVE_WORKFLOW_INVENTORY.xlsx"

    total = create_excel(output_path, db_path)
    print(f"Total entries: {total}")
