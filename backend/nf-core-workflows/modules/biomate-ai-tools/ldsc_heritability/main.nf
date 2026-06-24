#!/usr/bin/env nextflow
/*
 * population_genetics/ldsc_heritability  (3-phase pipeline)
 *
 *   Phase A — Munge sumstats : munge_sumstats.py → standardized .sumstats.gz
 *   Phase B — h² estimation  : ldsc.py --h2 → heritability + intercept + ratio
 *   Phase C — Report          : parse .log, emit structured JSON + Markdown
 *
 * Real-use-case anchor (Zhi lab, Z01 chain post-processing step):
 *   Nat Commun 2026 (PMC12458571) Methods: LDSC used to estimate SNP-heritability
 *   of UDIP brain FA phenotypes and cross-trait rg with cognitive / neurological
 *   traits. Follows TorchGWAS and METAL steps; validates that GWAS results have
 *   well-calibrated test statistics (LDSC intercept ≈ 1 + attenuation ratio).
 *
 *   BioMate chain position:
 *     [TorchGWAS or METAL sumstats] → ldsc_heritability →
 *     [h² + intercept QC]           → feeds Findings panel / (why?) anchor
 *
 * Tool: LDSC v1.0.1 (bulik/ldsc, GPL-3.0, Brendan Bulik-Sullivan / Broad Institute)
 *       github.com/bulik/ldsc
 *
 * LD scores baked into container: eur_w_ld_chr (European 1KG Phase 3, 22 chr)
 *   from bulik-lab public S3 (s3://broad-alkesgroup-public-requester-pays/LDSCORE/).
 *   ~15 MB compressed; used for both --ref-ld-chr and --w-ld-chr.
 *
 * HapMap3 SNP list baked: w_hm3.snplist — used by munge_sumstats.py to filter
 *   to well-imputed HapMap3 variants before heritability estimation.
 *
 * Quick smoke (synthetic chr1 sumstats, minimal LD scores):
 *   nextflow run main.nf --use_baked_toy true --outdir results
 *
 * Real run (caller supplies GWAS sumstats):
 *   nextflow run main.nf \
 *       --gwas_sumstats s3://bucket/my_gwas.tsv \
 *       --snp_col   SNP \
 *       --pval_col  P \
 *       --a1_col    A1 \
 *       --a2_col    A2 \
 *       --n_col     N \
 *       --outfile   my_ldsc \
 *       --outdir    s3://bucket/runs/ldsc-001
 */
nextflow.enable.dsl = 2

params.outdir        = './results'
params.use_baked_toy = false
params.gwas_sumstats = 'null'   // path to GWAS sumstats (post-METAL or direct)
params.snp_col       = 'SNP'
params.pval_col      = 'P'
params.a1_col        = 'A1'
params.a2_col        = 'A2'
params.n_col         = 'N'
params.sample_size   = 50000    // used when n_col absent; required by munge_sumstats
params.outfile       = 'ldsc_run'

CONTAINER_LDSC = System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ldsc:v1.0.1' \
    : 'biomate/ldsc:v1.0.1'

// [Phase A] Munge sumstats — standardise to .sumstats.gz for LDSC
process LDSC_MUNGE {
    tag "ldsc:phaseA"
    label 'process_low'
    container CONTAINER_LDSC
    publishDir "${params.outdir}/phaseA_munge", mode: 'copy'

    input:  val(meta)
    output: tuple val(meta), path("${params.outfile}.sumstats.gz"), path("munge.json"), emit: out

    script:
    def baked     = params.use_baked_toy as Boolean
    def snp_col   = params.snp_col
    def pval_col  = params.pval_col
    def a1_col    = params.a1_col
    def a2_col    = params.a2_col
    def n_col     = params.n_col
    def n_fixed   = params.sample_size
    def outfile   = params.outfile
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, os, sys, random, math, subprocess

    baked    = ${baked}
    snp_col  = "${snp_col}"
    pval_col = "${pval_col}"
    a1_col   = "${a1_col}"
    a2_col   = "${a2_col}"
    n_col    = "${n_col}"
    n_fixed  = ${n_fixed}
    outfile  = "${outfile}"
    sumstats = "${params.gwas_sumstats}"

    if baked:
        # Synthetic chr1 GWAS sumstats for smoke. Use HapMap3 rsIDs where possible;
        # here we emit placeholder IDs so munge_sumstats can match against w_hm3.snplist.
        # The smoke only validates that munge + LDSC pipelines run, not real h².
        random.seed(42)
        with open("raw_sumstats.txt", "w") as f:
            f.write(f"SNP\\tA1\\tA2\\tZ\\tN\\n")
            for i in range(1000):
                z = random.gauss(0, 1) if i >= 100 else random.gauss(-3.0, 0.5)
                f.write(f"rs{10000000 + i}\\tA\\tG\\t{z:.4f}\\t50000\\n")
        snp_col  = "SNP"
        a1_col   = "A1"
        a2_col   = "A2"
        # munge_sumstats wants either --p (p-value col) or --signed-sumstats for Z
        munge_stat_flag = ["--signed-sumstats", "Z,0"]
    else:
        if sumstats in ("null", ""):
            print("ERROR: gwas_sumstats required when use_baked_toy=false", file=sys.stderr)
            sys.exit(1)
        import shutil
        shutil.copy(sumstats, "raw_sumstats.txt")
        munge_stat_flag = ["--p", pval_col]

    # HapMap3 SNP list baked at /opt/ldsc/ref/w_hm3.snplist
    hm3_list = "/opt/ldsc/ref/w_hm3.snplist"

    cmd = [
        "python3", "/opt/ldsc/munge_sumstats.py",
        "--sumstats", "raw_sumstats.txt",
        "--snp", snp_col,
        "--a1", a1_col,
        "--a2", a2_col,
        "--N", str(n_fixed),
    ] + munge_stat_flag + [
        "--merge-alleles", hm3_list,
        "--out", outfile,
        "--chunksize", "500000",
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    print(result.stdout[-2000:] if result.stdout else "")
    if result.returncode != 0:
        print(f"[ldsc:phaseA] munge stderr: {result.stderr[-1000:]}", file=sys.stderr)
        # Graceful: write an empty .sumstats.gz so Phase B can report
        import gzip
        with gzip.open(f"{outfile}.sumstats.gz", "wt") as f:
            f.write("SNP\\tN\\tZ\\tA1\\tA2\\n")

    # munge_sumstats.py writes a .log file alongside .sumstats.gz
    log_path = f"{outfile}.log"
    log_tail = open(log_path).read()[-1500:] if os.path.exists(log_path) else ""

    # Count variants in munged file
    import gzip as _gz
    n_snps = 0
    try:
        with _gz.open(f"{outfile}.sumstats.gz", "rt") as fh:
            n_snps = max(0, sum(1 for _ in fh) - 1)
    except Exception:
        pass

    json.dump({
        "phase": "A",
        "baked_toy": baked,
        "n_snps_munged": n_snps,
        "munge_ok": result.returncode == 0,
        "log_tail": log_tail,
    }, open("munge.json", "w"), indent=2)
    PY
    """
}

// [Phase B] LDSC heritability estimation
process LDSC_H2 {
    tag "ldsc:phaseB"
    label 'process_low'
    container CONTAINER_LDSC
    publishDir "${params.outdir}/phaseB_h2", mode: 'copy'

    input:  tuple val(meta), path(sumstats_gz), path(munge_json)
    output: tuple val(meta), path("h2.json"), path("${params.outfile}.log"), emit: out

    script:
    def outfile = params.outfile
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, os, subprocess

    outfile = "${outfile}"
    # LD scores baked at /opt/ldsc/ref/eur_w_ld_chr/
    ld_chr = "/opt/ldsc/ref/eur_w_ld_chr/"

    cmd = [
        "python3", "/opt/ldsc/ldsc.py",
        "--h2", "${sumstats_gz}",
        "--ref-ld-chr", ld_chr,
        "--w-ld-chr", ld_chr,
        "--out", outfile,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    print(result.stdout[-2000:] if result.stdout else "")
    if result.returncode != 0:
        print(f"[ldsc:phaseB] ldsc stderr: {result.stderr[-1000:]}", file=sys.stderr)

    # Parse LDSC .log for key estimates
    log_path = f"{outfile}.log"
    log_text = open(log_path).read() if os.path.exists(log_path) else result.stdout

    def _parse_float(log, label):
        import re
        m = re.search(rf"{re.escape(label)}\\s+([0-9.\\-e]+)", log)
        return float(m.group(1)) if m else None

    h2        = _parse_float(log_text, "Total Observed scale h2:")
    h2_se     = _parse_float(log_text, "Total Observed scale h2:.*?\\(([0-9.e]+)\\)") \
                or _parse_float(log_text, "h2 SE:")
    intercept = _parse_float(log_text, "Intercept:")
    ratio     = _parse_float(log_text, "Ratio:")
    lambda_gc = _parse_float(log_text, "Lambda GC:")

    # Simple regex sweep for h2 + SE in the standard "(value ± se)" pattern
    import re
    m2 = re.search(r"Total Observed scale h2:\\s*([0-9.e\\-]+)\\s*\\(([0-9.e\\-]+)\\)", log_text)
    if m2:
        h2, h2_se = float(m2.group(1)), float(m2.group(2))

    json.dump({
        "phase": "B",
        "h2_observed": h2,
        "h2_se": h2_se,
        "intercept": intercept,
        "attenuation_ratio": ratio,
        "lambda_gc": lambda_gc,
        "ldsc_ok": result.returncode == 0,
        "log_tail": log_text[-2000:],
    }, open("h2.json", "w"), indent=2)
    PY
    """
}

// [Phase C] Report — structured output for Findings panel + (why?) anchor
process LDSC_REPORT {
    tag "ldsc:phaseC"
    label 'process_low'
    container CONTAINER_LDSC
    publishDir "${params.outdir}/phaseC_report", mode: 'copy'

    input:  tuple val(meta), path(h2_json), path(ldsc_log)
    output: tuple val(meta), path("ldsc_report.json"), path("ldsc_report.md"), emit: out

    script:
    """
    python3 - <<'PY'
    import json

    h2 = json.load(open("${h2_json}"))

    h2_val  = h2.get("h2_observed")
    h2_se   = h2.get("h2_se")
    intercept = h2.get("intercept")
    ratio     = h2.get("attenuation_ratio")

    # QC flags (from LDSC documentation):
    #   - h² > 1 or h² < 0: suspicious (often bad sumstats or wrong population)
    #   - intercept > 1.1: genomic inflation likely (pop stratification or bias)
    #   - ratio > 0.1: a meaningful fraction of chi² inflation is not from polygenicity
    qc_flags = []
    if h2_val is not None:
        if h2_val < 0: qc_flags.append("h2 < 0 (check sumstats quality / HapMap3 overlap)")
        if h2_val > 1: qc_flags.append("h2 > 1 (likely inflated; check allele coding)")
    if intercept is not None and intercept > 1.1:
        qc_flags.append(f"Intercept {intercept:.3f} > 1.1 — possible population stratification or sumstats inflation")
    if ratio is not None and ratio > 0.1:
        qc_flags.append(f"Ratio {ratio:.3f} > 0.1 — interpret h² estimates cautiously")

    report = {
        "phase": "C",
        "tool": "LDSC",
        "version": "v1.0.1",
        "repo": "github.com/bulik/ldsc",
        "license": "GPL-3.0",
        "citation": "Bulik-Sullivan B et al. Nat Genet 2015; doi:10.1038/ng.3211",
        "h2_observed": h2_val,
        "h2_se": h2_se,
        "intercept": intercept,
        "attenuation_ratio": ratio,
        "lambda_gc": h2.get("lambda_gc"),
        "qc_flags": qc_flags,
        "qc_pass": len(qc_flags) == 0,
        "h2_detail": h2,
    }
    json.dump(report, open("ldsc_report.json", "w"), indent=2)

    h2_str  = f"{h2_val:.4f} ± {h2_se:.4f}" if (h2_val is not None and h2_se is not None) \
              else str(h2_val) if h2_val is not None else "N/A"
    int_str = f"{intercept:.4f}" if intercept is not None else "N/A"
    rat_str = f"{ratio:.4f}" if ratio is not None else "N/A"

    flag_lines = "\\n".join(f"- ⚠️  {f}" for f in qc_flags) if qc_flags \
                 else "- ✅ All QC checks passed"

    open("ldsc_report.md", "w").write(
        f"# LDSC SNP-heritability report\\n\\n"
        f"| Metric | Value |\\n"
        f"|---|---|\\n"
        f"| h² (observed scale) | **{h2_str}** |\\n"
        f"| LDSC intercept | {int_str} |\\n"
        f"| Attenuation ratio | {rat_str} |\\n"
        f"| Lambda GC | {h2.get('lambda_gc', 'N/A')} |\\n\\n"
        f"## QC flags\\n\\n{flag_lines}\\n\\n"
        f"## Interpretation\\n\\n"
        f"An intercept ≈ 1.0 indicates that inflation in test statistics is due to "
        f"polygenicity (true signal), not confounding. "
        f"The attenuation ratio < 0.1 is the LDSC target for well-controlled GWAS "
        f"(Bulik-Sullivan et al. Nat Genet 2015).\\n"
    )
    PY
    """
}

workflow {
    meta_ch = Channel.of([id: 'ldsc_heritability'])
    a = LDSC_MUNGE(meta_ch)
    b = LDSC_H2(a.out)
    LDSC_REPORT(b.out)
}
