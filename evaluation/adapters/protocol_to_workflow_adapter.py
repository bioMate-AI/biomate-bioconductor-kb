"""
ProtocolToWorkflowAdapter — Tests BioMate's ability to translate bioinformatics
protocol text into an executable workflow with correctly filled parameters.

Each case supplies a 100–300 word methods-section excerpt. The adapter:
  1. Sends the protocol to BioMate via a natural prompt.
  2. Checks the returned workflow_card against the expected workflow label.
  3. Uses an LLM judge to assess parameter extraction quality.
  4. For ambiguous protocols, checks whether BioMate asked for clarification.

Scoring (three dimensions, weighted):
  routing_accuracy      (40 %): workflow_card.name / source maps to expected_workflow
  param_extraction      (40 %): F1-like score for extractable params (LLM judge)
  clarification_handling(20 %): for ambiguous cases, did BioMate ask the right question?

Usage:
    adapter = ProtocolToWorkflowAdapter(config)
    results = adapter.run(client, max_tasks=None)
"""

from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult
from evaluation.core.llm_judge import LLMJudge

_DATASET_PATH = (
    Path(__file__).parent.parent / "datasets" / "protocol_to_workflow" / "cases.yaml"
)

# ---------------------------------------------------------------------------
# Prompt templates
# ---------------------------------------------------------------------------

PROMPT_TEMPLATE = """\
I have a bioinformatics experiment described in the following protocol. \
Please identify the appropriate analysis workflow and set up the parameters \
based on what is described in the text.

PROTOCOL:
{protocol_text}

Please confirm which workflow you would run and what parameters you can determine \
from the protocol description.
"""

PARAM_JUDGE_PROMPT = """\
A protocol described a bioinformatics experiment. An AI assistant was asked to identify parameters.

PROTOCOL EXCERPT: {protocol_excerpt}
EXPECTED PARAMETERS: {expected_params}
AI RESPONSE: {ai_response}

Did the AI correctly identify the following parameters from the protocol text?
For each expected parameter, answer whether the AI mentioned it correctly (yes/no/partial).

Respond with JSON: {{"extracted": {{"param_name": "yes|no|partial", ...}}, "explanation": "brief"}}
"""

# ---------------------------------------------------------------------------
# Workflow category map — keywords → canonical label
# Ordered from most-specific to most-generic to avoid false matches.
# ---------------------------------------------------------------------------

_WORKFLOW_CATEGORY_MAP: List[tuple[List[str], str]] = [
    # Single-cell / spatial
    (["scrna", "single-cell", "single cell", "seurat", "scanpy", "cellranger", "cell ranger",
      "10x chromium", "droplet", "snrna", "sn-rna"], "scrna_seq"),
    (["visium", "spatial transcriptomics", "spatial gene expression", "space ranger",
      "spatially variable", "spatialde"], "spatial_transcriptomics"),
    # Variant calling / WGS / WES
    (["haplotypecaller", "mutect", "mutect2", "strelka", "sarek", "gatk", "bqsr",
      "variant call", "gvcf", "joint genotyp", "vqsr", "somatic variant",
      "germline variant", "wgs germline", "wes variant"], "variant_calling"),
    # CRISPR screen
    (["mageck", "crispr screen", "crispr knockout screen", "sgrna count",
      "crispr pooled", "brunello", "gecko"], "crispr_screen"),
    # ChIP-seq
    (["chip-seq", "chip_seq", "chipseq", "chromatin immunoprecipitation",
      "histone mark", "macs2", "macs3", "cut&run", "cut&tag", "cutnrun"], "chip_seq"),
    # ATAC-seq
    (["atac-seq", "atac_seq", "atacseq", "open chromatin", "tn5 tagmentation",
      "omni-atac", "scatac"], "atac_seq"),
    # Hi-C / 3D genome
    (["hi-c", "hic", "hic-pro", "topdom", "hiccups", "juicer", "chromatin conformation",
      "tad calling", "a/b compartment"], "hic"),
    # Bisulfite / methylation
    (["bisulfite", "wgbs", "rrbs", "bismark", "methylseq", "methylation seq",
      "dna methylation", "dmr", "cpg methylation"], "bisulfite_seq"),
    # RNA-seq bulk
    (["rna-seq", "rna_seq", "rnaseq", "deseq2", "edger", "star aligner",
      "featurecounts", "htseq", "salmon quant", "bulk rna", "differential expression",
      "gene expression"], "rnaseq"),
    # Long-read
    (["nanopore", "pacbio", "long-read", "long read", "minimap2", "sniffles",
      "dorado", "guppy", "promethion", "ont sequenc", "ont align",
      "structural variant", "sv calling"], "long_read_seq"),
    # GWAS
    (["gwas", "genome-wide association", "regenie", "plink", "imputation",
      "topmed", "association study", "polygenic risk"], "gwas"),
    # Metagenomics / 16S
    (["metagenomics", "16s rrna", "16s amplicon", "qiime", "dada2", "kraken",
      "metaphlan", "silva", "microbiome", "amplicon sequence variant",
      "asv", "taxonomic profil"], "metagenomics"),
    # Proteomics DIA
    (["dia-nn", "diann", "data-independent acquisition", "dia proteomics",
      "spectronaut", "dia window"], "proteomics_dia"),
    # Proteomics LFQ / DDA
    (["maxquant", "label-free quantification", "lfq", "proteomics", "perseus",
      "dda proteomics", "msfragger", "fragpipe", "pasef", "isobaric",
      "tmt", "itraq", "mass spec"], "proteomics_lfq"),
    # Metabolomics
    (["metabolomics", "xcms", "masslynx", "metabolite", "lc-ms metabol",
      "nmr metabol", "untargeted metabol", "targeted metabol"], "metabolomics"),
    # CryoEM / cryo-ET
    (["cryoem", "cryo-em", "cryo em", "relion", "cryosparc", "motionco",
      "ctffind", "topaz", "single particle analysis", "spa workflow",
      "cryo-et", "subtomogram", "vitrif"], "cryo_em"),
    # AlphaFold
    (["alphafold", "alpha fold", "structure prediction", "plddt", "pae plot",
      "hhblits jackhmmer", "msa depth", "full_dbs preset"], "alphafold"),
    # Molecular dynamics
    (["molecular dynamics", "gromacs", "amber md", "namd", "charmm",
      "nvt equilibration", "npt equilibration", "production md",
      "pmemd", "mm-gbsa", "rmsd rmsf"], "molecular_dynamics"),
    # Molecular docking
    (["molecular docking", "autodock", "vina", "glide", "docking score",
      "binding pose", "docking grid", "virtual screen"], "molecular_docking"),
    # ADMET
    (["admet", "swissadme", "pkcsm", "herg", "lipinski", "adme",
      "oral bioavailability", "ames mutagen", "dili risk"], "admet"),
    # X-ray crystallography
    (["x-ray crystallography", "xray", "diffraction data", "ccp4",
      "phenix refine", "structure factor"], "xray_crystallography"),
]


def _classify_response(text: str, workflow_card: Optional[Dict[str, Any]]) -> Optional[str]:
    """
    Attempt to resolve the workflow category from a ChatResponse.

    Priority:
      1. workflow_card.source / workflow_card.name  (exact substring match)
      2. Keyword scan of the full response text
    """
    # --- 1. workflow_card fields ---
    if workflow_card:
        candidate = " ".join([
            str(workflow_card.get("name") or ""),
            str(workflow_card.get("source") or ""),
            str(workflow_card.get("nextflow_path") or ""),
            str(workflow_card.get("workflow_type") or ""),
        ]).lower()
        for keywords, label in _WORKFLOW_CATEGORY_MAP:
            if any(kw in candidate for kw in keywords):
                return label

    # --- 2. Keyword scan of free-text response ---
    text_lower = text.lower()
    for keywords, label in _WORKFLOW_CATEGORY_MAP:
        if any(kw in text_lower for kw in keywords):
            return label

    return None


def _score_routing(
    predicted_category: Optional[str],
    expected_workflow: Optional[str],
) -> float:
    """Return 1.0 for exact match, 0.0 otherwise. null expected_workflow → 0.0 always."""
    if expected_workflow is None:
        return 0.0
    return 1.0 if predicted_category == expected_workflow else 0.0


def _keyword_param_score(ai_response: str, expected_params: Dict[str, Any]) -> float:
    """
    Fallback param scorer when LLM judge is unavailable.
    Checks whether key values from expected_params appear in the response.
    """
    if not expected_params:
        return 1.0

    text = ai_response.lower()
    hits = 0
    for key, value in expected_params.items():
        if value is None or value == "":
            continue
        # Check both the key name and the value string
        val_str = str(value).lower()
        if val_str in text or key.lower() in text:
            hits += 1

    return hits / len(expected_params) if expected_params else 1.0


class ProtocolToWorkflowAdapter(BenchmarkAdapter):
    """
    Benchmark adapter: protocol text → workflow identification + parameter extraction.

    Scoring breakdown:
      routing_accuracy       40 %
      param_extraction       40 %
      clarification_handling 20 %
    """

    name = "protocol_to_workflow"

    _ROUTING_WEIGHT = 0.40
    _PARAM_WEIGHT = 0.40
    _CLARIF_WEIGHT = 0.20

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        llm_config = config.get("llm_judge", {})
        try:
            self._judge = LLMJudge(
                model=llm_config.get("model", "claude-haiku-4-5-20251001"),
                api_key=llm_config.get("api_key"),
                max_tokens=llm_config.get("max_tokens", 400),
                temperature=llm_config.get("temperature", 0.0),
            )
        except (KeyError, Exception):
            self._judge = None

    # ------------------------------------------------------------------
    # BenchmarkAdapter interface
    # ------------------------------------------------------------------

    def load_tasks(self) -> List[BenchmarkTask]:
        with open(_DATASET_PATH) as f:
            data = yaml.safe_load(f)

        tasks: List[BenchmarkTask] = []
        for case in data["cases"]:
            prompt = PROMPT_TEMPLATE.format(
                protocol_text=case["protocol_text"].strip()
            )
            task = BenchmarkTask(
                task_id=case["id"],
                question=prompt,
                ground_truth={
                    "expected_workflow": case.get("expected_workflow"),
                    "expected_params": case.get("expected_params") or {},
                    "expected_clarifications": case.get("expected_clarifications") or [],
                },
                domain=case.get("domain", "life_science"),
                task_type="workflow",
                answer_type="open",
                metadata={
                    "source_type": case.get("source_type", "published_methods"),
                    "expected_workflow": case.get("expected_workflow"),
                    "expected_params": case.get("expected_params") or {},
                    "expected_clarifications": case.get("expected_clarifications") or [],
                    "notes": case.get("notes", ""),
                    "benchmark": "protocol_to_workflow",
                    "protocol_text": case["protocol_text"].strip(),
                },
            )
            tasks.append(task)
        return tasks

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """
        Single-turn scoring path used by base class run().
        Workflow card is not available here so routing falls back to text scan.
        """
        gt = task.ground_truth
        routing = _score_routing(
            _classify_response(agent_response, None),
            gt["expected_workflow"],
        )
        param_score = self._score_params(
            protocol_excerpt=task.metadata["protocol_text"][:300],
            expected_params=gt["expected_params"],
            ai_response=agent_response,
        )
        clarif_score = self._score_clarification(
            response_text=agent_response,
            needs_input=False,
            missing_items=[],
            expected_clarifications=gt["expected_clarifications"],
            expected_workflow=gt["expected_workflow"],
        )
        return self._combine(routing, param_score, clarif_score)

    # ------------------------------------------------------------------
    # Full run() — overrides base to access ChatResponse fields
    # ------------------------------------------------------------------

    def run(
        self,
        client: Any,
        max_tasks: Optional[int] = None,
        source_type: Optional[str] = None,
    ) -> List[BenchmarkResult]:
        """
        Execute benchmark tasks with ThreadPoolExecutor (max_workers=6).

        Args:
            client:       BioMateEvalClient instance
            max_tasks:    cap on number of tasks (None = all)
            source_type:  filter by source_type field
                          ("published_methods" | "lab_sop" | "ambiguous" | None = all)
        """
        from concurrent.futures import ThreadPoolExecutor, as_completed

        tasks = self.load_tasks()

        if source_type and source_type != "all":
            tasks = [t for t in tasks if t.metadata.get("source_type") == source_type]

        if max_tasks:
            tasks = tasks[:max_tasks]

        results: List[BenchmarkResult] = []

        def _run_one(task: BenchmarkTask) -> BenchmarkResult:
            t0 = time.time()
            error: Optional[str] = None
            ai_text = ""
            workflow_card = None
            needs_input = False
            missing_items: List[str] = []

            try:
                response = client.ask(task.question)
                ai_text = response.text if hasattr(response, "text") else str(response)
                workflow_card = getattr(response, "workflow_card", None)
                needs_input = getattr(response, "needs_input", False)
                missing_items = getattr(response, "missing_items", [])
            except Exception as exc:
                error = str(exc)

            gt = task.ground_truth
            routing = 0.0
            param_score = 0.0
            clarif_score = 0.0

            if not error:
                routing = _score_routing(
                    _classify_response(ai_text, workflow_card),
                    gt["expected_workflow"],
                )
                param_score = self._score_params(
                    protocol_excerpt=task.metadata["protocol_text"][:300],
                    expected_params=gt["expected_params"],
                    ai_response=ai_text,
                )
                clarif_score = self._score_clarification(
                    response_text=ai_text,
                    needs_input=needs_input,
                    missing_items=missing_items,
                    expected_clarifications=gt["expected_clarifications"],
                    expected_workflow=gt["expected_workflow"],
                )

            final_score = self._combine(routing, param_score, clarif_score)
            elapsed = time.time() - t0

            indicator = "✓" if final_score >= 0.75 else ("~" if final_score >= 0.4 else "✗")
            src = task.metadata.get("source_type", "")[:3]
            print(
                f"  [{task.task_id}|{src}] "
                f"route={routing:.2f} param={param_score:.2f} clarif={clarif_score:.2f} "
                f"→ {indicator} total={final_score:.2f} ({elapsed:.0f}s)"
            )

            return BenchmarkResult(
                task_id=task.task_id,
                benchmark=self.name,
                score=final_score,
                agent_response=ai_text[:2000],
                ground_truth=task.ground_truth,
                latency_sec=elapsed,
                error=error,
                metadata={
                    **task.metadata,
                    "routing_score": routing,
                    "param_score": param_score,
                    "clarification_score": clarif_score,
                },
            )

        max_workers = self.config.get("concurrency", {}).get("max_parallel_tasks", 6)
        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = {pool.submit(_run_one, t): t for t in tasks}
            for future in as_completed(futures):
                results.append(future.result())

        return results

    # ------------------------------------------------------------------
    # Scoring helpers
    # ------------------------------------------------------------------

    def _combine(
        self,
        routing: float,
        param_score: float,
        clarif_score: float,
    ) -> float:
        return (
            routing * self._ROUTING_WEIGHT
            + param_score * self._PARAM_WEIGHT
            + clarif_score * self._CLARIF_WEIGHT
        )

    def _score_params(
        self,
        protocol_excerpt: str,
        expected_params: Dict[str, Any],
        ai_response: str,
    ) -> float:
        """
        Use LLM judge to assess parameter extraction quality.
        Falls back to keyword matching when judge is unavailable.
        Returns F1-like score 0.0–1.0.
        """
        if not expected_params:
            # No params to check — full credit
            return 1.0

        if self._judge is None:
            return _keyword_param_score(ai_response, expected_params)

        prompt = PARAM_JUDGE_PROMPT.format(
            protocol_excerpt=protocol_excerpt,
            expected_params=json.dumps(expected_params),
            ai_response=ai_response[:1500],
        )
        try:
            raw = self._judge._call(prompt, max_tokens=400)
            json_match = re.search(r"\{.*\}", raw, re.DOTALL)
            if not json_match:
                return _keyword_param_score(ai_response, expected_params)

            verdict = json.loads(json_match.group())
            extracted: Dict[str, str] = verdict.get("extracted", {})
            if not extracted:
                return _keyword_param_score(ai_response, expected_params)

            # F1: yes=1.0, partial=0.5, no=0.0
            score_map = {"yes": 1.0, "partial": 0.5, "no": 0.0}
            scores = [score_map.get(str(v).lower(), 0.0) for v in extracted.values()]
            return sum(scores) / len(scores) if scores else 0.0

        except Exception:
            return _keyword_param_score(ai_response, expected_params)

    def _score_clarification(
        self,
        response_text: str,
        needs_input: bool,
        missing_items: List[str],
        expected_clarifications: List[str],
        expected_workflow: Optional[str],
    ) -> float:
        """
        Score clarification behaviour.

        Cases:
          - No clarifications expected (unambiguous protocol):
              Full credit (1.0) if BioMate did NOT ask; 0.0 if it asks unnecessarily.
          - Clarifications expected (ambiguous protocol):
              1.0  if needs_input=True  OR  "?" appears in response targeting the right dimension.
              0.5  if BioMate asked but didn't target the right dimension.
              0.0  if BioMate routed directly without asking.
          - expected_workflow is null AND clarifications expected:
              Treated the same as the ambiguous case above.
        """
        asked = needs_input or ("?" in response_text)

        if not expected_clarifications:
            # Unambiguous case — reward not asking
            return 1.0 if not asked else 0.5

        # Ambiguous case — BioMate should ask
        if not asked:
            return 0.0

        # BioMate asked — check whether it targeted the right dimension
        text_lower = response_text.lower()
        items_lower = [m.lower() for m in (missing_items or [])]
        dimension_hits = 0
        for dim in expected_clarifications:
            dim_lower = dim.lower().replace("_", " ")
            if (
                dim_lower in text_lower
                or any(dim_lower in m for m in items_lower)
            ):
                dimension_hits += 1

        if dimension_hits >= len(expected_clarifications):
            return 1.0
        elif dimension_hits > 0:
            return 0.5
        else:
            # Asked, but about the wrong thing
            return 0.3
