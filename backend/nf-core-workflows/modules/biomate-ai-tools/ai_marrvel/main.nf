#!/usr/bin/env nextflow
/*
 * rare_disease/ai_marrvel  (4-phase wrap of upstream LiuzLab/AI_MARRVEL pipeline)
 *
 *   Phase A — Inputs       : validate vcf_input + hpo_terms; emit inputs.json
 *   Phase B — Ref-resolve  : verify ref_dir staged (or trigger
 *                            `aws s3 sync s3://aim-data-dependencies-2.4-public …
 *                            --no-sign-request`); emit ref_manifest.json
 *   Phase C — AIM pipeline : invoke upstream `nextflow run /opt/ai_marrvel/main.nf`
 *                            with --input_vcf --input_hpo --ref_dir --run_id
 *                            --ref_ver --outdir --storedir; emit aim_run.json
 *   Phase D — Report       : parse upstream outputs into ranked_variants.tsv +
 *                            ranked_genes.tsv + marrvel_report.{json,md}
 *
 * Real-use-case anchor:
 *   Mao D., Liu C., Wang L. et al. (2024). "AI-MARRVEL — A Knowledge-Driven
 *   AI System for Diagnosing Mendelian Disorders." NEJM AI 1(5):AIoa2300009.
 *   doi: 10.1056/AIoa2300009
 *
 * Promotes Liu rare-disease chain id 1 (rare_disease_multimodal_workup) from
 * L01 (RareCollab upstream tools: sarek + VEP + rnaseq + DROP) to L01-v2
 * (Liu's actual published end-to-end tool).
 *
 * Upstream:    https://github.com/LiuzLab/AI_MARRVEL  (GPL-3.0)
 * Upstream ver: v1.1.3 (manifest in upstream nextflow.config; task description
 *               cited v1.1.2 — we use the live head 1.1.3).
 * Image:       biomate/ai_marrvel:v1 — sibling container/Dockerfile.
 *              Bakes nextflow + cloned upstream repo. Ref data NOT baked
 *              (~tens of GB; pull from s3://aim-data-dependencies-2.4-public).
 *
 * Quick smoke (no real ref_dir — runs upstream --help via Phase A only):
 *   nextflow run main.nf --use_baked_example true --outdir results -stub-run
 *
 * Real run:
 *   nextflow run main.nf \
 *       --vcf_input s3://bucket/proband.vep.vcf.gz \
 *       --hpo_terms "HP:0001250,HP:0001263" \
 *       --ref_dir   /mnt/aim-ref-2.4 \
 *       --ref_ver   hg38 \
 *       --proband_id PROBAND01 \
 *       --outdir    s3://bucket/runs/aim-001
 */
nextflow.enable.dsl = 2

params.outdir            = './results'
params.use_baked_example = false

// BioMate-side param names (snake_case, friendly):
params.vcf_input         = 'null'                                            // s3:// or local annotated VCF (e.g. sarek+VEP output)
params.hpo_terms         = 'null'                                            // comma-separated, e.g. "HP:0001250,HP:0001263"
params.proband_id        = 'PROBAND01'                                       // mapped to upstream --run_id
params.ref_ver           = 'hg38'                                            // hg19 | hg38 (upstream --ref_ver)
params.ref_dir           = '/opt/ai_marrvel_ref'                             // pre-staged AIM ref dependencies (~tens of GB)
params.ref_s3_bucket     = 'aim-data-dependencies-2.4-public'                // upstream public bucket (no-sign-request)
params.auto_stage_ref    = false                                             // if true, Phase B runs `aws s3 sync` (slow + large)
params.outfile           = 'aim_run'
params.top_n             = 10                                                // top-N variants for marrvel_report

CONTAINER_AIM = System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai_marrvel:v1' \
    : 'biomate/ai_marrvel:v1'

// [Phase A] Input resolution + validation
process AIM_INPUTS {
    tag "ai_marrvel:phaseA"
    label 'process_low'
    container CONTAINER_AIM
    publishDir "${params.outdir}/phaseA_inputs", mode: 'copy'

    input:  val(meta)
    output: tuple val(meta), path("inputs.json"), path("input_hpo.txt"), emit: out

    script:
    def baked = (params.use_baked_example as Boolean) ? 'True' : 'False'
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, sys, re, os

    baked = ${baked}
    vcf   = "${params.vcf_input}"
    hpo   = "${params.hpo_terms}"
    ver   = "${params.ref_ver}"
    proband = "${params.proband_id}"

    if baked:
        # Stub-smoke path: no real inputs, fall through to upstream --help in Phase C.
        vcf_resolved = "<baked-example-no-vcf>"
        hpo_list = ["HP:0001250", "HP:0001263"]  # seizures + intellectual disability (illustrative)
    else:
        if vcf in ("null", "", None):
            print("ERROR: vcf_input required when use_baked_example=false", file=sys.stderr); sys.exit(1)
        if hpo in ("null", "", None):
            print("ERROR: hpo_terms required when use_baked_example=false", file=sys.stderr); sys.exit(1)
        vcf_resolved = vcf
        hpo_list = [t.strip() for t in re.split(r"[,\\s]+", hpo) if t.strip()]
        bad = [t for t in hpo_list if not re.match(r"^HP:\\d{7}\$", t)]
        if bad:
            print(f"ERROR: malformed HPO terms (expect HP:NNNNNNN): {bad}", file=sys.stderr); sys.exit(1)

    if ver not in ("hg19", "hg38"):
        print(f"ERROR: ref_ver must be hg19 or hg38, got {ver}", file=sys.stderr); sys.exit(1)

    # Upstream expects HPO as one term per line in a .txt file.
    with open("input_hpo.txt", "w") as fh:
        for t in hpo_list:
            fh.write(t + "\\n")

    json.dump({
        "phase": "A",
        "baked_example": baked,
        "vcf_input": vcf_resolved,
        "hpo_terms": hpo_list,
        "hpo_file": "input_hpo.txt",
        "ref_ver": ver,
        "proband_id": proband,
        "outfile": "${params.outfile}",
    }, open("inputs.json","w"), indent=2)
    PY
    """
}

// [Phase B] Ref-dir resolution + manifest
process AIM_REF_RESOLVE {
    tag "ai_marrvel:phaseB"
    label 'process_low'
    container CONTAINER_AIM
    publishDir "${params.outdir}/phaseB_ref", mode: 'copy'

    input:  tuple val(meta), path(inputs_json), path(hpo_file)
    output: tuple val(meta), path(inputs_json), path(hpo_file), path("ref_manifest.json"), emit: out

    script:
    def baked = (params.use_baked_example as Boolean) ? 'True' : 'False'
    def auto  = (params.auto_stage_ref as Boolean) ? 'True' : 'False'
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, os, subprocess, sys

    baked   = ${baked}
    auto    = ${auto}
    ref_dir = "${params.ref_dir}"
    bucket  = "${params.ref_s3_bucket}"

    info = {"phase": "B", "ref_dir": ref_dir, "bucket": bucket,
            "baked_example": baked, "auto_stage_ref": auto}

    if baked:
        info["status"] = "skipped (baked_example)"
    elif not os.path.isdir(ref_dir) or not os.listdir(ref_dir):
        if auto:
            info["status"] = "syncing from s3"
            cmd = ["aws", "s3", "sync", f"s3://{bucket}", ref_dir, "--no-sign-request"]
            print("[ref] " + " ".join(cmd))
            rc = subprocess.call(cmd)
            info["sync_rc"] = rc
            if rc != 0:
                print(f"ERROR: aws s3 sync failed rc={rc}", file=sys.stderr); sys.exit(1)
        else:
            print(f"ERROR: ref_dir {ref_dir} empty/missing; set --auto_stage_ref true or pre-stage it",
                  file=sys.stderr); sys.exit(1)
    else:
        info["status"] = "pre-staged"
        info["entries"] = sorted(os.listdir(ref_dir))[:25]

    json.dump(info, open("ref_manifest.json","w"), indent=2)
    PY
    """
}

// [Phase C] Invoke upstream AI-MARRVEL pipeline
// NOTE: AI-MARRVEL is itself a Nextflow pipeline (not a single CLI). We delegate
// to it with a sub-`nextflow run`. In stub mode we invoke `--help` so Phase A/B
// wiring can be verified end-to-end without ref data.
process AIM_RUN {
    tag "ai_marrvel:phaseC"
    label 'process_high'
    container CONTAINER_AIM
    publishDir "${params.outdir}/phaseC_aim", mode: 'copy'

    input:  tuple val(meta), path(inputs_json), path(hpo_file), path(ref_manifest)
    output: tuple val(meta),
            path("aim_out", type: 'dir', optional: true),
            path("aim_run.json"),
            path("aim_run.log"), emit: out

    script:
    def baked = (params.use_baked_example as Boolean) ? 'True' : 'False'
    """
    set -euo pipefail
    mkdir -p aim_out aim_store

    if [ ${baked} = "True" ]; then
        # Stub-smoke: just exercise the upstream --help to prove the pipeline parses.
        /opt/nextflow/nextflow run /opt/ai_marrvel/main.nf --help 2>&1 | tee aim_run.log || true
        AIM_STATUS="stub_help_only"
    else
        /opt/nextflow/nextflow run /opt/ai_marrvel/main.nf \\
            -profile docker \\
            --input_vcf  "${params.vcf_input}" \\
            --input_hpo  "${hpo_file}" \\
            --ref_dir    "${params.ref_dir}" \\
            --ref_ver    "${params.ref_ver}" \\
            --run_id     "${params.proband_id}" \\
            --outdir     aim_out \\
            --storedir   aim_store 2>&1 | tee aim_run.log
        AIM_STATUS="completed"
    fi

    python3 - <<PY
    import json, os, glob
    out_files = []
    for root, _dirs, files in os.walk("aim_out"):
        for f in files:
            p = os.path.join(root, f)
            try:
                sz = os.path.getsize(p)
            except OSError:
                sz = -1
            out_files.append({"path": p, "bytes": sz})
    json.dump({
        "phase": "C",
        "status": "${'$'}AIM_STATUS",
        "upstream": "LiuzLab/AI_MARRVEL@v1.1.3",
        "doi": "10.1056/AIoa2300009",
        "out_file_count": len(out_files),
        "out_files_head": out_files[:50],
    }, open("aim_run.json","w"), indent=2)
    PY
    """
}

// [Phase D] Parse AI-MARRVEL outputs into ranked_variants + report
process AIM_REPORT {
    tag "ai_marrvel:phaseD"
    label 'process_low'
    container CONTAINER_AIM
    publishDir "${params.outdir}/phaseD_report", mode: 'copy'

    input:  tuple val(meta), path(aim_out, stageAs: 'aim_out'), path(aim_run_json), path(aim_run_log)
    output: tuple val(meta),
            path("ranked_variants.tsv"),
            path("ranked_genes.tsv"),
            path("marrvel_report.json"),
            path("marrvel_report.md"), emit: out

    script:
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, os, glob
    import pandas as pd

    TOPN = int("${params.top_n}")
    aim_run = json.load(open("${aim_run_json}"))

    # AI-MARRVEL upstream emits per-run scored predictions. Exact filenames vary
    # by upstream version; common patterns observed:
    #   - <run_id>/final_matrix_expanded/<run_id>.csv     (full scored variants)
    #   - <run_id>/conf_4Model/<run_id>.csv               (confidence-scored)
    #   - <run_id>/score/<run_id>.csv                     (prediction score)
    # We scan aim_out/ for the largest CSV and treat it as the scored-variant
    # table; if none found (stub-smoke), we emit empty placeholders.
    candidate_csvs = sorted(
        glob.glob("aim_out/**/*.csv", recursive=True),
        key=lambda p: os.path.getsize(p), reverse=True,
    )

    cols_variant = ["chrom", "pos", "ref", "alt", "gene", "prediction_score",
                    "confidence_score", "rank"]
    cols_gene    = ["gene", "best_variant_score", "n_variants", "rank"]

    variants_df = pd.DataFrame(columns=cols_variant)
    genes_df    = pd.DataFrame(columns=cols_gene)

    if candidate_csvs:
        src = candidate_csvs[0]
        try:
            df = pd.read_csv(src)
        except Exception as e:
            df = pd.DataFrame()
            note = f"failed to parse {src}: {e}"
        else:
            note = f"parsed {src} rows={len(df)}"
        # Normalize column names to lowercase for fuzzy match.
        if not df.empty:
            df.columns = [c.lower() for c in df.columns]
            # Heuristic field mapping — varies by upstream version.
            score_col = next((c for c in df.columns
                              if c in ("predict","prediction","prediction_score","score")),
                             None)
            conf_col  = next((c for c in df.columns
                              if c in ("confidence","confidence_score","conf")), None)
            gene_col  = next((c for c in df.columns
                              if c in ("gene","genesymbol","symbol")), None)
            if score_col:
                df = df.sort_values(score_col, ascending=False).reset_index(drop=True)
                df["rank"] = df.index + 1
                pick = lambda c: df[c] if c in df.columns else ""
                variants_df = pd.DataFrame({
                    "chrom":            pick("chrom") if "chrom" in df.columns else pick("chr"),
                    "pos":              pick("pos"),
                    "ref":              pick("ref"),
                    "alt":              pick("alt"),
                    "gene":             df[gene_col] if gene_col else "",
                    "prediction_score": df[score_col],
                    "confidence_score": df[conf_col] if conf_col else "",
                    "rank":             df["rank"],
                }).head(TOPN)
                if gene_col:
                    g = (df.groupby(gene_col)[score_col].agg(['max','count'])
                            .reset_index()
                            .rename(columns={gene_col:'gene','max':'best_variant_score','count':'n_variants'})
                            .sort_values('best_variant_score', ascending=False)
                            .reset_index(drop=True))
                    g["rank"] = g.index + 1
                    genes_df = g.head(TOPN)
    else:
        note = "no upstream CSV found (stub or failed run); emitting empty placeholders"

    variants_df.to_csv("ranked_variants.tsv", sep="\\t", index=False)
    genes_df.to_csv("ranked_genes.tsv",       sep="\\t", index=False)

    summary = {
        "phase": "D",
        "tool":  "AI-MARRVEL",
        "version": "v1.1.3",
        "citation": "Mao et al. 2024 NEJM AI 10.1056/AIoa2300009",
        "license": "GPL-3.0",
        "upstream": "https://github.com/LiuzLab/AI_MARRVEL",
        "parsed_csv_count": len(candidate_csvs),
        "parse_note": note,
        "top_n": TOPN,
        "top_variants": variants_df.to_dict(orient='records'),
        "top_genes":    genes_df.to_dict(orient='records'),
        "phase_c": aim_run,
    }
    json.dump(summary, open("marrvel_report.json","w"), indent=2, default=str)

    with open("marrvel_report.md","w") as fh:
        fh.write("# AI-MARRVEL Report\\n\\n")
        fh.write("Tool: AI-MARRVEL v1.1.3 (Mao et al. 2024 NEJM AI, 10.1056/AIoa2300009).\\n")
        fh.write("Upstream: https://github.com/LiuzLab/AI_MARRVEL (GPL-3.0).\\n\\n")
        fh.write(f"- Phase-C status: **{aim_run.get('status','unknown')}**\\n")
        fh.write(f"- Upstream output CSVs scanned: **{len(candidate_csvs)}**\\n")
        fh.write(f"- Parse note: {note}\\n\\n")
        fh.write(f"## Top {TOPN} candidate variants\\n\\n")
        if not variants_df.empty:
            fh.write("| " + " | ".join(variants_df.columns) + " |\\n")
            fh.write("| " + " | ".join(["---"]*len(variants_df.columns)) + " |\\n")
            for _, r in variants_df.iterrows():
                fh.write("| " + " | ".join(str(r[c]) for c in variants_df.columns) + " |\\n")
        else:
            fh.write("_No ranked variants (stub-smoke or upstream produced no scored CSV)._\\n")
        fh.write(f"\\n## Top {TOPN} candidate genes\\n\\n")
        if not genes_df.empty:
            fh.write("| " + " | ".join(genes_df.columns) + " |\\n")
            fh.write("| " + " | ".join(["---"]*len(genes_df.columns)) + " |\\n")
            for _, r in genes_df.iterrows():
                fh.write("| " + " | ".join(str(r[c]) for c in genes_df.columns) + " |\\n")
        else:
            fh.write("_No ranked genes._\\n")
    PY
    """
}

workflow {
    meta_ch = Channel.of([id: 'ai_marrvel'])
    a = AIM_INPUTS(meta_ch)
    b = AIM_REF_RESOLVE(a.out)
    c = AIM_RUN(b.out)
    AIM_REPORT(c.out)
}
