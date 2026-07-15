#!/usr/bin/env nextflow
/*
 * Local fan-out test for predict_admet_properties (NO Docker required).
 *
 * Reuses the REAL reduce process (PREDICT_ADMET_PROPERTIES) from ../main.nf so
 * the QC-critical global worst-case aggregation is exercised for real, and
 * mocks only the expensive ADMET-AI inference (which needs the biomni-admet
 * container). The mock is deterministic: the SMILES literal "CWORST" gets a
 * dominating hERG_prob so we can assert the global worst surfaces across shards.
 *
 * Run:
 *   nextflow run tests/test_shard.nf -profile local -with-trace trace.txt \
 *     --smiles_list '["C1","C2","C3","C4","CWORST","C6","C7"]' --admet_shard_size 3
 */

nextflow.enable.dsl = 2

include { PREDICT_ADMET_PROPERTIES } from '../main.nf'

params.smiles_list = '["C1","C2","C3","C4","CWORST","C6","C7"]'
params.admet_shard_size = 3
params.outdir = './results'

// Mock of ADMET_INFER_SHARD — same I/O contract, deterministic, no admet_ai.
process ADMET_INFER_SHARD_MOCK {
    tag "$meta.id"

    input:
    tuple val(meta), val(smiles_json)

    output:
    path("shard_admet_${meta.id}.json"), emit: partial

    script:
    """
    export PARAM_SMILES_LIST='${smiles_json}'
    export SHARD_ID='${meta.id}'
    python3 << 'PYEOF'
import json, os
smiles = json.loads(os.environ.get("PARAM_SMILES_LIST", "[]") or "[]")
rows = []
for smi in smiles:
    # Deterministic mock: designated worst compound dominates hERG.
    herg = 0.99 if smi == "CWORST" else round(len(str(smi)) / 1000.0, 4)
    rows.append({"smiles": smi, "hERG_prob": herg, "DILI_prob": 0.10, "clintox_prob": 0.05})
sid = os.environ.get("SHARD_ID", "x")
with open("shard_admet_" + sid + ".json", "w") as f:
    json.dump({"shard_id": sid, "per_compound_admet": rows}, f)
PYEOF
    """
}

workflow {
    def parsed = new groovy.json.JsonSlurper().parseText((params.smiles_list ?: '[]').toString())
    def shard_size = (params.admet_shard_size ?: 25) as int
    def shard_tuples = []
    parsed.collate(shard_size).eachWithIndex { chunk, i ->
        shard_tuples << [ [id: "shard_${i}"], groovy.json.JsonOutput.toJson(chunk) ]
    }
    ch_shards = Channel.fromList(shard_tuples)

    ADMET_INFER_SHARD_MOCK(ch_shards)
    PREDICT_ADMET_PROPERTIES(ADMET_INFER_SHARD_MOCK.out.partial.collect())

    PREDICT_ADMET_PROPERTIES.out.toxicity_report.view { "TOX_REPORT: $it" }
}
