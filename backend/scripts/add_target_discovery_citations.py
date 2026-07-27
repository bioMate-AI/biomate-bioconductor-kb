#!/usr/bin/env python3
"""Register the target-discovery workflows and attach peer-reviewed citations.

Adds a `citations` TEXT (JSON) column to `workflows` if absent, then registers /
updates:
  - target_scorecard_ranker              (drug_discovery)
  - query_opentarget                     (database / data_source)
  - autoantibody_isotype_stratification  (immunology)

Each row's `citations` is a JSON list of {ref, doi, supports} so the platform can
surface the scientific provenance of every scoring choice (the reason to use the
Open Targets methodology over hand-tuned heuristics: it is fully citable).

Idempotent: safe to re-run (ADD COLUMN guarded; check-before-insert; citations
always refreshed).
"""
from __future__ import annotations
import json, os, sqlite3, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB_PATH = os.path.join(ROOT, "backend", "database", "galaxy_ai_tools.db")

# --- peer-reviewed reference library ---------------------------------------
OT_PLATFORM = [
    {"ref": "Ochoa et al. 2021, Open Targets Platform: supporting systematic "
            "drug–target identification and prioritisation, Nucleic Acids Research "
            "49(D1):D1302", "doi": "10.1093/nar/gkaa1027",
     "supports": "association-score harmonic-sum aggregation"},
    {"ref": "Ochoa et al. 2023, The next-generation Open Targets Platform, "
            "Nucleic Acids Research 51(D1):D1353", "doi": "10.1093/nar/gkac1046",
     "supports": "platform data model + scoring"},
    {"ref": "Buniello et al. 2025, Open Targets Platform: facilitating therapeutic "
            "hypotheses building in drug discovery, Nucleic Acids Research "
            "53(D1):D1467", "doi": "10.1093/nar/gkae1080",
     "supports": "Precedence/Tractability/Doability/Safety prioritisation framework"},
]
GENETIC_SUPPORT = [
    {"ref": "Nelson et al. 2015, The support of human genetic evidence for approved "
            "drug indications, Nature Genetics 47:856", "doi": "10.1038/ng.3314",
     "supports": "genetic support raises approval odds (2.0%→8.2%)"},
    {"ref": "Minikel et al. 2024, Refining the impact of genetic evidence on clinical "
            "success, Nature 629:624", "doi": "10.1038/s41586-024-07316-0",
     "supports": "2.6× higher clinical success with genetic support"},
]
TRACTABILITY = [
    {"ref": "Oprea et al. 2018, Unexplored therapeutic opportunities in the human "
            "genome, Nature Reviews Drug Discovery 17:317", "doi": "10.1038/nrd.2018.14",
     "supports": "Target Development Level / tractability"},
]
CONSTRAINT = [
    {"ref": "Karczewski et al. 2020, The mutational constraint spectrum quantified "
            "from variation in 141,456 humans (gnomAD), Nature 581:434",
     "doi": "10.1038/s41586-020-2308-7",
     "supports": "LOEUF genetic-constraint safety metric"},
]
FCRN_ISOTYPE = [
    {"ref": "Howard et al. 2021, Safety, efficacy, and tolerability of efgartigimod "
            "in generalised myasthenia gravis (ADAPT), Lancet Neurology 20:526",
     "doi": "10.1016/S1474-4422(21)00159-9",
     "supports": "FcRn inhibition is IgG-selective (no effect on IgA/IgM)"},
    {"ref": "Vincent et al., AChR autoantibody isotype/subclass heterogeneity in "
            "myasthenia gravis, Neurology: Neuroimmunology & Neuroinflammation",
     "doi": "", "supports": "isotype/subclass heterogeneity of AChR autoantibodies"},
    {"ref": "RemeGen/Vor Bio, Telitacicept (dual BAFF/APRIL) Phase 3 in generalised "
            "myasthenia gravis, 2026", "doi": "",
     "supports": "BAFF/APRIL depletion lowers all isotypes incl. IgA/IgM"},
]

WORKFLOWS = [
    {
        "name": "target_scorecard_ranker",
        "filename": "nextflow_nfcore/subworkflows/drug_discovery/"
                    "target_scorecard_ranker/main.nf",
        "domain": "drug_discovery",
        "description": ("Fuse multi-omic, per-target evidence into a ranked, "
                        "provenance-backed target scorecard. Open Targets association "
                        "aggregation + genetic-support weighting + tractability/safety "
                        "prioritisation; coverage-aware; human-in-the-loop; advisory "
                        "network-propagation / harmonic-sum second opinion."),
        "citations": OT_PLATFORM + GENETIC_SUPPORT + TRACTABILITY + CONSTRAINT,
        "step_count": 1,
        "tags": ["target_discovery", "prioritisation", "open_targets", "scorecard"],
    },
    {
        "name": "query_opentarget",
        "filename": "nextflow/subworkflows/database/query_opentarget.nf",
        "domain": "database",
        "description": ("Query the Open Targets Platform GraphQL API for a disease's "
                        "associated targets; emit a per-target evidence table "
                        "(genetic / biological / tractability / safety) in the "
                        "target-scorecard schema."),
        "citations": OT_PLATFORM,
        "step_count": 1,
        "tags": ["open_targets", "data_source", "evidence", "target_discovery"],
    },
    {
        "name": "autoantibody_isotype_stratification",
        "filename": "nextflow_nfcore/subworkflows/immunology/"
                    "autoantibody_isotype_stratification/main.nf",
        "domain": "immunology",
        "description": ("Stratify autoantibody-driven autoimmune patients (MG/SLE/"
                        "Sjögren's) by autoantibody isotype (IgG vs IgA/IgM) to predict "
                        "FcRn-inhibitor non-response and flag BAFF/APRIL (telitacicept) "
                        "candidates."),
        "citations": FCRN_ISOTYPE,
        "step_count": 1,
        "tags": ["immunology", "myasthenia_gravis", "stratification",
                 "autoantibody", "fcrn", "baff_april"],
    },
]


def main():
    if not os.path.exists(DB_PATH):
        print(f"DB not found: {DB_PATH}", file=sys.stderr)
        return 1
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cols = {c[1] for c in cur.execute("PRAGMA table_info(workflows)").fetchall()}
        if "citations" not in cols:
            cur.execute("ALTER TABLE workflows ADD COLUMN citations TEXT")
            print("  + added column workflows.citations")
            cols.add("citations")

        for w in WORKFLOWS:
            cites = json.dumps(w["citations"])
            exists = cur.execute("SELECT 1 FROM workflows WHERE name=?",
                                 (w["name"],)).fetchone()
            if exists:
                cur.execute("UPDATE workflows SET citations=? WHERE name=?",
                            (cites, w["name"]))
                print(f"  ~ updated citations: {w['name']} ({len(w['citations'])} refs)")
                continue
            row = {
                "name": w["name"],
                "filename": w["filename"],
                "domain": w["domain"],
                "description": w["description"],
                "workflow_json": json.dumps({"name": w["name"], "steps": {},
                                             "tags": w["tags"],
                                             "annotation": w["description"]}),
                "format": "nextflow",
                "source": "biomate_target_discovery",
                "category": "target_discovery",
                "step_count": w["step_count"],
                "tags": json.dumps(w["tags"]),
                "citations": cites,
                "executable": 1,
            }
            fields = [f for f in row if f in cols]
            cur.execute(
                f"INSERT INTO workflows ({','.join(fields)}) "
                f"VALUES ({','.join('?'*len(fields))})",
                [row[f] for f in fields],
            )
            print(f"  + registered: {w['name']} (+{len(w['citations'])} citations)")
        conn.commit()
    print("done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
