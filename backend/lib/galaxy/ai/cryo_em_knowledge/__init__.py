"""
cryo_em_knowledge — structured cryo-EM protocol knowledge backed by SQLite.

Entry points:
    from galaxy.ai.cryo_em_knowledge import get_retriever, apply_migration, populate_db

Quick start:
    r = get_retriever()
    ctx = r.get_compact_context("saposin_nanodisc")   # inject into prompt
    px  = r.get_parameter("mw_lt50", "pixel_size_angstrom")  # "0.649"
"""

from .retriever import CryoEMKnowledgeRetriever, get_retriever


def apply_migration(db_path: str) -> bool:
    from .schema import apply_migration as _apply
    return _apply(db_path)


def populate_db(db_path: str) -> None:
    from .populate import populate
    populate(db_path)


def build_rag_index(
    docs_dir: str = "/home/yzhang/biomate/docs/cryo_em_skills",
    db_path: str | None = None,
    force: bool = False,
) -> int:
    """
    Build (or rebuild) the semantic RAG index from skill documents.
    Returns number of chunks indexed.

    Set VOYAGE_API_KEY or OPENAI_API_KEY for high-quality semantic embeddings.
    Without an API key, falls back to deterministic hash-based embeddings
    (fast, free, lower semantic quality).
    """
    import os
    if db_path is None:
        db_path = os.environ.get(
            "GALAXY_AI_DB_PATH",
            "/home/yzhang/biomate/backend/galaxy_ai_tools.db"
        )
    import sys
    sys.path.insert(0, os.path.dirname(__file__))
    from rag_index import build_index
    return build_index(docs_dir, db_path, force=force)


__all__ = [
    "CryoEMKnowledgeRetriever",
    "get_retriever",
    "apply_migration",
    "populate_db",
    "build_rag_index",
]
