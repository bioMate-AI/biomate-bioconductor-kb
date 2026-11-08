#!/usr/bin/env python3
"""json_to_boltz_yaml.py — build_cofold_input JSON -> Boltz-2 cofold YAML (container artifact).

The missing piece for a real Batch cofold job: converts the spec-derived cofold input
(receptor protein chains + cofactor CCD ligands + cyclic peptides — metal is just `ligands`)
into the Boltz-2 YAML the `boltz predict` call consumes. Format matches the proven
launch_cofold_v2.sh driver EXACTLY (receptor `protein` entities, cofactor `ligand` entities
by CCD, a cyclic `protein` chain P per peptide). Pure stdlib — safe to drop into the Boltz
container (pulled from S3 by physics_batch, no image rebuild).

Usage:
  json_to_boltz_yaml.py cofold_input.json out.yaml            # single YAML (first peptide)
  json_to_boltz_yaml.py cofold_input.json outdir/ [--all]     # one YAML per peptide -> manifest JSON on stdout
"""
import json, os, sys


def to_yaml(receptor_chains, ligands, pep):
    """One Boltz-2 YAML string: receptor chains + cofactor ion ligands + one cyclic peptide chain P."""
    lines = ["version: 1", "sequences:"]
    for cid, cseq in receptor_chains.items():
        lines += ["  - protein:", f"      id: {cid}", f"      sequence: {cseq}"]
    for i, ccd in enumerate(ligands):
        lines += ["  - ligand:", f"      id: M{i + 1}", f"      ccd: {ccd}"]
    lines += ["  - protein:", "      id: P", f"      sequence: {pep}", "      cyclic: true"]
    return "\n".join(lines) + "\n"


def convert(inp, out):
    d = json.load(open(inp))
    rc = d["receptor_chains"]; lig = d.get("ligands", []); peps = d["peptides"]
    if not rc:
        raise SystemExit(f"receptor not prepped (no chains) for {d.get('target')}")

    def norm(it):
        return (it["id"], it["pep"]) if isinstance(it, dict) else (f"P{peps.index(it)+1}", it)

    if out.endswith(".yaml") or out.endswith(".yml"):
        pid, pep = norm(peps[0])
        open(out, "w").write(to_yaml(rc, lig, pep))
        return [{"id": pid, "yaml": out, "pep": pep}]
    os.makedirs(out, exist_ok=True)
    manifest = []
    for it in peps:
        pid, pep = norm(it)
        path = os.path.join(out, f"in_{pid}.yaml")
        open(path, "w").write(to_yaml(rc, lig, pep))
        manifest.append({"id": pid, "yaml": path, "pep": pep})
    return manifest


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    man = convert(args[0], args[1])
    print(json.dumps(man))
