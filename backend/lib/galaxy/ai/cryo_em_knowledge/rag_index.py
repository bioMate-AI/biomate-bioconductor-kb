"""
cryo_em_knowledge/rag_index.py — Build and query a semantic RAG index over
the cryo-EM skill documents stored in docs/cryo_em_skills/.

Architecture
============
• All vectors live in galaxy_ai_tools.db (no external vector DB).
• sqlite-vec extension provides fast ANN search over float32 embeddings.
• Two new tables:
    cryo_em_chunks      — chunked text + metadata
    cryo_em_chunks_vec  — vector index (linked to cryo_em_chunks by rowid)
• Embeddings are generated once via Anthropic text-embedding-3-small
  (or a local fallback using TF-IDF cosine similarity if no API key).
• The retriever.py semantic_search() method calls this index.

Cost
====
• One-time build: ~45,000 words / 750 ≈ 60 chunks × $0.00002 = $0.0012
• Per-query: 1 embedding call ($0.0001) + SQL ANN search (free)

Usage
=====
    # Build the index (run once)
    python3 rag_index.py build \
        --docs /home/yzhang/biomate/docs/cryo_em_skills \
        --db   /home/yzhang/biomate/backend/galaxy_ai_tools.db

    # Test search
    python3 rag_index.py search \
        --query "saposin reconstitution failed, aggregates" \
        --db    /home/yzhang/biomate/backend/galaxy_ai_tools.db

    # Status
    python3 rag_index.py status \
        --db /home/yzhang/biomate/backend/galaxy_ai_tools.db
"""

from __future__ import annotations

import argparse
import json
import os

# Force CPU for sentence-transformers — the production GPU (NVIDIA GB10, sm_121)
# is not compatible with the installed PyTorch build.
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")
import re
import sqlite3
import struct
import sys
import textwrap
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Sample-class tags inferred from filename
# ---------------------------------------------------------------------------
_FILE_TO_SAMPLE_CLASS = {
    "00_GENERAL_FRAMEWORK": "general",
    "01_MFSD2B_preprint":   "saposin_nanodisc",
    "02_VMAT2_nature2023":  "saposin_nanodisc",
    "03_CaV1_2_cell2023":   "detergent_ion_channel",
    "04_BAX_pore_science2025": "liposome_pore_forming",
    "05_muOR_cell2022":     "msp_nanodisc_gpcr",
    "06_D1_PAM_preprint2025": "msp_nanodisc_gpcr",
    "07_spliceosome_multistate": "rna_protein_endogenous",
    "08_symmetric_assembly_capsid": "symmetric_assembly",
}

_CHUNK_TOKEN_TARGET = 350   # ~350 tokens per chunk (≈ 1400 chars)
_CHUNK_OVERLAP_LINES = 3    # lines of overlap between consecutive chunks


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS cryo_em_chunks (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    source_file  TEXT NOT NULL,
    section      TEXT,
    sample_class TEXT,
    chunk_type   TEXT,
    entities     TEXT,
    chunk_index  INTEGER,
    chunk_text   TEXT NOT NULL,    -- full_text: context_header + body (embedded)
    chunk_body   TEXT,             -- body only (for display)
    char_count   INTEGER,
    indexed_at   TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_cryo_em_chunks_class
    ON cryo_em_chunks(sample_class);

CREATE INDEX IF NOT EXISTS idx_cryo_em_chunks_file
    ON cryo_em_chunks(source_file);

CREATE INDEX IF NOT EXISTS idx_cryo_em_chunks_type
    ON cryo_em_chunks(chunk_type);
"""

MIGRATION_NAME = "cryo_em_rag_v1"


# ---------------------------------------------------------------------------
# Vector helpers
# ---------------------------------------------------------------------------

def _load_vec_extension(conn: sqlite3.Connection) -> bool:
    try:
        import sqlite_vec
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
        conn.enable_load_extension(False)
        return True
    except Exception as e:
        print(f"  [WARN] sqlite-vec not available: {e}", file=sys.stderr)
        return False


def _serialize(vec: list[float]) -> bytes:
    return struct.pack(f"{len(vec)}f", *vec)


def _deserialize(blob: bytes) -> list[float]:
    n = len(blob) // 4
    return list(struct.unpack(f"{n}f", blob))


# ---------------------------------------------------------------------------
# Embedding
# ---------------------------------------------------------------------------

def _embed_with_anthropic(texts: list[str], api_key: str) -> list[list[float]]:
    """
    Embed texts using Anthropic's text-embedding API via the SDK.
    Falls back to TF-IDF mock if API call fails.
    """
    import anthropic
    client = anthropic.Anthropic(api_key=api_key)
    results = []
    for i, text in enumerate(texts):
        try:
            resp = client.messages.create(
                model="gemini-3.5-flash",
                max_tokens=1,
                messages=[{"role": "user", "content": text}],
                system="Return a single token.",
            )
            # Anthropic doesn't have a dedicated embedding endpoint yet —
            # use the response's hidden logprobs approximation.
            # For now we fall back to the deterministic mock.
            raise NotImplementedError("Anthropic embedding endpoint not yet public")
        except Exception:
            # Deterministic fallback: project text into 384-dim space
            # using character n-gram hashing (reproducible, no LLM cost,
            # poor semantic quality — swap for OpenAI/Voyage when available)
            vec = _tfidf_mock_embed(text)
            results.append(vec)
        if (i + 1) % 10 == 0:
            print(f"  Embedded {i+1}/{len(texts)}")
    return results


def _tfidf_mock_embed(text: str, dim: int = 384) -> list[float]:
    """
    Deterministic pseudo-embedding via character n-gram hashing.
    Used as fallback when no embedding API is available.
    Provides reproducible results; semantic quality is limited.
    """
    import hashlib, math
    vec = [0.0] * dim
    words = re.findall(r"\b\w+\b", text.lower())
    for word in words:
        h = int(hashlib.md5(word.encode()).hexdigest(), 16)
        idx = h % dim
        vec[idx] += 1.0
    # L2-normalize
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [x / norm for x in vec]


def _embed_with_voyage(texts: list[str], api_key: str) -> list[list[float]]:
    """Embed with Voyage AI (voyage-2 or voyage-code-2). Best quality."""
    import voyageai
    client = voyageai.Client(api_key=api_key)
    result = client.embed(texts, model="voyage-2", input_type="document")
    return result.embeddings


def _has_embedding_blob_column(conn: sqlite3.Connection) -> bool:
    """Return True if cryo_em_chunks has an embedding_blob column."""
    try:
        cols = [r[1] for r in conn.execute("PRAGMA table_info(cryo_em_chunks)").fetchall()]
        return "embedding_blob" in cols
    except Exception:
        return False


# Module-level singleton — loaded once per process, reused on every query call.
# Using BAAI/bge-small-en-v1.5: 384-dim, MTEB 62.17 (+9% vs MiniLM), same size.
_BGE_MODEL_NAME = "BAAI/bge-small-en-v1.5"
_bge_model = None  # type: ignore[assignment]


def _get_bge_model():
    """Return the cached BGE model, loading it on first call.

    Forces offline mode (TRANSFORMERS_OFFLINE=1) so the server never attempts
    a HuggingFace network check — the model is already cached locally.
    """
    global _bge_model
    if _bge_model is None:
        # Prevent huggingface_hub from attempting network calls — model is cached.
        os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
        os.environ.setdefault("HF_DATASETS_OFFLINE", "1")
        from sentence_transformers import SentenceTransformer
        print(f"  [INFO] Loading {_BGE_MODEL_NAME} (device=cpu, offline)", file=sys.stderr)
        _bge_model = SentenceTransformer(_BGE_MODEL_NAME, device="cpu",
                                         local_files_only=True)
    return _bge_model


def get_embeddings(texts: list[str]) -> list[list[float]]:
    """
    Embed texts using the best available provider.
    Priority: Voyage AI > BAAI/bge-small-en-v1.5 (local) > deterministic hash.
    Set VOYAGE_API_KEY in environment to use Voyage AI (highest quality).
    """
    if os.environ.get("VOYAGE_API_KEY"):
        print("  Using Voyage AI for embeddings (best semantic quality)")
        try:
            return _embed_with_voyage(texts, os.environ["VOYAGE_API_KEY"])
        except Exception as e:
            print(f"  [WARN] Voyage AI failed: {e}")

    # BGE-small-en-v1.5: local, no API key, best semantic quality available locally.
    # Model is cached at module level to avoid reloading on every query.
    try:
        model = _get_bge_model()
        vecs = model.encode(texts, show_progress_bar=len(texts) > 20,
                            normalize_embeddings=True)
        return [v.tolist() for v in vecs]
    except Exception as e:
        print(f"  [WARN] BGE embedding failed: {e}", file=sys.stderr)

    print("  [INFO] Using deterministic hash fallback (poor semantic quality).", file=sys.stderr)
    return [_tfidf_mock_embed(t) for t in texts]


# ---------------------------------------------------------------------------
# Chunking
# ---------------------------------------------------------------------------

def _extract_section(line: str) -> Optional[str]:
    """Extract heading text from markdown heading lines (# or ##)."""
    m = re.match(r"^#{1,3}\s+(.+)", line)
    return m.group(1).strip() if m else None


def chunk_markdown(text: str, source_file: str,
                   sample_class: str = "general") -> list[dict]:
    """
    Structural chunker: delegates to rag_chunker.chunk_document.
    Returns list of dicts compatible with the rest of rag_index.py.
    Each chunk carries a self-contained context header.
    """
    try:
        from .rag_chunker import chunk_document, chunk_general_framework
    except ImportError:
        import importlib, sys as _sys
        _sys.path.insert(0, str(Path(__file__).parent))
        _mod = importlib.import_module("rag_chunker")
        chunk_document = _mod.chunk_document
        chunk_general_framework = _mod.chunk_general_framework

    if "00_GENERAL_FRAMEWORK" in source_file:
        chunks = chunk_general_framework(text, source_file)
    else:
        chunks = chunk_document(text, source_file, sample_class)

    return [
        {
            "source_file": c.source_file,
            "section":     " > ".join(c.section_path) if c.section_path else "General",
            "chunk_type":  c.chunk_type,
            "chunk_text":  c.full_text,       # header + body (what gets embedded)
            "chunk_body":  c.chunk_body,
            "entities":    ",".join(c.entities),
            "char_count":  c.char_count,
            "chunk_index": c.chunk_index,
        }
        for c in chunks
    ]


# ---------------------------------------------------------------------------
# Build index
# ---------------------------------------------------------------------------

def build_index(docs_dir: str, db_path: str, force: bool = False) -> int:
    """
    Chunk all markdown files in docs_dir, embed them, and store in db_path.
    Returns number of chunks indexed.
    """
    docs_path = Path(docs_dir)
    md_files = sorted(docs_path.glob("*.md"))
    # Exclude index file (it's a table of contents, not knowledge)
    md_files = [f for f in md_files if f.stem != "00_INDEX"]

    print(f"Found {len(md_files)} skill documents in {docs_dir}")

    conn = sqlite3.connect(db_path)
    has_vec = _load_vec_extension(conn)

    # Apply schema
    conn.executescript(SCHEMA_SQL)

    # Check if vec table exists
    if has_vec:
        # Detect embedding dimension from existing rows or default
        try:
            sample = conn.execute(
                "SELECT embedding FROM cryo_em_chunks_vec LIMIT 1"
            ).fetchone()
            if sample:
                dim = len(_deserialize(sample[0]))
            else:
                dim = 384  # default for hash fallback; 1536 for OpenAI
        except Exception:
            dim = 384

        # Recreate vec table if force
        if force:
            try:
                conn.execute("DROP TABLE IF EXISTS cryo_em_chunks_vec")
            except Exception:
                pass

        # Create vec table (ignore if exists)
        try:
            conn.execute(
                f"CREATE VIRTUAL TABLE IF NOT EXISTS cryo_em_chunks_vec "
                f"USING vec0(embedding float[{dim}])"
            )
        except Exception as e:
            print(f"  [WARN] Could not create vec table: {e}")
            has_vec = False

    conn.commit()

    # Check migration
    try:
        cur = conn.execute(
            "SELECT id FROM schema_migrations WHERE migration_name = ?",
            (MIGRATION_NAME,)
        )
        if cur.fetchone() and not force:
            existing = conn.execute(
                "SELECT COUNT(*) FROM cryo_em_chunks"
            ).fetchone()[0]
            print(f"RAG index already built ({existing} chunks). Use --force to rebuild.")
            return existing
    except Exception:
        pass  # schema_migrations may not exist

    # Clear existing chunks
    if force:
        conn.execute("DELETE FROM cryo_em_chunks")
        if has_vec:
            try:
                conn.execute("DELETE FROM cryo_em_chunks_vec")
            except Exception:
                pass
        conn.commit()

    # Chunk all documents
    all_chunks = []
    for md_file in md_files:
        stem_key = next(
            (k for k in _FILE_TO_SAMPLE_CLASS if k in md_file.stem),
            "general"
        )
        sample_class = _FILE_TO_SAMPLE_CLASS.get(stem_key, "general")
        text = md_file.read_text(encoding="utf-8")
        chunks = chunk_markdown(text, md_file.name, sample_class=sample_class)
        for c in chunks:
            c["sample_class"] = sample_class
        all_chunks.extend(chunks)
        print(f"  {md_file.name}: {len(chunks)} chunks ({sample_class})")

    print(f"\nTotal chunks: {len(all_chunks)}")
    print("Generating embeddings...")

    texts = [c["chunk_text"] for c in all_chunks]
    embeddings = get_embeddings(texts)
    dim = len(embeddings[0])
    print(f"Embedding dimension: {dim}")

    # Recreate vec table with correct dimension
    if has_vec:
        try:
            conn.execute("DROP TABLE IF EXISTS cryo_em_chunks_vec")
            conn.execute(
                f"CREATE VIRTUAL TABLE cryo_em_chunks_vec "
                f"USING vec0(embedding float[{dim}])"
            )
        except Exception as e:
            print(f"  [WARN] vec table recreation failed: {e}")
            has_vec = False

    # Ensure embedding_blob column exists in cryo_em_chunks
    try:
        conn.execute("ALTER TABLE cryo_em_chunks ADD COLUMN embedding_blob BLOB")
        conn.commit()
    except Exception:
        pass  # Column already exists

    # Insert chunks + vectors
    for chunk, emb in zip(all_chunks, embeddings):
        emb_blob = _serialize(emb)
        cur = conn.execute(
            """INSERT INTO cryo_em_chunks
               (source_file, section, sample_class, chunk_type, entities,
                chunk_index, chunk_text, chunk_body, char_count, embedding_blob)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                chunk["source_file"],
                chunk.get("section"),
                chunk["sample_class"],
                chunk.get("chunk_type", "general"),
                chunk.get("entities", ""),
                chunk["chunk_index"],
                chunk["chunk_text"],     # full_text (header+body) — what gets embedded
                chunk.get("chunk_body", chunk["chunk_text"]),
                chunk["char_count"],
                emb_blob,               # sentence-transformer vector stored as BLOB
            )
        )
        row_id = cur.lastrowid

        if has_vec:
            try:
                conn.execute(
                    "INSERT INTO cryo_em_chunks_vec(rowid, embedding) VALUES (?, ?)",
                    (row_id, emb_blob)
                )
            except Exception as e:
                print(f"  [WARN] Vec insert failed row {row_id}: {e}")

    # Record migration
    try:
        conn.execute(
            "INSERT OR REPLACE INTO schema_migrations (migration_name, applied_at, status) "
            "VALUES (?, datetime('now'), 'applied')",
            (MIGRATION_NAME,)
        )
    except Exception:
        pass

    conn.commit()
    conn.close()

    print(f"\nRAG index built: {len(all_chunks)} chunks, dim={dim}, vec={has_vec}")
    return len(all_chunks)


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

def semantic_search(
    query: str,
    db_path: str,
    top_k: int = 5,
    sample_class_filter: Optional[str] = None,
    chunk_type_filter: Optional[str] = None,
) -> list[dict]:
    """
    Find the top_k most relevant chunks for the given query.
    Uses sqlite-vec ANN if available; falls back to brute-force cosine.
    Returns list of {source_file, section, sample_class, chunk_text, score}.
    """
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    has_vec = _load_vec_extension(conn)

    # Check if index exists
    count = conn.execute("SELECT COUNT(*) FROM cryo_em_chunks").fetchone()[0]
    if count == 0:
        conn.close()
        return []

    # Embed query
    query_vecs = get_embeddings([query])
    query_vec = query_vecs[0]
    q_blob = _serialize(query_vec)

    results = []

    if has_vec:
        try:
            sql = """
                SELECT c.source_file, c.section, c.sample_class, c.chunk_type,
                       c.entities, c.chunk_body, v.distance AS score
                FROM cryo_em_chunks_vec v
                JOIN cryo_em_chunks c ON c.id = v.rowid
                WHERE v.embedding MATCH ? AND k = ?
                ORDER BY v.distance
            """
            rows = conn.execute(sql, (q_blob, top_k * 3)).fetchall()

            # Post-filter (sqlite-vec WHERE clause is limited)
            if sample_class_filter:
                rows = [r for r in rows if r["sample_class"] == sample_class_filter]
            if chunk_type_filter:
                rows = [r for r in rows if r["chunk_type"] == chunk_type_filter]
            rows = rows[:top_k]

            results = [
                {
                    "source_file":  r["source_file"],
                    "section":      r["section"],
                    "sample_class": r["sample_class"],
                    "chunk_type":   r["chunk_type"],
                    "entities":     r["entities"],
                    "chunk_text":   r["chunk_body"] or "",   # display body only
                    "score":        float(r["score"]),
                    "method":       "vec_ann",
                }
                for r in rows
            ]
        except Exception as e:
            print(f"  [WARN] ANN search failed ({e}), falling back to brute force")
            has_vec = False

    if not has_vec or not results:
        # Brute-force cosine similarity using stored embedding_blob when available,
        # falling back to hash-based re-embedding.
        import math
        where_parts = []
        params: list = []
        if sample_class_filter:
            where_parts.append("sample_class = ?")
            params.append(sample_class_filter)
        where = ("WHERE " + " AND ".join(where_parts)) if where_parts else ""

        rows = conn.execute(
            f"SELECT id, source_file, section, sample_class, chunk_text, chunk_body, "
            f"chunk_type, entities, embedding_blob "
            f"FROM cryo_em_chunks {where}",
            params
        ).fetchall() if _has_embedding_blob_column(conn) else conn.execute(
            f"SELECT id, source_file, section, sample_class, chunk_text, chunk_body, "
            f"chunk_type, entities "
            f"FROM cryo_em_chunks {where}",
            params
        ).fetchall()

        def cosine(a: list[float], b: list[float]) -> float:
            dot = sum(x * y for x, y in zip(a, b))
            na = math.sqrt(sum(x * x for x in a)) or 1.0
            nb = math.sqrt(sum(x * x for x in b)) or 1.0
            return dot / (na * nb)

        scored = []
        for r in rows:
            r_dict = dict(r) if hasattr(r, "keys") else {
                "id": r[0], "source_file": r[1], "section": r[2],
                "sample_class": r[3], "chunk_text": r[4],
                "chunk_body": r[5] if len(r) > 5 else r[4],
                "chunk_type": r[6] if len(r) > 6 else "general",
                "entities": r[7] if len(r) > 7 else "",
                "embedding_blob": r[8] if len(r) > 8 else None,
            }
            blob = r_dict.get("embedding_blob")
            if blob:
                chunk_vec = _deserialize(blob)
            else:
                chunk_vec = _tfidf_mock_embed(r_dict.get("chunk_text", ""))
            sim = cosine(query_vec, chunk_vec)
            scored.append((sim, r_dict))

        scored.sort(key=lambda x: x[0], reverse=True)
        results = [
            {
                "source_file": r.get("source_file", ""),
                "section": r.get("section", ""),
                "sample_class": r.get("sample_class", ""),
                "chunk_type": r.get("chunk_type", "general"),
                "entities": r.get("entities", ""),
                "chunk_text": r.get("chunk_body") or r.get("chunk_text", ""),
                "score": sim,
                "method": "brute_cosine_blob" if r.get("embedding_blob") else "brute_cosine_hash",
            }
            for sim, r in scored[:top_k]
        ]

    conn.close()
    return results


def format_for_prompt(results: list[dict], max_tokens: int = 800) -> str:
    """
    Format retrieved chunks for injection into a system prompt.
    Respects token budget.
    """
    if not results:
        return ""

    lines = ["<cryo_em_knowledge>"]
    budget = max_tokens * 4  # rough chars-per-token
    used = 0

    for r in results:
        header = f"[{r['source_file']} / {r['section']}]"
        text = r["chunk_text"].strip()
        snippet = f"{header}\n{text}\n"
        if used + len(snippet) > budget:
            # Truncate to fit
            remaining = budget - used - len(header) - 10
            if remaining > 100:
                snippet = f"{header}\n{text[:remaining]}...\n"
            else:
                break
        lines.append(snippet)
        used += len(snippet)

    lines.append("</cryo_em_knowledge>")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

def print_status(db_path: str) -> None:
    conn = sqlite3.connect(db_path)
    try:
        total = conn.execute("SELECT COUNT(*) FROM cryo_em_chunks").fetchone()[0]
        by_class = conn.execute(
            "SELECT sample_class, COUNT(*) as n FROM cryo_em_chunks GROUP BY sample_class ORDER BY n DESC"
        ).fetchall()
        by_file = conn.execute(
            "SELECT source_file, COUNT(*) as n FROM cryo_em_chunks GROUP BY source_file ORDER BY source_file"
        ).fetchall()

        print(f"\nRAG Index Status — {db_path}")
        print(f"  Total chunks: {total}")
        print("\n  By sample class:")
        for row in by_class:
            print(f"    {row[0]:35s}  {row[1]} chunks")
        print("\n  By source file:")
        for row in by_file:
            print(f"    {row[0]:45s}  {row[1]} chunks")

        # Check vec table
        has_vec = _load_vec_extension(conn)
        if has_vec:
            try:
                vec_count = conn.execute(
                    "SELECT COUNT(*) FROM cryo_em_chunks_vec"
                ).fetchone()[0]
                print(f"\n  Vector index: {vec_count} vectors embedded")
            except Exception:
                print("\n  Vector index: NOT BUILT (run build first)")
        else:
            print("\n  Vector index: sqlite-vec not available")
    except Exception as e:
        print(f"  Index not built yet: {e}")
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="CryoEM RAG index builder")
    sub = parser.add_subparsers(dest="command")

    # build
    p_build = sub.add_parser("build", help="Build the RAG index")
    p_build.add_argument("--docs", default="/home/yzhang/biomate/docs/cryo_em_skills")
    p_build.add_argument("--db",   default="/home/yzhang/biomate/backend/galaxy_ai_tools.db")
    p_build.add_argument("--force", action="store_true", help="Rebuild even if already built")

    # search
    p_search = sub.add_parser("search", help="Test semantic search")
    p_search.add_argument("--query", required=True)
    p_search.add_argument("--db",    default="/home/yzhang/biomate/backend/galaxy_ai_tools.db")
    p_search.add_argument("--top_k", type=int, default=5)
    p_search.add_argument("--class", dest="sample_class")

    # status
    p_status = sub.add_parser("status", help="Print index stats")
    p_status.add_argument("--db", default="/home/yzhang/biomate/backend/galaxy_ai_tools.db")

    args = parser.parse_args()

    if args.command == "build":
        build_index(args.docs, args.db, force=args.force)

    elif args.command == "search":
        results = semantic_search(args.query, args.db, top_k=args.top_k,
                                   sample_class_filter=args.sample_class)
        if not results:
            print("No results (index may not be built yet)")
            return
        for i, r in enumerate(results, 1):
            print(f"\n--- Result {i} (score={r['score']:.4f}, method={r['method']}) ---")
            print(f"File: {r['source_file']}  Section: {r['section']}")
            print(f"Sample class: {r['sample_class']}")
            print(textwrap.fill(r["chunk_text"][:400], width=80))

    elif args.command == "status":
        print_status(args.db)

    else:
        parser.print_help()


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).parent.parent.parent))
    main()
