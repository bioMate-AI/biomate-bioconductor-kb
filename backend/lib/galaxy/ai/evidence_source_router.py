"""Intent-aware evidence-source selection for the research agent.

WHY THIS EXISTS
---------------
`federated_query` selects sources by a single DETECTED ENTITY TYPE
(`ENTITY_SOURCES[detect_entity_type(query)]`). That is too coarse for real
questions: a SAR / potency question about the *target* "ABL1" detects as a
`gene`, so it pulls the gene source list (NCBI/Ensembl/UniProt/STRING/KEGG/GO/…)
and NEVER reaches ChEMBL / BindingDB / PDB / Pharos — exactly the sources that
hold the answer. Source choice must follow the QUESTION'S INTENT (what evidence
it needs), not just the entity's type.

This module is the "source-selection skill" in code: a readable, declarative
map from question *facets* (structure, bioactivity, target, pathway, variant,
disease, expression, literature) to the registry source ids that serve them.
Every id is validated against `galaxy.ai.data_sources` (the single source of
truth) at call time, so the registry stays authoritative — add a source there,
reference it here. The human/LLM-readable companion is
`skills/evidence-source-selection.md`.

Design follows the repo rule "rule-based inference first, LLM as fallback":
the facet detection here is deterministic and testable; an LLM selector can be
layered on later for ambiguous prose without changing this contract.
"""
from __future__ import annotations

import re
from typing import Dict, List, Optional, Sequence

try:  # registry is the authoritative catalog; degrade gracefully if unavailable
    from galaxy.ai import data_sources as _registry
except Exception:  # pragma: no cover - import guard
    _registry = None


# ── Facet → candidate source ids ────────────────────────────────────────────
# Ids MUST exist in data_sources.py. Ordered by usefulness within a facet; the
# final list is de-duplicated preserving first-seen order. Literature is always
# appended as corroboration (never the only channel for a factual question).
FACET_SOURCES: Dict[str, List[str]] = {
    # 3D structure, fold, domain architecture, binding-site geometry
    "structure":   ["pdb", "pdbe", "alphafold", "interpro", "uniprot"],
    # SAR / potency / affinity / binding tables — the medicinal-chemistry answer
    "bioactivity": ["chembl", "bindingdb", "pubchem", "chebi", "pharos", "uniprot", "pdb"],
    # target biology: druggability, tractability, target-disease association
    "target":      ["pharos", "opentargets", "chembl", "uniprot", "string"],
    # pathways, signalling, interaction networks, enrichment context
    "pathway":     ["kegg", "reactome", "go", "string"],
    # sequence variants / mutations / polymorphisms
    "variant":     ["clinvar", "dbsnp", "gnomad"],
    # disease / phenotype / clinical indication
    "disease":     ["opentargets", "hpo", "omim", "clinvar", "clinicaltrials"],
    # gene-centric baseline (identity, orthology, function + gnomAD LoF constraint, which
    # is a core gene-level property — pLI/LOEUF — not just variant data)
    "gene":        ["ncbi_gene", "ensembl", "uniprot", "go", "string", "gnomad"],
}

# Always-on literature corroboration (kept small; the agent's literature client
# already fans PubMed/EuropePMC/S2/OpenAlex — these ids mark them as selected).
LITERATURE_SOURCES: List[str] = ["pubmed", "europepmc", "semantic_scholar", "corpus_fs", "paperclip"]

# ── Facet keyword cues (lowercased, word-boundary matched) ──────────────────
_FACET_CUES: Dict[str, Sequence[str]] = {
    "structure":   ["structure", "crystal", "fold", "domain", "conformation", "binding site",
                    "pocket", "3d", "apo", "holo", "dfg", "allosteric", "cryo-em", "cryoem"],
    # NB: bare "sar"/"scaffold" are word-bounded — unbounded they matched "SARS-CoV-2"
    # and genome-assembly "scaffold N50" and mis-fired the bioactivity facet
    # (committee review, 2026-11-11).
    "bioactivity": ["\\bsar\\b", "potency", "affinity", "ic50", "ec50", "\\bki\\b", "\\bkd\\b",
                    "binding", "inhibitor", "inhibition", "bioactivity", "ligand", "pharmacophore",
                    "selectivity", "nanomolar", "dose-response", "dose response", "structure-activity",
                    "structure activity", "medicinal chemistry", "scaffold hop", "analogue"],
    "target":      ["target", "druggable", "druggability", "tractability", "target identification",
                    "target id", "disease association", "therapeutic target", "actionab"],
    "pathway":     ["pathway", "signalling", "signaling", "network", "interaction", "interactome",
                    "enrichment", "cascade", "upstream", "downstream", "regulat"],
    "variant":     ["variant", "mutation", "\\bsnp\\b", "allele", "polymorphism", "genotype",
                    "missense", "resistance mutation", "\\brs\\d",
                    # gene-constraint / LoF-intolerance cues → gnomAD (pLI/LOEUF) is in this facet
                    "constraint", "loss-of-function", "loss of function", "\\blof\\b", "loeuf",
                    "\\bpli\\b", "intoleran", "haploinsufficien", "essential gene"],
    "disease":     ["disease", "phenotype", "syndrome", "indication", "clinical", "patient",
                    "prognosis", "biomarker"],
}


def _federation_serveable_ids() -> set:
    """Ids the FEDERATED fan-out can actually serve — registry sources that are live AND
    reachable via the federation surface. Gating on live-status alone advertised sources
    (bindingdb/pharos/opentargets/pdbe) that federated_query silently drops because they
    have no federation fetcher — overstating coverage (committee review, 2026-11-11).
    Open Targets / Pharos reach the answer via the target_id path, not this fan-out."""
    if _registry is None:
        return set()
    _fed = getattr(_registry, "SURFACE_FEDERATION", "federation")
    ids = set()
    for s in getattr(_registry, "SOURCES", []):
        _status = getattr(s, "status", "live")
        _surfaces = getattr(s, "surfaces", None) or []
        _sid = getattr(s, "id", None)
        if _sid and _status == "live" and _fed in _surfaces:
            ids.add(_sid)
    return ids


# Explicit cues that a question wants a RANKED list of candidate targets/genes —
# the job of the target_id engine (fuse_channels across Open Targets / STRING /
# LLM), not a literature synthesis. Kept conservative on purpose: a false positive
# fires the (costly, live) orchestrator, so match only clear ranking intent.
_TARGET_RANKING_CUES: Sequence[str] = (
    "which targets", "which genes", "identify targets", "identify drug targets",
    "drug targets for", "therapeutic targets for", "prioriti", "rank targets",
    "rank the targets", "best targets", "candidate targets", "target identification",
    "actionable targets", "top targets", "nominate targets",
)


def is_target_ranking_question(question: str) -> bool:
    """True when the question asks to RANK/identify candidate targets — route these
    to the target_id engine (fuse_channels) rather than literature synthesis."""
    q = (question or "").lower()
    return any(cue in q for cue in _TARGET_RANKING_CUES)


def detect_facets(question: str) -> List[str]:
    """Return the evidence facets a question needs, in priority order.

    Deterministic keyword match. 'gene' is a baseline only added when the
    question names a gene/target but no more specific facet fired, so a plain
    "what is GENE" still gets identity sources without over-selecting.
    """
    q = (question or "").lower()
    facets: List[str] = []
    for facet, cues in _FACET_CUES.items():
        for cue in cues:
            # cues containing regex metachars are matched as patterns; plain
            # phrases as substrings (cheaper, and phrases have word context).
            if cue.startswith("\\") or cue.endswith("\\b") or "\\d" in cue:
                if re.search(cue, q):
                    facets.append(facet)
                    break
            elif cue in q:
                facets.append(facet)
                break
    return facets


def select_sources(
    question: str,
    entities: Optional[Sequence[str]] = None,
    include_literature: bool = True,
    max_sources: int = 14,
) -> List[str]:
    """Pick the evidence sources a question needs (registry ids, deduped, ordered).

    - Facets drive the chemistry/structure/target/pathway/variant/disease sources.
    - A named gene/protein entity adds the 'gene' baseline (identity/function).
    - Literature is always appended (unless disabled) as corroboration.
    - Every id is validated against the registry; unknown/non-live ids are dropped
      so this never asks federated_query for a source it can't serve.
    """
    facets = detect_facets(question)
    if entities and "gene" not in facets:
        # A named target with no specific facet still deserves identity sources.
        facets.append("gene")

    ordered: List[str] = []
    for facet in facets:
        for sid in FACET_SOURCES.get(facet, []):
            if sid not in ordered:
                ordered.append(sid)
    if include_literature:
        for sid in LITERATURE_SOURCES:
            if sid not in ordered:
                ordered.append(sid)

    known = _federation_serveable_ids()
    if known:
        ordered = [sid for sid in ordered if sid in known]
    return ordered[:max_sources]
