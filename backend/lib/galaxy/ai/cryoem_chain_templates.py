"""
Cryo-EM pipeline chain templates.

These chains use existing cryo-EM workflows indexed in the DB, chained through
the existing workflow_chain executor. They are registered in the workflow_chains
DB table at startup via register_cryoem_chains().

Naming convention:
  cryoem_<analysis> = multi-step cryo-EM pipeline (this file)

Three chains:
  cryoem_standard_refinement          — post-SPA refinement ladder (5 steps)
  cryoem_conformational_heterogeneity — 3D variability + cryoDRGN (2 steps)
  cryoem_model_building               — map sharpening + symmetry expansion +
                                        particle subtraction for model-building prep (3 steps)
                                        Note: Phenix/Coot/MolProbity are not in the DB; this
                                        chain prepares the map using in-DB steps only.
"""

import json
import logging
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

log = logging.getLogger(__name__)

_DB_PATH = Path(__file__).parent.parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"

# ── Chain template definitions ────────────────────────────────────────────────
# Each step's workflow_name must match an existing workflow in the DB.
# Verified against: SELECT name FROM workflows WHERE domain='cryo_em';
# connections: from_step/to_step use 1-based step order.

CRYOEM_CHAIN_TEMPLATES: List[Dict[str, Any]] = [
    {
        "name": "cryoem_standard_refinement",
        "display_name": "Cryo-EM Standard Refinement Pipeline",
        "domain": "cryo_em",
        "description": (
            "Post-SPA refinement ladder: 3D classification to separate conformations, "
            "focused refinement with a soft mask around the region of interest, "
            "per-particle local refinement, global CTF refinement (beam-tilt + trefoil), "
            "and DeepEMhancer post-processing for map sharpening. Follows the "
            "cryoSPARC/RELION best-practices refinement workflow documented in "
            "Punjani et al. 2017 (cryoSPARC) and Zivanov et al. 2018 (RELION 3)."
        ),
        "steps": [
            {
                "order": 1,
                "workflow_name": "3D Variability Pipeline",
                "role": "heterogeneity_classification",
                "params_template": {},
            },
            {
                "order": 2,
                "workflow_name": "Focused Refinement Pipeline",
                "role": "focused_refinement",
                "params_template": {},
            },
            {
                "order": 3,
                "workflow_name": "Local Refinement",
                "role": "local_refinement",
                "params_template": {},
            },
            {
                "order": 4,
                "workflow_name": "Global Ctf Refinement",
                "role": "ctf_polish",
                "params_template": {},
            },
            {
                "order": 5,
                "workflow_name": "DeepEMhancer Post-Processing",
                "role": "map_sharpening",
                "params_template": {},
            },
        ],
        "connections": [
            {"from_step": 1, "from_output": "particles", "to_step": 2, "to_input": "particles"},
            {"from_step": 2, "from_output": "refined_map", "to_step": 3, "to_input": "input_map"},
            {"from_step": 3, "from_output": "polished_particles", "to_step": 4, "to_input": "particles"},
            {"from_step": 4, "from_output": "refined_map", "to_step": 5, "to_input": "input_map"},
        ],
        "required_inputs": ["cs_particles", "reference_map"],
        "expected_outputs": ["sharpened_map_mrc", "local_resolution_map", "ctf_corrected_particles"],
        "example_queries": [
            "what to do after cryosparc spa",
            "refine my cryo-em structure",
            "improve resolution after spa",
            "3d classification refinement pipeline",
            "post-spa refinement",
            "sharpen my cryo-em map",
            "relion refinement workflow",
            "cryosparc refinement pipeline",
        ],
        "tags": ["cryo_em", "cryosparc", "relion", "refinement", "3d_classification", "deepemhancer"],
        "trigger_on_workflows": [
            "cryosparc_standard_spa",
            "CryoSPARC Standard Single-Particle Analysis",
            "Cryosparc Standard Spa",
            "relion",
            "cistem",
            "helical_spa_pipeline",
        ],
        "trigger_on_output_extensions": ["cs", "mrc", "mrcs", "star"],
    },
    {
        "name": "cryoem_conformational_heterogeneity",
        "display_name": "Cryo-EM Conformational Heterogeneity Analysis",
        "domain": "cryo_em",
        "description": (
            "Latent-space analysis of continuous conformational heterogeneity: "
            "3D variability analysis (cryoSPARC) to identify principal motion components, "
            "followed by cryoDRGN neural-network heterogeneous reconstruction for a "
            "continuous latent-space landscape. Implements the workflow from "
            "Zhong et al. 2021 (cryoDRGN, Nature Methods) for characterizing "
            "conformational dynamics beyond discrete classification."
        ),
        "steps": [
            {
                "order": 1,
                "workflow_name": "3D Variability Analysis",
                "role": "variability_components",
                "params_template": {},
            },
            {
                "order": 2,
                "workflow_name": "Cryo-EM Conformational Heterogeneity (cryoDRGN)",
                "role": "latent_space_landscape",
                "params_template": {},
            },
        ],
        "connections": [
            {
                "from_step": 1,
                "from_output": "variability_components",
                "to_step": 2,
                "to_input": "input_particles",
            },
        ],
        "required_inputs": ["cs_particles", "ctf_corrected_stack"],
        "expected_outputs": ["latent_space_plot", "conformational_landscape_mrc", "heterogeneity_report"],
        "example_queries": [
            "analyze conformational states in my cryo-em data",
            "continuous heterogeneity analysis",
            "cryodrgn latent space",
            "multiple conformations cryo-em",
            "3d variability cryodrgn pipeline",
            "protein dynamics cryo-em",
            "conformational landscape analysis",
        ],
        "tags": ["cryo_em", "cryodrgn", "heterogeneity", "3d_variability", "latent_space", "conformational_dynamics"],
        "trigger_on_workflows": [
            "3d_variability_pipeline",
            "3D Variability Pipeline",
            "cryosparc_standard_spa",
            "CryoSPARC Standard Single-Particle Analysis",
        ],
        "trigger_on_output_extensions": ["cs", "star"],
    },
    {
        "name": "cryoem_model_building",
        "display_name": "Cryo-EM Map Post-Processing for Model Building",
        "domain": "cryo_em",
        "description": (
            "Map preparation pipeline for downstream atomic model building: "
            "DeepEMhancer post-processing to sharpen the half-maps and improve "
            "secondary-structure visibility, symmetry expansion to generate "
            "symmetry-equivalent particle views for sub-region analysis, and "
            "particle subtraction to remove adjacent-subunit density before "
            "focused refinement and hand-off to Phenix/Coot for model building. "
            "Use after obtaining a high-resolution (< 4 Å) refined reconstruction. "
            "Note: Phenix AutoBuild and MolProbity validation are external tools "
            "not yet indexed as BioMate workflows — this chain prepares the map. "
            "Required inputs: half-maps (.mrc) from a completed refinement run."
        ),
        "steps": [
            {
                "order": 1,
                "workflow_name": "DeepEMhancer Post-Processing",
                "role": "map_sharpening",
                "params_template": {"sharpening_type": "tightTarget"},
            },
            {
                "order": 2,
                "workflow_name": "Symmetry Expansion",
                "role": "symmetry_expansion",
                "params_template": {},
            },
            {
                "order": 3,
                "workflow_name": "Particle Subtraction",
                "role": "subunit_subtraction",
                "params_template": {},
            },
        ],
        "connections": [
            {"from_step": 1, "from_output": "sharpened_map", "to_step": 2, "to_input": "volume_in"},
            {"from_step": 2, "from_output": "expanded_particles", "to_step": 3, "to_input": "particles"},
        ],
        "required_inputs": ["halfmaps_mrc"],
        "expected_outputs": ["sharpened_map_mrc", "subtracted_particles_cs"],
        "example_queries": [
            "I have a refined map at 3 angstrom build atomic model",
            "prepare cryo-em map for model building",
            "sharpen map for phenix coot",
            "particle subtraction for asymmetric feature",
            "map post-processing before model building",
        ],
        "tags": [
            "cryo_em", "deepemhancer", "map_sharpening", "symmetry_expansion",
            "particle_subtraction", "model_building_prep",
        ],
        "trigger_on_workflows": [
            "deepemhancer_post_processing",
            "DeepEMhancer Post-Processing",
            "local_refinement",
            "Local Refinement",
            "focused_refinement_pipeline",
            "Focused Refinement Pipeline",
        ],
        "trigger_on_output_extensions": ["mrc", "map"],
    },
]


# ── Registration ──────────────────────────────────────────────────────────────

def register_cryoem_chains(db_path: Path = _DB_PATH) -> int:
    """
    Insert or update CRYOEM_CHAIN_TEMPLATES in the workflow_chains table.
    Returns the number of chains upserted.
    """
    now = datetime.now(timezone.utc).isoformat()
    conn = sqlite3.connect(str(db_path))
    upserted = 0
    try:
        for tpl in CRYOEM_CHAIN_TEMPLATES:
            conn.execute(
                """
                INSERT INTO workflow_chains
                  (name, display_name, domain, description, steps, connections,
                   required_inputs, expected_outputs, example_queries, tags,
                   source, usage_count, success_rate, created_at, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?, 'cryoem_reactive', 0, 0.0, ?,?)
                ON CONFLICT(name) DO UPDATE SET
                  display_name    = excluded.display_name,
                  domain          = excluded.domain,
                  description     = excluded.description,
                  steps           = excluded.steps,
                  connections     = excluded.connections,
                  required_inputs = excluded.required_inputs,
                  expected_outputs= excluded.expected_outputs,
                  example_queries = excluded.example_queries,
                  tags            = excluded.tags,
                  updated_at      = excluded.updated_at
                """,
                (
                    tpl["name"],
                    tpl["display_name"],
                    tpl["domain"],
                    tpl["description"],
                    json.dumps(tpl["steps"]),
                    json.dumps(tpl["connections"]),
                    json.dumps(tpl.get("required_inputs", [])),
                    json.dumps(tpl.get("expected_outputs", [])),
                    json.dumps(tpl.get("example_queries", [])),
                    json.dumps(tpl.get("tags", [])),
                    now,
                    now,
                ),
            )
            upserted += 1
        conn.commit()
        log.info("cryoem_chain_templates: upserted %d chains", upserted)
    except Exception as exc:
        log.error("cryoem_chain_templates registration failed: %s", exc)
        conn.rollback()
        raise
    finally:
        conn.close()
    return upserted


def suggest_chains_for_run(
    workflow_name: str,
    output_extensions: List[str],
    db_path: Path = _DB_PATH,
) -> List[Dict[str, Any]]:
    """
    Given the name of a completed workflow and its output file extensions,
    return matching cryo-EM chain templates ranked by relevance.

    Matches on:
      - trigger_on_workflows: workflow_name substring match
      - trigger_on_output_extensions: any output extension match
    """
    candidates = []
    wf_lower = workflow_name.lower()
    ext_set = {e.lstrip(".").lower() for e in output_extensions}

    for tpl in CRYOEM_CHAIN_TEMPLATES:
        score = 0
        triggers_wf = [t.lower() for t in tpl.get("trigger_on_workflows", [])]
        triggers_ext = [e.lower() for e in tpl.get("trigger_on_output_extensions", [])]

        # Workflow name match (strong signal)
        if any(t in wf_lower or wf_lower in t for t in triggers_wf):
            score += 3

        # Output extension match (medium signal)
        if ext_set & set(triggers_ext):
            score += 2

        if score > 0:
            candidates.append({"score": score, "chain": tpl})

    candidates.sort(key=lambda x: -x["score"])
    return [c["chain"] for c in candidates]


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    n = register_cryoem_chains()
    print(f"Registered {n} cryo-EM chain templates.")

    # Quick tests
    matches = suggest_chains_for_run("CryoSPARC Standard Single-Particle Analysis", ["cs", "mrc"])
    print(f"Matches for cryosparc+cs+mrc: {[m['name'] for m in matches]}")

    matches2 = suggest_chains_for_run("local_refinement", ["mrc", "map"])
    print(f"Matches for local_refinement+mrc: {[m['name'] for m in matches2]}")
