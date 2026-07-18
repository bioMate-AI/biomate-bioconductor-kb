#!/usr/bin/env nextflow
/*
 * drug_discovery/fpsim2_chemical_similarity
 *
 * Fast chemical-similarity search with FPSim2 (ChEMBL's own engine that powers
 * the ChEMBL / SureChEMBL similarity UIs). Searches one or more query molecules
 * (SMILES) against a PREBUILT fingerprint database — e.g. ChEMBL (~2.4M) or
 * PubChem-scale — by Tanimoto over Morgan fingerprints, with BitBound pruning
 * for speed at threshold >= 0.7.
 *
 * The fingerprint DB (.h5) is a MOUNTED path (params.fpsim2_db), never
 * Nextflow-staged — a ChEMBL/PubChem index is large and must not be copied per
 * task. Build/host it once with tools/prepare_fpsim2_db.sh (-> S3).
 *
 * Fan-out: one parallel Batch job per query molecule (searches are independent).
 * QC (optional, downstream): exact re-score / substructure confirm on top hits.
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir               = './results'
params.query_smiles         = null      // comma-separated query SMILES (required)
params.fpsim2_db            = null      // path to a prebuilt FPSim2 .h5 DB (mounted; required)
params.similarity_threshold = 0.7       // min Tanimoto (>=0.7 enables BitBound pruning)
params.max_hits             = 100       // top hits to keep per query
// A recent FPSim2 biocontainer; on Batch, mirror to ECR as needed.
params.fpsim2_container     = 'quay.io/biocontainers/fpsim2:0.5.0--py310h4b81fae_0'

process FPSIM2_SIMILARITY_SEARCH {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container params.fpsim2_container

    input:
    tuple val(meta), val(query_smiles)

    output:
    tuple val(meta), path("${meta.id}_similarity_hits.json"), emit: hits
    path "versions.yml",                                      emit: versions

    script:
    """
    export PARAM_QUERY_SMILES='${query_smiles}'
    export PARAM_FPSIM2_DB='${params.fpsim2_db}'
    export PARAM_THRESHOLD='${params.similarity_threshold}'
    export PARAM_MAX_HITS='${params.max_hits}'
    export QUERY_ID='${meta.id}'
    python3 << 'PYEOF'
import json, os
from FPSim2 import FPSim2Engine

q   = os.environ.get("PARAM_QUERY_SMILES", "")
db  = os.environ.get("PARAM_FPSIM2_DB", "")
thr = float(os.environ.get("PARAM_THRESHOLD", "0.7"))
mx  = int(os.environ.get("PARAM_MAX_HITS", "100"))
qid = os.environ.get("QUERY_ID", "query")

hits = []
try:
    eng = FPSim2Engine(db)
    # returns a structured array of (mol_id, coeff) sorted by descending Tanimoto
    res = eng.similarity(q, thr, n_workers=1)
    for row in res[:mx]:
        mol_id = int(row[0]); coeff = float(row[1])
        hits.append({"mol_id": mol_id, "tanimoto": round(coeff, 4)})
except Exception as e:
    print("FPSim2 error: " + str(e))

out = {
    "query": q,
    "n_hits": len(hits),
    "threshold": thr,
    "best_hit": hits[0] if hits else None,
    "hits": hits,
    "method": "fpsim2_tanimoto_morgan",
}
with open(qid + "_similarity_hits.json", "w") as f:
    json.dump(out, f, indent=2)
print("fpsim2_chemical_similarity: %d hits for %s" % (len(hits), qid))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fpsim2: \$(python3 -c "import FPSim2; print(getattr(FPSim2,'__version__','unknown'))" 2>/dev/null)
    END_VERSIONS
    """
}

workflow FPSIM2_CHEMICAL_SIMILARITY_WORKFLOW {
    take:
    ch_queries   // channel: [ val(meta), val(smiles) ]

    main:
    FPSIM2_SIMILARITY_SEARCH(ch_queries)   // one parallel search per query molecule

    emit:
    hits     = FPSIM2_SIMILARITY_SEARCH.out.hits
    versions = FPSIM2_SIMILARITY_SEARCH.out.versions
}

// Entry workflow for standalone execution
workflow {
    if (!params.query_smiles) {
        error "Please provide --query_smiles (comma-separated SMILES)"
    }
    if (!params.fpsim2_db) {
        error "Please provide --fpsim2_db (path to a prebuilt FPSim2 .h5 fingerprint DB)"
    }

    // Fan-out: one parallel search per query SMILES.
    def q_list = (params.query_smiles instanceof List) ? params.query_smiles
        : params.query_smiles.toString().split(',').collect { it.trim() }.findAll { it }
    def tuples = []
    q_list.eachWithIndex { smi, i -> tuples << [ [id: "q_${i}"], smi ] }
    ch_queries = Channel.fromList(tuples)

    FPSIM2_CHEMICAL_SIMILARITY_WORKFLOW(ch_queries)

    FPSIM2_CHEMICAL_SIMILARITY_WORKFLOW.out.hits.view { "Hits: $it" }
}
