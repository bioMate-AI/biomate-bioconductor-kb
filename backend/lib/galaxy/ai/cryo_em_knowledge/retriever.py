"""
CryoEMKnowledgeRetriever — SQL-only query interface for cryo_em_* tables.

All methods hit SQLite directly. Zero LLM cost.
The get_compact_context() method returns a structured JSON string suitable
for injection into a system prompt (200-400 tokens).

Usage:
    from galaxy.ai.cryo_em_knowledge.retriever import CryoEMKnowledgeRetriever
    r = CryoEMKnowledgeRetriever(db_path)
    ctx = r.get_compact_context("saposin_nanodisc")  # inject into prompt
    px  = r.get_parameter("saposin_nanodisc", "pixel_size_angstrom")  # "0.649"
"""

from __future__ import annotations

import json
import math
import os
import sqlite3
from functools import lru_cache
from typing import Any

# ---------------------------------------------------------------------------
# BGE model singleton — shared with rag_index.py
# ---------------------------------------------------------------------------

_BGE_MODEL_NAME = "BAAI/bge-small-en-v1.5"
_bge_model = None  # type: ignore[assignment]


def _get_bge_model():
    """Return the cached BGE embedding model (loaded once per process)."""
    global _bge_model
    if _bge_model is None:
        os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
        os.environ.setdefault("HF_DATASETS_OFFLINE", "1")
        from sentence_transformers import SentenceTransformer
        _bge_model = SentenceTransformer(_BGE_MODEL_NAME, device="cpu",
                                         local_files_only=True)
    return _bge_model


# Canonical descriptions used to build per-class BGE centroids.
# Each string is dense enough to encode the semantic space of its class.
_CLASS_DESCRIPTIONS: dict[str, str] = {
    "saposin_nanodisc": (
        "saposin nanodisc membrane protein reconstitution small lipid bilayer scaffold "
        "mfsd vmat lipid scaffold gamma-cyclodextrin POPC POPE POPG molar ratio"
    ),
    "msp_nanodisc_gpcr": (
        "GPCR G protein complex MSP nanodisc opioid receptor dopamine receptor apyrase "
        "scFv16 Gi Gs biased agonism mu-opioid D1R beta-arrestin"
    ),
    "detergent_ion_channel": (
        "detergent solubilized ion channel DDM digitonin GDN calcium channel CaV "
        "voltage-gated potassium channel sodium channel detergent exchange"
    ),
    "liposome_pore_forming": (
        "liposome pore forming protein BAX bcl-2 lipid bilayer ANTS DPX fluorescence "
        "proteoliposome reconstitution membrane insertion apoptosis"
    ),
    "rna_protein_endogenous": (
        "spliceosome ribosome RNA protein complex endogenous purification glycerol gradient "
        "multistate 3DVA cryo-EM flexible RNA binding nucleoprotein"
    ),
    "symmetric_assembly": (
        "symmetric assembly capsid virus icosahedral symmetry expansion T=4 T=7 "
        "HBV AAV symmetry subunit assembly preferred orientation"
    ),
    "cryo_et": (
        "cryo-ET tomography tilt series subtomogram averaging FIB milling lamella "
        "AreTomo2 in-cell cryo-ET missing wedge reconstruction"
    ),
}

_class_centroids: dict[str, list[float]] | None = None  # lazy


def _get_class_centroids() -> dict[str, list[float]]:
    """Compute and cache per-class BGE centroids (called once per worker)."""
    global _class_centroids
    if _class_centroids is None:
        try:
            model = _get_bge_model()
            classes = list(_CLASS_DESCRIPTIONS.keys())
            texts = [_CLASS_DESCRIPTIONS[c] for c in classes]
            vecs = model.encode(texts, normalize_embeddings=True)
            _class_centroids = {c: v.tolist() for c, v in zip(classes, vecs)}
        except Exception:
            _class_centroids = {}
    return _class_centroids


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a)) or 1.0
    nb = math.sqrt(sum(x * x for x in b)) or 1.0
    return dot / (na * nb)


def _format_rag_for_prompt(results: list[dict], max_tokens: int = 500) -> str:
    """Inline format_for_prompt — avoids cross-module import issues."""
    if not results:
        return ""
    lines = ["<cryo_em_knowledge>"]
    budget = max_tokens * 4
    used = 0
    for r in results:
        section = r.get("section") or "General"
        header  = f"[{r.get('source_file', '?')} / {section[:50]}]"
        text    = (r.get("chunk_text") or "").strip()
        snippet = f"{header}\n{text}\n"
        if used + len(snippet) > budget:
            remaining = budget - used - len(header) - 10
            if remaining > 100:
                snippet = f"{header}\n{text[:remaining]}...\n"
            else:
                break
        lines.append(snippet)
        used += len(snippet)
    lines.append("</cryo_em_knowledge>")
    return "\n".join(lines)


class CryoEMKnowledgeRetriever:
    def __init__(self, db_path: str):
        self.db_path = db_path

    # ──────────────────────────────────────────────────────────────────────────
    # Internal helpers
    # ──────────────────────────────────────────────────────────────────────────

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _json_or_raw(self, value: str | None) -> Any:
        """Parse JSON fields; return raw string if not JSON."""
        if value is None:
            return None
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            return value

    def _row_to_dict(self, row: sqlite3.Row) -> dict:
        d = dict(row)
        JSON_FIELDS = {
            "collection_params", "reconstitution_params", "qc_gates",
            "picking_strategy", "refinement_strategy", "model_building",
            "use_cases", "limitations", "key_principles", "tool_requirements",
            "reference_papers", "use_when", "key_parameters", "alternatives",
        }
        for field in JSON_FIELDS:
            if field in d and d[field] is not None:
                d[field] = self._json_or_raw(d[field])
        return d

    # ──────────────────────────────────────────────────────────────────────────
    # Protocol queries
    # ──────────────────────────────────────────────────────────────────────────

    def get_protocol(self, sample_class: str) -> dict | None:
        """Full protocol row for a sample class."""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM cryo_em_protocols WHERE sample_class = ?",
                (sample_class,)
            ).fetchone()
        return self._row_to_dict(row) if row else None

    def list_protocols(self) -> list[dict]:
        """All protocols (id, sample_class, display_name, typical_mw_range_kda)."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT id, sample_class, display_name, typical_mw_range_kda, reconstitution_type "
                "FROM cryo_em_protocols ORDER BY id"
            ).fetchall()
        return [dict(r) for r in rows]

    def search_protocols(self, query: str, limit: int = 5) -> list[dict]:
        """FTS5 search over protocols. Returns ranked rows."""
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT p.sample_class, p.display_name, p.typical_mw_range_kda,
                       p.reconstitution_type, p.use_cases, p.key_principles
                FROM cryo_em_protocols_fts f
                JOIN cryo_em_protocols p ON p.id = f.rowid
                WHERE cryo_em_protocols_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """,
                (query, limit)
            ).fetchall()
        return [self._row_to_dict(r) for r in rows]

    # ──────────────────────────────────────────────────────────────────────────
    # Parameter queries
    # ──────────────────────────────────────────────────────────────────────────

    def get_parameter(self, context: str, parameter: str) -> str | None:
        """Single parameter lookup. Returns raw string value or None."""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT value FROM cryo_em_parameters WHERE context = ? AND parameter = ?",
                (context, parameter)
            ).fetchone()
        return row["value"] if row else None

    def get_parameters_for_context(self, context: str) -> dict[str, str]:
        """All parameters for a context. Returns {parameter: value}."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT parameter, value, unit, rationale "
                "FROM cryo_em_parameters WHERE context = ? ORDER BY parameter",
                (context,)
            ).fetchall()
        return {r["parameter"]: r["value"] for r in rows}

    def get_parameters_for_mw(self, mw_kda: float) -> dict[str, str]:
        """
        Determine the right MW context and return all parameters.
        Merges primary context with overlapping shared contexts
        (mw_lt300 for defocus < 300 kDa; mw_gt600 for large complexes).

        MW ranges: <50, 50-100, 100-300, 300-600, 600-1500, >1500
        """
        if mw_kda < 50:
            primary, secondary = "mw_lt50", ["mw_lt300"]
        elif mw_kda < 100:
            primary, secondary = "mw_50_100", ["mw_lt300"]
        elif mw_kda < 300:
            primary, secondary = "mw_100_300", ["mw_lt300"]
        elif mw_kda < 600:
            primary, secondary = "mw_300_600", []
        elif mw_kda < 1500:
            primary, secondary = "mw_600_1500", ["mw_gt600"]
        else:
            primary, secondary = "mw_gt1500", ["mw_gt600"]

        # Secondary loaded first so primary values override
        params: dict[str, str] = {}
        for ctx in secondary:
            params.update(self.get_parameters_for_context(ctx))
        params.update(self.get_parameters_for_context(primary))
        params["_context"] = primary
        return params

    def get_parameter_with_detail(self, context: str, parameter: str) -> dict | None:
        """Full parameter row including unit and rationale."""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM cryo_em_parameters WHERE context = ? AND parameter = ?",
                (context, parameter)
            ).fetchone()
        return dict(row) if row else None

    # ──────────────────────────────────────────────────────────────────────────
    # Tool queries
    # ──────────────────────────────────────────────────────────────────────────

    def get_tool_status(self, tool_name: str) -> dict | None:
        """BioMate status + gap notes for a specific tool."""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT tool_name, tool_category, biomate_status, biomate_gap_notes, "
                "       use_when, alternatives "
                "FROM cryo_em_tools WHERE tool_name = ?",
                (tool_name,)
            ).fetchone()
        return self._row_to_dict(row) if row else None

    def list_tools_by_status(self, status: str) -> list[dict]:
        """Tools filtered by biomate_status: 'have'|'partial'|'missing'."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT tool_name, tool_category, biomate_status, biomate_gap_notes "
                "FROM cryo_em_tools WHERE biomate_status = ? ORDER BY tool_category, tool_name",
                (status,)
            ).fetchall()
        return [dict(r) for r in rows]

    def get_tools_for_protocol(self, sample_class: str) -> list[dict]:
        """
        Returns tool requirements from the protocol's tool_requirements JSON field.
        Each element: {tool, version, step, status}
        """
        protocol = self.get_protocol(sample_class)
        if not protocol:
            return []
        reqs = protocol.get("tool_requirements", [])
        if isinstance(reqs, str):
            reqs = json.loads(reqs)
        return reqs

    # ──────────────────────────────────────────────────────────────────────────
    # Compact context for prompt injection
    # ──────────────────────────────────────────────────────────────────────────

    def get_compact_context(self, sample_class: str) -> str:
        """
        Returns a compact JSON string (200-400 tokens) for system prompt injection.

        Includes:
          - collection parameters
          - picking + refinement strategy (key fields only)
          - QC gates (name + criterion only)
          - key principles (top 5)
          - limitations (top 3)
          - tool requirements (name + step + status)

        This is what gets injected into the AI prompt — NOT the full markdown docs.
        """
        protocol = self.get_protocol(sample_class)
        if not protocol:
            return json.dumps({"error": f"Unknown sample class: {sample_class}"})

        # Trim QC gates to name + criterion only
        qc_gates = protocol.get("qc_gates", [])
        if isinstance(qc_gates, list):
            qc_gates = [{"name": g.get("name"), "criterion": g.get("criterion")} for g in qc_gates]

        # Key principles: top 5
        key_principles = protocol.get("key_principles", [])[:5]

        # Limitations: top 3
        limitations = protocol.get("limitations", [])[:3]

        # Picking strategy: keep all (it's small)
        picking = protocol.get("picking_strategy", {})

        # Refinement strategy: key fields
        refine = protocol.get("refinement_strategy", {})

        # Tool requirements: name + step + status
        tool_reqs = protocol.get("tool_requirements", [])
        if isinstance(tool_reqs, list):
            tool_reqs = [{"tool": t.get("tool"), "step": t.get("step"), "status": t.get("status")} for t in tool_reqs]

        compact = {
            "sample_class": sample_class,
            "display_name": protocol.get("display_name"),
            "mw_range_kda": protocol.get("typical_mw_range_kda"),
            "collection": protocol.get("collection_params"),
            "picking": picking,
            "refinement": refine,
            "qc_gates": qc_gates,
            "key_principles": key_principles,
            "limitations": limitations,
            "tools": tool_reqs,
        }

        return json.dumps(compact, separators=(",", ":"))

    def get_parameter_table_for_prompt(self) -> str:
        """
        Returns a compact markdown table of MW-based parameters for prompt injection.
        Format: | MW | pixel_size | box_size | defocus | dose |
        ~80 tokens.
        """
        rows = []
        # (context, secondary_contexts, label)
        mw_specs = [
            ("mw_lt50",    ["mw_lt300"],  "<50 kDa"),
            ("mw_50_100",  ["mw_lt300"],  "50-100 kDa"),
            ("mw_100_300", ["mw_lt300"],  "100-300 kDa"),
            ("mw_300_600", [],            "300-600 kDa"),
            ("mw_600_1500",["mw_gt600"],  "600-1500 kDa"),
            ("mw_gt1500",  ["mw_gt600"],  ">1500 kDa"),
        ]
        contexts = [s[0] for s in mw_specs]
        labels   = [s[2] for s in mw_specs]

        with self._connect() as conn:
            for spec, label in zip(mw_specs, labels):
                primary, secondary, _ = spec
                merged: dict[str, str] = {}
                for ctx in secondary:
                    for r in conn.execute(
                        "SELECT parameter, value FROM cryo_em_parameters WHERE context = ?", (ctx,)
                    ).fetchall():
                        merged[r["parameter"]] = r["value"]
                for r in conn.execute(
                    "SELECT parameter, value FROM cryo_em_parameters WHERE context = ?", (primary,)
                ).fetchall():
                    merged[r["parameter"]] = r["value"]
                params = merged
                rows.append({
                    "MW": label,
                    "pixel_size": params.get("pixel_size_angstrom", "—"),
                    "box_size_px": params.get("box_size_px", "—"),
                    "defocus_min_um": params.get("defocus_min_um", "—"),
                    "total_dose": params.get("total_dose_e_per_A2", "—"),
                })

        header = "| MW | pixel_size (Å) | box_size (px) | defocus_min (μm) | total_dose (e⁻/Ų) |"
        sep    = "|---|---|---|---|---|"
        lines  = [header, sep]
        for r in rows:
            lines.append(
                f"| {r['MW']} | {r['pixel_size']} | {r['box_size_px']} | "
                f"{r['defocus_min_um']} | {r['total_dose']} |"
            )
        return "\n".join(lines)

    def get_gap_summary(self) -> dict:
        """
        Returns a summary of BioMate tool gaps.
        {have: [...], partial: [...], missing: [...]}
        """
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT tool_name, biomate_status, biomate_gap_notes FROM cryo_em_tools ORDER BY tool_name"
            ).fetchall()

        result: dict[str, list] = {"have": [], "partial": [], "missing": []}
        for r in rows:
            status = r["biomate_status"]
            entry = {"tool": r["tool_name"]}
            if r["biomate_gap_notes"]:
                entry["note"] = r["biomate_gap_notes"]
            result.setdefault(status, []).append(entry)
        return result

    # ──────────────────────────────────────────────────────────────────────────
    # Sample class detection helpers
    # ──────────────────────────────────────────────────────────────────────────

    def detect_sample_class(self, query: str) -> str | None:
        """
        Hybrid sample class detection: keyword match first (zero-cost),
        then BGE cosine similarity if keywords are inconclusive.

        Returns sample_class string or None if confidence is too low.
        """
        q = query.lower()

        # --- Pass 1: unambiguous keyword signals ---
        keywords_map = [
            ("saposin_nanodisc",       ["saposin", "saposin nanodisc", "mfsd", "vmat"]),
            ("msp_nanodisc_gpcr",      ["gpcr", "g protein", "gi complex", "gs complex", "msp nanodisc",
                                        "opioid receptor", "dopamine receptor", "beta-2 adrenergic",
                                        "scfv16", "apyrase"]),
            ("detergent_ion_channel",  ["detergent", "gdn", "ddm", "digitonin", "ion channel",
                                        "calcium channel", "cav1", "cav2", "potassium channel"]),
            ("liposome_pore_forming",  ["liposome", "pore forming", "bax", "bcl", "ants", "dpx",
                                        "proteoliposome", "membrane pore"]),
            ("rna_protein_endogenous", ["spliceosome", "ribosome", "rnp", "endogenous purification",
                                        "glycerol gradient", "3dva", "multi-state"]),
            ("symmetric_assembly",     ["capsid", "virus", "icosahedral", "t=4", "t=7",
                                        "hbv", "aav", "symmetry expansion"]),
            ("cryo_et",                ["cryo-et", "cryo et", "tomography", "subtomogram",
                                        "tilt series", "fib milling", "lamella", "in-cell"]),
        ]
        for cls, kws in keywords_map:
            for kw in kws:
                if kw in q:
                    return cls

        # --- Pass 2: BGE cosine match as semantic fallback ---
        # Handles indirect phrasing like "my protein is in a lipid bilayer scaffold with saposin A"
        try:
            centroids = _get_class_centroids()
            if not centroids:
                return None
            model = _get_bge_model()
            q_vec = model.encode([query], normalize_embeddings=True)[0].tolist()
            scored = [(cls, _cosine(q_vec, centroid))
                      for cls, centroid in centroids.items()]
            scored.sort(key=lambda x: -x[1])
            best_cls, best_score = scored[0]
            second_score = scored[1][1] if len(scored) > 1 else 0.0
            # Require a clear winner: top score ≥ 0.55 and margin ≥ 0.05
            if best_score >= 0.55 and (best_score - second_score) >= 0.05:
                return best_cls
        except Exception:
            pass

        return None


    # ──────────────────────────────────────────────────────────────────────────
    # RAG — semantic search over chunked skill documents
    # ──────────────────────────────────────────────────────────────────────────

    def _rag_available(self) -> bool:
        """True if the RAG chunk index has been built."""
        try:
            with self._connect() as conn:
                n = conn.execute("SELECT COUNT(*) FROM cryo_em_chunks").fetchone()[0]
                return n > 0
        except Exception:
            return False

    def semantic_search(
        self,
        query: str,
        top_k: int = 5,
        sample_class: str | None = None,
        chunk_type: str | None = None,
    ) -> list[dict]:
        """
        Find the most relevant skill-document chunks for the given query.
        Returns list of {source_file, section, sample_class, chunk_type,
                         entities, chunk_text, score, method}.

        Requires the RAG index to be built first:
            python3 rag_index.py build --db galaxy_ai_tools.db
        """
        try:
            import sys, os
            sys.path.insert(0, os.path.dirname(__file__))
            from rag_index import semantic_search as _search
            return _search(
                query=query,
                db_path=self.db_path,
                top_k=top_k,
                sample_class_filter=sample_class,
                chunk_type_filter=chunk_type,
            )
        except Exception as e:
            import logging
            logging.getLogger(__name__).warning(f"RAG search failed: {e}")
            return []

    def get_full_context(
        self,
        query: str,
        sample_class: str | None = None,
        max_rag_tokens: int = 500,
    ) -> str:
        """
        Combined structured + RAG context for system prompt injection.

        Returns a compact block (600-900 tokens total) containing:
          1. Structured protocol (compact JSON) from cryo_em_protocols — always
          2. Parameter table from cryo_em_parameters — always
          3. Semantic RAG chunks from skill documents — when index is built

        The first two are zero-cost SQL lookups.
        The third adds ~1 embedding API call per query.
        """
        parts = []

        # 1. Structured protocol (from DB, always available)
        if sample_class:
            ctx_json = self.get_compact_context(sample_class)
            if '"error"' not in ctx_json:
                parts.append(f"<cryo_em_protocol>\n{ctx_json}\n</cryo_em_protocol>")

        # 2. Parameter table (always available)
        parts.append(
            "<cryo_em_parameters>\n"
            + self.get_parameter_table_for_prompt()
            + "\n</cryo_em_parameters>"
        )

        # 3. RAG chunks (when index is built)
        if self._rag_available():
            try:
                chunks = self.semantic_search(
                    query, top_k=5, sample_class=sample_class
                )
                if chunks:
                    rag_block = _format_rag_for_prompt(chunks, max_tokens=max_rag_tokens)
                    if rag_block:
                        parts.append(rag_block)
            except Exception as e:
                import logging
                logging.getLogger(__name__).warning(f"RAG inject failed: {e}")

        return "\n\n".join(parts)

    def get_rag_status(self) -> dict:
        """Return RAG index status for diagnostics."""
        try:
            with self._connect() as conn:
                total = conn.execute(
                    "SELECT COUNT(*) FROM cryo_em_chunks"
                ).fetchone()[0]
                by_type = {
                    r[0]: r[1]
                    for r in conn.execute(
                        "SELECT chunk_type, COUNT(*) FROM cryo_em_chunks "
                        "GROUP BY chunk_type ORDER BY chunk_type"
                    ).fetchall()
                }
                vec_count = 0
                try:
                    import sqlite_vec as _sv
                    conn.enable_load_extension(True)
                    _sv.load(conn)
                    conn.enable_load_extension(False)
                    vec_count = conn.execute(
                        "SELECT COUNT(*) FROM cryo_em_chunks_vec"
                    ).fetchone()[0]
                except Exception:
                    pass
            return {
                "total_chunks": total,
                "vec_indexed": vec_count,
                "by_type": by_type,
                "available": total > 0,
            }
        except Exception:
            return {"available": False, "total_chunks": 0}


# ──────────────────────────────────────────────────────────────────────────────
# Module-level singleton factory (avoids repeated instantiation)
# ──────────────────────────────────────────────────────────────────────────────

_instance: CryoEMKnowledgeRetriever | None = None


def get_retriever(db_path: str | None = None) -> CryoEMKnowledgeRetriever:
    global _instance
    if _instance is None:
        if db_path is None:
            import os
            db_path = os.environ.get(
                "GALAXY_AI_DB_PATH",
                "/home/yzhang/biomate/backend/galaxy_ai_tools.db"
            )
        _instance = CryoEMKnowledgeRetriever(db_path)
    return _instance
