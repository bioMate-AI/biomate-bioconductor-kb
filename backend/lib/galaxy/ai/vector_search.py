"""
Vector Embedding Search for Galaxy Tools

Uses sentence-transformers to create embeddings for semantic similarity search.
This enables finding tools even when queries don't match exact keywords.

Example:
- Query: "protein database search"
- Matches: "Query Uniprot" (via semantic similarity)
"""

import sqlite3
import logging
import threading
from pathlib import Path
from typing import List, Dict, Any, Optional
import numpy as np

log = logging.getLogger(__name__)

# Side-channel so a caller/aggregator can tell "[] because the search ERRORED"
# (embed server down, dtype/DB failure — an infra outage) from "[] no matches".
# search() still returns a list; a caller reads this right after the call. Without
# it, an outage surfaces to the user as "no tools match" (a fake content result).
_vs_tls = threading.local()


def last_vector_search_error() -> Optional[str]:
    """Reason the most recent search() on THIS thread errored, or None (reset per call)."""
    return getattr(_vs_tls, "error", None)

# Try to import sentence-transformers, gracefully degrade if not available. Catch any import-time
# failure (not just ImportError): a binary-broken optional dep — e.g. a scipy/numpy ABI mismatch
# that raises TypeError/OSError while importing — must degrade like a missing one, never crash init.
try:
    from sentence_transformers import SentenceTransformer
    SENTENCE_TRANSFORMERS_AVAILABLE = True
except Exception as _st_exc:  # noqa: BLE001
    SENTENCE_TRANSFORMERS_AVAILABLE = False
    log.warning("sentence-transformers unavailable (%s). Vector search will be disabled.", _st_exc)


# Bump when the embedded-text recipe changes so cached vectors are recomputed
# even if the underlying DB rows are unchanged (per-row hash + DB signature fold
# this in). "shorttext" = name/desc/category/help/tags/edam only — NOT
# scientific_context (that's large and already drives EnhancedToolSearch scoring,
# so embedding it too was redundant and made the 12k build impractically slow).
_EMBED_RECIPE = "shorttext-v1"  # redeploy-tag


def _detect_device_safe(timeout_seconds: float = 5.0) -> str:
    """
    Safely detect if CUDA is available with a timeout.

    Some systems have CUDA driver issues that cause torch.cuda.is_available()
    to hang indefinitely. This function uses a timeout to detect such cases
    and falls back to CPU.

    Returns:
        'cuda' if CUDA is available and working, 'cpu' otherwise
    """
    import threading
    import queue

    result_queue = queue.Queue()

    def check_cuda():
        try:
            import torch
            if torch.cuda.is_available():
                # Also test that CUDA actually works
                try:
                    torch.tensor([1.0]).cuda()
                    result_queue.put('cuda')
                except Exception:
                    result_queue.put('cpu')
            else:
                result_queue.put('cpu')
        except Exception:
            result_queue.put('cpu')

    thread = threading.Thread(target=check_cuda, daemon=True)
    thread.start()
    thread.join(timeout=timeout_seconds)

    if thread.is_alive():
        log.warning(f"CUDA detection timed out after {timeout_seconds}s, falling back to CPU")
        return 'cpu'

    try:
        return result_queue.get_nowait()
    except queue.Empty:
        return 'cpu'


class VectorToolSearch:
    """
    Semantic search using vector embeddings.

    Pre-computes embeddings for all tools and enables fast similarity search.
    Falls back gracefully if sentence-transformers is not installed.
    """

    # BAAI/bge-small-en-v1.5: 384 dimensions, MTEB 62.17 (+9% recall vs MiniLM)
    # Benchmarked in docs/20260121_AI_TOOLS_COMPARISON.md — chosen as the standard model.
    DEFAULT_MODEL = 'BAAI/bge-small-en-v1.5'

    def __init__(
        self,
        db_path: str,
        model_name: str = None,
        embedding_path: str = None,
        auto_create: bool = True,
        device: str = None
    ):
        """
        Initialize vector search.

        Args:
            db_path: Path to galaxy_ai_tools.db
            model_name: Sentence transformer model name
            embedding_path: Path to save/load embeddings (default: db_path with .npz)
            auto_create: Automatically create embeddings if not found
            device: Device to use ('cpu', 'cuda', or None for auto-detect with timeout)
        """
        self.db_path = db_path
        self.model_name = model_name or self.DEFAULT_MODEL
        self.embedding_path = embedding_path or db_path.replace('.db', '_embeddings.npz')
        self.auto_create = auto_create
        self.device = device

        self.model = None
        self.tool_ids: List[str] = []
        self.embeddings: Optional[np.ndarray] = None
        self._initialized = False
        self._use_server = False   # prefer the shared embed_server over in-process ST

        # Prefer the shared embed server (bge-small, same model) so we don't load
        # a SentenceTransformer per gunicorn worker. Fall back to in-process ST.
        if self._embed_server_available() or SENTENCE_TRANSFORMERS_AVAILABLE:
            self._initialize()
        else:
            log.warning("Vector search disabled - no embed server and no sentence-transformers")

    @staticmethod
    def _embed_server_available() -> bool:
        try:
            from galaxy.ai.embed_client import get_client
            return get_client().available()
        except Exception:
            return False

    def _initialize(self):
        """Load embeddings; use the shared embed server if up, else in-process ST."""
        try:
            if self._embed_server_available():
                self._use_server = True
                log.info("[VectorSearch] Embed server available — skipping in-process model load")
            else:
                # Determine device - use safe detection if not specified
                if self.device is None:
                    self.device = _detect_device_safe(timeout_seconds=5.0)
                    log.info(f"Auto-detected device: {self.device}")
                log.info(f"Loading sentence transformer model: {self.model_name} on {self.device}")
                self.model = SentenceTransformer(self.model_name, device=self.device,
                                                 local_files_only=True)

            # Doc-embedding source, in preference order:
            #   1. tools.embedding BLOB column — DB-NATIVE. Propagates with the DB
            #      via the normal sync, updated incrementally per tool at enrichment
            #      time (mirrors cryo_em_chunks.embedding_blob). This is the real home.
            #   2. shipped/legacy .npz artifact (transitional; being retired).
            #   3. build from scratch (last resort).
            if self._load_from_db_column():
                log.info("[VectorSearch] loaded %d embeddings from tools.embedding column",
                         len(self.tool_ids))
            elif Path(self.embedding_path).exists():
                self._load_embeddings()
                if getattr(self, '_shipped', False):
                    log.info("[VectorSearch] using shipped .npz artifact — skipping staleness rebuild")
                elif self.auto_create and self._embeddings_stale():
                    log.info("[VectorSearch] .npz is stale vs DB — rebuilding")
                    self._create_embeddings()
            elif self.auto_create:
                self._create_embeddings()
            else:
                log.warning(f"Embeddings not found at {self.embedding_path}")

            self._initialized = True
            log.info(f"Vector search initialized with {len(self.tool_ids)} tools")

        except Exception as e:
            log.error(f"Failed to initialize vector search: {e}")
            self._initialized = False

    def _lazy_load_model(self):
        """Last-resort in-process model load — used only if the embed server is
        preferred but a call fails (e.g. server not yet restarted with a new op)."""
        if self.model is not None or not SENTENCE_TRANSFORMERS_AVAILABLE:
            return
        try:
            if self.device is None:
                self.device = _detect_device_safe(timeout_seconds=5.0)
            log.warning("[VectorSearch] embed server unusable — loading in-process ST fallback")
            self.model = SentenceTransformer(self.model_name, device=self.device,
                                             local_files_only=True)
        except Exception as exc:
            log.error("[VectorSearch] in-process ST fallback load failed: %s", exc)

    def _encode_batch(self, texts):
        """Encode a batch of texts to a (N,384) matrix via the shared embed
        server (bge, no in-worker model), falling back to in-process ST. None on
        total failure."""
        if self._use_server:
            try:
                from galaxy.ai.embed_client import get_client
                vecs = get_client().encode_batch_wf(texts)
                if vecs is not None:
                    return vecs
                log.warning("[VectorSearch] embed server batch failed; falling back to in-process")
            except Exception as exc:
                log.warning("[VectorSearch] embed server batch error: %s", exc)
        if self.model is None:
            self._lazy_load_model()
        if self.model is not None:
            return self.model.encode(texts, batch_size=64, convert_to_numpy=True)
        return None

    def _encode_query(self, text):
        """Encode one query to a (384,) vector via the shared embed server, else ST."""
        if self._use_server:
            try:
                from galaxy.ai.embed_client import get_client
                vec = get_client().encode_wf(text)
                if vec is not None:
                    return vec
            except Exception as exc:
                log.warning("[VectorSearch] embed server query error: %s", exc)
        if self.model is None:
            self._lazy_load_model()
        if self.model is not None:
            return self.model.encode([text], convert_to_numpy=True)[0]
        return None

    def _load_from_db_column(self) -> bool:
        """Load doc embeddings from the tools.embedding BLOB column — the DB-native
        home (propagates with the DB, incremental per tool). Returns True iff it
        loaded a non-empty set. No model/extension needed to READ (plain BLOBs +
        numpy); the query is still encoded via the embed server / ST."""
        import struct
        try:
            conn = sqlite3.connect(self.db_path)
            cols = {r[1] for r in conn.execute("PRAGMA table_info(tools)")}
            if "embedding" not in cols:
                conn.close()
                return False
            rows = conn.execute(
                "SELECT tool_id, embedding FROM tools WHERE embedding IS NOT NULL"
            ).fetchall()
            conn.close()
            if not rows:
                return False
            ids, mats = [], []
            for tid, blob in rows:
                if not blob:
                    continue
                n = len(blob) // 4
                mats.append(struct.unpack(f"{n}f", blob))
                ids.append(tid)
            if not ids:
                return False
            self.tool_ids = ids
            self.embeddings = np.asarray(mats, dtype=np.float32)
            return True
        except Exception as exc:
            log.warning("[VectorSearch] tools.embedding column load failed: %s", exc)
            return False

    def upsert_tool_embedding(self, tool_id: str, text: str) -> bool:
        """INCREMENTAL: compute one tool's embedding and store it in the
        tools.embedding column. Call this from the enrichment pipeline whenever a
        tool is added or its text changes — no full rebuild, just one row. The
        vector rides the DB to dev on the next sync."""
        import struct
        try:
            vec = self._encode_query(text)   # bge via embed server or ST
            if vec is None:
                return False
            blob = struct.pack(f"{len(vec)}f", *[float(x) for x in vec])
            conn = sqlite3.connect(self.db_path)
            try:
                conn.execute("ALTER TABLE tools ADD COLUMN embedding BLOB")
            except Exception:
                pass
            conn.execute("UPDATE tools SET embedding=? WHERE tool_id=?", (blob, tool_id))
            conn.commit()
            conn.close()
            return True
        except Exception as exc:
            log.warning("[VectorSearch] upsert_tool_embedding failed for %s: %s", tool_id, exc)
            return False

    def embed_missing_tools(self, reembed_all: bool = False) -> int:
        """INCREMENTAL population of the tools.embedding column: embed every tool
        that has no vector yet (or all of them if the text recipe changed). Run
        this after tool ingestion/enrichment — it only touches new/changed rows,
        so it's cheap, and the vectors then ride the DB to dev on the next sync.
        Returns the number embedded."""
        import struct
        conn = sqlite3.connect(self.db_path)
        try:
            conn.execute("ALTER TABLE tools ADD COLUMN embedding BLOB")
        except Exception:
            pass
        where = "" if reembed_all else "WHERE embedding IS NULL"
        rows = conn.execute(
            f"SELECT tool_id, name, description, category, help_text, tags, "
            f"edam_operations, edam_topics FROM tools {where}"
        ).fetchall()
        if not rows:
            conn.close()
            log.info("[VectorSearch] embed_missing_tools: nothing to embed")
            return 0
        ids, texts = [], []
        for r in rows:
            text, _ = self._tool_row_fields(r)
            ids.append(r[0])
            texts.append(text or r[0] or "")
        vecs = self._encode_batch(texts)
        if vecs is None:
            conn.close()
            log.warning("[VectorSearch] embed_missing_tools: encode unavailable (no server/model)")
            return 0
        for tid, vec in zip(ids, vecs):
            blob = struct.pack(f"{len(vec)}f", *[float(x) for x in vec])
            conn.execute("UPDATE tools SET embedding=? WHERE tool_id=?", (blob, tid))
        conn.commit()
        conn.close()
        log.info("[VectorSearch] embed_missing_tools: embedded %d tools into tools.embedding", len(ids))
        return len(ids)

    def _load_embeddings(self):
        """Load pre-computed embeddings from disk."""
        log.info(f"Loading embeddings from {self.embedding_path}")
        data = np.load(self.embedding_path, allow_pickle=True)

        self.tool_ids = list(data['tool_ids'])
        self.embeddings = data['embeddings']
        # A "shipped" marker means this .npz was built offline as a deploy
        # artifact (fast box) and shipped via S3 — TRUST it, don't trigger the
        # slow in-container rebuild even if the DB signature drifts slightly.
        self._shipped = 'shipped' in getattr(data, 'files', [])

        log.info(f"Loaded {len(self.tool_ids)} tool embeddings "
                f"(shape: {self.embeddings.shape}, shipped={self._shipped})")

    @staticmethod
    def _tool_row_fields(row):
        """(text_for_embedding, per_row_hash) from a tools row. The hash covers
        the same fields, so a content change flips it and forces re-encode."""
        import hashlib
        tool_id, name, desc, category, help_text, tags, edam_ops, edam_topics = row
        parts = [name] if name else []
        if desc:
            parts.append(desc[:500])  # Truncate long descriptions
        if category:
            parts.append(f"Category: {category}")
        if help_text:
            parts.append(f"Help: {help_text[:300]}")
        if tags:
            parts.append(f"Tags: {tags}")
        if edam_ops:
            parts.append(f"Operations: {edam_ops}")
        if edam_topics:
            parts.append(f"Topics: {edam_topics}")
        text = ". ".join(parts)
        # Recipe token folded in so a text-recipe change forces re-encode even
        # when the raw row is unchanged.
        h = hashlib.sha256(
            (_EMBED_RECIPE + "\x1e" + "\x1e".join(str(x or "") for x in row)).encode("utf-8", "replace")
        ).hexdigest()
        return text, h

    def _create_embeddings(self):
        """Build or INCREMENTALLY update tool embeddings.

        Only new tools and tools whose text changed are encoded; unchanged
        tools reuse their cached vector. This avoids re-encoding the whole
        ~12k corpus (minutes of compute + cost) on every small drift — a
        27-row drift costs 27 encodes, not 12,297.

        Legacy .npz files with no per-row hashes are TRUSTED for the tool_ids
        they already carry (only genuinely new tools are encoded), so the
        migration to incremental itself does NOT trigger a full rebuild.
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            SELECT tool_id, name, description, category, help_text, tags,
                   edam_operations, edam_topics
            FROM tools
        ''')
        rows = cursor.fetchall()
        conn.close()
        if not rows:
            log.warning("No tools found in database")
            return

        # Load cached vectors + per-row hashes (if any) for reuse.
        cache = {}  # tool_id -> (vector, hash_or_None)
        if Path(self.embedding_path).exists():
            try:
                data = np.load(self.embedding_path, allow_pickle=True)
                ids = list(data['tool_ids'])
                embs = data['embeddings']
                hashes = list(data['row_hashes']) if 'row_hashes' in data.files else [None] * len(ids)
                for i, tid in enumerate(ids):
                    cache[tid] = (embs[i], hashes[i])
            except Exception as exc:
                log.warning(f"[VectorSearch] incremental cache load failed (full rebuild): {exc}")

        tool_ids, row_hashes = [], []
        final = []                 # per-position vector or None (to fill after encode)
        to_encode, enc_pos = [], []
        reused = 0
        for pos, row in enumerate(rows):
            tid = row[0]
            text, h = self._tool_row_fields(row)
            tool_ids.append(tid)
            row_hashes.append(h)
            cached = cache.get(tid)
            # Reuse when: cached vector exists AND (hash matches, or legacy row has
            # no stored hash → trust it rather than force a corpus-wide re-encode).
            if cached is not None and cached[0] is not None and (cached[1] is None or cached[1] == h):
                final.append(cached[0])
                reused += 1
            else:
                final.append(None)
                to_encode.append(text)
                enc_pos.append(pos)

        if to_encode:
            log.info(f"[VectorSearch] incremental: encoding {len(to_encode)} new/changed "
                     f"of {len(rows)} tools (reused {reused}, server={self._use_server})")
            vecs = self._encode_batch(to_encode)
            if vecs is None:
                raise RuntimeError("tool embedding encode failed (server + in-process both unavailable)")
            for j, pos in enumerate(enc_pos):
                final[pos] = vecs[j]
        else:
            log.info(f"[VectorSearch] incremental: all {reused} tool embeddings current — nothing to encode")

        self.tool_ids = tool_ids
        self.embeddings = np.vstack(final)

        try:
            _, sig = self._compute_tools_db_signature()
        except Exception as exc:
            log.warning(f"[VectorSearch] signature compute on save failed: {exc}")
            sig = ""

        log.info(f"Saving embeddings to {self.embedding_path}")
        np.savez_compressed(
            self.embedding_path,
            tool_ids=np.array(self.tool_ids, dtype=object),
            embeddings=self.embeddings,
            row_hashes=np.array(row_hashes, dtype=object),
            tools_signature=np.array(sig, dtype=object),
        )
        log.info(f"[VectorSearch] saved {len(self.tool_ids)} embeddings "
                 f"({len(to_encode)} encoded, {reused} reused, sig={sig[:12] if sig else 'none'}..)")

    # ------------------------------------------------------------------
    # Staleness detection (mirror of unified_workflow_search's pattern)
    # ------------------------------------------------------------------

    def _compute_tools_db_signature(self) -> tuple:
        """Compute (row_count, sha256_hex) over the DB's tools rows.

        Hashes the same fields _create_embeddings reads (name/description/
        category/help_text/tags/edam_*), so any change that would affect the
        encoded text shows up as a different signature.
        """
        import hashlib
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute(
            "SELECT tool_id, COALESCE(name,''), COALESCE(description,''), "
            "COALESCE(category,''), COALESCE(help_text,''), COALESCE(tags,''), "
            "COALESCE(edam_operations,''), COALESCE(edam_topics,'') "
            "FROM tools ORDER BY tool_id"
        )
        rows = cursor.fetchall()
        conn.close()
        h = hashlib.sha256()
        h.update((_EMBED_RECIPE + "\x1f").encode("utf-8"))  # recipe change => new sig
        for r in rows:
            h.update("\x1e".join(str(x) for x in r).encode("utf-8", errors="replace"))
            h.update(b"\x1f")
        return len(rows), h.hexdigest()

    def _embeddings_stale(self) -> bool:
        """True iff the loaded .npz no longer matches the live tools DB.

        Same conservative policy as the workflow side: pre-signature
        .npz files pass on row-count alone; the next rebuild lands the
        signature so subsequent loads get the full check.
        """
        try:
            db_count, db_sig = self._compute_tools_db_signature()
        except Exception as exc:
            log.warning(f"[VectorSearch] DB signature failed (treating as fresh): {exc}")
            return False

        if db_count != len(self.tool_ids):
            log.info(
                f"[VectorSearch] Row-count drift: DB={db_count} .npz={len(self.tool_ids)}"
            )
            return True

        try:
            data = np.load(self.embedding_path, allow_pickle=True)
            stored = data.get("tools_signature")
            if stored is not None:
                stored_sig = stored.item() if hasattr(stored, "item") else str(stored)
                if stored_sig != db_sig:
                    log.info(
                        f"[VectorSearch] Content signature mismatch "
                        f"(stored={str(stored_sig)[:12]}.. live={db_sig[:12]}..)"
                    )
                    return True
        except Exception as exc:
            log.warning(f"[VectorSearch] Signature read failed: {exc}")

        return False

    def search(
        self,
        query: str,
        expanded_terms: List[str] = None,
        limit: int = 20,
        min_similarity: float = 0.1
    ) -> List[Dict[str, Any]]:
        """
        Search tools by semantic similarity.

        Args:
            query: Original user query
            expanded_terms: Additional terms to include (from LLM expansion)
            limit: Maximum number of results
            min_similarity: Minimum cosine similarity threshold

        Returns:
            List of tool dicts with similarity scores, sorted by relevance
        """
        _vs_tls.error = None  # reset per-call; set only if THIS search errors
        if not self._initialized or self.embeddings is None:
            _vs_tls.error = "vector search not initialized"
            log.error("Vector search not initialized — returning empty (DEGRADED, not 'no matches')")
            return []

        # Combine query with expanded terms
        if expanded_terms:
            search_text = f"{query}. {' '.join(expanded_terms)}"
        else:
            search_text = query

        try:
            # Encode query (shared embed server if up, else in-process ST)
            query_embedding = self._encode_query(search_text)
            if query_embedding is None:
                _vs_tls.error = "query embedding failed (embed server down?)"
                log.error("Vector search: query embedding failed — returning empty (DEGRADED, not 'no matches')")
                return []

            # Compute cosine similarity with all tools
            # Normalize embeddings for cosine similarity
            query_norm = query_embedding / np.linalg.norm(query_embedding)
            embeddings_norm = self.embeddings / np.linalg.norm(self.embeddings, axis=1, keepdims=True)

            similarities = np.dot(embeddings_norm, query_norm)

            # Get top-k indices above threshold
            valid_indices = np.where(similarities >= min_similarity)[0]
            sorted_indices = valid_indices[np.argsort(similarities[valid_indices])[::-1]][:limit]

            if len(sorted_indices) == 0:
                log.debug(f"No results above threshold {min_similarity} for query: {query[:50]}")
                return []

            # Fetch tool details from database
            results = self._fetch_tool_details(sorted_indices, similarities)

            log.debug(f"Vector search found {len(results)} results for: {query[:50]}")
            return results

        except Exception as e:
            _vs_tls.error = "%s: %s" % (type(e).__name__, e)
            log.error(f"Vector search failed: {e} — returning empty (DEGRADED, not 'no matches')")
            return []

    def _fetch_tool_details(
        self,
        indices: np.ndarray,
        similarities: np.ndarray
    ) -> List[Dict[str, Any]]:
        """Fetch full tool details for given indices.

        EXCLUDES ToolShed tools since they're not installed in Galaxy.
        Only returns Biomni tools and other non-ToolShed tools.
        """
        results = []

        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        for idx in indices:
            tool_id = self.tool_ids[idx]
            similarity = float(similarities[idx])

            # Skip ToolShed tools - they're not installed in Galaxy
            if tool_id.startswith('toolshed.'):
                continue

            cursor.execute('SELECT * FROM tools WHERE tool_id = ?', (tool_id,))
            row = cursor.fetchone()

            if row:
                tool = dict(row)
                tool['vector_similarity'] = similarity
                tool['search_method'] = 'vector'
                # Boost Biomni tools
                if tool_id.startswith('biomni/'):
                    tool['biomni_boost'] = 50
                results.append(tool)

        conn.close()
        return results

    def is_available(self) -> bool:
        """Check if vector search is available and initialized."""
        return self._initialized and self.embeddings is not None

    def get_stats(self) -> Dict[str, Any]:
        """Get statistics about the vector index."""
        return {
            'available': self.is_available(),
            'model': self.model_name,
            'num_tools': len(self.tool_ids) if self.tool_ids else 0,
            'embedding_dim': self.embeddings.shape[1] if self.embeddings is not None else 0,
            'embedding_path': self.embedding_path
        }

    def rebuild_index(self):
        """Force rebuild of embeddings."""
        if not SENTENCE_TRANSFORMERS_AVAILABLE:
            log.error("Cannot rebuild - sentence-transformers not installed")
            return

        log.info("Rebuilding vector index...")
        self._create_embeddings()
        log.info("Vector index rebuilt successfully")


class MockVectorSearch:
    """
    Mock vector search for testing without sentence-transformers.
    Returns empty results but doesn't fail.
    """

    def __init__(self, *args, **kwargs):
        log.info("Using MockVectorSearch (sentence-transformers not available)")

    def search(self, query: str, **kwargs) -> List[Dict[str, Any]]:
        return []

    def is_available(self) -> bool:
        return False

    def get_stats(self) -> Dict[str, Any]:
        return {'available': False, 'reason': 'sentence-transformers not installed'}


def get_vector_search(db_path: str, **kwargs) -> VectorToolSearch:
    """
    Factory function to get vector search instance.
    Returns MockVectorSearch if sentence-transformers not available.
    """
    if SENTENCE_TRANSFORMERS_AVAILABLE:
        return VectorToolSearch(db_path, **kwargs)
    else:
        return MockVectorSearch(db_path, **kwargs)

# tool-embed-ship redeploy 1786496282
