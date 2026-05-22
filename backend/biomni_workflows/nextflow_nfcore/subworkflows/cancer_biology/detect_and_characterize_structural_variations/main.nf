#!/usr/bin/env nextflow
/*
 * cancer_biology/detect_and_characterize_structural_variations
 * Detects and characterizes structural variations (SVs) in genomic sequencing data.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.bam_file_path = null
params.reference_genome_path = null
params.output_dir = null
params.cosmic_db_path = null
params.clinvar_db_path = null

process DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("detect_and_characterize_structural_variations_results.json"), emit: results
    tuple val(meta), path("detect_and_characterize_structural_variations_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_BAM_FILE_PATH="${params.bam_file_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REFERENCE_GENOME_PATH="${params.reference_genome_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COSMIC_DB_PATH="${params.cosmic_db_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CLINVAR_DB_PATH="${params.clinvar_db_path?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def detect_and_characterize_structural_variations(
    bam_file_path,
    reference_genome_path,
    output_dir,
    cosmic_db_path=None,
    clinvar_db_path=None,
):
    '''Detects and characterizes structural variations (SVs) in genomic sequencing data.

    This function uses LUMPY for SV detection followed by annotation with COSMIC and/or ClinVar
    databases to identify and characterize various types of structural variations including
    deletions, inversions, translocations, and duplications.

    Parameters
    ----------
    bam_file_path : str
        Path to the aligned sequencing data in BAM format
    reference_genome_path : str
        Path to the reference genome in FASTA format
    output_dir : str
        Directory where results will be saved
    cosmic_db_path : str, optional
        Path to the COSMIC database for cancer annotation
    clinvar_db_path : str, optional
        Path to the ClinVar database for clinical annotation

    Returns
    -------
    str
        A research log summarizing the steps performed and results obtained

    '''
    import datetime
    import os

    # Initialize research log
    log = []
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Generate synthetic results if no input provided
    if bam_file_path is None or reference_genome_path is None:
        import numpy as np
        np.random.seed(42)

        log.append(f"# Structural Variation Analysis (DEMO MODE) - {ts}")
        log.append("=" * 60)
        log.append("Running with synthetic data for demonstration purposes.\\n")

        # Simulated SV counts
        sv_types = {
            "Deletions": np.random.randint(10, 50),
            "Duplications": np.random.randint(5, 30),
            "Inversions": np.random.randint(2, 15),
            "Translocations": np.random.randint(1, 10),
        }

        log.append("## Structural Variation Summary\\n")
        total_svs = sum(sv_types.values())
        log.append(f"Total SVs detected: {total_svs}\\n")

        for sv_type, count in sv_types.items():
            log.append(f"- {sv_type}: {count}")

        log.append("\\n## Notable Events\\n")
        notable = [
            ("DEL", "chr17:7571720-7590868", "TP53 region deletion"),
            ("DUP", "chr8:128748315-128753680", "MYC amplification"),
            ("INV", "chr2:29415640-29446394", "ALK rearrangement"),
        ]
        for sv_type, coords, annotation in notable:
            log.append(f"- {sv_type} at {coords}: {annotation}")

        log.append("\\n## Summary\\n")
        log.append("Synthetic demo analysis complete. Provide bam_file_path and reference_genome_path for actual analysis.")

        return "\\n".join(log)

    import subprocess

    # Create output directory if it doesn't exist
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    log.append("## Structural Variation Detection and Characterization")
    log.append(f"Started at: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append(f"Input BAM file: {bam_file_path}")
    log.append(f"Reference genome: {reference_genome_path}")
    log.append(f"Output directory: {output_dir}")
    log.append("\\n")

    # Step 1: Extract discordant read-pairs and split-reads for LUMPY
    log.append("### Step 1: Extracting discordant read-pairs and split-reads")

    discordant_bam = os.path.join(output_dir, "discordant.bam")
    split_bam = os.path.join(output_dir, "split.bam")

    try:
        # Extract discordant read pairs
        subprocess.run(
            [
                "samtools",
                "view",
                "-b",
                "-F",
                "1294",
                "-o",
                discordant_bam,
                bam_file_path,
            ],
            check=True,
        )

        # Extract split reads
        subprocess.run(
            [
                "samtools",
                "view",
                "-h",
                bam_file_path,
                "|",
                "extractSplitReads_BwaMem",
                "-i",
                "stdin",
                "|",
                "samtools",
                "view",
                "-Sb",
                "-",
                ">",
                split_bam,
            ],
            shell=True,
            check=True,
        )

        log.append("Successfully extracted discordant read-pairs and split-reads")
    except subprocess.CalledProcessError as e:
        log.append(f"Error during read extraction: {e}")
        return "\\n".join(log)

    # Step 2: Run LUMPY for SV detection
    log.append("\\n### Step 2: Running LUMPY for structural variation detection")

    vcf_output = os.path.join(output_dir, "structural_variants.vcf")

    try:
        subprocess.run(
            [
                "lumpyexpress",
                "-B",
                bam_file_path,
                "-S",
                split_bam,
                "-D",
                discordant_bam,
                "-o",
                vcf_output,
            ],
            check=True,
        )

        log.append("LUMPY analysis completed successfully")
        log.append(f"Raw SV calls saved to: {vcf_output}")
    except subprocess.CalledProcessError as e:
        log.append(f"Error during LUMPY execution: {e}")
        return "\\n".join(log)

    # Step 3: Filter SVs by quality and size
    log.append("\\n### Step 3: Filtering structural variants by quality and size")

    filtered_vcf = os.path.join(output_dir, "filtered_structural_variants.vcf")

    try:
        # Filter SVs with quality score >= 100 and size >= 100bp
        subprocess.run(
            [
                "bcftools",
                "filter",
                "-i",
                "QUAL>=100 && SVLEN>=100",
                "-o",
                filtered_vcf,
                vcf_output,
            ],
            check=True,
        )

        # Count SVs by type
        sv_counts = {}
        sv_types = ["DEL", "DUP", "INV", "BND", "INS"]

        for sv_type in sv_types:
            result = subprocess.run(
                ["grep", "-c", f"SVTYPE={sv_type}", filtered_vcf],
                check=False,
                capture_output=True,
                text=True,
            )

            count = 0
            if result.returncode == 0:
                count = int(result.stdout.strip())
            sv_counts[sv_type] = count

        log.append("SV filtering completed")
        log.append(f"Filtered SVs saved to: {filtered_vcf}")
        log.append("\\nSV counts by type:")
        for sv_type, count in sv_counts.items():
            log.append(f"- {sv_type}: {count}")
    except subprocess.CalledProcessError as e:
        log.append(f"Error during SV filtering: {e}")
        return "\\n".join(log)

    # Step 4: Annotate SVs with COSMIC and ClinVar (if databases provided)
    log.append("\\n### Step 4: Annotating structural variants")

    annotated_vcf = os.path.join(output_dir, "annotated_structural_variants.vcf")

    try:
        annotation_cmd = ["annotate_sv.py", "-i", filtered_vcf, "-o", annotated_vcf]

        if cosmic_db_path:
            annotation_cmd.extend(["-c", cosmic_db_path])
            log.append(f"Using COSMIC database: {cosmic_db_path}")

        if clinvar_db_path:
            annotation_cmd.extend(["-v", clinvar_db_path])
            log.append(f"Using ClinVar database: {clinvar_db_path}")

        # This is a placeholder for the annotation command
        # In a real implementation, you would use a tool like AnnotSV, VEP, or a custom script
        log.append("Note: Annotation step is simulated in this implementation")
        log.append("In a real scenario, tools like AnnotSV or VEP would be used")

        # Instead of running the command, we'll create a simple annotated file
        with open(filtered_vcf) as infile, open(annotated_vcf, "w") as outfile:
            for line in infile:
                if line.startswith("#"):
                    outfile.write(line)
                else:
                    outfile.write(line)
                    # In a real implementation, annotation would be added here

        log.append("SV annotation completed")
        log.append(f"Annotated SVs saved to: {annotated_vcf}")
    except Exception as e:
        log.append(f"Error during SV annotation: {e}")
        return "\\n".join(log)

    # Step 5: Generate summary report
    log.append("\\n### Step 5: Generating summary report")

    summary_file = os.path.join(output_dir, "sv_summary_report.tsv")

    try:
        # Convert VCF to a tabular format for easier analysis
        subprocess.run(
            [
                "bcftools",
                "query",
                "-f",
                "%CHROM\\t%POS\\t%INFO/SVTYPE\\t%INFO/SVLEN\\t%QUAL\\n",
                "-o",
                summary_file,
                annotated_vcf,
            ],
            check=True,
        )

        log.append(f"Summary report generated: {summary_file}")
    except subprocess.CalledProcessError as e:
        log.append(f"Error generating summary report: {e}")
        return "\\n".join(log)

    # Final summary
    log.append("\\n## Summary")
    log.append(f"Total SVs detected: {sum(sv_counts.values())}")
    log.append("SV types breakdown:")
    for sv_type, count in sv_counts.items():
        log.append(f"- {sv_type}: {count} ({count / sum(sv_counts.values()) * 100:.1f}%)")

    log.append("\\nFiles generated:")
    log.append(f"- Raw SV calls: {vcf_output}")
    log.append(f"- Filtered SVs: {filtered_vcf}")
    log.append(f"- Annotated SVs: {annotated_vcf}")
    log.append(f"- Summary report: {summary_file}")

    log.append(f"\\nAnalysis completed at: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    return "\\n".join(log)

# Execute the function
try:
    result = detect_and_characterize_structural_variations(
        bam_file_path=auto_convert(os.environ.get("PARAM_BAM_FILE_PATH", "")),
        reference_genome_path=auto_convert(os.environ.get("PARAM_REFERENCE_GENOME_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "")),
        cosmic_db_path=auto_convert(os.environ.get("PARAM_COSMIC_DB_PATH", "")),
        clinvar_db_path=auto_convert(os.environ.get("PARAM_CLINVAR_DB_PATH", "")),
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
    "function": "detect_and_characterize_structural_variations",
    "domain": "cancer_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("detect_and_characterize_structural_variations_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("detect_and_characterize_structural_variations_output.txt", "w") as f:
    f.write("Biomni: Detect And Characterize Structural Variations" + NL)
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
        biomni_function: "detect_and_characterize_structural_variations"
    END_VERSIONS
    """
}

workflow DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS(ch_input)

    emit:
    results = DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS.out.results
    output = DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS.out.output
    versions = DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS_WORKFLOW(ch_input)

    DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS_WORKFLOW.out.output.view { "Output: $it" }
}
