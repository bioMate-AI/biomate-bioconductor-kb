#!/usr/bin/env nextflow
/*
 * immunology/analyze_atac_seq_differential_accessibility
 * Perform ATAC-seq peak calling and differential accessibility analysis using MACS2.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.treatment_bam = null
params.control_bam = null
params.output_dir = './atac_results'
params.genome_size = 'hs'
params.q_value = '0.05'
params.name_prefix = 'atac'

process ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_atac_seq_differential_accessibility_results.json"), emit: results
    tuple val(meta), path("analyze_atac_seq_differential_accessibility_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TREATMENT_BAM="${params.treatment_bam?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CONTROL_BAM="${params.control_bam?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GENOME_SIZE="${params.genome_size?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_Q_VALUE="${params.q_value?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NAME_PREFIX="${params.name_prefix?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_atac_seq_differential_accessibility(
    treatment_bam,
    control_bam,
    output_dir="./atac_results",
    genome_size="hs",
    q_value=0.05,
    name_prefix="atac",
):
    '''Perform ATAC-seq peak calling and differential accessibility analysis using MACS2.

    Parameters
    ----------
    treatment_bam : str
        Path to the treatment condition BAM file with aligned ATAC-seq reads
    control_bam : str
        Path to the control condition BAM file with aligned ATAC-seq reads
    output_dir : str
        Directory to save output files (default: "./atac_results")
    genome_size : str
        Genome size parameter for MACS2 (default: "hs" for human)
    q_value : float
        q-value cutoff for peak detection (default: 0.05)
    name_prefix : str
        Prefix for output file names (default: "atac")

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import datetime
    import os
    import subprocess

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Initialize research log
    log = f"ATAC-seq Analysis Log - {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n"
    log += "=" * 80 + "\\n\\n"

    # Step 1: Run MACS2 for peak calling on treatment sample
    log += "Step 1: Peak calling on treatment sample\\n"
    treatment_output = os.path.join(output_dir, f"{name_prefix}_treatment")
    treatment_cmd = [
        "macs2",
        "callpeak",
        "-t",
        treatment_bam,
        "-f",
        "BAM",
        "-g",
        genome_size,
        "-n",
        treatment_output,
        "--outdir",
        output_dir,
        "--nomodel",
        "--shift",
        "-100",
        "--extsize",
        "200",
        "-q",
        str(q_value),
    ]

    log += f"Command: {' '.join(treatment_cmd)}\\n"
    try:
        subprocess.run(treatment_cmd, check=True, capture_output=True, text=True)
        log += "Treatment peak calling completed successfully.\\n"
        treatment_peaks_file = f"{treatment_output}_peaks.narrowPeak"

        # Count peaks in treatment
        with open(os.path.join(output_dir, treatment_peaks_file)) as f:
            treatment_peak_count = sum(1 for _ in f)
        log += f"Identified {treatment_peak_count} peaks in treatment sample.\\n\\n"
    except subprocess.CalledProcessError as e:
        log += f"Error in treatment peak calling: {e.stderr}\\n\\n"
        return log

    # Step 2: Run MACS2 for peak calling on control sample
    log += "Step 2: Peak calling on control sample\\n"
    control_output = os.path.join(output_dir, f"{name_prefix}_control")
    control_cmd = [
        "macs2",
        "callpeak",
        "-t",
        control_bam,
        "-f",
        "BAM",
        "-g",
        genome_size,
        "-n",
        control_output,
        "--outdir",
        output_dir,
        "--nomodel",
        "--shift",
        "-100",
        "--extsize",
        "200",
        "-q",
        str(q_value),
    ]

    log += f"Command: {' '.join(control_cmd)}\\n"
    try:
        subprocess.run(control_cmd, check=True, capture_output=True, text=True)
        log += "Control peak calling completed successfully.\\n"
        control_peaks_file = f"{control_output}_peaks.narrowPeak"

        # Count peaks in control
        with open(os.path.join(output_dir, control_peaks_file)) as f:
            control_peak_count = sum(1 for _ in f)
        log += f"Identified {control_peak_count} peaks in control sample.\\n\\n"
    except subprocess.CalledProcessError as e:
        log += f"Error in control peak calling: {e.stderr}\\n\\n"
        return log

    # Step 3: Perform differential accessibility analysis using MACS2 bdgdiff
    log += "Step 3: Differential accessibility analysis\\n"
    treatment_pileup = os.path.join(output_dir, f"{treatment_output}_treat_pileup.bdg")
    control_pileup = os.path.join(output_dir, f"{control_output}_treat_pileup.bdg")
    diff_output = os.path.join(output_dir, f"{name_prefix}_differential")

    diff_cmd = [
        "macs2",
        "bdgdiff",
        "--t1",
        treatment_pileup,
        "--c1",
        os.path.join(output_dir, f"{treatment_output}_control_lambda.bdg"),
        "--t2",
        control_pileup,
        "--c2",
        os.path.join(output_dir, f"{control_output}_control_lambda.bdg"),
        "--d1",
        "1",
        "--d2",
        "1",
        "--o-prefix",
        diff_output,
    ]

    log += f"Command: {' '.join(diff_cmd)}\\n"
    try:
        subprocess.run(diff_cmd, check=True, capture_output=True, text=True)
        log += "Differential accessibility analysis completed successfully.\\n"

        # Count differential regions
        enriched_in_treatment = f"{diff_output}_cond1.bed"
        enriched_in_control = f"{diff_output}_cond2.bed"

        with open(os.path.join(output_dir, enriched_in_treatment)) as f:
            treatment_enriched_count = sum(1 for _ in f)

        with open(os.path.join(output_dir, enriched_in_control)) as f:
            control_enriched_count = sum(1 for _ in f)

        log += f"Found {treatment_enriched_count} regions with higher accessibility in treatment.\\n"
        log += f"Found {control_enriched_count} regions with higher accessibility in control.\\n\\n"
    except subprocess.CalledProcessError as e:
        log += f"Error in differential analysis: {e.stderr}\\n\\n"
        return log

    # Step 4: Summary of results
    log += "Step 4: Analysis Summary\\n"
    log += f"Total peaks in treatment: {treatment_peak_count}\\n"
    log += f"Total peaks in control: {control_peak_count}\\n"
    log += f"Differentially accessible regions: {treatment_enriched_count + control_enriched_count}\\n"
    log += f"  - Enriched in treatment: {treatment_enriched_count}\\n"
    log += f"  - Enriched in control: {control_enriched_count}\\n\\n"

    # Output file locations
    log += "Output Files:\\n"
    log += f"  - Treatment peaks: {os.path.join(output_dir, treatment_peaks_file)}\\n"
    log += f"  - Control peaks: {os.path.join(output_dir, control_peaks_file)}\\n"
    log += f"  - Treatment-enriched regions: {os.path.join(output_dir, enriched_in_treatment)}\\n"
    log += f"  - Control-enriched regions: {os.path.join(output_dir, enriched_in_control)}\\n"

    return log

# Execute the function
try:
    result = analyze_atac_seq_differential_accessibility(
        treatment_bam=auto_convert(os.environ.get("PARAM_TREATMENT_BAM", "")),
        control_bam=auto_convert(os.environ.get("PARAM_CONTROL_BAM", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./atac_results")),
        genome_size=auto_convert(os.environ.get("PARAM_GENOME_SIZE", "hs")),
        q_value=auto_convert(os.environ.get("PARAM_Q_VALUE", "0.05")),
        name_prefix=auto_convert(os.environ.get("PARAM_NAME_PREFIX", "atac")),
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
    "function": "analyze_atac_seq_differential_accessibility",
    "domain": "immunology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_atac_seq_differential_accessibility_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_atac_seq_differential_accessibility_output.txt", "w") as f:
    f.write("Biomni: Analyze Atac Seq Differential Accessibility" + NL)
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
        biomni_function: "analyze_atac_seq_differential_accessibility"
    END_VERSIONS
    """
}

workflow ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY(ch_input)

    emit:
    results = ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY.out.results
    output = ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY.out.output
    versions = ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY_WORKFLOW(ch_input)

    ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY_WORKFLOW.out.output.view { "Output: $it" }
}
