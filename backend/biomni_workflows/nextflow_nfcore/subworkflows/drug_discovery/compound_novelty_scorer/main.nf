#!/usr/bin/env nextflow
/*
 * drug_discovery/compound_novelty_scorer
 *
 * Patent / FTO-oriented novelty scoring for GENERATED molecules. For each query
 * SMILES it runs an FPSim2 Tanimoto/Morgan search against the SAME prebuilt
 * ChEMBL fingerprint index used by fpsim2_chemical_similarity (params.fpsim2_db,
 * a MOUNTED .h5 — never Nextflow-staged), then emits a novelty verdict:
 *   - max_tanimoto      : nearest-neighbour Tanimoto to the known-actives library
 *   - nearest_known_id  : mol_id of that nearest known compound
 *   - novel             : max_tanimoto < params.novelty_tanimoto_cutoff (default 0.85)
 * The cutoff (0.85) is the usual "materially distinct scaffold" threshold; a
 * generated molecule at/above it is essentially a re-discovery of a known active
 * and should NOT be treated as novel.
 *
 * OFF by default: params.check_patents. When true, each query additionally gets a
 * COARSE patent-presence signal from SureChEMBL / PubChem via the same
 * urllib.request pattern the repo already uses (target_evidence_positioning,
 * alphafold_db_search). The core novelty path needs NO network beyond the
 * mounted FPSim2 DB, so patent lookup stays opt-in.
 *
 * The fingerprint DB (.h5) is a MOUNTED path (params.fpsim2_db), identical to
 * fpsim2_chemical_similarity. Build/host it once with that subworkflow's
 * tools/prepare_fpsim2_db.sh (-> S3). DB registration is a separate dev-side step.
 *
 * Honesty contract: if FPSim2 or the .h5 index is unavailable, the workflow
 * FAILS LOUDLY — it emits an explicit {"status": "index_unavailable"} record and
 * exits non-zero. It never fabricates a max_tanimoto or a novelty verdict.
 *
 * Fan-out: one parallel Batch job per query molecule (searches are independent).
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir                  = './results'
params.query_smiles            = null      // comma-separated query SMILES (required)
params.fpsim2_db               = null      // path to a prebuilt FPSim2 .h5 DB (mounted; required)
params.novelty_tanimoto_cutoff = 0.85      // novel = max_tanimoto < cutoff
params.check_patents           = false     // OFF: opt-in coarse patent-presence lookup (network)
// A recent FPSim2 biocontainer; on Batch, mirror to ECR as needed.
params.fpsim2_container        = 'quay.io/biocontainers/fpsim2:0.5.0--py310h4b81fae_0'

process NOVELTY_SCORE {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container params.fpsim2_container

    input:
    tuple val(meta), val(query_smiles)

    output:
    tuple val(meta), path("${meta.id}_novelty.json"), emit: novelty
    path "versions.yml",                              emit: versions

    script:
    """
    export PARAM_QUERY_SMILES='${query_smiles}'
    export PARAM_FPSIM2_DB='${params.fpsim2_db}'
    export PARAM_CUTOFF='${params.novelty_tanimoto_cutoff}'
    export PARAM_CHECK_PATENTS='${params.check_patents}'
    export QUERY_ID='${meta.id}'
    python3 << 'PYEOF'
    import json, os, sys, urllib.request, urllib.parse, urllib.error

    q       = os.environ.get("PARAM_QUERY_SMILES", "")
    db      = os.environ.get("PARAM_FPSIM2_DB", "")
    cutoff  = float(os.environ.get("PARAM_CUTOFF", "0.85"))
    checkp  = os.environ.get("PARAM_CHECK_PATENTS", "false").lower() in ("1", "true", "yes")
    qid     = os.environ.get("QUERY_ID", "query")

    outpath = qid + "_novelty.json"

    def die_unavailable(reason):
        # Honesty: never fake a verdict. Emit an explicit status + exit non-zero.
        rec = {
            "query": q,
            "query_id": qid,
            "status": "index_unavailable",
            "reason": reason,
            "method": "fpsim2_tanimoto_morgan",
        }
        with open(outpath, "w") as f:
            json.dump(rec, f, indent=2)
        print("compound_novelty_scorer: index_unavailable for %s (%s)" % (qid, reason))
        sys.exit(1)

    # FPSim2 must be importable, and the .h5 must exist and load.
    try:
        from FPSim2 import FPSim2Engine
    except Exception as e:
        die_unavailable("FPSim2 not importable: " + str(e))

    if not db or not os.path.exists(db):
        die_unavailable("fpsim2_db path missing: " + str(db))

    try:
        eng = FPSim2Engine(db)
    except Exception as e:
        die_unavailable("FPSim2Engine failed to load DB: " + str(e))

    # Nearest-neighbour search. Threshold 0.0 so we always retrieve the true NN,
    # even for a clearly-novel scaffold whose best match is far below the cutoff.
    try:
        res = eng.similarity(q, 0.0, n_workers=1)
    except Exception as e:
        die_unavailable("similarity search failed for query '" + q + "': " + str(e))

    if res is not None and len(res) > 0:
        top = res[0]
        max_tanimoto     = round(float(top[1]), 4)
        nearest_known_id = int(top[0])
    else:
        # Valid, honest result: nothing in the library is similar at all.
        max_tanimoto     = 0.0
        nearest_known_id = None

    novel = max_tanimoto < cutoff

    rec = {
        "query": q,
        "query_id": qid,
        "status": "ok",
        "max_tanimoto": max_tanimoto,
        "nearest_known_id": nearest_known_id,
        "novelty_tanimoto_cutoff": cutoff,
        "novel": bool(novel),
        "method": "fpsim2_tanimoto_morgan",
    }

    # OFF by default: coarse patent-presence signal (SureChEMBL via PubChem PUG-REST).
    if checkp:
        patent = {"checked": True, "source": "surechembl_via_pubchem", "present": None, "n_patents": None}
        try:
            base = "https://pubchem.ncbi.nlm.nih.gov/rest/pug"
            cid_url = base + "/compound/smiles/" + urllib.parse.quote(q) + "/cids/JSON"
            with urllib.request.urlopen(cid_url, timeout=30) as r:
                cids = (json.loads(r.read().decode()).get("IdentifierList", {}) or {}).get("CID", [])
            if cids:
                cid = cids[0]
                patent["pubchem_cid"] = cid
                xr_url = base + "/compound/cid/" + str(cid) + "/xrefs/PatentID/JSON"
                try:
                    with urllib.request.urlopen(xr_url, timeout=30) as r:
                        info = (json.loads(r.read().decode()).get("InformationList", {}) or {}).get("Information", [])
                    pats = info[0].get("PatentID", []) if info else []
                    patent["present"] = len(pats) > 0
                    patent["n_patents"] = len(pats)
                except urllib.error.HTTPError as he:
                    # 404 = no patent xref for this CID: a real "absent" signal.
                    if he.code == 404:
                        patent["present"] = False
                        patent["n_patents"] = 0
                    else:
                        patent["error"] = "patent xref HTTP %d" % he.code
            else:
                patent["present"] = False
                patent["n_patents"] = 0
        except Exception as e:
            # Patent lookup is a best-effort signal; a network failure must not
            # corrupt the novelty verdict. Record the error honestly.
            patent["error"] = str(e)
        rec["patent"] = patent
    else:
        rec["patent"] = {"checked": False}

    with open(outpath, "w") as f:
        json.dump(rec, f, indent=2)
    print("compound_novelty_scorer: %s max_tanimoto=%s novel=%s" % (qid, max_tanimoto, novel))
    PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fpsim2: \$(python3 -c "import FPSim2; print(getattr(FPSim2,'__version__','unknown'))" 2>/dev/null)
    END_VERSIONS
    """
}

workflow COMPOUND_NOVELTY_SCORER_WORKFLOW {
    take:
    ch_queries   // channel: [ val(meta), val(smiles) ]

    main:
    NOVELTY_SCORE(ch_queries)   // one parallel novelty score per query molecule

    emit:
    novelty  = NOVELTY_SCORE.out.novelty
    versions = NOVELTY_SCORE.out.versions
}

// Entry workflow for standalone execution
workflow {
    if (!params.query_smiles) {
        error "Please provide --query_smiles (comma-separated SMILES)"
    }
    if (!params.fpsim2_db) {
        error "Please provide --fpsim2_db (path to a prebuilt FPSim2 .h5 fingerprint DB)"
    }

    // Fan-out: one parallel novelty score per query SMILES.
    def q_list = (params.query_smiles instanceof List) ? params.query_smiles
        : params.query_smiles.toString().split(',').collect { it.trim() }.findAll { it }
    def tuples = []
    q_list.eachWithIndex { smi, i -> tuples << [ [id: "q_${i}"], smi ] }
    ch_queries = Channel.fromList(tuples)

    COMPOUND_NOVELTY_SCORER_WORKFLOW(ch_queries)

    COMPOUND_NOVELTY_SCORER_WORKFLOW.out.novelty.view { "Novelty: $it" }
}
