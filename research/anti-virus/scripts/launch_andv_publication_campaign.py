#!/usr/bin/env python3
"""
Prepare real ANDV campaign assets and launch publication-grade Batch runs.

Tracks launched (when --launch-all or individual --launch-* flags):
  - Plan A: full-length Q9E006 GP (1138 aa) epitopeprediction (mhcnuggets, expanded HLA panel)
  - Plan B: ANDV GP reverse-translated CDS → codon opt → RNA2D → LNP
  - Inhibitor: pharmacophore → ADMET → Vina on ZINC subset (reuses pocket from prior run)

Also writes local asset bundle under research/anti-virus/runs/publication_<stamp>/.

Usage:
  python3 research/anti-virus/scripts/launch_andv_publication_campaign.py --prepare-only
  python3 research/anti-virus/scripts/launch_andv_publication_campaign.py --launch-all --no-wait
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
S3_PREFIX = "s3://biomate-nextflow-work/inputs/andv_campaign/publication_20260528"
ANDV_GP_ACCESSION = "Q9E006"

# Expanded HLA panel (common supertypes for vaccine epitope screening).
HLA_PANEL = "A*02:01;A*01:01;A*03:01;A*24:02;B*07:02;B*08:01;B*27:05;B*35:01"

# Human codon usage (fraction per codon) — simplified most-frequent choice per aa.
HUMAN_CODON: dict[str, str] = {
    "A": "GCT",
    "C": "TGT",
    "D": "GAT",
    "E": "GAG",
    "F": "TTC",
    "G": "GGT",
    "H": "CAT",
    "I": "ATC",
    "K": "AAG",
    "L": "CTG",
    "M": "ATG",
    "N": "AAT",
    "P": "CCT",
    "Q": "CAG",
    "R": "CGC",
    "S": "AGC",
    "T": "ACC",
    "V": "GTG",
    "W": "TGG",
    "Y": "TAC",
    "*": "TAA",
}

# Known antiviral reference actives for pharmacophore (real SMILES, not demo aspirin-only).
REFERENCE_ACTIVES = """ribavirin\tNC(=O)c1nc(C=C(C)CO)c(C=O)[nH]1
favipiravir\tC1CC(=O)NC(=O)C1N
umifenovir\tCC(C)(C)c1ccc(C(O)c2ccc(Cl)cc2)cc1
oseltamivir\tCCOC(=O)C1=C[C@@H](OC(CC)CC)[C@H](NC(C)=O)[C@@H](O)[C@H]1O
"""


def log(msg: str) -> None:
    print(msg, flush=True)


def load_api_key() -> str:
    if os.environ.get("GALAXY_API_KEY"):
        return os.environ["GALAXY_API_KEY"]
    gal = ROOT / "backend/config/galaxy.yml"
    text = gal.read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", text)
    if not m:
        raise SystemExit("Set GALAXY_API_KEY or bootstrap_admin_api_key in backend/config/galaxy.yml")
    return m.group(1).strip()


def fetch_uniprot_fasta(accession: str) -> tuple[str, str]:
    url = f"https://rest.uniprot.org/uniprotkb/{urllib.parse.quote(accession)}.fasta"
    req = urllib.request.Request(url, headers={"User-Agent": "BioMate-andv-publication/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        text = resp.read().decode("utf-8", errors="replace")
    lines = text.strip().splitlines()
    header = lines[0][1:].strip()
    seq = "".join(line.strip() for line in lines[1:]).upper()
    return header, seq


def reverse_translate_protein(protein: str) -> str:
    dna: list[str] = []
    for aa in protein:
        if aa not in HUMAN_CODON:
            raise ValueError(f"Unsupported amino acid {aa!r} in protein sequence")
        dna.append(HUMAN_CODON[aa])
    return "".join(dna)


def s3_cp(local: Path, s3_uri: str) -> None:
    r = subprocess.run(["aws", "s3", "cp", str(local), s3_uri], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"aws s3 cp failed: {r.stderr or r.stdout}")


def post_execute(
    api_url: str,
    api_key: str,
    nextflow_path: str,
    parameters: dict[str, Any],
    user_id: str,
    profile: str,
    workflow_domain: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "nextflow_path": nextflow_path,
        "parameters": parameters,
        "compute_config": {"executor": "awsbatch", "s3_bucket": "biomate-nextflow-work"},
        "user_id": user_id,
        "profile": profile,
    }
    if workflow_domain:
        payload["workflow_domain"] = workflow_domain
    req = urllib.request.Request(
        f"{api_url.rstrip('/')}/api/nextflow/execute",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-API-Key": api_key},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


def prepare_assets(out_dir: Path, stamp: str) -> dict[str, Any]:
    out_dir.mkdir(parents=True, exist_ok=True)
    assets_dir = out_dir / "assets"
    assets_dir.mkdir(exist_ok=True)

    log(f"Fetching UniProt {ANDV_GP_ACCESSION} …")
    header, protein = fetch_uniprot_fasta(ANDV_GP_ACCESSION)
    log(f"  {len(protein)} aa — {header[:80]}…")

    gp_fasta = assets_dir / "andv_gp_full_Q9E006.fasta"
    gp_fasta.write_text(f">{ANDV_GP_ACCESSION}|ANDV_GP_full\n{protein}\n", encoding="utf-8")

    cds = reverse_translate_protein(protein)
    cds_fasta = assets_dir / "andv_gp_cds_reverse_translated.fasta"
    cds_fasta.write_text(f">{ANDV_GP_ACCESSION}|ANDV_GP_CDS_rt\n{cds}\n", encoding="utf-8")
    log(f"  Reverse-translated CDS: {len(cds)} nt")

    samplesheet = assets_dir / "samplesheet_full_gp_s3.csv"
    gp_s3 = f"{S3_PREFIX}/andv_gp_full_Q9E006.fasta"
    with samplesheet.open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["sample", "alleles", "mhc_class", "filename"])
        w.writerow(["PLAN_A_FULL_GP", HLA_PANEL, "I", gp_s3])

    ref_actives = assets_dir / "reference_actives_antiviral.smi"
    ref_actives.write_text(
        "\n".join(line.split("\t", 1)[1] for line in REFERENCE_ACTIVES.strip().splitlines()) + "\n",
        encoding="utf-8",
    )
    ref_actives_named = assets_dir / "reference_actives_antiviral_named.tsv"
    ref_actives_named.write_text(REFERENCE_ACTIVES.strip() + "\n", encoding="utf-8")

    zinc_src = ROOT / "research/anti-virus/libraries/zinc20_2d_aaac_20260510T040610Z.smi"
    zinc_subset = assets_dir / "zinc600_library.smi"
    if zinc_src.is_file():
        zinc_subset.write_text(zinc_src.read_text(encoding="utf-8"), encoding="utf-8")
        log(f"  ZINC library: {len(zinc_subset.read_text().splitlines())} compounds")
        # Attach substance IDs + manifest (see build_zinc600_library_manifest.py)
        build_manifest = ROOT / "research/anti-virus/scripts/build_zinc600_library_manifest.py"
        if build_manifest.is_file():
            subprocess.run(
                [
                    sys.executable,
                    str(build_manifest),
                    "--publication-run",
                    str(out_dir),
                ],
                check=False,
            )
    else:
        log(f"WARNING: missing {zinc_src}")

    manifest = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "stamp": stamp,
        "accession": ANDV_GP_ACCESSION,
        "protein_length_aa": len(protein),
        "cds_length_nt": len(cds),
        "hla_panel": HLA_PANEL.split(";"),
        "s3_prefix": S3_PREFIX,
        "local_assets": {k: str(v) for k, v in {
            "gp_fasta": gp_fasta,
            "cds_fasta": cds_fasta,
            "samplesheet": samplesheet,
            "reference_actives": ref_actives,
            "zinc_library": zinc_subset,
        }.items()},
        "output_prefixes": {
            "plan_a": f"s3://biomate-nextflow-work/nextflow/outputs/plan_a_full_gp/{stamp}",
            "plan_b_codon": f"s3://biomate-nextflow-work/nextflow/outputs/plan_b_andv_gp/{stamp}/codon",
            "plan_b_rna2d": f"s3://biomate-nextflow-work/nextflow/outputs/plan_b_andv_gp/{stamp}/rna2d",
            "plan_b_lnp": f"s3://biomate-nextflow-work/nextflow/outputs/plan_b_andv_gp/{stamp}/lnp",
            "inhibitor": f"s3://biomate-nextflow-work/nextflow/outputs/inhibitor_publication/{stamp}",
        },
    }
    (out_dir / "campaign_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def upload_assets(manifest: dict[str, Any]) -> None:
    log("Uploading assets to S3 …")
    assets = manifest["local_assets"]
    prefix = manifest["s3_prefix"]
    for name, local in assets.items():
        s3_uri = f"{prefix}/{Path(local).name}"
        log(f"  {name} → {s3_uri}")
        s3_cp(Path(local), s3_uri)
    manifest["s3_uris"] = {
        k: f"{prefix}/{Path(v).name}" for k, v in manifest["local_assets"].items()
    }


def launch_plan_a(api_url: str, api_key: str, manifest: dict[str, Any]) -> dict[str, Any]:
    outdir = manifest["output_prefixes"]["plan_a"]
    samplesheet_s3 = f"{manifest['s3_prefix']}/samplesheet_full_gp_s3.csv"
    log(f"Launching Plan A epitopeprediction → {outdir}")
    return post_execute(
        api_url,
        api_key,
        "nfcore/epitopeprediction/main.nf",
        {
            "input": samplesheet_s3,
            "outdir": outdir,
            "tools": "mhcnuggets",
            "genome_reference": "grch37",
        },
        user_id="plan-a-publication",
        profile="docker",
    )


def launch_plan_b(api_url: str, api_key: str, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    cds_path = manifest["local_assets"]["cds_fasta"]
    cds = Path(cds_path).read_text(encoding="utf-8")
    cds_seq = "".join(line.strip() for line in cds.splitlines() if not line.startswith(">"))
    runs: list[dict[str, Any]] = []

    codon_out = manifest["output_prefixes"]["plan_b_codon"]
    log(f"Launching Plan B codon optimization → {codon_out}")
    runs.append(
        {
            "track": "plan_b_codon",
            "response": post_execute(
                api_url,
                api_key,
                "nextflow_nfcore/subworkflows/synthetic_biology/optimize_codons_for_heterologous_expression/main.nf",
                {
                    "outdir": codon_out,
                    "target_sequence": cds_seq,
                    "host_codon_usage": json.dumps({"TTT": 0.58, "TTC": 0.42, "ATG": 1.0}),
                },
                user_id="plan-b-publication",
                profile="aws",
                workflow_domain="synthetic_biology",
            ),
        }
    )

    rna_out = manifest["output_prefixes"]["plan_b_rna2d"]
    log(f"Launching Plan B RNA2D (first 500 nt window for ViennaRNA limits) → {rna_out}")
    rna_window = cds_seq[:500].replace("T", "U")
    runs.append(
        {
            "track": "plan_b_rna2d",
            "response": post_execute(
                api_url,
                api_key,
                "nextflow_nfcore/subworkflows/microbiology/predict_rna_secondary_structure/main.nf",
                {
                    "outdir": rna_out,
                    "rna_sequence": rna_window,
                    "output_prefix": "andv_gp_5prime",
                },
                user_id="plan-b-publication",
                profile="aws",
                workflow_domain="microbiology",
            ),
        }
    )

    lnp_out = manifest["output_prefixes"]["plan_b_lnp"]
    log(f"Launching Plan B LNP formulation → {lnp_out}")
    runs.append(
        {
            "track": "plan_b_lnp",
            "response": post_execute(
                api_url,
                api_key,
                "nextflow_nfcore/subworkflows/drug_discovery/lnp_formulation_optimization/main.nf",
                {
                    "outdir": lnp_out,
                    "cargo_type": "mRNA",
                    "target_tissue": "liver",
                    "run_ratio_sweep": "false",
                },
                user_id="plan-b-publication",
                profile="aws",
                workflow_domain="drug_discovery",
            ),
        }
    )
    return runs


def launch_inhibitor(api_url: str, api_key: str, manifest: dict[str, Any], out_dir: Path) -> dict[str, Any]:
    """Delegate to run_andv_inhibitor_pipeline_nextflow.py for steps 2–4."""
    script = ROOT / "research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py"
    ref_s3 = f"{manifest['s3_prefix']}/reference_actives_antiviral.smi"
    lib_s3 = f"{manifest['s3_prefix']}/zinc600_library.smi"
    pdb_s3 = "s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb"
    prior_manifest = ROOT / "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/pipeline_manifest.json"

    cmd = [
        sys.executable,
        str(script),
        "--append-to-run",
        str(prior_manifest.parent),
        "--through-step",
        "4",
        "--pdb-input",
        pdb_s3,
        "--reference-actives-s3",
        ref_s3,
        "--compound-library-s3",
        lib_s3,
        "--use-top-pocket-box",
        "--skip-downloads",
    ]
    log(f"Launching inhibitor pipeline: {' '.join(cmd)}")
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(ROOT))
    log(r.stdout)
    if r.stderr:
        log(r.stderr)
    result = {"returncode": r.returncode, "stdout_tail": r.stdout[-2000:] if r.stdout else ""}
    (out_dir / "inhibitor_launch.log").write_text(r.stdout + "\n" + r.stderr, encoding="utf-8")
    return result


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--api-url", default=os.environ.get("BIOMATE_API_URL", "http://127.0.0.1:8081"))
    ap.add_argument("--prepare-only", action="store_true")
    ap.add_argument("--upload-only", action="store_true")
    ap.add_argument("--launch-all", action="store_true")
    ap.add_argument("--launch-plan-a", action="store_true")
    ap.add_argument("--launch-plan-b", action="store_true")
    ap.add_argument("--launch-inhibitor", action="store_true")
    ap.add_argument("--no-upload", action="store_true", help="Skip S3 upload (assets must already be on S3)")
    args = ap.parse_args()

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = ROOT / "research/anti-virus/runs" / f"publication_{stamp}"
    manifest = prepare_assets(out_dir, stamp)

    if not args.no_upload:
        upload_assets(manifest)
        (out_dir / "campaign_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    if args.prepare_only or args.upload_only:
        log(f"Assets ready: {out_dir}")
        return

    if not (args.launch_all or args.launch_plan_a or args.launch_plan_b or args.launch_inhibitor):
        log(f"Prepared only (pass --launch-all to submit Batch jobs). Assets: {out_dir}")
        return

    api_key = load_api_key()
    launches: dict[str, Any] = {"launched_at": datetime.now(timezone.utc).isoformat()}

    if args.launch_all or args.launch_plan_a:
        launches["plan_a"] = launch_plan_a(args.api_url, api_key, manifest)

    if args.launch_all or args.launch_plan_b:
        launches["plan_b"] = launch_plan_b(args.api_url, api_key, manifest)

    if args.launch_all or args.launch_inhibitor:
        launches["inhibitor"] = launch_inhibitor(args.api_url, api_key, manifest, out_dir)

    (out_dir / "launches.json").write_text(json.dumps(launches, indent=2), encoding="utf-8")
    log(f"Launches recorded: {out_dir / 'launches.json'}")


if __name__ == "__main__":
    main()
