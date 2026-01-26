#!/usr/bin/env nextflow
/*
 * genomics/perform_chipseq_peak_calling_with_macs2
 * Perform ChIP-seq peak calling using MACS2 to identify genomic regions with significant binding.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.chip_seq_file = null
params.control_file = null
params.output_name = 'macs2_output'
params.genome_size = 'hs'
params.q_value = '0.05'

process PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2 {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("perform_chipseq_peak_calling_with_macs2_results.json"), emit: results
    tuple val(meta), path("perform_chipseq_peak_calling_with_macs2_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_CHIP_SEQ_FILE="${params.chip_seq_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CONTROL_FILE="${params.control_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_NAME="${params.output_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GENOME_SIZE="${params.genome_size?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_Q_VALUE="${params.q_value?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
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



def perform_chipseq_peak_calling_with_macs2(
    chip_seq_file,
    control_file,
    output_name="macs2_output",
    genome_size="hs",
    q_value=0.05,
):
    '''Perform ChIP-seq peak calling using MACS2 to identify genomic regions with significant binding.

    Parameters
    ----------
    chip_seq_file : str
        Path to the ChIP-seq read data file (BAM, BED, or other supported format)
    control_file : str
        Path to the control/input data file (BAM, BED, or other supported format)
    output_name : str, optional
        Prefix for output files (default: "macs2_output")
    genome_size : str, optional
        Effective genome size shorthand: 'hs' for human, 'mm' for mouse, etc. (default: "hs")
    q_value : float, optional
        q-value (minimum FDR) cutoff for peak calling (default: 0.05)

    Returns
    -------
    str
        A research log summarizing the peak calling process and results

    '''
    import datetime
    import subprocess

    # Create log with timestamp
    log = f"ChIP-seq Peak Calling with MACS2 - {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n"
    log += "=" * 80 + "\\n\\n"

    # Validate input files
    if not os.path.exists(chip_seq_file):
        log += f"Error: ChIP-seq file does not exist: {chip_seq_file}\\n"
        return log

    if not os.path.exists(control_file):
        log += f"Error: Control file does not exist: {control_file}\\n"
        return log

    # Create output directory if needed
    output_dir = os.path.dirname(output_name)
    if output_dir and not os.path.exists(output_dir):
        try:
            os.makedirs(output_dir, exist_ok=True)
            log += f"Created output directory: {output_dir}\\n"
        except Exception as e:
            log += f"Error creating output directory: {str(e)}\\n"

    # Log input parameters
    log += "Input Parameters:\\n"
    log += f"- ChIP-seq data: {chip_seq_file}\\n"
    log += f"- Control data: {control_file}\\n"
    log += f"- Output prefix: {output_name}\\n"
    log += f"- Genome size: {genome_size}\\n"
    log += f"- q-value cutoff: {q_value}\\n\\n"

    # Check if MACS2 is installed
    try:
        check_process = subprocess.run(
            ["macs2", "--version"],
            check=False,
            capture_output=True,
            timeout=5,
        )
        log += f"MACS2 is available: {check_process.stdout.decode().strip() if check_process.stdout else check_process.stderr.decode().strip()}\\n\\n"
    except (subprocess.SubprocessError, FileNotFoundError):
        log += "Error: MACS2 is not installed or not available in the system PATH.\\n"
        log += "Please install MACS2 using: pip install macs2\\n"
        return log
    except Exception as e:
        log += f"Error checking for MACS2: {str(e)}\\n"

    # Construct MACS2 command
    macs2_cmd = [
        "macs2",
        "callpeak",
        "-t",
        chip_seq_file,
        "-c",
        control_file,
        "-n",
        output_name,
        "-g",
        genome_size,
        "-q",
        str(q_value),
    ]

    # Add output directory parameter if it exists
    if output_dir:
        macs2_cmd.extend(["--outdir", output_dir])

    log += "Executing MACS2 with the following command:\\n"
    log += " ".join(macs2_cmd) + "\\n\\n"

    # Define expected output files with full paths
    output_dir_prefix = output_dir + "/" if output_dir else ""
    expected_files = [
        f"{output_dir_prefix}{output_name}_peaks.xls",
        f"{output_dir_prefix}{output_name}_peaks.narrowPeak",
        f"{output_dir_prefix}{output_name}_summits.bed",
    ]

    try:
        # Run MACS2
        log += "Running MACS2 peak calling...\\n"
        process = subprocess.run(macs2_cmd, capture_output=True, text=True, check=True, timeout=300)

        # Log stdout and stderr (truncate if too long)
        stdout_text = process.stdout
        if len(stdout_text) > 2000:
            stdout_text = stdout_text[:1000] + "\\n...[output truncated]...\\n" + stdout_text[-1000:]

        stderr_text = process.stderr
        if stderr_text and len(stderr_text) > 2000:
            stderr_text = stderr_text[:1000] + "\\n...[output truncated]...\\n" + stderr_text[-1000:]

        log += "MACS2 Standard Output:\\n"
        log += stdout_text + "\\n"

        if stderr_text:
            log += "MACS2 Standard Error:\\n"
            log += stderr_text + "\\n"

        # Check for output files
        log += "Output Files Generated:\\n"
        peak_count = 0

        for file in expected_files:
            if os.path.exists(file):
                file_size = os.path.getsize(file)
                log += f"- {file} ({file_size} bytes)\\n"

                # Count peaks in narrowPeak file
                if file.endswith("narrowPeak") and os.path.exists(file):
                    try:
                        with open(file) as f:
                            peak_count = sum(1 for _ in f)
                        log += f"\\nTotal peaks identified: {peak_count}\\n"
                    except Exception as e:
                        log += f"Error reading peak file: {str(e)}\\n"
            else:
                log += f"- {file} (Not found)\\n"

        log += "\\nPeak calling completed successfully.\\n"

        # Add more detailed explanation about the output files
        log += "\\nOutput Files Explanation:\\n"
        log += "1. *_peaks.narrowPeak: BED6+4 format file containing peak locations with statistical significance\\n"
        log += "   - Each line represents a peak with chromosome, start, end, and statistical significance\\n"
        log += "   - Additional columns include summit position, -log10(pvalue), -log10(qvalue), and fold enrichment\\n"
        log += "2. *_summits.bed: BED format file containing the summit locations (highest point) of each peak\\n"
        log += "3. *_peaks.xls: Tab-delimited file with detailed information about each peak\\n"

        # Add basic statistics
        log += "\\nBasic Statistics:\\n"
        log += f"- Total peaks called: {peak_count}\\n"

    except subprocess.CalledProcessError as e:
        log += "Error during MACS2 execution:\\n"
        if e.stderr:
            log += e.stderr + "\\n"
        log += "Peak calling failed.\\n"
    except subprocess.TimeoutExpired:
        log += "Error: MACS2 execution timed out after 300 seconds.\\n"
        log += "This may happen with very large input files or insufficient computational resources.\\n"
    except Exception as e:
        log += f"An unexpected error occurred: {str(e)}\\n"

    return log

# Execute the function
try:
    result = perform_chipseq_peak_calling_with_macs2(
        chip_seq_file=auto_convert(os.environ.get("PARAM_CHIP_SEQ_FILE", "")),
        control_file=auto_convert(os.environ.get("PARAM_CONTROL_FILE", "")),
        output_name=auto_convert(os.environ.get("PARAM_OUTPUT_NAME", "macs2_output")),
        genome_size=auto_convert(os.environ.get("PARAM_GENOME_SIZE", "hs")),
        q_value=auto_convert(os.environ.get("PARAM_Q_VALUE", "0.05")),
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
    "function": "perform_chipseq_peak_calling_with_macs2",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("perform_chipseq_peak_calling_with_macs2_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("perform_chipseq_peak_calling_with_macs2_output.txt", "w") as f:
    f.write("Biomni: Perform Chipseq Peak Calling With Macs2" + NL)
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
        biomni_function: "perform_chipseq_peak_calling_with_macs2"
    END_VERSIONS
    """
}

workflow PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2(ch_input)

    emit:
    results = PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2.out.results
    output = PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2.out.output
    versions = PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2_WORKFLOW(ch_input)

    PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2_WORKFLOW.out.output.view { "Output: $it" }
}
