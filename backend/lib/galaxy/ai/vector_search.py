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
from pathlib import Path
from typing import List, Dict, Any, Optional
import numpy as np

log = logging.getLogger(__name__)

# Try to import sentence-transformers, gracefully degrade if not available
try:
    from sentence_transformers import SentenceTransformer
    SENTENCE_TRANSFORMERS_AVAILABLE = True
except ImportError:
    SENTENCE_TRANSFORMERS_AVAILABLE = False
    log.warning("sentence-transformers not installed. Vector search will be disabled.")


# Bump when the embedded-text recipe changes so cached vectors are recomputed
# even if the underlying DB rows are unchanged (the per-row hash + DB signature
# both fold this in). "sciflat" = scientific_context flattened from JSON prose.
_EMBED_RECIPE = "sciflat-v1"

# Keys in the scientific_context JSON that are provenance/confidence metadata,
# not scientific content — skipped when flattening to embedded prose.
_SCI_CTX_NOISE_KEYS = frozenset({
    "evidence", "confidence", "evidence_quality", "missing_evidence_for",
    "information_sources", "needs_verification", "claim", "source",
    "tool_homepage", "tool_documentation", "key_publications",
    "min_samples", "min_replicates", "not_suitable", "not_recommended_for",
})


def _flatten_sci_context(raw, cap: int = 800) -> str:
    """Pull human-readable prose out of a scientific_context JSON blob (v1 or v2
    shape), dropping provenance/confidence metadata. Returns '' for empty input;
    falls back to the truncated raw string if it isn't JSON."""
    if not raw:
        return ""
    import json as _json
    try:
        doc = _json.loads(raw)
    except Exception:
        return str(raw)[:cap]
    out = []

    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in _SCI_CTX_NOISE_KEYS:
                    continue
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
        elif isinstance(o, str):
            s = o.strip()
            if s and s.lower() != "n/a" and "needs_verification" not in s.lower():
                out.append(s)

    walk(doc)
    seen, parts = set(), []
    for s in out:
        if s not in seen:
            seen.add(s)
            parts.append(s)
    return "; ".join(parts)[:cap]


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

        if SENTENCE_TRANSFORMERS_AVAILABLE:
            self._initialize()
        else:
            log.warning("Vector search disabled - sentence-transformers not available")

    def _initialize(self):
        """Load model and embeddings."""
        try:
            # Determine device - use safe detection if not specified
            if self.device is None:
                self.device = _detect_device_safe(timeout_seconds=5.0)
                log.info(f"Auto-detected device: {self.device}")

            # Load model on specified device — local_files_only prevents network
            # check on HuggingFace (model is already cached).
            log.info(f"Loading sentence transformer model: {self.model_name} on {self.device}")
            self.model = SentenceTransformer(self.model_name, device=self.device,
                                             local_files_only=True)

            # Load or create embeddings.
            # Staleness contract (added 2026-06-13 — same fix as the
            # workflow side; see docs/20260613_DENSE_EMBEDDINGS_PATHS.md §6):
            # after a load, compare the live DB's content signature to
            # the one stamped into the .npz at build time. Mismatch →
            # rebuild. Catches both row-count drift and in-place edits.
            if Path(self.embedding_path).exists():
                self._load_embeddings()
                if self.auto_create and self._embeddings_stale():
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

    def _load_embeddings(self):
        """Load pre-computed embeddings from disk."""
        log.info(f"Loading embeddings from {self.embedding_path}")
        data = np.load(self.embedding_path, allow_pickle=True)

        self.tool_ids = list(data['tool_ids'])
        self.embeddings = data['embeddings']

        log.info(f"Loaded {len(self.tool_ids)} tool embeddings "
                f"(shape: {self.embeddings.shape})")

    @staticmethod
    def _tool_row_fields(row):
        """(text_for_embedding, per_row_hash) from a tools row. The hash covers
        the same fields, so a content change flips it and forces re-encode."""
        import hashlib
        (tool_id, name, desc, category, help_text, tags, edam_ops, edam_topics,
         sci_ctx, sci_ctx_v2) = row
        parts = [name] if name else []
        if desc:
            parts.append(desc[:500])  # Truncate long descriptions
        # scientific_context is the richest enrichment (~10k tools) — prefer v2,
        # flattened from JSON to prose (drops provenance/confidence noise).
        sci = _flatten_sci_context(sci_ctx_v2) or _flatten_sci_context(sci_ctx)
        if sci:
            parts.append(f"Scientific context: {sci}")
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
                   edam_operations, edam_topics, scientific_context, scientific_context_v2
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
                     f"of {len(rows)} tools (reused {reused})")
            vecs = self.model.encode(
                to_encode, show_progress_bar=True, batch_size=64, convert_to_numpy=True
            )
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

        Hashes the same fields _create_embeddings reads (incl.
        scientific_context / scientific_context_v2), so any change that
        would affect the encoded text shows up as a different signature.
        """
        import hashlib
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute(
            "SELECT tool_id, COALESCE(name,''), COALESCE(description,''), "
            "COALESCE(category,''), COALESCE(help_text,''), COALESCE(tags,''), "
            "COALESCE(edam_operations,''), COALESCE(edam_topics,''), "
            "COALESCE(scientific_context,''), COALESCE(scientific_context_v2,'') "
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
        if not self._initialized or self.embeddings is None:
            log.warning("Vector search not initialized, returning empty results")
            return []

        # Combine query with expanded terms
        if expanded_terms:
            search_text = f"{query}. {' '.join(expanded_terms)}"
        else:
            search_text = query

        try:
            # Encode query
            query_embedding = self.model.encode([search_text], convert_to_numpy=True)[0]

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
            log.error(f"Vector search failed: {e}")
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
