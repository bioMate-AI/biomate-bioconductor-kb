#!/usr/bin/env nextflow
/*
 * genomics/perform_chipseq_peak_calling_with_macs2
 * Perform ChIP-seq peak calling using MACS2 to identify genomic regions with significant binding.
 *
 * nf-core style module generated from tested Galaxy wrapper
 *
 * Quick-run demo default: with no --chip_seq_file/--control_file, falls back to the canonical
 * MACS CTCF ChIP-seq test pair (chr22, ~50k-read single-end ChIP + matched input control, from
 * macs3-project/MACS) and runs the SAME macs2 callpeak path on that REAL public data. Honest-fail
 * only if the demo download fails (never fabricated peaks).
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
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    // Peak-calling engine = MACS3 (the maintained, CLI-compatible successor to MACS2).
    // Why not macs2: workflow-tools:x86 ships no macs2 (real Batch probe: `which macs2` empty),
    // AND every available bioconda macs2 biocontainer (2.2.9.1 py39/py310 _5) fails at runtime
    // with `undefined symbol: __log_finite` — their compiled .so links a glibc math alias that
    // modern glibc dropped (verified broken on 2 builds in isolation, 2026-10-04). MACS3 is built
    // against modern glibc; `macs3 callpeak` takes the same -t/-c/-n/-g/-q args and emits the
    // same *_peaks.narrowPeak / *_peaks.xls / *_summits.bed. Literal directive (merfish/voyager
    // pattern); always-on host-libz + /opt/aws-cli mounts make quay biocontainers work on Batch.
    container 'quay.io/biocontainers/macs3:3.0.5--py312h9639c01_0'

    input:
    // ChIP (treatment) + input/control alignments are STAGED path inputs so Nextflow
    // localises them into the task work dir — this is what makes `os.path.exists()`
    // true inside the container and lets the pipeline actually REACH `macs2 callpeak`.
    // Previously the process took only `val(meta)` with no staged files, so the Python
    // body always saw chip_seq_file=None and returned early in fake "demo mode" before
    // peak calling (root cause of "ChIP-seq did not reach peak calling").
    tuple val(meta), path(chip_seq_file), path(control_file)

    output:
    tuple val(meta), path("perform_chipseq_peak_calling_with_macs2_results.json"), emit: results
    tuple val(meta), path("perform_chipseq_peak_calling_with_macs2_output.txt"), emit: output
    // Real MACS2 peak-calling artefacts (published when callpeak succeeds).
    tuple val(meta), path("*_peaks.narrowPeak"), emit: narrowpeak, optional: true
    tuple val(meta), path("*_peaks.xls"),        emit: peaks_xls, optional: true
    tuple val(meta), path("*_summits.bed"),      emit: summits,   optional: true
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables. The ChIP + control files are the
    # STAGED input basenames (localised by Nextflow), NOT raw params — so they exist
    # on disk inside the task and peak calling is reachable.
    #
    # The built-in demo pair (and many public ChIP/control tracks) arrive gzipped (.bed.gz).
    # Decompress any gzipped staged input in-place with the real `gzip` tool so macs2 (-f AUTO)
    # can read plain BED/BAM. User-supplied plain BAM/BED are left untouched (the test is false).
    CHIP_IN="${chip_seq_file}"
    CTRL_IN="${control_file}"
    if [ "\${CHIP_IN##*.}" = "gz" ]; then gzip -dc "\$CHIP_IN" > "\${CHIP_IN%.gz}" && CHIP_IN="\${CHIP_IN%.gz}"; fi
    if [ "\${CTRL_IN##*.}" = "gz" ]; then gzip -dc "\$CTRL_IN" > "\${CTRL_IN%.gz}" && CTRL_IN="\${CTRL_IN%.gz}"; fi
    export PARAM_CHIP_SEQ_FILE="\$CHIP_IN"
    export PARAM_CONTROL_FILE="\$CTRL_IN"
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

    # Validate input files. These MUST exist (they are staged Nextflow path inputs).
    # Honest-fail if absent — never fabricate "demo"/"simulated" peaks (CLAUDE.md:
    # no fabrication; a fake success log masks a real missing-input failure).
    if chip_seq_file is None or not os.path.exists(str(chip_seq_file)):
        raise FileNotFoundError(
            f"ChIP-seq (treatment) file not found: {chip_seq_file}. "
            "A real BAM/BED must be staged; refusing to emit fabricated demo peaks."
        )

    if control_file is None or not os.path.exists(str(control_file)):
        raise FileNotFoundError(
            f"Control/input file not found: {control_file}. "
            "A real BAM/BED must be staged; refusing to emit fabricated demo peaks."
        )

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

    # Check the peak caller is installed. Engine = MACS3 (maintained macs2 successor; see the
    # container directive note for why the macs2 biocontainers are unusable).
    try:
        check_process = subprocess.run(
            ["macs3", "--version"],
            check=False,
            capture_output=True,
            timeout=5,
        )
        log += f"MACS3 (MACS2 successor) is available: {check_process.stdout.decode().strip() if check_process.stdout else check_process.stderr.decode().strip()}\\n\\n"
    except (subprocess.SubprocessError, FileNotFoundError):
        # Honest-fail: the container must provide the peak caller. Do not return a "success"
        # log that silently skipped peak calling.
        raise RuntimeError(
            "MACS3 is not installed or not on PATH in this container. Peak calling cannot run."
        )
    except Exception as e:
        log += f"Error checking for MACS3: {str(e)}\\n"

    # Construct MACS2 command
    macs2_cmd = [
        "macs3",
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

    def _run_macs(cmd):
        return subprocess.run(cmd, capture_output=True, text=True, timeout=300)

    try:
        # Run MACS3. Model building needs >=100 paired peaks to estimate a fragment size;
        # single-end / sparse ChIP (including the built-in demo) can't build it. macs3 itself
        # recommends --nomodel --extsize, so auto-fall back to that when model building fails —
        # sparse/SE data then still produces peaks instead of hard-failing (robust for real
        # single-end data, not a demo-only hack).
        log += "Running MACS3 peak calling...\\n"
        process = _run_macs(macs2_cmd)
        if process.returncode != 0 and ("build the model" in (process.stderr or "") or "--nomodel" in (process.stderr or "")):
            log += "Model-building could not estimate a fragment size (sparse/single-end input); retrying with --nomodel --extsize 200.\\n"
            macs2_cmd_nomodel = macs2_cmd + ["--nomodel", "--extsize", "200"]
            log += " ".join(macs2_cmd_nomodel) + "\\n"
            process = _run_macs(macs2_cmd_nomodel)
        if process.returncode != 0:
            raise subprocess.CalledProcessError(process.returncode, macs2_cmd, output=process.stdout, stderr=process.stderr)

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
    f.write("BioMate: Perform Chipseq Peak Calling With Macs2" + NL)
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

// Entry workflow for standalone execution.
// Builds the staged [meta, chip, control] channel and REACHES macs2 callpeak.
//
// Built-in demo default (mirrors merfish/metaboanalystr): when no ChIP/control pair is supplied,
// fall back to the canonical MACS CTCF ChIP-seq test pair — a single-end CTCF ChIP track plus its
// matched input control, chr22 subset (~50k reads each) from the macs3-project/MACS repository —
// so a param-less "quick run" works end-to-end on REAL, clearly-labeled public data. The demo
// files are staged, decompressed in the process, and run through the SAME macs2 callpeak path.
// Honest-fail only if the demo download itself fails (never fabricated/synthetic peaks).
workflow {
    def demo        = ( !params.chip_seq_file || !params.control_file )
    // Canonical MACS test pair — real public CTCF ChIP-seq (NA12878), chr22, ~50k single-end reads.
    def demo_chip   = "${projectDir}/../../../../sample_data/chipseq/CTCF_SE_ChIP_chr22_50k.bed.gz"
    def demo_ctrl   = "${projectDir}/../../../../sample_data/chipseq/CTCF_SE_CTRL_chr22_50k.bed.gz"
    def chip_src    = demo ? demo_chip : params.chip_seq_file
    def control_src = demo ? demo_ctrl : params.control_file

    if( demo ) {
        log.warn "[demo] no --chip_seq_file/--control_file supplied -> using vendored MACS CTCF " +
                 "demo pair under sample_data/chipseq (CTCF_SE_ChIP_chr22_50k + CTCF_SE_CTRL_chr22_50k)"
    }

    ch_input = Channel.of(
        tuple(
            [ id: (params.output_name ?: (demo ? 'ctcf_demo' : 'run')) ],
            file(chip_src,    checkIfExists: true),
            file(control_src, checkIfExists: true)
        )
    )

    PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2_WORKFLOW(ch_input)

    PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2_WORKFLOW.out.output.view { "Output: $it" }
}
