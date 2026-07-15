#!/usr/bin/env nextflow
/*
 * population_genetics/fuma_functional_annotation  (4-phase HTTP-client pipeline)
 *
 *   Phase A — Input prep    : resolve sumstats + assemble FUMA SNP2GENE params
 *   Phase B — Submit job    : POST sumstats to FUMA SNP2GENE endpoint
 *   Phase C — Poll          : GET status every poll_interval_s until COMPLETED
 *                              (or max_wait_min reached), download result zip
 *   Phase D — Report        : extract zip, parse GenomicRiskLoci.txt +
 *                              magma.genes.out + magma.gsa.out -> fuma_report.{json,md}
 *
 * Real-use-case anchor:
 *   Watanabe, Taskesen, van Bochoven, Posthuma (2017). "Functional mapping
 *   and annotation of genetic associations with FUMA." Nat Commun 8:1826.
 *   doi: 10.1038/s41467-017-01261-5
 *
 * Required to complete the Zhi UDIP-FA paper-faithful pipeline (PMC12458571):
 *   TorchGWAS -> GCTA -> MAGMA -> METAL -> LDSC -> FUMA
 *
 * ----------------------------------------------------------------------------
 * !!! STATUS — v1 (2026-06-20) !!!
 *
 * FUMA (https://fuma.ctglab.nl) is a hosted web service. As of this wrap,
 * we could NOT verify the presence of a public REST API for programmatic
 * job submission (the FUMA site was unreachable from the build sandbox, so
 * the endpoint shape below is structural/best-guess from the FUMA web UI).
 *
 * If no public API exists:
 *   - Phase B/C will FAIL at runtime on live submit
 *   - Operators must instead submit sumstats manually via the FUMA web UI
 *     (https://fuma.ctglab.nl/), download the result zip, and re-enter this
 *     pipeline at Phase D (--results_zip path/to/FUMA_jobNNN.zip)
 *   - Phase A stub-smoke (this file's nextflow stub-run) still passes
 *     regardless, validating the wrap's structural shape for the catalog
 *
 * TODO(fuma-api): once the FUMA team publishes a public API spec, replace the
 * Phase B endpoint URL + auth header + payload schema and remove this
 * status banner.
 * ----------------------------------------------------------------------------
 *
 * Upstream: https://fuma.ctglab.nl/
 * Image:    biomate/fuma:v1 — thin requests+pandas client.
 *
 * Quick smoke (uses baked example, zero external inputs):
 *   nextflow run main.nf --use_baked_example true --outdir results
 *
 * Real run (once API verified):
 *   nextflow run main.nf \
 *       --sumstats_input s3://bucket/my-gwas.txt \
 *       --population EUR \
 *       --outdir s3://bucket/runs/fuma-001
 */
nextflow.enable.dsl = 2

params.outdir            = './results'
params.use_baked_example = false
params.sumstats_input    = 'null'                                              // GWAS sumstats (SNP CHR BP A1 A2 P ...)
params.population        = 'EUR'                                               // EUR/EAS/AFR/AMR/SAS for FUMA LD ref
params.maf_threshold     = 0.01
params.r2_window         = 0.6
params.gene_based        = true                                                // run MAGMA gene-based test inside FUMA
params.poll_interval_s   = 60
params.max_wait_min      = 30
params.results_zip       = 'null'                                              // re-entry point when API unavailable; pre-downloaded FUMA zip
params.outfile           = 'fuma_run'
params.fuma_api_base     = 'https://fuma.ctglab.nl'                            // TODO(fuma-api): confirm
params.fuma_token        = 'null'                                              // TODO(fuma-api): auth header if required

CONTAINER_FUMA = System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/fuma:v1' \
    : 'biomate/fuma:v1'

// [Phase A] Input prep — resolve sumstats path + assemble SNP2GENE params.
process FUMA_INPUTS {
    tag "fuma:phaseA"
    label 'process_low'
    container CONTAINER_FUMA
    publishDir "${params.outdir}/phaseA_inputs", mode: 'copy'

    input:  val(meta)
    output: tuple val(meta), path("inputs.json"), emit: out

    script:
    def baked = (params.use_baked_example as Boolean) ? 'True' : 'False'
    """
    set -euo pipefail
    python3 - <<PY
    import json, os, sys

    baked = ${baked}
    if baked:
        sumstats = "/opt/fuma/example/example_sumstats.txt"   # placeholder; bake-or-skip
    else:
        sumstats = "${params.sumstats_input}"
        if sumstats in ("null","") and "${params.results_zip}" in ("null",""):
            print("ERROR: sumstats_input OR results_zip required when use_baked_example=false", file=sys.stderr)
            sys.exit(1)

    info = {
        "phase":"A",
        "baked_example": baked,
        "sumstats_path": sumstats,
        "population":   "${params.population}",
        "maf_threshold": ${params.maf_threshold},
        "r2_window":     ${params.r2_window},
        "gene_based":    ${(params.gene_based as Boolean) ? 'True' : 'False'},
        "poll_interval_s": ${params.poll_interval_s},
        "max_wait_min":    ${params.max_wait_min},
        "fuma_api_base":  "${params.fuma_api_base}",
        "results_zip":    "${params.results_zip}",
        "outfile": "${params.outfile}",
    }
    json.dump(info, open("inputs.json","w"), indent=2)
    PY
    """

    stub:
    """
    echo '{"phase":"A","stub":true}' > inputs.json
    """
}

// [Phase B] Submit FUMA SNP2GENE job.
//
// TODO(fuma-api): the endpoint URL + request body shape below is
// structural — FUMA may require a registered-user session cookie + CSRF
// token + multipart form submission rather than a JSON REST POST. Verify
// against the FUMA web service before enabling on production.
process FUMA_SUBMIT {
    tag "fuma:phaseB"
    label 'process_low'
    container CONTAINER_FUMA
    publishDir "${params.outdir}/phaseB_submit", mode: 'copy'

    input:  tuple val(meta), path(inputs_json)
    output: tuple val(meta), path("submit.json"), emit: out

    script:
    """
    set -euo pipefail
    python3 - <<PY
    import json, os, sys

    cfg = json.load(open("${inputs_json}"))
    # If operator pre-downloaded results, skip submit entirely.
    if cfg.get("results_zip") not in ("null", "", None):
        json.dump({
            "phase":"B",
            "submit_skipped": True,
            "reason": "results_zip provided; re-entering at Phase D",
            "job_id": None,
        }, open("submit.json","w"), indent=2)
        sys.exit(0)

    try:
        import requests
    except Exception as e:
        print(f"ERROR: requests not available: {e}", file=sys.stderr); sys.exit(2)

    # TODO(fuma-api): replace with confirmed endpoint shape.
    url = cfg["fuma_api_base"].rstrip("/") + "/api/snp2gene/submit"
    payload = {
        "population":   cfg["population"],
        "maf":          cfg["maf_threshold"],
        "r2":           cfg["r2_window"],
        "gene_based":   cfg["gene_based"],
    }
    files = {"sumstats": open(cfg["sumstats_path"], "rb")} if os.path.exists(cfg["sumstats_path"]) else None
    try:
        r = requests.post(url, data=payload, files=files, timeout=120)
        r.raise_for_status()
        body = r.json()
        job_id = body.get("job_id") or body.get("jobID") or body.get("id")
    except Exception as e:
        print(f"ERROR: FUMA submit failed: {e}", file=sys.stderr)
        print("HINT: FUMA may have no public API — submit manually via "
              "https://fuma.ctglab.nl and re-run with --results_zip <path>",
              file=sys.stderr)
        sys.exit(3)

    json.dump({
        "phase":"B",
        "submit_skipped": False,
        "job_id": job_id,
        "endpoint": url,
    }, open("submit.json","w"), indent=2)
    PY
    """

    stub:
    """
    echo '{"phase":"B","stub":true,"job_id":"STUB_JOB_123"}' > submit.json
    """
}

// [Phase C] Poll FUMA job status; on COMPLETED, download result zip.
//
// TODO(fuma-api): status + download endpoints are structural; verify
// against FUMA web service.
process FUMA_POLL {
    tag "fuma:phaseC"
    label 'process_medium'
    container CONTAINER_FUMA
    publishDir "${params.outdir}/phaseC_poll", mode: 'copy'

    input:  tuple val(meta), path(submit_json), path(inputs_json)
    output: tuple val(meta), path("${params.outfile}.zip"), path("poll.json"), emit: out

    script:
    """
    set -euo pipefail
    python3 - <<PY
    import json, os, sys, time, shutil

    cfg = json.load(open("${inputs_json}"))
    sub = json.load(open("${submit_json}"))

    # Re-entry path: operator provided a pre-downloaded zip.
    if cfg.get("results_zip") not in ("null", "", None):
        src = cfg["results_zip"]
        if not os.path.exists(src):
            print(f"ERROR: results_zip not found: {src}", file=sys.stderr); sys.exit(1)
        shutil.copy(src, "${params.outfile}.zip")
        json.dump({"phase":"C","mode":"reentry","src":src}, open("poll.json","w"), indent=2)
        sys.exit(0)

    job_id = sub.get("job_id")
    if not job_id:
        print("ERROR: no job_id from Phase B", file=sys.stderr); sys.exit(2)

    import requests
    base       = cfg["fuma_api_base"].rstrip("/")
    status_url = f"{base}/api/snp2gene/status/{job_id}"      # TODO(fuma-api)
    dl_url     = f"{base}/api/snp2gene/download/{job_id}"    # TODO(fuma-api)
    interval   = int(cfg["poll_interval_s"])
    max_wait   = int(cfg["max_wait_min"]) * 60
    waited     = 0
    final      = None

    while waited < max_wait:
        try:
            r = requests.get(status_url, timeout=30)
            r.raise_for_status()
            st = r.json().get("status","").upper()
            if st in ("COMPLETED","DONE","SUCCESS"):
                final = "COMPLETED"; break
            if st in ("FAILED","ERROR"):
                final = st; break
        except Exception as e:
            print(f"[fuma:poll] status check error (continuing): {e}", file=sys.stderr)
        time.sleep(interval); waited += interval

    if final != "COMPLETED":
        print(f"ERROR: FUMA job did not complete (final={final}, waited={waited}s)", file=sys.stderr)
        sys.exit(3)

    r = requests.get(dl_url, timeout=600)
    r.raise_for_status()
    open("${params.outfile}.zip","wb").write(r.content)
    json.dump({"phase":"C","mode":"poll","job_id":job_id,"waited_s":waited}, open("poll.json","w"), indent=2)
    PY
    """

    stub:
    """
    : > ${params.outfile}.zip
    echo '{"phase":"C","stub":true}' > poll.json
    """
}

// [Phase D] Report — extract zip + parse risk loci / genes / pathways.
process FUMA_REPORT {
    tag "fuma:phaseD"
    label 'process_low'
    container CONTAINER_FUMA
    publishDir "${params.outdir}/phaseD_report", mode: 'copy'

    input:  tuple val(meta), path(results_zip), path(poll_json)
    output: tuple val(meta), path("fuma_report.json"), path("fuma_report.md"), emit: out

    script:
    """
    set -euo pipefail
    python3 - <<PY
    import json, os, zipfile
    import pandas as pd

    extract = "fuma_extracted"
    os.makedirs(extract, exist_ok=True)
    n_loci = n_genes = n_pathways = 0
    top_loci = top_genes = top_pathways = []
    if os.path.getsize("${results_zip}") > 0:
        try:
            with zipfile.ZipFile("${results_zip}") as zf:
                zf.extractall(extract)
        except Exception as e:
            print(f"WARN: zip extract failed: {e}")

        def _load(name):
            for root, _, files in os.walk(extract):
                if name in files:
                    return pd.read_csv(os.path.join(root, name), sep="\\t")
            return None

        loci = _load("GenomicRiskLoci.txt")
        if loci is not None:
            n_loci = int(len(loci))
            top_loci = loci.head(20).to_dict(orient="records")

        genes = _load("magma.genes.out")
        if genes is not None:
            pcol = "P" if "P" in genes.columns else genes.columns[-1]
            genes[pcol] = pd.to_numeric(genes[pcol], errors='coerce')
            genes = genes.sort_values(pcol, ascending=True)
            n_genes = int(len(genes))
            top_genes = genes.head(50).to_dict(orient="records")

        gsa = _load("magma.gsa.out")
        if gsa is not None:
            pcol = "P" if "P" in gsa.columns else gsa.columns[-1]
            gsa[pcol] = pd.to_numeric(gsa[pcol], errors='coerce')
            gsa = gsa.sort_values(pcol, ascending=True)
            n_pathways = int(len(gsa))
            top_pathways = gsa.head(30).to_dict(orient="records")

    summary = {
        "phase":"D",
        "tool":"FUMA",
        "citation":"Watanabe 2017 Nat Commun 10.1038/s41467-017-01261-5",
        "license":"UNKNOWN (web-hosted; see fuma.ctglab.nl TOS)",
        "n_genomic_risk_loci":  n_loci,
        "n_magma_genes":        n_genes,
        "n_magma_gene_sets":    n_pathways,
        "top_loci":      top_loci,
        "top_genes":     top_genes,
        "top_gene_sets": top_pathways,
    }
    json.dump(summary, open("fuma_report.json","w"), indent=2, default=str)

    fh = open("fuma_report.md","w")
    fh.write("# FUMA Functional Annotation Report\\n\\n")
    fh.write("Tool: FUMA (Watanabe 2017 Nat Commun).\\n\\n")
    fh.write("- Genomic risk loci: **%d**\\n" % n_loci)
    fh.write("- MAGMA gene-based hits: **%d**\\n" % n_genes)
    fh.write("- MAGMA gene-set hits: **%d**\\n\\n" % n_pathways)
    if top_loci:
        fh.write("## Top genomic risk loci\\n\\n")
        cols = list(top_loci[0].keys())
        fh.write("| " + " | ".join(cols) + " |\\n")
        fh.write("| " + " | ".join(["---"]*len(cols)) + " |\\n")
        for r in top_loci:
            fh.write("| " + " | ".join(str(r[c]) for c in cols) + " |\\n")
    else:
        fh.write("_No loci parsed._\\n")
    fh.close()
    PY
    """

    stub:
    """
    echo '{"phase":"D","stub":true}' > fuma_report.json
    echo "# FUMA Functional Annotation Report (stub)" > fuma_report.md
    """
}

workflow {
    meta_ch = Channel.of([id: 'fuma_functional_annotation'])
    a = FUMA_INPUTS(meta_ch)
    b = FUMA_SUBMIT(a.out)
    c_in = b.out.join(a.out)
    c = FUMA_POLL(c_in)
    FUMA_REPORT(c.out)
}
