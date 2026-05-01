"""
CRISPR screen knowledge integration for BioMate AI assistant.

Uses BioGRID ORCS (Open Repository of CRISPR Screens) to answer questions
about essential genes identified in CRISPR knockout screens.

Two-pass strategy:
1. IDF-weighted candidate fingerprinting: maps candidates → Entrez IDs, queries
   each gene's screen membership, votes for the source screen with IDF weighting
   (genes in few screens = more diagnostic = higher weight)
2. Ranked hit extraction: fetches the ranked hit list from the source screen

API key: stored in config.yaml as external_apis.biogrid_orcs_key

Usage:
    from backend.lib.galaxy.ai.knowledge.crispr_screens import CRISPRScreenKnowledge
    crispr = CRISPRScreenKnowledge()
    context = crispr.lookup_screen(
        cell_line="THP-1",
        perturbation="AZD5576",
        candidate_genes=["CDK7", "CDK9", "CCNT1"]
    )
"""

from __future__ import annotations

import logging
import math
import os
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

_ORCS_KEY = os.environ.get("BIOGRID_ORCS_KEY", "5bec3884b8d8deddaab64c6743ed4cff")


def _genes_to_entrez(gene_symbols: List[str], timeout: int = 5) -> Dict[str, str]:
    """Batch-convert gene symbols to Entrez IDs via MyGene.info."""
    try:
        import requests as _req
        syms = ",".join(gene_symbols[:25])
        r = _req.get(
            "https://mygene.info/v3/query",
            params={"q": syms, "fields": "entrezgene,symbol", "species": "human",
                    "scopes": "symbol", "size": len(gene_symbols)},
            timeout=timeout,
        )
        if r.status_code != 200:
            return {}
        mapping = {}
        for h in r.json().get("hits", []):
            sym = h.get("symbol", "")
            eid = h.get("entrezgene")
            if sym and eid:
                mapping[sym.upper()] = str(int(eid))
        return mapping
    except Exception:
        return {}


def _ranked_hits(screen_id: str, analysis: str, score1_type: str, orcs_key: str,
                 timeout: int = 10) -> List[str]:
    """Fetch ranked hit list from a BioGRID ORCS screen."""
    try:
        import requests as _req
        r = _req.get(
            f"https://orcsws.thebiogrid.org/screen/{screen_id}",
            params={"accesskey": orcs_key, "format": "json", "hit": "yes", "max": 500},
            timeout=timeout,
        )
        if r.status_code != 200 or not r.text.strip():
            return []
        hits_list = r.json()
        if not isinstance(hits_list, list):
            return []
        s1t = (score1_type or "").lower()
        ascending = any(x in s1t for x in ("p-value", "pvalue", "fdr", "rra", "mageck score"))

        def _sort_key(h):
            s = h.get("SCORE.1")
            try:
                return float(s) if s not in (None, "-", "") else (9999.0 if ascending else -9999.0)
            except (ValueError, TypeError):
                return 9999.0 if ascending else -9999.0

        hit_entries = [h for h in hits_list if h.get("HIT") == "YES" and h.get("OFFICIAL_SYMBOL")]
        if not hit_entries:
            hit_entries = [h for h in hits_list if h.get("OFFICIAL_SYMBOL")]
        return [h["OFFICIAL_SYMBOL"] for h in sorted(hit_entries, key=_sort_key, reverse=not ascending)]
    except Exception as exc:
        logger.debug("ORCS ranked hits failed for screen %s: %s", screen_id, exc)
        return []


def lookup_screen(
    cell_line: str,
    perturbation: str,
    candidate_genes: List[str],
    orcs_key: Optional[str] = None,
    timeout: int = 10,
) -> str:
    """
    Query BioGRID ORCS to find the source screen and return its ranked hit list.

    Returns formatted context block for AI injection, or empty string on failure.
    """
    key = orcs_key or _ORCS_KEY
    if not key:
        return ""

    try:
        import requests as _req

        cand_upper = {c.upper() for c in candidate_genes}

        # Pass 1: IDF-weighted candidate fingerprinting
        entrez_map = _genes_to_entrez(list(cand_upper), timeout=min(timeout, 8))
        votes: Dict[str, float] = {}
        for eid in list(entrez_map.values())[:15]:
            r = _req.get(
                f"https://orcsws.thebiogrid.org/gene/{eid}",
                params={"accesskey": key, "format": "json", "hit": "yes"},
                timeout=timeout,
            )
            if r.status_code == 200 and r.text.strip():
                try:
                    gene_screens = r.json() if isinstance(r.json(), list) else []
                    n_screens = max(len(gene_screens), 1)
                    idf_weight = 1.0 / math.log1p(n_screens)
                    for gs in gene_screens:
                        sid = gs.get("SCREEN_ID")
                        if sid:
                            votes[sid] = votes.get(sid, 0.0) + idf_weight
                except Exception:
                    pass

        screen_meta = {}
        best_sid = None

        if votes:
            best_sid = max(votes, key=lambda k: votes[k])
            rm = _req.get(
                "https://orcsws.thebiogrid.org/screens/",
                params={"accesskey": key, "format": "json", "max": 2000},
                timeout=timeout,
            )
            all_screens = rm.json() if rm.status_code == 200 and isinstance(rm.json(), list) else []
            screen_meta = next((s for s in all_screens if s.get("SCREEN_ID") == best_sid), {})
        else:
            # Pass 1 fallback: keyword search by cell line + perturbation
            cl_norm = cell_line.lower().replace("-", "").replace(" ", "") if cell_line else ""
            for cl_q, pert_q in [(cl_norm, perturbation), ("", perturbation), (cl_norm, "")]:
                p = {"accesskey": key, "format": "json", "max": 10}
                if cl_q:
                    p["cellLine"] = cl_q
                if pert_q:
                    p["conditionName"] = pert_q
                rk = _req.get("https://orcsws.thebiogrid.org/screens/", params=p, timeout=timeout)
                if rk.status_code == 200 and rk.text.strip():
                    try:
                        scr = rk.json() if isinstance(rk.json(), list) else []
                    except Exception:
                        scr = []
                    if scr:
                        def _prio(s):
                            return (
                                (10 if "mageck" in s.get("ANALYSIS", "").lower() else 0)
                                + int(s.get("NUMBER_OF_HITS", 0) or 0)
                            )
                        screen_meta = max(scr, key=_prio)
                        best_sid = screen_meta.get("SCREEN_ID")
                        break

        if not best_sid:
            return ""

        analysis = screen_meta.get("ANALYSIS", "unknown")
        score1_type = screen_meta.get("SCORE.1_TYPE", "")
        top_hits = _ranked_hits(best_sid, analysis, score1_type, key, timeout=timeout)
        if not top_hits:
            return ""

        candidates_in_hits = [g for g in top_hits if g.upper() in cand_upper]
        source_id = screen_meta.get("SOURCE_ID", "")
        pmid_str = f"PMID:{source_id}" if screen_meta.get("SOURCE_TYPE") == "pubmed" and source_id else ""
        condition = screen_meta.get("CONDITION_NAME", perturbation or "-")

        lines = [
            f"[BioGRID ORCS — {analysis} Screen {pmid_str}]",
            f"Cell: {screen_meta.get('CELL_LINE', cell_line)}  |  Condition: {condition}",
            f"Ranked hits (strongest effect first, {analysis}):",
        ]
        for rank, g in enumerate(top_hits[:20], 1):
            marker = "  *** IN CANDIDATE LIST ***" if g.upper() in cand_upper else ""
            lines.append(f"  #{rank}: {g}{marker}")
        if candidates_in_hits:
            lines.append(f"\nCANDIDATES IN TOP HITS: {', '.join(candidates_in_hits)}")
            lines.append("→ The FIRST candidate in this ranked list is the correct answer.")
        return "\n".join(lines)

    except Exception as exc:
        logger.debug("BioGRID ORCS query failed: %s", exc)
        return ""


class CRISPRScreenKnowledge:
    """
    High-level interface for CRISPR screen knowledge retrieval.
    Used by ai_assistant.py when users ask about gene essentiality
    or CRISPR screen hits.
    """

    def lookup_screen(
        self,
        cell_line: str,
        perturbation: str,
        candidate_genes: List[str],
        timeout: int = 10,
    ) -> str:
        """
        Query BioGRID ORCS for screen context.
        Returns formatted block for AI prompt injection.
        """
        return lookup_screen(
            cell_line=cell_line,
            perturbation=perturbation,
            candidate_genes=candidate_genes,
            timeout=timeout,
        )

    def get_format_instruction(self) -> str:
        return (
            "IF the context above contains '[BioGRID ORCS' data with "
            "'*** IN CANDIDATE LIST ***' markers:\n"
            "→ The #1 ranked candidate in the ORCS list IS the answer. Trust ORCS completely.\n"
            "IF no ORCS data is available: use gene essentiality knowledge "
            "(essential genes: involved in fundamental cellular processes like "
            "transcription, translation, cell cycle, DNA repair).\n"
            "Respond with ONLY the gene symbol. Nothing else."
        )
