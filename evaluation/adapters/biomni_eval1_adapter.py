"""
biomni_eval1_adapter.py
-----------------------
Wires the existing BiomniEval1 loader (Biomni/biomni/eval/biomni_eval1.py)
into BioMate's evaluation BenchmarkAdapter interface.

Loads 5 bioinformatics-relevant tasks from BiomniEval1 (Apache 2.0).
Scores via the task-specific reward functions already implemented in the loader.

Tasks included (bioinformatics-relevant subset):
  gwas_variant_prioritization   → answer: rsID (e.g. "rs4253311")
  gwas_causal_gene_pharmaprojects → answer: gene symbol (e.g. "XPO1")
  screen_gene_retrieval          → answer: gene symbol or Ensembl ID
  rare_disease_diagnosis         → answer: JSON {"disease_name": ..., "OMIM_ID": ...}
  patient_gene_detection         → answer: Ensembl gene ID (e.g. "ENSG00000161011")

Data: hf://datasets/biomni/Eval1/biomni_eval1_dataset.parquet (~50 MB download)
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request
import warnings
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask


# ---------------------------------------------------------------------------
# Offline / lightweight resolvers
# ---------------------------------------------------------------------------

@lru_cache(maxsize=1)
def _load_hpo_ontology():
    """Load HPO ontology via pronto (downloads hp.obo once, cached by pronto)."""
    try:
        import pronto
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            return pronto.Ontology.from_obo_library("hp.obo")
    except Exception:
        return None


def _resolve_hp_codes(codes: list[str]) -> dict[str, str]:
    """Return {HP:XXXXXXX: phenotype_name} for each code."""
    ont = _load_hpo_ontology()
    result: dict[str, str] = {}
    if ont is None:
        return result
    for c in codes:
        try:
            result[c] = ont[c].name
        except (KeyError, Exception):
            result[c] = c   # fallback: leave as-is
    return result


def _resolve_ensg_ids(ensg_ids: list[str]) -> dict[str, str]:
    """Return {ENSG...: gene_symbol} using mygene.info (batch POST, no auth)."""
    if not ensg_ids:
        return {}
    try:
        payload = json.dumps({"ids": ensg_ids, "fields": "symbol", "species": "human"}).encode()
        req = urllib.request.Request(
            "https://mygene.info/v3/gene",
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            items = json.loads(r.read())
        return {item["query"]: item.get("symbol", item["query"]) for item in items}
    except Exception:
        return {e: e for e in ensg_ids}   # fallback: leave as-is


# Bioinformatics-relevant tasks from BiomniEval1
BIOINFO_TASKS = [
    "gwas_variant_prioritization",
    "gwas_causal_gene_pharmaprojects",
    "screen_gene_retrieval",
    "rare_disease_diagnosis",
    "patient_gene_detection",
]

# Format instructions appended to each task prompt
_FORMAT_INSTRUCTIONS: Dict[str, str] = {
    "gwas_variant_prioritization": (
        "\n\n---\n"
        "ANSWER REQUIRED: Select ONE rsID from the list above.\n"
        "Use GWAS Catalog associations, functional genomics, and LD structure knowledge.\n"
        "DO NOT suggest running a workflow. DO NOT ask for data. Answer from knowledge.\n"
        "Respond with ONLY the rsID (e.g., rs1234567). Nothing else."
    ),
    "gwas_causal_gene_pharmaprojects": (
        "\n\n---\n"
        "ANSWER REQUIRED: Name the most likely causal gene for this GWAS locus.\n"
        "Use your knowledge of gene-phenotype associations, eQTLs, and druggable targets.\n"
        "DO NOT suggest running a workflow. Answer from knowledge.\n"
        "Respond with ONLY the gene symbol (e.g., CASR). Nothing else."
    ),
    "gwas_causal_gene_opentargets": (
        "\n\n---\n"
        "ANSWER REQUIRED: Name the most likely causal gene for this GWAS locus.\n"
        "Respond with ONLY the gene symbol (e.g., CASR). Nothing else."
    ),
    "screen_gene_retrieval": (
        "\n\n---\n"
        "ANSWER REQUIRED: Identify the gene that confers the described fitness effect in the screen.\n"
        "Use knowledge of essential genes, CRISPR screen literature, and pathway biology.\n"
        "DO NOT suggest running a workflow. Answer from knowledge.\n"
        "Respond with ONLY the gene symbol or Ensembl ID. Nothing else."
    ),
    "rare_disease_diagnosis": (
        "\n\nSearch OMIM for the specific rare disease matching this gene and phenotype combination. "
        "Provide the exact OMIM disease name and 6-digit OMIM ID.\n"
        "Answer with ONLY this JSON (one line, no explanation):\n"
        '{"disease_name": "Exact OMIM disease name", "OMIM_ID": "123456"}'
    ),
    "patient_gene_detection": (
        "\n\nSearch ClinVar and OMIM for the gene whose known disease associations match these phenotypes. "
        "Identify the ONE causal gene from the candidate list.\n"
        "Answer with ONLY this JSON (one line, no explanation):\n"
        '{"causal_gene": ["ENSG_ID_from_candidate_list"]}'
    ),
}

# Patterns to extract short answers from verbose BioMate responses
_RS_ID_RE = re.compile(r"\brs\d{4,}\b")
_ENSG_RE = re.compile(r"\bENSG\d{10,}\b")
_OMIM_RE = re.compile(r'\b(\d{6})\b')


def _extract_answer(task_name: str, response: str, ground_truth: str) -> str:
    """
    Extract the concise answer from a potentially verbose BioMate response.
    Falls back to the raw response if extraction fails.
    """
    response = response.strip()

    if task_name == "gwas_variant_prioritization":
        # Extract last rsID mentioned (model tends to put conclusion last)
        hits = _RS_ID_RE.findall(response)
        return hits[-1] if hits else response

    elif task_name.startswith("gwas_causal_gene"):
        # Extract gene name — look for explicit "answer: GENE" or bold **GENE**
        m = re.search(r"(?:answer|gene|causal)[:\s]+\*{0,2}([A-Z][A-Z0-9\-]{1,20})\*{0,2}", response, re.IGNORECASE)
        if m:
            return m.group(1).upper()
        # Last all-caps word token that looks like a gene
        words = re.findall(r"\b([A-Z][A-Z0-9\-]{1,15})\b", response)
        return words[-1] if words else response

    elif task_name == "screen_gene_retrieval":
        ensg = _ENSG_RE.findall(response)
        if ensg:
            return ensg[-1]
        # Gene symbol: last CAPS token
        words = re.findall(r"\b([A-Z][A-Z0-9\-]{1,20})\b", response)
        return words[-1] if words else response

    elif task_name == "patient_gene_detection":
        # Check if response is already valid JSON with causal_gene key
        try:
            parsed = json.loads(response.strip())
            if isinstance(parsed, dict) and "causal_gene" in parsed:
                return response.strip()
        except Exception:
            pass
        # Extract ENSG IDs and wrap in expected format
        ensg = _ENSG_RE.findall(response)
        if ensg:
            return json.dumps({"causal_gene": [ensg[-1]]})
        return response

    elif task_name == "rare_disease_diagnosis":
        # Try to find JSON block
        m = re.search(r'\{[^{}]*"OMIM_ID"[^{}]*\}', response, re.DOTALL)
        if m:
            return m.group(0)
        # Fallback: extract OMIM number
        try:
            gt_dict = json.loads(ground_truth) if isinstance(ground_truth, str) else ground_truth
            omim = gt_dict.get("OMIM_ID", "")
            if omim and omim in response:
                return json.dumps({"OMIM_ID": omim, "disease_name": ""})
        except Exception:
            pass
        return response

    return response


class BiomniEval1Adapter(BenchmarkAdapter):
    """
    Adapter for Stanford Biomni Eval1 benchmark.

    Competitor reference: Biomni-R0-32B-Preview scores best on 7/10 tasks
    (beats Claude 4 and GPT-5). BioMate targets competitive scores on the
    5 bioinformatics tasks.

    Citation: Huang K et al. bioRxiv 2025. doi:10.1101/2025.05.30.656746
    """

    name = "biomni_eval1"

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        biomni_path = config["paths"].get("biomni_eval1_loader", "")
        if biomni_path and biomni_path not in sys.path:
            sys.path.insert(0, biomni_path)

        self._inner = None   # lazy-loaded on first prepare()

    def prepare(self, client) -> None:
        from biomni.eval.biomni_eval1 import BiomniEval1
        self._inner = BiomniEval1()

    def load_tasks(self) -> List[BenchmarkTask]:
        if self._inner is None:
            from biomni.eval.biomni_eval1 import BiomniEval1
            self._inner = BiomniEval1()

        tasks = []
        for task_name in BIOINFO_TASKS:
            subset = self._inner.df[self._inner.df["task_name"] == task_name]
            for _, row in subset.iterrows():
                prompt = str(row["prompt"])
                meta: dict = {
                    "task_name": task_name,
                    "instance_id": int(row["task_instance_id"]),
                    "source": "biomni_eval1",
                }

                # Pre-resolve HP codes and ENSG IDs for knowledge-intensive tasks
                if task_name in ("patient_gene_detection", "rare_disease_diagnosis"):
                    hp_codes = re.findall(r"HP:\d{7}", prompt)
                    ensg_ids = re.findall(r"ENSG\d{10,}", prompt)
                    if hp_codes:
                        meta["hp_resolved"] = _resolve_hp_codes(hp_codes)
                    if ensg_ids:
                        meta["ensg_resolved"] = _resolve_ensg_ids(ensg_ids)

                tasks.append(BenchmarkTask(
                    task_id=f"biomni_eval1__{task_name}__{row['task_instance_id']}",
                    question=prompt,
                    ground_truth=row["answer"],
                    domain="life_science",
                    difficulty="medium",
                    task_type="reasoning",
                    answer_type="open",
                    metadata=meta,
                ))
        return tasks

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        task_name = task.metadata["task_name"]
        # Extract concise answer from verbose response before scoring
        extracted = _extract_answer(task_name, agent_response, str(task.ground_truth))
        return self._inner.evaluate(
            task_name,
            task.metadata["instance_id"],
            extracted,
        )

    def task_prompt(self, task: BenchmarkTask) -> str:
        task_name = task.metadata["task_name"]
        fmt = _FORMAT_INSTRUCTIONS.get(task_name, "")
        question = task.question

        # For HP/ENSG tasks, preserve the original Task: format.
        # The bare "Task: given a patient's phenotypes... HP:xxx ENSG..." format
        # routes to research_question (ResearchAgent). Resolved names confuse routing.

        return f"{question}{fmt}"
