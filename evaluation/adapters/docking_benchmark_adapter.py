"""
docking_benchmark_adapter.py
----------------------------
B2 Docking Triage benchmark.

Dataset: datasets/drug_discovery_e2e/pdb_systems.yaml (15 PDB systems)
Each system has 3 ligands with experimental Kd/IC50 values.

Task types generated per system:
  Type A (complete):   NL query with all ligand SMILES + PDB ID → should route to docking
                       and include SMILES + PDB ID in generated params
  Type B (incomplete): Partial query with SMILES but no target/PDB → BioMate should ask
                       for the missing information (prereq detection)
  Type C (negative):   ADMET screening query → should NOT route to docking

Total: 15 systems × 3 types = 45 tasks

Scoring:
  Type A: 1.0 if docking workflow identified AND SMILES in params AND PDB ID in params
          0.5 if docking workflow identified but params missing
          0.0 if wrong workflow
  Type B: 1.0 if BioMate asks for PDB/target info (prereq detected)
          0.5 if BioMate routes to docking but doesn't ask (routing OK, prereq missed)
          0.0 if BioMate routes to wrong workflow
  Type C: 1.0 if BioMate does NOT route to docking (routes to ADMET or asks for info)
          0.0 if BioMate incorrectly routes to docking

Usage:
    adapter = DockingBenchmarkAdapter(config)
    tasks   = adapter.load_tasks()   # 45 tasks
    results = adapter.run(client)    # or use run_tasks()
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import yaml

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask

_DATASET_PATH = (
    Path(__file__).parent.parent
    / "datasets"
    / "drug_discovery_e2e"
    / "pdb_systems.yaml"
)

# Keywords that identify docking-related workflow names / paths
_DOCKING_KEYWORDS = {
    "dock", "docking", "vina", "glide", "diffdock", "autodock",
    "smina", "gnina", "ledock", "virtual_screen", "virtual screening",
    "molecular docking",
}

# Keywords for ADMET workflows
_ADMET_KEYWORDS = {
    "admet", "pharmacokinetics", "toxicity", "herg", "dili",
    "ames", "ro5", "lipinski", "absorption", "distribution",
    "metabolism", "excretion", "predict_admet",
}

# Params that should contain the PDB ID or receptor structure
_PDB_PARAM_NAMES = {
    "pdb_id", "receptor_pdb", "receptor", "protein_pdb",
    "pdb", "target_pdb", "structure_id",
}

# Params that should carry SMILES strings
_SMILES_PARAM_NAMES = {
    "ligand_smiles", "smiles", "ligand", "compound_smiles",
    "input_smiles", "molecules",
}

# Phrases that indicate BioMate is asking for missing information
_PREREQ_PHRASES = [
    r"which (protein|target|receptor|pdb)",
    r"need.*pdb",
    r"pdb (id|code|identifier)",
    r"target protein",
    r"what.*target",
    r"provide.*pdb",
    r"specify.*receptor",
    r"please.*pdb",
    r"missing.*pdb",
    r"need.*target",
    r"which.*structure",
]
_PREREQ_RE = re.compile("|".join(_PREREQ_PHRASES), re.IGNORECASE)


def _smiles_list_str(ligands: list[dict], max_per_line: int = 3) -> str:
    """Format a list of ligand SMILES for inclusion in NL query."""
    entries = [f"{lig['name']}: {lig['smiles']}" for lig in ligands]
    if len(entries) <= max_per_line:
        return ", ".join(entries)
    return "; ".join(entries)


def _contains_docking_workflow(response: str) -> bool:
    """Return True if the response indicates a docking workflow was selected."""
    resp_lower = response.lower()
    return any(kw in resp_lower for kw in _DOCKING_KEYWORDS)


def _contains_admet_workflow(response: str) -> bool:
    """Return True if the response indicates an ADMET workflow was selected."""
    resp_lower = response.lower()
    return any(kw in resp_lower for kw in _ADMET_KEYWORDS)


def _extract_workflow_name(response: str) -> str:
    """Try to extract the suggested workflow name from a BioMate response."""
    # Look for patterns like "workflow: X", "pipeline: X", JSON field "workflow_name": "X"
    for pattern in (
        r'"workflow_name"\s*:\s*"([^"]+)"',
        r'"nextflow_path"\s*:\s*"([^"]+)"',
        r'workflow[:\s]+([A-Za-z0-9_\-/]+)',
        r'pipeline[:\s]+([A-Za-z0-9_\-/]+)',
    ):
        m = re.search(pattern, response, re.IGNORECASE)
        if m:
            return m.group(1).strip().lower()
    return ""


def _params_contain_pdb(response: str, pdb_id: str) -> bool:
    """Return True if the response or its params mention the specific PDB ID."""
    return pdb_id.lower() in response.lower()


def _params_contain_smiles(response: str, ligands: list[dict]) -> bool:
    """Return True if at least one ligand SMILES appears in the response."""
    for lig in ligands:
        smiles = lig.get("smiles", "")
        if smiles and smiles[:20] in response:
            return True
    return False


def _asks_for_prereq(response: str) -> bool:
    """Return True if BioMate is asking for missing information (PDB/target)."""
    return bool(_PREREQ_RE.search(response))


class DockingBenchmarkAdapter(BenchmarkAdapter):
    """
    B2 Docking Triage benchmark adapter.

    45 tasks across 15 PDB systems × 3 query types.
    Tests:
      - Correct workflow routing to docking (Type A, C)
      - Parameter extraction (PDB ID + SMILES) for complete queries (Type A)
      - Prerequisite detection for incomplete queries (Type B)
      - Negative-case discrimination: ADMET ≠ docking (Type C)
    """

    name = "docking_benchmark"

    def load_tasks(self) -> list[BenchmarkTask]:
        # The YAML file is a mixed document: a sequence of system dicts followed
        # by an 'evaluation' mapping key at the root.  This is technically invalid
        # YAML for a single safe_load but yaml.safe_load_all handles it via the
        # multi-document stream.  We parse manually: read lines up to the
        # 'evaluation:' key, then load just that section.
        with open(_DATASET_PATH) as f:
            raw_text = f.read()

        # Split off the 'evaluation:' section (appears after all system dicts)
        # so we only parse the list portion
        eval_marker = "\nevaluation:"
        if eval_marker in raw_text:
            systems_text = raw_text[: raw_text.index(eval_marker)]
        else:
            systems_text = raw_text

        raw = yaml.safe_load(systems_text)
        if raw is None:
            raw = []

        # The systems section is a list; filter to items that have an 'id' field
        if isinstance(raw, list):
            systems: list[dict] = [item for item in raw if isinstance(item, dict) and "id" in item]
        else:
            systems = []

        tasks: list[BenchmarkTask] = []

        for system in systems:
            sys_id    = system["id"]
            target    = system["target"]
            pdb_id    = system["pdb_id"]
            ligands   = system.get("ligands", [])
            notes     = system.get("notes", "")

            smiles_str = _smiles_list_str(ligands)
            n = len(ligands)

            # ── Type A: complete query (all SMILES + PDB ID) ─────────────────
            query_a = (
                f"Run molecular docking of these {n} ligands against {target} "
                f"(PDB: {pdb_id}): {smiles_str}"
            )
            tasks.append(BenchmarkTask(
                task_id=f"{sys_id}_typeA",
                question=query_a,
                ground_truth={
                    "query_type": "complete",
                    "expected_workflow": "docking",
                    "pdb_id": pdb_id,
                    "ligands": ligands,
                },
                domain="drug_discovery",
                difficulty="easy",
                task_type="workflow",
                answer_type="json",
                metadata={
                    "system_id": sys_id,
                    "target": target,
                    "pdb_id": pdb_id,
                    "ligands": ligands,
                    "query_type": "complete",
                    "notes": notes,
                    "benchmark": "docking_benchmark",
                },
            ))

            # ── Type B: incomplete query (SMILES but no PDB / target name) ───
            first_smiles = ligands[0]["smiles"] if ligands else "CC1=NC(=NC1=O)N"
            query_b = (
                f"I need to dock my compound against CDK2. "
                f"The compound is {first_smiles}."
            )
            tasks.append(BenchmarkTask(
                task_id=f"{sys_id}_typeB",
                question=query_b,
                ground_truth={
                    "query_type": "incomplete",
                    "expected_behavior": "ask_for_pdb",
                },
                domain="drug_discovery",
                difficulty="medium",
                task_type="workflow",
                answer_type="json",
                metadata={
                    "system_id": sys_id,
                    "target": target,
                    "pdb_id": pdb_id,
                    "ligands": ligands[:1],
                    "query_type": "incomplete",
                    "notes": notes,
                    "benchmark": "docking_benchmark",
                },
            ))

            # ── Type C: negative case (ADMET query — should NOT route to docking)
            first_smiles_c = ligands[0]["smiles"] if ligands else "CC1=NC(=NC1=O)N"
            query_c = f"Perform ADMET screening on {first_smiles_c}"
            tasks.append(BenchmarkTask(
                task_id=f"{sys_id}_typeC",
                question=query_c,
                ground_truth={
                    "query_type": "negative",
                    "expected_behavior": "not_docking",
                },
                domain="drug_discovery",
                difficulty="easy",
                task_type="workflow",
                answer_type="json",
                metadata={
                    "system_id": sys_id,
                    "target": target,
                    "pdb_id": pdb_id,
                    "ligands": ligands[:1],
                    "query_type": "negative",
                    "notes": notes,
                    "benchmark": "docking_benchmark",
                },
            ))

        return tasks

    # ------------------------------------------------------------------
    # Prompt construction
    # ------------------------------------------------------------------

    def task_prompt(self, task: BenchmarkTask) -> str:
        """Return the NL query to send to BioMate."""
        return task.question

    # ------------------------------------------------------------------
    # Scoring
    # ------------------------------------------------------------------

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """
        Score BioMate's response for one task.

        Type A (complete): 1.0 = docking + PDB + SMILES in response
                           0.5 = docking workflow found but params incomplete
                           0.0 = wrong workflow
        Type B (incomplete): 1.0 = asks for PDB/target info
                              0.5 = routes to docking but doesn't ask
                              0.0 = wrong workflow or hallucination
        Type C (negative):   1.0 = does NOT route to docking (routes to ADMET or asks)
                             0.0 = incorrectly routes to docking
        """
        gt = task.ground_truth
        query_type = gt.get("query_type") or task.metadata.get("query_type", "")

        if query_type == "complete":
            return self._score_type_a(task, agent_response)
        elif query_type == "incomplete":
            return self._score_type_b(task, agent_response)
        elif query_type == "negative":
            return self._score_type_c(task, agent_response)
        else:
            return 0.0

    def _score_type_a(self, task: BenchmarkTask, response: str) -> float:
        """Type A: complete query — docking workflow + PDB ID + SMILES in params."""
        pdb_id  = task.ground_truth.get("pdb_id", "")
        ligands = task.ground_truth.get("ligands", [])

        routed_to_docking = _contains_docking_workflow(response)
        has_pdb    = _params_contain_pdb(response, pdb_id)
        has_smiles = _params_contain_smiles(response, ligands)

        if routed_to_docking and has_pdb and has_smiles:
            return 1.0
        elif routed_to_docking:
            return 0.5
        else:
            return 0.0

    def _score_type_b(self, task: BenchmarkTask, response: str) -> float:
        """Type B: incomplete query — should ask for PDB ID or target."""
        asks_prereq = _asks_for_prereq(response)
        routed_to_docking = _contains_docking_workflow(response)

        if asks_prereq:
            return 1.0
        elif routed_to_docking:
            # Routing was correct but prereq not surfaced
            return 0.5
        else:
            return 0.0

    def _score_type_c(self, task: BenchmarkTask, response: str) -> float:
        """Type C: negative case — should route to ADMET, NOT docking."""
        routed_to_docking = _contains_docking_workflow(response)
        if routed_to_docking:
            return 0.0
        # Any non-docking response is correct (ADMET, clarification, etc.)
        return 1.0
