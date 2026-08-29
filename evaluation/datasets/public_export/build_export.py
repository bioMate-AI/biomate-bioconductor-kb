#!/usr/bin/env python3
"""Build the PUBLIC, neutralized export of BioMate's self-designed benchmarks for Hugging Face.

Goal: let ANY system be scored on the SAME tasks against objective ground truth — a fair
cross-system comparison — without exposing BioMate's internals (self-protection) and without
any BioMate-favouring framing.

Design rules enforced here:
  * Leave the internal source datasets untouched; write only to public_export/.
  * Keep the neutral ground truth; DROP internal fields (biomate_profile, expected_fixer_class)
    and RENAME BioMate-specific labels (expected_biomate_action -> expected_correct_action).
  * Routing is neutralized to DOMAIN level: exact workflow names are BioMate-catalog-specific and
    therefore unfair (and revealing) for cross-system comparison; the fair task is "which domain".
  * license_gating is HELD from v1 (tests a BioMate-specific behaviour, no neutral ground truth).
  * Every item's ground-truth field is objective (string/number/list), scorable without an LLM judge.

Run: python3 build_export.py   (emits public_export/<name>/{data.jsonl, README.md} + MANIFEST.json)
"""
import yaml, json, os, glob

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)  # evaluation/datasets

def load_list(path, list_key=None):
    y = yaml.safe_load(open(path))
    if isinstance(y, list):
        return y, y
    if list_key and list_key in y:
        return y[list_key], y
    for k, v in y.items():
        if isinstance(v, list) and v and isinstance(v[0], dict):
            return v, y
    raise ValueError(f"no item list in {path}")

# name -> spec
RULES = {
    "cross_domain_routing": dict(
        src="cross_domain_routing/queries.yaml",
        keep=["id", "query", "domain", "difficulty", "correct_workflow", "acceptable_alts"],
        drop=["disqualified", "notes"],
        gt="correct_workflow",
        task="Given a natural-language analysis request, name the single correct WORKFLOW that should run it (targets are public nf-core pipeline names where applicable). Credit for acceptable_alts.",
        note="Targets are public workflow names (mostly nf-core), so this is a real, catalog-neutral routing task any system can attempt.",
    ),
    "param_prefill": dict(
        src="param_prefill/cases.yaml",
        keep=["id", "category", "user_query", "expected_params", "must_not_fill", "difficulty"],
        drop=["workflow", "notes"],
        gt="expected_params",
        task="Extract structured parameters from a natural-language request; do not fill parameters that were not specified (must_not_fill).",
    ),
    "protocol_thresholds": dict(
        src="protocol_thresholds/datasets.yaml",
        keep=["id", "accession", "protocol", "universal_threshold_problem", "expected_naive_action", "ground_truth", "notes"],
        rename={"expected_biomate_action": "expected_correct_action"},
        drop=["biomate_profile"],
        gt=["ground_truth", "expected_correct_action"],
        task="Given a sequencing protocol and a generic QC threshold, decide whether the sample is biologically VALID and whether it should PASS or FAIL — vs the naive universal-threshold action.",
    ),
    "autofix_benchmark": dict(
        src="autofix_benchmark/cases.yaml",
        keep=["id", "category", "workflow", "description", "params", "error_log", "expected_fix", "fix_difficulty"],
        drop=["expected_fixer_class"],
        gt="category",
        task="Given a failed pipeline run and its error log, classify the failure into one of 10 objective fix categories (genome_mismatch, resource_failure, container_error, dependency_mismatch, missing_input, param_type_error, param_scope_error, data_format_error, output_assertion_error, cloud_storage_error). A free-text 'expected_fix' reference is provided as a secondary signal.",
    ),
    "workflow_generation": dict(
        src="workflow_generation/cases.yaml",
        keep=["id", "partition", "intent", "key_tools", "expected_category", "difficulty"],
        gt={"any": ["expected_category", "key_tools"]},
        task="Given a research intent, select the correct analysis category (partition A) OR identify the required key tools (partition B). Both ground truths are standard and catalog-neutral.",
    ),
    # HELD from v1: memory_benchmark — its correction/adversarial items score against specific
    # workflow choices (BioMate-catalog-specific) and test agent-memory-of-BioMate-behaviour,
    # not a catalog-neutral science task. Same reason as license_gating.
    "boin_benchmark": dict(
        src="boin_benchmark/cases.yaml",
        keep=["id", "scenario", "inputs", "reference", "difficulty"],
        gt="reference",
        task="Given a BOIN dose-escalation scenario, produce the correct dose decision.",
        attribution="BOIN design: Liu & Yuan, JRSS-C 2015. Scenarios are original.",
    ),
    "pbpk_benchmark": dict(
        src="pbpk_benchmark/cases.yaml",
        keep=["id", "name", "smiles", "dose_mg", "route", "inputs", "reference", "difficulty"],
        gt="reference",
        task="Given a compound (SMILES), dose and route, predict PK; reference = published clinical PK values.",
        attribution="Reference PK values from published clinical pharmacology sources (per-item 'reference').",
    ),
    "drug_discovery_e2e": dict(
        src="drug_discovery_e2e/pdb_systems.yaml", list_key="systems",
        keep=["id", "target", "pdb_id", "chain", "binding_site_residues", "ligands", "ligand_rank_order", "notes"],
        gt=["ligand_rank_order"],
        task="Given a protein structure (PDB) and ligands with experimental Kd, reproduce the affinity rank order.",
        attribution="Structures: RCSB PDB. Affinities: experimental Kd (PDBbind-derived where noted).",
    ),
    # HELD from v1: license_gating (BioMate-specific behaviour, no neutral ground truth).
}

# truly-internal fields that must never be published. (correct_workflow/acceptable_alts are PUBLIC
# nf-core pipeline names — they are the routing ground truth, not a leak.)
LEAK_FIELDS = {"biomate_profile", "expected_fixer_class", "expected_biomate_action"}

def neutralize(item, spec):
    keep = set(spec["keep"])
    ren = spec.get("rename", {})
    out = {}
    for k, v in item.items():
        if k in ren:
            out[ren[k]] = v
        elif k in keep:
            out[k] = v
    return out

def main():
    manifest = {"suite": "RealBio Benchmark", "repo": "realbio_benchmark", "tagline": "Real-world execution benchmarks for bioinformatics AI agents",
                "benchmarks": [], "license": "CC-BY-4.0", "version": "v1",
                "note": "Public neutralized export for fair cross-system comparison. Internal source not included."}
    for name, spec in RULES.items():
        items, _ = load_list(os.path.join(SRC, spec["src"]), spec.get("list_key"))
        outdir = os.path.join(HERE, name)
        os.makedirs(outdir, exist_ok=True)
        rows = [neutralize(it, spec) for it in items]
        # leak guard
        leaked = sorted({k for r in rows for k in r} & LEAK_FIELDS)
        assert not leaked, f"{name}: leaked internal fields survived: {leaked}"
        with open(os.path.join(outdir, "data.jsonl"), "w") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")
        gt = spec["gt"]
        card = f"""---
license: cc-by-4.0
---
# RealBio Benchmark — {name}

*Part of **RealBio Benchmark**: real-world execution benchmarks for bioinformatics AI agents (see the suite README).*

**Task.** {spec['task']}

**Items.** {len(rows)}  ·  **Ground-truth field(s).** `{gt}`  ·  **Scoring.** objective (see ../score.py) — no LLM judge required.

Any system can run this benchmark and be scored on the same items. {spec.get('note','')}

{('**Attribution.** ' + spec['attribution']) if spec.get('attribution') else ''}
"""
        open(os.path.join(outdir, "README.md"), "w").write(card)
        manifest["benchmarks"].append({"name": name, "items": len(rows), "gt": gt, "task": spec["task"]})
        print(f"  {name:22} {len(rows):>4} items  gt={gt}")
    json.dump(manifest, open(os.path.join(HERE, "MANIFEST.json"), "w"), indent=2)
    print(f"\nTotal: {sum(b['items'] for b in manifest['benchmarks'])} items across {len(manifest['benchmarks'])} benchmarks")
    print("HELD from v1: license_gating (BioMate-specific; no neutral ground truth)")

if __name__ == "__main__":
    main()
