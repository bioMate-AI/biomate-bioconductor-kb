#!/usr/bin/env nextflow
/*
 * population_genetics/metal_meta_analysis  (2-phase pipeline)
 *
 *   Phase A — Input prep   : validate cohort sumstats; write METAL script file;
 *                             optionally generate synthetic baked-toy cohorts
 *   Phase B — METAL run    : execute METAL → METAANALYSIS1.TBL + .TBL.info;
 *                             parse results; emit meta-analyzed sumstats + report
 *
 * Real-use-case anchor (Zhi lab, Z01 chain pre-processing step):
 *   Nat Commun 2026 (PMC12458571) Methods: multi-cohort GWAS meta-analysis
 *   of UDIP FA brain-image phenotypes using METAL (Willer et al. Bioinformatics
 *   2010, doi:10.1093/bioinformatics/btq340). Combines per-cohort GWAS sumstats
 *   (e.g. UKB + ENIGMA sub-cohorts) before downstream MAGMA / TorchGWAS analysis.
 *
 *   BioMate chain position:
 *     [per-cohort GWAS sumstats] → metal_meta_analysis →
 *     [combined sumstats]        → magma_gene_analysis  →
 *     [.genes.out / _boxcox.txt] → torchgwas or scgwas
 *
 * Tool: METAL (statgen/METAL, MIT, University of Michigan / Willer lab)
 *       Binary compiled from source at container build time.
 *
 * Quick smoke (two synthetic cohorts, 1 000 SNPs each, chr1):
 *   nextflow run main.nf --use_baked_toy true --outdir results
 *
 * Real run (caller supplies ≥2 sumstats files, comma-separated):
 *   nextflow run main.nf \
 *       --sumstats_list "s3://bucket/cohort1.tsv,s3://bucket/cohort2.tsv" \
 *       --scheme STDERR \
 *       --snp_col  SNP \
 *       --a1_col   A1 \
 *       --a2_col   A2 \
 *       --beta_col BETA \
 *       --se_col   SE \
 *       --pval_col P \
 *       --freq_col FRQ \
 *       --outfile  my_meta \
 *       --outdir   s3://bucket/runs/metal-001
 */
nextflow.enable.dsl = 2

params.outdir        = './results'
params.use_baked_toy = false
params.sumstats_list = 'null'   // comma-separated paths to cohort sumstats (≥2)
params.scheme        = 'STDERR' // STDERR (inverse-variance) | SAMPLESIZE (N-weighted)
params.snp_col       = 'SNP'
params.a1_col        = 'A1'
params.a2_col        = 'A2'
params.beta_col      = 'BETA'
params.se_col        = 'SE'
params.pval_col      = 'P'
params.freq_col      = 'FRQ'
params.n_col         = 'N'
params.outfile       = 'metal_run'

CONTAINER_METAL = System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/metal:latest' \
    : 'biomate/metal:latest'

// [Phase A] Input prep — write METAL script; stage or generate cohort files
process METAL_PREP {
    tag "metal:phaseA"
    label 'process_low'
    container CONTAINER_METAL
    publishDir "${params.outdir}/phaseA_prep", mode: 'copy'

    input:  val(meta)
    output: tuple val(meta), path("metal_script.txt"), path("prep.json"), emit: out

    script:
    def baked    = params.use_baked_toy as Boolean
    def scheme   = params.scheme
    def snp_col  = params.snp_col
    def a1_col   = params.a1_col
    def a2_col   = params.a2_col
    def beta_col = params.beta_col
    def se_col   = params.se_col
    def pval_col = params.pval_col
    def freq_col = params.freq_col
    def n_col    = params.n_col
    def outfile  = params.outfile
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, os, sys, random, math

    baked    = ${baked}
    scheme   = "${scheme}"
    snp_col  = "${snp_col}"
    a1_col   = "${a1_col}"
    a2_col   = "${a2_col}"
    beta_col = "${beta_col}"
    se_col   = "${se_col}"
    pval_col = "${pval_col}"
    freq_col = "${freq_col}"
    n_col    = "${n_col}"
    outfile  = "${outfile}"
    sumstats_list = "${params.sumstats_list}"

    cohort_files = []

    if baked:
        random.seed(42)
        alleles_pool = [("A", "G"), ("C", "T"), ("G", "A"), ("T", "C")]
        n_snps = 1000

        # Generate two synthetic cohorts — same SNPs, slightly different effects.
        # Cluster of strong signal (chr1 50–55 Mb) shared across both cohorts.
        snp_data = []
        for i in range(n_snps):
            chr_n = 1
            bp = random.randint(1_000_000, 249_000_000) if i >= 100 \
                 else random.randint(50_000_000, 55_000_000)
            a1, a2 = random.choice(alleles_pool)
            freq = round(random.uniform(0.05, 0.49), 4)
            true_beta = -0.05 + random.gauss(0, 0.01) if i < 100 else random.gauss(0, 0.02)
            snp_data.append((f"rs_toy_{i}", chr_n, bp, a1, a2, freq, true_beta))

        header = f"{snp_col}\\tCHR\\tBP\\t{a1_col}\\t{a2_col}\\t{freq_col}\\t{beta_col}\\t{se_col}\\t{pval_col}\\t{n_col}"
        for cohort_idx, (n_cohort, noise) in enumerate([(5000, 0.03), (7200, 0.025)], 1):
            fname = f"cohort{cohort_idx}.tsv"
            with open(fname, "w") as f:
                f.write(header + "\\n")
                for snp_id, chr_n, bp, a1, a2, freq, true_beta in snp_data:
                    beta = true_beta + random.gauss(0, noise)
                    se   = abs(noise) + random.uniform(0.005, 0.015)
                    z    = beta / se
                    # Approximate p-value from normal distribution
                    p = min(1.0, 2 * (1 - 0.5 * (1 + math.erf(abs(z) / math.sqrt(2)))))
                    p = max(1e-15, p)
                    f.write(f"{snp_id}\\t{chr_n}\\t{bp}\\t{a1}\\t{a2}\\t{freq:.4f}\\t{beta:.6f}\\t{se:.6f}\\t{p:.3e}\\t{n_cohort}\\n")
            cohort_files.append(fname)
    else:
        if sumstats_list in ("null", ""):
            print("ERROR: sumstats_list required when use_baked_toy=false", file=sys.stderr)
            sys.exit(1)
        raw_paths = [p.strip() for p in sumstats_list.split(",") if p.strip()]
        if len(raw_paths) < 2:
            print("ERROR: at least 2 cohort files required for meta-analysis", file=sys.stderr)
            sys.exit(1)
        import shutil
        for i, path in enumerate(raw_paths, 1):
            dest = f"cohort{i}.tsv"
            shutil.copy(path, dest)
            cohort_files.append(dest)

    # Write METAL script
    lines = [
        f"SCHEME {scheme}",
        "SEPARATOR TAB",
        f"MARKERLABEL {snp_col}",
        f"ALLELELABELS {a1_col} {a2_col}",
        f"EFFECTLABEL {beta_col}",
        f"STDERRLABEL {se_col}",
        f"PVALUELABEL {pval_col}",
        f"FREQLABEL {freq_col}",
        "GENOMICCONTROL ON",
        "",
    ]
    for f in cohort_files:
        lines.append(f"PROCESS {f}")
    lines += ["", "ANALYZE HETEROGENEITY", "QUIT"]

    with open("metal_script.txt", "w") as fh:
        fh.write("\\n".join(lines) + "\\n")

    json.dump({
        "phase": "A",
        "baked_toy": baked,
        "scheme": scheme,
        "n_cohorts": len(cohort_files),
        "cohort_files": cohort_files,
    }, open("prep.json", "w"), indent=2)
    PY
    """
}

// [Phase B] METAL run — produce meta-analyzed summary statistics
process METAL_RUN {
    tag "metal:phaseB"
    label 'process_medium'
    container CONTAINER_METAL
    publishDir "${params.outdir}/phaseB_meta", mode: 'copy'

    input:  tuple val(meta), path(metal_script), path(prep_json)
    output: tuple val(meta),
            path("${params.outfile}.meta.tsv"),
            path("metal_report.json"),
            path("metal_report.md"), emit: out

    script:
    def outfile = params.outfile
    """
    set -euo pipefail

    # METAL writes METAANALYSIS1.TBL (and .TBL.info); rename to our outfile.
    metal ${metal_script} 2>&1 | tee metal.log

    python3 - <<'PY'
    import json, os, csv, shutil

    prep    = json.load(open("${prep_json}"))
    outfile = "${outfile}"

    # METAL output is METAANALYSIS1.TBL (tab-separated)
    tbl_path = "METAANALYSIS1.TBL"
    if not os.path.exists(tbl_path):
        # Look for any .TBL in cwd
        for f in os.listdir("."):
            if f.endswith(".TBL"):
                tbl_path = f
                break

    rows = []
    if os.path.exists(tbl_path):
        with open(tbl_path) as fh:
            reader = csv.DictReader(fh, delimiter="\\t")
            for row in reader:
                rows.append(row)
        shutil.copy(tbl_path, f"{outfile}.meta.tsv")
    else:
        print("[metal:phaseB] WARNING: METAL TBL output not found; writing empty file")
        open(f"{outfile}.meta.tsv", "w").write(
            "MarkerName\\tAllele1\\tAllele2\\tWeight\\tZscore\\tP-value\\tDirection\\tHetISq\\n")

    # Count genome-wide significant hits (P < 5e-8)
    n_gw = 0
    for r in rows:
        try:
            if float(r.get("P-value", 1.0)) <= 5e-8:
                n_gw += 1
        except ValueError:
            pass

    log_tail = open("metal.log").read()[-1500:] if os.path.exists("metal.log") else ""

    report = {
        "phase": "B",
        "tool": "METAL",
        "repo": "github.com/statgen/METAL",
        "license": "MIT",
        "citation": "Willer CJ et al. Bioinformatics 2010; doi:10.1093/bioinformatics/btq340",
        "scheme": prep.get("scheme", "STDERR"),
        "n_cohorts": prep.get("n_cohorts", 0),
        "n_snps_meta": len(rows),
        "n_genome_wide_5e8": n_gw,
        "output_file": f"{outfile}.meta.tsv",
        "downstream": {
            "magma": f"--gwas_sumstats {outfile}.meta.tsv --snp_col MarkerName --pval_col P-value",
            "torchgwas": "Phase A genotype input is independent; meta sumstats inform MAGMA gene step",
            "ldsc": f"--gwas_sumstats {outfile}.meta.tsv (after munge_sumstats)",
        },
        "log_tail": log_tail,
    }
    json.dump(report, open("metal_report.json", "w"), indent=2)

    open("metal_report.md", "w").write(
        f"# METAL meta-analysis report\\n\\n"
        f"- Cohorts combined: {prep.get('n_cohorts', 0)}\\n"
        f"- Scheme: {prep.get('scheme', 'STDERR')}\\n"
        f"- SNPs in meta-output: {len(rows)}\\n"
        f"- Genome-wide significant (P ≤ 5×10⁻⁸): **{n_gw}**\\n\\n"
        f"## Next steps\\n\\n"
        f"- **MAGMA**: `--gwas_sumstats {outfile}.meta.tsv --snp_col MarkerName --pval_col P-value`\\n"
        f"- **LDSC**: munge `{outfile}.meta.tsv` then run `ldsc.py --h2`\\n"
    )
    PY
    """
}

workflow {
    meta_ch = Channel.of([id: 'metal_meta_analysis'])
    a = METAL_PREP(meta_ch)
    METAL_RUN(a.out)
}
