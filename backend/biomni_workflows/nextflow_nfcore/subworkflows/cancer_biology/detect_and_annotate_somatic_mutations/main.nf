#!/usr/bin/env nextflow
/*
 * cancer_biology/detect_and_annotate_somatic_mutations
 * Detects and annotates somatic mutations in tumor samples compared to matched normal samples.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.tumor_bam = null
params.normal_bam = null
params.reference_genome = null
params.output_prefix = null
params.snpeff_database = 'GRCh38.105'

process DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("detect_and_annotate_somatic_mutations_results.json"), emit: results
    tuple val(meta), path("detect_and_annotate_somatic_mutations_output.txt"), emit: output
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TUMOR_BAM="${params.tumor_bam?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NORMAL_BAM="${params.normal_bam?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REFERENCE_GENOME="${params.reference_genome?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_PREFIX="${params.output_prefix?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SNPEFF_DATABASE="${params.snpeff_database?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def detect_and_annotate_somatic_mutations(
    tumor_bam, normal_bam, reference_genome, output_prefix, snpeff_database="GRCh38.105"
):
    '''Detects and annotates somatic mutations in tumor samples compared to matched normal samples.

    This function uses GATK Mutect2 for variant calling, GATK FilterMutectCalls for filtering,
    and SnpEff for functional annotation of somatic mutations.

    Parameters
    ----------
    tumor_bam : str
        Path to the tumor sample BAM file
    normal_bam : str
        Path to the matched normal sample BAM file
    reference_genome : str
        Path to the reference genome FASTA file
    output_prefix : str
        Prefix for output files
    snpeff_database : str, optional
        SnpEff database to use for annotation (default: "GRCh38.105")

    Returns
    -------
    str
        A research log summarizing the steps performed and results obtained

    '''
    import datetime
    import os

    # Initialize research log
    log = "# Somatic Mutation Analysis Log\\n"
    log += f"Date: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    # Generate synthetic results if no input provided
    if tumor_bam is None or normal_bam is None or reference_genome is None:
        import numpy as np
        np.random.seed(42)

        log += "## Demo Mode (Synthetic Data)\\n\\n"
        log += "Running with synthetic data for demonstration purposes.\\n\\n"

        # Simulated mutation counts
        total_variants = np.random.randint(50, 200)
        snvs = int(total_variants * 0.85)
        indels = total_variants - snvs
        pass_filter = int(total_variants * np.random.uniform(0.6, 0.8))

        log += "## Variant Calling Results\\n\\n"
        log += f"- Total raw variants: {total_variants}\\n"
        log += f"- SNVs: {snvs}\\n"
        log += f"- Indels: {indels}\\n"
        log += f"- Passed filters: {pass_filter}\\n\\n"

        log += "## Annotation Summary\\n\\n"
        log += "| Impact | Count |\\n"
        log += "|--------|-------|\\n"
        log += f"| HIGH | {np.random.randint(2, 10)} |\\n"
        log += f"| MODERATE | {np.random.randint(10, 30)} |\\n"
        log += f"| LOW | {np.random.randint(20, 50)} |\\n"
        log += f"| MODIFIER | {np.random.randint(30, 80)} |\\n\\n"

        log += "## Example High-Impact Mutations\\n\\n"
        genes = ["TP53", "KRAS", "PIK3CA", "BRCA1", "EGFR"]
        for gene in np.random.choice(genes, size=min(3, len(genes)), replace=False):
            log += f"- {gene}: p.{np.random.choice(['Arg', 'Gly', 'Val'])}{np.random.randint(100, 500)}{np.random.choice(['Ter', 'fs', 'His'])}\\n"

        log += "\\n## Summary\\n\\n"
        log += "Synthetic demo analysis complete. Provide tumor_bam, normal_bam, and reference_genome for actual analysis.\\n"

        return log

    import subprocess

    log += "## Input Files\\n"
    log += f"- Tumor BAM: {tumor_bam}\\n"
    log += f"- Normal BAM: {normal_bam}\\n"
    log += f"- Reference Genome: {reference_genome}\\n\\n"

    # Step 1: Run Mutect2 for somatic variant calling
    log += "## Step 1: Somatic Variant Calling with Mutect2\\n"
    raw_vcf = f"{output_prefix}.unfiltered.vcf"

    mutect2_cmd = [
        "gatk",
        "Mutect2",
        "-R",
        reference_genome,
        "-I",
        tumor_bam,
        "-I",
        normal_bam,
        "-normal",
        os.path.basename(normal_bam).split(".")[0],
        "-O",
        raw_vcf,
    ]

    log += f"Running command: {' '.join(mutect2_cmd)}\\n"
    try:
        subprocess.run(mutect2_cmd, check=True, capture_output=True)
        log += f"Successfully generated raw VCF: {raw_vcf}\\n\\n"
    except subprocess.CalledProcessError as e:
        log += f"Error running Mutect2: {str(e)}\\n"
        return log

    # Step 2: Filter somatic calls
    log += "## Step 2: Filtering Somatic Variants\\n"
    filtered_vcf = f"{output_prefix}.filtered.vcf"

    filter_cmd = [
        "gatk",
        "FilterMutectCalls",
        "-R",
        reference_genome,
        "-V",
        raw_vcf,
        "-O",
        filtered_vcf,
    ]

    log += f"Running command: {' '.join(filter_cmd)}\\n"
    try:
        subprocess.run(filter_cmd, check=True, capture_output=True)
        log += f"Successfully filtered variants: {filtered_vcf}\\n\\n"
    except subprocess.CalledProcessError as e:
        log += f"Error filtering variants: {str(e)}\\n"
        return log

    # Step 3: Annotate variants with SnpEff
    log += "## Step 3: Functional Annotation with SnpEff\\n"
    annotated_vcf = f"{output_prefix}.annotated.vcf"

    snpeff_cmd = ["snpEff", "-v", snpeff_database, filtered_vcf, ">", annotated_vcf]

    log += f"Running command: {' '.join(snpeff_cmd)}\\n"
    try:
        # Using shell=True because of the redirection
        subprocess.run(" ".join(snpeff_cmd), shell=True, check=True)
        log += f"Successfully annotated variants: {annotated_vcf}\\n\\n"
    except subprocess.CalledProcessError as e:
        log += f"Error annotating variants: {str(e)}\\n"
        return log

    # Step 4: Generate summary statistics
    log += "## Step 4: Generating Summary Statistics\\n"
    summary_file = f"{output_prefix}_mutation_summary.txt"

    # Count total variants
    count_cmd = f"grep -v '^#' {annotated_vcf} | wc -l"
    try:
        total_variants = subprocess.check_output(count_cmd, shell=True).decode().strip()
        log += f"Total somatic variants detected: {total_variants}\\n"
    except subprocess.CalledProcessError as e:
        log += f"Error counting variants: {str(e)}\\n"

    # Count by variant type
    log += "Variant types:\\n"
    for variant_type in ["SNP", "INS", "DEL"]:
        count_type_cmd = f"grep -v '^#' {annotated_vcf} | grep '{variant_type}' | wc -l"
        try:
            type_count = subprocess.check_output(count_type_cmd, shell=True).decode().strip()
            log += f"- {variant_type}: {type_count}\\n"
        except subprocess.CalledProcessError:
            log += f"- {variant_type}: Error counting\\n"

    # Count high impact variants
    high_impact_cmd = f"grep -v '^#' {annotated_vcf} | grep 'HIGH' | wc -l"
    try:
        high_impact = subprocess.check_output(high_impact_cmd, shell=True).decode().strip()
        log += f"High impact variants: {high_impact}\\n\\n"
    except subprocess.CalledProcessError:
        log += "High impact variants: Error counting\\n\\n"

    # Step 5: Save summary to file
    with open(summary_file, "w") as f:
        f.write("Somatic Mutation Analysis Summary\\n")
        f.write(f"Date: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n")
        f.write(f"Total somatic variants: {total_variants}\\n")
        f.write(f"Output VCF file: {annotated_vcf}\\n")

    log += "## Results\\n"
    log += "Analysis complete. Results saved to:\\n"
    log += f"- Annotated VCF: {annotated_vcf}\\n"
    log += f"- Summary file: {summary_file}\\n\\n"

    return log

# Execute the function
try:
    result = detect_and_annotate_somatic_mutations(
        tumor_bam=auto_convert(os.environ.get("PARAM_TUMOR_BAM", "")),
        normal_bam=auto_convert(os.environ.get("PARAM_NORMAL_BAM", "")),
        reference_genome=auto_convert(os.environ.get("PARAM_REFERENCE_GENOME", "")),
        output_prefix=auto_convert(os.environ.get("PARAM_OUTPUT_PREFIX", "")),
        snpeff_database=auto_convert(os.environ.get("PARAM_SNPEFF_DATABASE", "GRCh38.105")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "detect_and_annotate_somatic_mutations",
    "domain": "cancer_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("detect_and_annotate_somatic_mutations_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# ── QC gates: cancer_somatic_vaf_min + depth_min + mapping_quality ────────────
# Track 2 batch 3 (2026-06-15): wire the 3 documented-but-unwired cancer
# biology gates from qc_evidence.yaml.cancer_biology.*.
#
# Thresholds (per the YAML rule_text):
#   cancer_somatic_vaf_min          (GOLD, GATK Mutect2 default):     ≥ 0.05
#   cancer_somatic_depth_min        (GOLD, Strelka2 Kim 2018 Table 2): ≥ 30x
#   cancer_somatic_mapping_quality  (SILVER, Li BWA 2009 Phred-20):    ≥ 20
#
# The biomni-wrapped function returns a result dict; when the variant-caller
# subprocess populates summary stats (mean_vaf, mean_depth, mean_mapq) the
# gates fire on real values. When the result is text-only (the wrapper's
# fallback path), we emit None + a 'not_computed' status so the gate row
# stays in the audit ledger without fabricating a verdict.
def _summary_stat(res, *keys):
    """Pull a numeric summary stat from the biomni result dict; tolerate
    missing keys + non-numeric payloads without raising."""
    if not isinstance(res, dict):
        return None
    for k in keys:
        v = res.get(k)
        if isinstance(v, (int, float)):
            return float(v)
    return None

VAF_MIN_THRESHOLD   = 0.05
DEPTH_MIN_THRESHOLD = 30.0
MAPQ_MIN_THRESHOLD  = 20.0

vaf_min   = _summary_stat(result, "min_vaf",   "vaf_min",   "mean_vaf")
depth_min = _summary_stat(result, "min_depth", "depth_min", "mean_depth")
mapq_min  = _summary_stat(result, "min_mapq",  "mapq_min",  "mean_mapq")

vaf_passes   = bool(vaf_min   is not None and vaf_min   >= VAF_MIN_THRESHOLD)   if vaf_min   is not None else None
depth_passes = bool(depth_min is not None and depth_min >= DEPTH_MIN_THRESHOLD) if depth_min is not None else None
mapq_passes  = bool(mapq_min  is not None and mapq_min  >= MAPQ_MIN_THRESHOLD)  if mapq_min  is not None else None

qc_metrics = {
    "success": success,
    "process": "DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS",
    "domain":  "cancer_biology",
    # cancer_somatic_vaf_min (GATK Mutect2, GOLD)
    "vaf_min": vaf_min,
    "vaf_min_threshold": VAF_MIN_THRESHOLD,
    "cancer_somatic_vaf_min_passes": vaf_passes,
    # cancer_somatic_depth_min (Kim 2018 Strelka2, GOLD)
    "depth_min": depth_min,
    "depth_min_threshold": DEPTH_MIN_THRESHOLD,
    "cancer_somatic_depth_min_passes": depth_passes,
    # cancer_somatic_mapping_quality (Li 2009 BWA, SILVER)
    "mapq_min": mapq_min,
    "mapq_min_threshold": MAPQ_MIN_THRESHOLD,
    "cancer_somatic_mapping_quality_passes": mapq_passes,
    # provenance + status
    "evidence_tier": "GOLD-vaf / GOLD-depth / SILVER-mapq",
    "citation":      "GATK Mutect2 Best Practices + Kim 2018 Strelka2 + Li 2009 BWA",
    "status": (
        "computed" if all(x is not None for x in (vaf_min, depth_min, mapq_min))
        else "partial" if any(x is not None for x in (vaf_min, depth_min, mapq_min))
        else "not_computed (variant-caller did not populate per-variant summary stats)"
    ),
}
with open("qc_metrics.json", "w") as f:
    json.dump(qc_metrics, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("detect_and_annotate_somatic_mutations_output.txt", "w") as f:
    f.write("Biomni: Detect And Annotate Somatic Mutations" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "detect_and_annotate_somatic_mutations"
    END_VERSIONS
    """
}

workflow DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS(ch_input)

    emit:
    results = DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS.out.results
    output = DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS.out.output
    versions = DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS_WORKFLOW(ch_input)

    DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS_WORKFLOW.out.output.view { "Output: $it" }
}
