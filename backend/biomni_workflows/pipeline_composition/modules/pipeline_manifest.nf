/*
 * PIPELINE_MANIFEST
 *
 * Final process in every BioMate pipeline.
 * Writes workflow_outputs.json to params.outdir, documenting what the pipeline
 * produced and where each named output port can be found.
 *
 * Include this module in staged pipelines:
 *
 *   include { PIPELINE_MANIFEST } from '../../modules/pipeline_manifest.nf'
 *
 * Then call at the end of your workflow block:
 *
 *   PIPELINE_MANIFEST(
 *       Channel.value("cryosparc_standard_spa"),  // pipeline_id
 *       Channel.value(params.invocation_id),       // invocation_id
 *       Channel.value(params.outdir),              // outdir
 *       Channel.value(ports_json_string),          // ports as JSON string
 *       Channel.value(params_json_string),         // params as JSON string (or "{}")
 *       Channel.value(metrics_json_string),        // metrics as JSON string (or "{}")
 *   )
 *
 * write_manifest.py lives at manifests/write_manifest.py relative to this module.
 */

nextflow.enable.dsl = 2

process PIPELINE_MANIFEST {
    tag "manifest:${pipeline_id}"
    publishDir "${outdir}", mode: 'copy', overwrite: true

    input:
    val pipeline_id
    val invocation_id
    val outdir
    val ports_json
    val params_json
    val metrics_json
    // trigger_files creates a data-flow dependency so this process only runs
    // after all upstream processes have produced their final outputs.
    // Pass the collected final output files (e.g. SHARPEN.out + LOCAL_RESOLUTION.out).
    path trigger_files

    output:
    path "workflow_outputs.json", emit: manifest

    script:
    // Manifest logic is inlined — no external script file, so this works on
    // AWS Batch containers that don't have access to the head-node filesystem.
    def safe_params  = params_json  ?: "{}"
    def safe_metrics = metrics_json ?: "{}"
    """
    python3 - <<'PYEOF'
import json
from datetime import datetime, timezone

ports   = json.loads('''${ports_json}''')
params  = json.loads('''${safe_params}''')
metrics = json.loads('''${safe_metrics}''')

manifest = {
    "schema_version": "1.0",
    "pipeline_id":    "${pipeline_id}",
    "invocation_id":  "${invocation_id}",
    "completed_at":   datetime.now(timezone.utc).isoformat(),
    "outdir":         "${outdir}",
    "ports":          ports,
}
if params:
    manifest["params"] = params
if metrics:
    manifest["metrics"] = metrics

with open("workflow_outputs.json", "w") as f:
    json.dump(manifest, f, indent=2)

print(f"Manifest written: {manifest['pipeline_id']} / {manifest['invocation_id']}")
PYEOF
    """

    stub:
    """
    python3 - <<'PYEOF'
import json
from datetime import datetime, timezone
ports = json.loads('''${ports_json}''')
manifest = {
    "schema_version": "1.0",
    "pipeline_id":    "${pipeline_id}",
    "invocation_id":  "${invocation_id}",
    "completed_at":   datetime.now(timezone.utc).isoformat(),
    "outdir":         "${outdir}",
    "ports":          ports,
}
json.dump(manifest, open("workflow_outputs.json", "w"), indent=2)
PYEOF
    """
}
