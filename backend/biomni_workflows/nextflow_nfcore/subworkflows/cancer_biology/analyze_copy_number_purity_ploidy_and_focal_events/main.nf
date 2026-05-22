#!/usr/bin/env nextflow
/*
 * cancer_biology/analyze_copy_number_purity_ploidy_and_focal_events
 * CNVkit-based copy number workflow: CNV segmentation, purity/ploidy & HRD approximation, focal events.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.tumor_bam = null
params.reference_genome = null
params.normal_bam = null
params.output_dir = 'cn_analysis_results'
params.targets_bed = null
params.antitargets_bed = null
params.gene_bed = null
params.focal_genes = null
params.log2_amp_threshold = '1.0'
params.log2_del_threshold = null

process ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_copy_number_purity_ploidy_and_focal_events_results.json"), emit: results
    tuple val(meta), path("analyze_copy_number_purity_ploidy_and_focal_events_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TUMOR_BAM="${params.tumor_bam?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REFERENCE_GENOME="${params.reference_genome?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NORMAL_BAM="${params.normal_bam?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TARGETS_BED="${params.targets_bed?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ANTITARGETS_BED="${params.antitargets_bed?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GENE_BED="${params.gene_bed?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FOCAL_GENES="${params.focal_genes?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LOG2_AMP_THRESHOLD="${params.log2_amp_threshold?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LOG2_DEL_THRESHOLD="${params.log2_del_threshold?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_copy_number_purity_ploidy_and_focal_events(
    tumor_bam,
    reference_genome,
    normal_bam=None,
    output_dir="cn_analysis_results",
    targets_bed=None,
    antitargets_bed=None,
    gene_bed=None,
    focal_genes=None,
    log2_amp_threshold=1.0,
    log2_del_threshold=-1.0,
):
    '''CNVkit-based copy number workflow: CNV segmentation, purity/ploidy & HRD approximation, focal events.

    This function orchestrates a CNVkit-based copy number analysis workflow for tumor samples.
    It performs CNV segmentation, derives approximate purity & ploidy metrics, calculates a simplified
    HRD-style summary, and detects focal amplifications/deletions in key oncogenes / tumor suppressors.

    Parameters
    ----------
    tumor_bam : str
        Path to tumor BAM (indexed)
    reference_genome : str
        Path to reference FASTA (with index files present)
    normal_bam : str, optional
        Matched normal BAM (recommended for allele-specific & purity inference)
    output_dir : str, default "cn_analysis_results"
        Directory for all outputs
    targets_bed : str, optional
        BED of target regions (e.g. exome / panel) for CNVkit / gCNV
    antitargets_bed : str, optional
        BED of antitarget regions for CNVkit (if panel / exome)
    gene_bed : str, optional
        BED file with gene coordinates (chrom, start, end, gene). Used for focal event annotation
    focal_genes : list[str], optional
        List of genes to highlight for focal amplification/deletion; defaults to ["MYC","ERBB2","CDKN2A"]
    log2_amp_threshold : float, default 1.0
        Log2 ratio threshold to call focal amplification (~ >2x copy relative to baseline)
    log2_del_threshold : float, default -1.0
        Log2 ratio threshold to call focal deep deletion (~ homozygous loss)

    Returns
    -------
    str
        Research log summarizing steps, tool executions, and findings.
    '''
    import datetime
    import os

    log = []
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Generate synthetic results if no input provided
    if tumor_bam is None or reference_genome is None:
        import numpy as np
        np.random.seed(42)

        log.append(f"CNVKIT COPY NUMBER ANALYSIS WORKFLOW (DEMO MODE) - {ts}")
        log.append("=" * 80)
        log.append("Running with synthetic data for demonstration purposes.\\n")

        # Simulated results
        purity = np.random.uniform(0.4, 0.9)
        ploidy = np.random.choice([2.0, 2.5, 3.0, 4.0], p=[0.5, 0.2, 0.2, 0.1])
        hrd_score = np.random.randint(5, 45)

        log.append("## Copy Number Analysis Results\\n")
        log.append(f"- Estimated tumor purity: {purity:.2f}")
        log.append(f"- Estimated ploidy: {ploidy:.1f}")
        log.append(f"- HRD score (approximation): {hrd_score}\\n")

        log.append("## Focal Events Detected\\n")
        focal_events = [
            ("MYC", "8q24", "Amplification", 2.3),
            ("CDKN2A", "9p21", "Deletion", -1.5),
            ("ERBB2", "17q12", "Neutral", 0.1),
        ]
        for gene, locus, event, log2 in focal_events:
            log.append(f"- {gene} ({locus}): {event} (log2={log2:.2f})")

        log.append("\\n## Summary\\n")
        log.append("Synthetic demo analysis complete. Provide tumor_bam and reference_genome for actual analysis.")

        return "\\n".join(log)

    import math
    import shutil
    import statistics
    import subprocess
    import pandas as pd

    log.append(f"CNVKIT COPY NUMBER ANALYSIS WORKFLOW - {ts}")
    log.append("=" * 80)
    log.append(f"Tumor BAM: {tumor_bam}")
    if normal_bam:
        log.append(f"Normal BAM: {normal_bam}")
    log.append(f"Reference genome: {reference_genome}")
    log.append(f"Output directory: {output_dir}\\n")

    os.makedirs(output_dir, exist_ok=True)
    sample_name = os.path.splitext(os.path.basename(tumor_bam))[0]

    if focal_genes is None:
        focal_genes = ["MYC", "ERBB2", "CDKN2A"]
    # Single informative log line (was duplicated previously)
    log.append(f"Focal genes for analysis: {', '.join(focal_genes)}")

    # ----------------------------------------------------------------------------------
    # STEP 1: CNV SEGMENTATION with CNVkit
    # ----------------------------------------------------------------------------------
    log.append("STEP 1: CNV Segmentation with CNVkit")
    cnvkit_path = shutil.which("cnvkit.py") or shutil.which("cnvkit")
    use_conda_env = False

    # Check if CNVkit is available in biomni_e1 environment
    if not cnvkit_path:
        try:
            result = subprocess.run(
                ["conda", "run", "-n", "biomni_e1", "which", "cnvkit.py"], capture_output=True, text=True, check=True
            )
            if result.returncode == 0 and result.stdout.strip():
                cnvkit_path = "cnvkit.py"  # Will use via conda run
                use_conda_env = True
                log.append("- CNVkit found in biomni_e1 environment")
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass

    # Fallback to bio_env_py310
    if not cnvkit_path:
        try:
            result = subprocess.run(
                ["conda", "run", "-n", "bio_env_py310", "which", "cnvkit.py"],
                capture_output=True,
                text=True,
                check=True,
            )
            if result.returncode == 0 and result.stdout.strip():
                cnvkit_path = "cnvkit.py"  # Will use via conda run
                use_conda_env = True
                log.append("- CNVkit found in bio_env_py310 environment")
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass

    if not cnvkit_path:
        log.append("- CNVkit not detected in current PATH, biomni_e1, or bio_env_py310 environment")
        log.append("- Install manually (e.g., pip install cnvkit==0.9.11) or run setup.sh")
        log.append("- Workflow will exit without CNVkit")
        return "\\n".join(log)

    cnvkit_cns = None
    log.append(f"- CNVkit detected at: {cnvkit_path}")

    # Determine environment prefix for CNVkit commands
    env_prefix = ["conda", "run", "-n", "biomni_e1"] if use_conda_env else []

    # CNVkit batch command
    batch_cmd = env_prefix + [cnvkit_path, "batch", tumor_bam, "-d", output_dir, "-f", reference_genome]
    if normal_bam:
        batch_cmd.extend(["-n", normal_bam])
    if targets_bed:
        batch_cmd.extend(["-t", targets_bed])
    if antitargets_bed:
        batch_cmd.extend(["-a", antitargets_bed])
    batch_cmd.extend(["--scatter", "--diagram"])

    log.append(f"- Running CNVkit batch command: {' '.join(batch_cmd)}")
    try:
        subprocess.run(batch_cmd, check=True, capture_output=True)
        log.append("- CNVkit batch completed successfully")
    except subprocess.CalledProcessError as e:
        log.append(f"- WARNING: CNVkit batch failed: {e}. Proceeding with limited downstream analyses")

    # Check for CNVkit output and run call command
    cnvkit_cns = os.path.join(output_dir, f"{sample_name}.cns")
    if os.path.exists(cnvkit_cns):
        call_cmd = env_prefix + [
            cnvkit_path,
            "call",
            cnvkit_cns,
            "-o",
            os.path.join(output_dir, f"{sample_name}.call.cns"),
            "-m",
            "clonal",
        ]
        log.append(f"- Calling absolute CN: {' '.join(call_cmd)}")
        try:
            subprocess.run(call_cmd, check=True, capture_output=True)
            cnvkit_cns = os.path.join(output_dir, f"{sample_name}.call.cns")
            log.append("- CNVkit call succeeded")
        except subprocess.CalledProcessError as e:
            log.append(f"- WARNING: CNVkit call failed: {e}")
    else:
        log.append("- WARNING: Expected CNVkit .cns file not found")

    # ----------------------------------------------------------------------------------
    # STEP 2: Purity & ploidy approximation (based on CNVkit outputs)
    # ----------------------------------------------------------------------------------
    log.append("\\nSTEP 2: Purity & Ploidy Approximation")
    purity_est = None
    ploidy_est = None
    seg_source = None
    seg_df = None
    try:
        if cnvkit_cns and os.path.exists(cnvkit_cns):
            seg_source = cnvkit_cns
            seg_df = pd.read_csv(cnvkit_cns, sep="\\t")
            log.append(f"- Using CNVkit segments from: {seg_source}")

            # Harmonize columns
            cols = [c.lower() for c in seg_df.columns]
            seg_df.columns = cols

            # Obtain log2 column
            log2_col = None
            for candidate in ["log2", "log2ratio", "cnlr", "logr"]:
                if candidate in cols:
                    log2_col = candidate
                    break
            for candidate in ["end", "chromend", "stop"]:
                if candidate in cols:
                    end_col = candidate
                    break
            for candidate in ["start", "chromstart", "begin"]:
                if candidate in cols:
                    start_col = candidate
                    break

            if log2_col and start_col and end_col:
                seg_df["seg_length"] = seg_df[end_col] - seg_df[start_col]
                # Weighted average absolute copy ratio -> approximate ploidy baseline
                # Convert log2 ratio to absolute copy ratio (assuming diploid baseline = 2)
                seg_df["abs_cn"] = 2 * (2 ** seg_df[log2_col])
                weighted_mean_cn = (seg_df["abs_cn"] * seg_df["seg_length"]).sum() / seg_df["seg_length"].sum()
                ploidy_est = weighted_mean_cn
                # Approximate purity: higher variance in log2 ratios suggests purity; naive formula
                mad_log2 = statistics.median([abs(x) for x in seg_df[log2_col] if not math.isnan(x)])
                purity_est = min(1.0, max(0.2, 1 - mad_log2 / 1.5))  # heuristic clamp
                log.append(f"- Estimated ploidy (weighted mean CN): {ploidy_est:.2f}")
                log.append(f"- Estimated purity (heuristic from segmentation dispersion): {purity_est:.2f}")
            else:
                log.append("- WARNING: Could not identify necessary columns for purity/ploidy estimation")
        else:
            log.append("- No CNVkit segmentation available for purity/ploidy estimation")
    except Exception as e:
        log.append(f"- ERROR: Purity/ploidy estimation failed: {e}")

    # ----------------------------------------------------------------------------------
    # STEP 3: HRD-like summary (simplified proxy)
    # ----------------------------------------------------------------------------------
    log.append("\\nSTEP 3: HRD Approximation (Simplified)")
    hrd_metrics = {}
    try:
        if seg_df is not None and "seg_length" in seg_df:
            # Count large-scale transitions (LST proxy: adjacent segments >10 Mb with log2 change >0.2)
            seg_df_sorted = seg_df.sort_values(
                by=[c for c in seg_df.columns if c.startswith("chrom") or c == "chrom" or c == "chromosome"][0]
                if any(c.startswith("chrom") for c in seg_df.columns)
                else seg_df.columns[0]
            )
            lst_count = 0
            prev = None
            for _, row in seg_df_sorted.iterrows():
                if prev is not None:
                    if row["seg_length"] >= 10_000_000 and prev["seg_length"] >= 10_000_000:
                        if log2_col and abs(row[log2_col] - prev[log2_col]) > 0.2:
                            lst_count += 1
                prev = row
            hrd_metrics["LST_like"] = lst_count
            # HRD-LOH proxy: segments with log2 < -0.3 and length >15 Mb
            if log2_col:
                hrd_loh = ((seg_df[log2_col] < -0.3) & (seg_df["seg_length"] > 15_000_000)).sum()
                hrd_metrics["HRD_LOH_like"] = int(hrd_loh)
            # Telomeric AI proxy omitted (needs allele-specific data)
            hrd_score = sum(hrd_metrics.values())
            hrd_metrics["Simplified_HRD_score"] = hrd_score
            log.append(f"- LST-like events: {hrd_metrics['LST_like']}")
            log.append(f"- HRD-LOH-like events: {hrd_metrics['HRD_LOH_like']}")
            log.append(f"- Simplified composite HRD score: {hrd_metrics['Simplified_HRD_score']}")
            log.append("- NOTE: For clinical/research use, apply scarHRD or HRDetect with allele-specific data")
        else:
            log.append("- Segmentation not available; HRD approximation skipped")
    except Exception as e:
        log.append(f"- ERROR: HRD approximation failed: {e}")

    # ----------------------------------------------------------------------------------
    # STEP 4: Focal amplifications/deletions in key genes
    # ----------------------------------------------------------------------------------
    log.append("\\nSTEP 4: Focal Amplifications / Deletions in Key Genes")
    focal_events = []
    try:
        if seg_df is not None and gene_bed and os.path.exists(gene_bed):
            genes_df = pd.read_csv(gene_bed, sep="\\t", header=None, names=["chrom", "start", "end", "gene"])

            # Normalize chromosome naming
            def norm_chr(x):
                return x.replace("chr", "") if isinstance(x, str) else x

            seg_df["chr_norm"] = (
                seg_df[[c for c in seg_df.columns if c in ["chrom", "chromosome", "chr"]][0]].astype(str).map(norm_chr)
            )
            genes_df["chr_norm"] = genes_df["chrom"].astype(str).map(norm_chr)
            for gene in focal_genes:
                region = genes_df[genes_df["gene"] == gene]
                if region.empty:
                    continue
                r = region.iloc[0]
                # Ensure we work on a copy to avoid SettingWithCopyWarning
                overlaps = seg_df[
                    (seg_df["chr_norm"] == r["chr_norm"])
                    & (seg_df[start_col] <= r["end"])
                    & (seg_df[end_col] >= r["start"])
                ].copy()
                if not overlaps.empty and log2_col:
                    # Choose segment with largest overlap length
                    r_end = r["end"]
                    r_start = r["start"]
                    overlaps["ov_len"] = overlaps.apply(
                        lambda row, r_end=r_end, r_start=r_start: min(row[end_col], r_end)
                        - max(row[start_col], r_start),
                        axis=1,
                    )
                    best = overlaps.sort_values("ov_len", ascending=False).iloc[0]
                    l2 = best[log2_col]
                    status = None
                    if l2 >= log2_amp_threshold:
                        status = "AMPLIFICATION"
                    elif l2 <= log2_del_threshold:
                        status = "DELETION"
                    if status:
                        focal_events.append((gene, status, l2))
            if focal_events:
                for gene, status, l2 in focal_events:
                    log.append(f"- {gene}: {status} (log2={l2:.2f})")
            else:
                log.append("- No focal events meeting thresholds in target genes")
        else:
            if not gene_bed:
                log.append("- Skipped: gene_bed not provided")
            else:
                log.append("- Skipped: gene_bed file not found or segmentation unavailable")
    except Exception as e:
        log.append(f"- ERROR: Focal event detection failed: {e}")

    # ----------------------------------------------------------------------------------
    # STEP 5: Summaries & file outputs
    # ----------------------------------------------------------------------------------
    log.append("\\nSTEP 5: Summary & Output Files")
    summary = {
        "purity_estimate": purity_est,
        "ploidy_estimate": ploidy_est,
    }
    summary.update(hrd_metrics)
    summary_file = os.path.join(output_dir, f"{sample_name}_cn_summary.tsv")
    try:
        pd.DataFrame([summary]).to_csv(summary_file, sep="\\t", index=False)
        log.append(f"- Saved summary metrics: {summary_file}")
    except Exception as e:
        log.append(f"- WARNING: Could not save summary file: {e}")

    if focal_events:
        focal_file = os.path.join(output_dir, f"{sample_name}_focal_events.tsv")
        try:
            pd.DataFrame(focal_events, columns=["Gene", "Event", "Log2"]).to_csv(focal_file, sep="\\t", index=False)
            log.append(f"- Saved focal events: {focal_file}")
        except Exception as e:
            log.append(f"- WARNING: Could not save focal events file: {e}")

    log.append("\\nNEXT STEPS:")
    log.append("- For improved purity/ploidy estimation, consider ABSOLUTE, FACETS, PureCN, or Sequenza")
    log.append("- For validated HRD scoring, use scarHRD or HRDetect with allele-specific data")
    log.append("- Integrate CN events with expression data to assess driver gene activation/dosage")
    log.append("- Visualize CNV profiles using CNVkit's built-in plotting functions")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_copy_number_purity_ploidy_and_focal_events(
        tumor_bam=auto_convert(os.environ.get("PARAM_TUMOR_BAM", "")),
        reference_genome=auto_convert(os.environ.get("PARAM_REFERENCE_GENOME", "")),
        normal_bam=auto_convert(os.environ.get("PARAM_NORMAL_BAM", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "cn_analysis_results")),
        targets_bed=auto_convert(os.environ.get("PARAM_TARGETS_BED", "")),
        antitargets_bed=auto_convert(os.environ.get("PARAM_ANTITARGETS_BED", "")),
        gene_bed=auto_convert(os.environ.get("PARAM_GENE_BED", "")),
        focal_genes=auto_convert(os.environ.get("PARAM_FOCAL_GENES", "")),
        log2_amp_threshold=auto_convert(os.environ.get("PARAM_LOG2_AMP_THRESHOLD", "1.0")),
        log2_del_threshold=auto_convert(os.environ.get("PARAM_LOG2_DEL_THRESHOLD", "")),
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
    "function": "analyze_copy_number_purity_ploidy_and_focal_events",
    "domain": "cancer_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_copy_number_purity_ploidy_and_focal_events_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_copy_number_purity_ploidy_and_focal_events_output.txt", "w") as f:
    f.write("Biomni: Analyze Copy Number Purity Ploidy And Focal Events" + NL)
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
        biomni_function: "analyze_copy_number_purity_ploidy_and_focal_events"
    END_VERSIONS
    """
}

workflow ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS(ch_input)

    emit:
    results = ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS.out.results
    output = ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS.out.output
    versions = ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS_WORKFLOW(ch_input)

    ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS_WORKFLOW.out.output.view { "Output: $it" }
}
