"""
BioMate pipeline manifest writer.

Called by the PIPELINE_MANIFEST Nextflow process at pipeline completion.
Also importable as a Python library for testing and tooling.

CLI usage (from Nextflow inline script or shell):
    python3 write_manifest.py \\
        --pipeline_id      cryosparc_standard_spa \\
        --invocation_id    inv_abc123 \\
        --outdir           /results/spa_run/ \\
        --ports_json       '{"volume_cs": "17_homogeneous_refinement/refined_volume.cs"}'
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_PATH = Path(__file__).parent / "manifest_schema.json"


def write_manifest(
    pipeline_id: str,
    invocation_id: str,
    outdir: str,
    ports: dict,
    params: dict = None,
    metrics: dict = None,
    upstream_invocation_ids: list = None,
    pipeline_version: str = None,
    output_path: str = "workflow_outputs.json",
    validate: bool = True,
) -> dict:
    """Write a pipeline manifest JSON file. Returns the manifest dict.

    Args:
        pipeline_id: Must match a key in pipeline_registry.json.
        invocation_id: BioMate invocation ID (from params.invocation_id).
        outdir: Absolute path to the pipeline output directory.
        ports: Dict mapping output port names to relative paths from outdir.
        params: Key acquisition/processing parameters (subset relevant to downstream).
        metrics: Key scientific metrics (pipeline-specific).
        upstream_invocation_ids: IDs of pipelines whose outputs were used as inputs.
        pipeline_version: Git SHA or semver tag of the pipeline at runtime.
        output_path: Where to write the manifest (default: workflow_outputs.json).
        validate: Validate against manifest_schema.json before writing (default True).

    Returns:
        The manifest dict (as written to file).

    Raises:
        jsonschema.ValidationError: If the manifest fails schema validation.
        ValueError: If ports is empty.
    """
    if not ports:
        raise ValueError("ports must have at least one entry")

    manifest = {
        "schema_version": "1.0",
        "pipeline_id": pipeline_id,
        "invocation_id": invocation_id,
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "outdir": str(outdir),
        "ports": ports,
    }
    if params:
        manifest["params"] = params
    if metrics:
        manifest["metrics"] = metrics
    if upstream_invocation_ids:
        manifest["upstream_invocation_ids"] = upstream_invocation_ids
    if pipeline_version:
        manifest["pipeline_version"] = pipeline_version

    if validate:
        try:
            import jsonschema

            with open(SCHEMA_PATH) as f:
                schema = json.load(f)
            jsonschema.validate(instance=manifest, schema=schema)
        except ImportError:
            pass  # jsonschema not installed; skip schema validation

    with open(output_path, "w") as f:
        json.dump(manifest, f, indent=2)

    return manifest


def _cli_main():
    parser = argparse.ArgumentParser(description="Write BioMate pipeline output manifest")
    parser.add_argument("--pipeline_id", required=True)
    parser.add_argument("--invocation_id", required=True)
    parser.add_argument("--outdir", required=True)
    parser.add_argument(
        "--ports_json",
        required=True,
        help='JSON object: {"port_name": "relative/path.ext", ...}',
    )
    parser.add_argument("--params_json", default="{}")
    parser.add_argument("--metrics_json", default="{}")
    parser.add_argument(
        "--upstream_ids",
        default="",
        help="Comma-separated upstream invocation IDs",
    )
    parser.add_argument("--pipeline_version", default=None)
    parser.add_argument("--output", default="workflow_outputs.json")
    args = parser.parse_args()

    ports = json.loads(args.ports_json)
    params = json.loads(args.params_json) or None
    metrics = json.loads(args.metrics_json) or None
    upstream = [x for x in args.upstream_ids.split(",") if x] or None

    manifest = write_manifest(
        pipeline_id=args.pipeline_id,
        invocation_id=args.invocation_id,
        outdir=args.outdir,
        ports=ports,
        params=params,
        metrics=metrics,
        upstream_invocation_ids=upstream,
        pipeline_version=args.pipeline_version,
        output_path=args.output,
    )
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    _cli_main()
