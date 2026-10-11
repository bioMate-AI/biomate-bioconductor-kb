"""Corpus-as-filesystem index (Option B, slice 1).

A grounded virtual filesystem over a literature/document corpus. Agents navigate
the corpus with ``ls`` / ``cat`` / ``grep`` / ``find`` instead of embedding free
text, so every returned snippet is text that *physically exists* in the store --
grounded by construction. This structurally prevents citation confabulation: the
primitives can only ever return bytes that were ingested.

Backends are pluggable behind the :class:`CorpusIndex` Protocol (mirroring
BioMate's ``RunStateStore`` Protocol + InMemory/Redis + factory pattern), chosen
by the ``CORPUS_INDEX_BACKEND`` env var:

- ``fts5`` (default): embedded SQLite FTS5 -- zero-ops, on-prem-safe. The
  shipping default. Extends ``local_literature.py``'s ``documents`` + FTS5
  ``chunks`` shape to *block* granularity (section / kind / line range).
- ``es`` (optional, NOT yet implemented): Elasticsearch for large-corpus/cloud
  deployments. Drops in behind the same interface later (design doc section 2).

Virtual-FS path convention::

    /papers/<doc_id>/sections/<Section>.lines

Python 3.9-safe: ``from __future__ import annotations`` + ``typing`` generics
(no PEP 604 ``X | None``, no subscripted builtins instantiated at runtime).
Inert / additive: wired into no live path, no network, no external services.
"""

from __future__ import annotations

import fnmatch
import json
import os
import re
import sqlite3
from contextlib import closing
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Union, runtime_checkable

try:  # Protocol is in typing for 3.8+, but guard for ancient interpreters.
    from typing import Protocol
except ImportError:  # pragma: no cover - 3.9 always has Protocol
    Protocol = object  # type: ignore


# Default on-disk location for the embedded index. Kept inert: nothing creates
# this file unless a caller explicitly ingests.
_DEFAULT_DB_ENV = "CORPUS_INDEX_DB"
_BACKEND_ENV = "CORPUS_INDEX_BACKEND"

# Virtual-FS path template + parser.
_PATH_PREFIX = "/papers/"
_SECTIONS_SEG = "/sections/"
_PATH_SUFFIX = ".lines"
_PATH_RE = re.compile(r"^/papers/(?P<doc_id>[^/]+)/sections/(?P<section>.+)\.lines$")


def section_path(doc_id: str, section: str) -> str:
    """Build the virtual-FS path for a document section."""
    return "{}{}{}{}{}".format(_PATH_PREFIX, doc_id, _SECTIONS_SEG, section, _PATH_SUFFIX)


def parse_path(path: str) -> Dict[str, str]:
    """Parse a virtual-FS section path into ``{"doc_id", "section"}``.

    Raises ``ValueError`` on a path that does not match the convention.
    """
    match = _PATH_RE.match(path or "")
    if not match:
        raise ValueError(
            "not a corpus-fs section path (expected "
            "/papers/<doc_id>/sections/<Section>.lines): {!r}".format(path)
        )
    return {"doc_id": match.group("doc_id"), "section": match.group("section")}


@runtime_checkable
class CorpusIndex(Protocol):
    """Pluggable corpus-as-filesystem index.

    Any backend (``fts5`` today, ``es`` later) implements these grounded
    primitives so callers never depend on the concrete store.
    """

    def ingest(self, docs: Any) -> Dict[str, int]:
        """Ingest documents; return counts (documents / blocks / skipped...)."""
        ...

    def ls(self, doc_id: str) -> List[str]:
        """List the virtual-FS section paths for a document."""
        ...

    def cat(self, doc_id: str, path: str) -> str:
        """Return the joined stored text addressed by a section path."""
        ...

    def grep(
        self,
        pattern: str,
        path_glob: Optional[str] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        """Return grounded hits ({doc_id, path, section, line_start, line_end, snippet})."""
        ...

    def find(self, **predicate: Any) -> List[str]:
        """Return doc_ids whose metadata / text match the given predicate."""
        ...

    def doc_meta(self, doc_id: str) -> Dict[str, Any]:
        """Return a document's metadata row as a dict (empty if unknown)."""
        ...


class Fts5CorpusIndex(object):
    """SQLite FTS5 implementation of :class:`CorpusIndex`.

    Schema (extends ``local_literature.py``'s documents + FTS5 chunks to block
    granularity)::

        documents(doc_id PK, title, year, source, url, licence)
        blocks(block_id PK, doc_id, section, kind, line_start, line_end, text)
        blocks_fts USING fts5(block_id UNINDEXED, doc_id UNINDEXED,
                              section UNINDEXED, text)
    """

    def __init__(self, db_path: Union[str, Path]):
        self.db_path = str(db_path)
        self._ensure_schema()

    # -- connection helpers -------------------------------------------------

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _connect_ro(self) -> sqlite3.Connection:
        # Read-only connection for query primitives (mirrors local_literature).
        # Falls back to a normal connection for the in-memory case.
        if self.db_path == ":memory:":
            conn = self._connect()
        else:
            uri = Path(self.db_path).resolve().as_uri() + "?mode=ro"
            conn = sqlite3.connect(uri, uri=True)
            conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        with closing(self._connect()) as db:
            db.executescript(
                """
                CREATE TABLE IF NOT EXISTS documents(
                    doc_id  TEXT PRIMARY KEY,
                    title   TEXT,
                    year    INTEGER,
                    source  TEXT,
                    url     TEXT,
                    licence TEXT
                );
                CREATE TABLE IF NOT EXISTS blocks(
                    block_id   INTEGER PRIMARY KEY,
                    doc_id     TEXT NOT NULL,
                    section    TEXT NOT NULL,
                    kind       TEXT,
                    line_start INTEGER,
                    line_end   INTEGER,
                    text       TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_blocks_doc
                    ON blocks(doc_id, section, line_start);
                CREATE VIRTUAL TABLE IF NOT EXISTS blocks_fts USING fts5(
                    block_id UNINDEXED,
                    doc_id   UNINDEXED,
                    section  UNINDEXED,
                    text
                );
                """
            )
            db.commit()

    # -- ingest -------------------------------------------------------------

    def ingest(self, docs: Any) -> Dict[str, int]:
        """Ingest documents.

        ``docs`` may be a path to a JSONL file, or any iterable of record dicts.
        Each record::

            {"doc_id": str, "title"?, "year"?, "source"?, "url"?, "licence"?,
             "blocks": [{"section", "kind"?, "text", "line_start"?, "line_end"?}, ...]}

        Idempotent-ish: ``INSERT OR IGNORE`` on ``doc_id`` -- a document already
        present (same id) is skipped wholesale (its blocks are not re-added).
        """
        records = self._as_records(docs)
        counts = {
            "documents": 0,
            "blocks": 0,
            "skipped_documents": 0,
            "duplicate_documents": 0,
        }
        with closing(self._connect()) as db:
            for record in records:
                if not isinstance(record, dict):
                    counts["skipped_documents"] += 1
                    continue
                doc_id = record.get("doc_id")
                if not isinstance(doc_id, str) or not doc_id.strip():
                    counts["skipped_documents"] += 1
                    continue
                inserted = db.execute(
                    "INSERT OR IGNORE INTO documents"
                    "(doc_id,title,year,source,url,licence) VALUES(?,?,?,?,?,?)",
                    (
                        doc_id,
                        record.get("title"),
                        record.get("year"),
                        record.get("source"),
                        record.get("url"),
                        record.get("licence"),
                    ),
                )
                if not inserted.rowcount:
                    counts["duplicate_documents"] += 1
                    continue
                counts["documents"] += 1
                cursor_line = 1
                for block in record.get("blocks") or []:
                    if not isinstance(block, dict):
                        continue
                    text = block.get("text")
                    section = block.get("section")
                    if not isinstance(text, str) or not text or not isinstance(section, str) or not section:
                        continue
                    line_start = block.get("line_start")
                    if not isinstance(line_start, int):
                        line_start = cursor_line
                    line_end = block.get("line_end")
                    if not isinstance(line_end, int):
                        # text spanning N newlines occupies N+1 lines
                        line_end = line_start + text.count("\n")
                    cursor_line = line_end + 1
                    block_cursor = db.execute(
                        "INSERT INTO blocks"
                        "(doc_id,section,kind,line_start,line_end,text) "
                        "VALUES(?,?,?,?,?,?)",
                        (doc_id, section, block.get("kind"), line_start, line_end, text),
                    )
                    db.execute(
                        "INSERT INTO blocks_fts(block_id,doc_id,section,text) "
                        "VALUES(?,?,?,?)",
                        (block_cursor.lastrowid, doc_id, section, text),
                    )
                    counts["blocks"] += 1
            db.commit()
            db.execute("INSERT INTO blocks_fts(blocks_fts) VALUES('optimize')")
            db.commit()
        return counts

    @staticmethod
    def _as_records(docs: Any) -> Iterable[Dict[str, Any]]:
        # A path to an existing JSONL file -> stream of parsed records.
        if isinstance(docs, (str, Path)):
            candidate = Path(docs)
            if candidate.exists():
                out = []  # materialize; the file handle must not outlive this call
                with candidate.open("r", encoding="utf-8") as handle:
                    for raw in handle:
                        raw = raw.strip()
                        if raw:
                            out.append(json.loads(raw))
                return out
            raise ValueError("ingest path does not exist: {!r}".format(str(docs)))
        return list(docs)

    # -- navigation primitives ---------------------------------------------

    def ls(self, doc_id: str) -> List[str]:
        """List the virtual-FS section paths for a document (sorted, de-duped)."""
        with closing(self._connect_ro()) as db:
            rows = db.execute(
                "SELECT DISTINCT section FROM blocks WHERE doc_id=? ORDER BY section",
                (doc_id,),
            ).fetchall()
        return [section_path(doc_id, row["section"]) for row in rows]

    def cat(self, doc_id: str, path: str) -> str:
        """Return the joined stored text for a section path.

        Blocks of the section are joined in document order by ``\\n``. Returns
        only text that exists in the store (grounded by construction).
        """
        parsed = parse_path(path)
        section = parsed["section"]
        target_doc = doc_id or parsed["doc_id"]
        with closing(self._connect_ro()) as db:
            rows = db.execute(
                "SELECT text FROM blocks WHERE doc_id=? AND section=? "
                "ORDER BY line_start, block_id",
                (target_doc, section),
            ).fetchall()
        return "\n".join(row["text"] for row in rows)

    def grep(
        self,
        pattern: str,
        path_glob: Optional[str] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        """Grounded search.

        Returns hits whose snippet is a literal substring of a stored block, each
        carrying full provenance: ``{doc_id, path, section, line_start, line_end,
        snippet}``. An FTS5 ``MATCH`` provides fast candidate recall for simple
        tokens (``LIKE`` otherwise); every candidate is then verified by a literal
        case-insensitive substring check so no stemmed / fuzzy match leaks through
        and the returned snippet always exists in the store. An absent term
        returns ``[]``.
        """
        if not isinstance(pattern, str) or pattern == "":
            return []
        if not isinstance(limit, int) or limit <= 0:
            limit = 50

        token = pattern if re.fullmatch(r"\w+", pattern) else None
        rows: List[sqlite3.Row] = []
        with closing(self._connect_ro()) as db:
            if token is not None:
                # FTS5 candidate recall. Over-fetch, then literal-verify below.
                expr = '"' + token + '"'
                rows = db.execute(
                    "SELECT b.block_id, b.doc_id, b.section, b.line_start, "
                    "       b.line_end, b.text "
                    "FROM blocks_fts f JOIN blocks b ON b.block_id=f.block_id "
                    "WHERE f.text MATCH ? ORDER BY bm25(blocks_fts)",
                    (expr,),
                ).fetchall()
            else:
                like = "%" + _escape_like(pattern) + "%"
                rows = db.execute(
                    "SELECT block_id, doc_id, section, line_start, line_end, text "
                    "FROM blocks WHERE text LIKE ? ESCAPE '\\' "
                    "ORDER BY doc_id, line_start",
                    (like,),
                ).fetchall()

        hits: List[Dict[str, Any]] = []
        lowered = pattern.lower()
        for row in rows:
            text = row["text"]
            offset = text.lower().find(lowered)
            if offset < 0:
                # FTS5 matched a tokenized/stemmed variant with no literal
                # occurrence -> drop it so every snippet is truly grounded.
                continue
            path = section_path(row["doc_id"], row["section"])
            if path_glob and not _glob_match(path, path_glob):
                continue
            hits.append(
                {
                    "doc_id": row["doc_id"],
                    "path": path,
                    "section": row["section"],
                    "line_start": row["line_start"],
                    "line_end": row["line_end"],
                    "snippet": _snippet(text, offset, len(pattern)),
                }
            )
            if len(hits) >= limit:
                break
        return hits

    def find(self, **predicate: Any) -> List[str]:
        """Return doc_ids matching a metadata / text predicate.

        Supported keys: ``title``, ``source``, ``licence`` (case-insensitive
        substring), ``year`` (exact), ``text`` (a term present in any block),
        ``limit`` (int). With no predicate, returns all doc_ids.
        """
        limit = predicate.pop("limit", None)
        clauses: List[str] = []
        params: List[Any] = []
        for key in ("title", "source", "licence"):
            value = predicate.get(key)
            if isinstance(value, str) and value:
                clauses.append("LOWER({}) LIKE ?".format(key))
                params.append("%" + _escape_like(value).lower() + "%")
        year = predicate.get("year")
        if isinstance(year, int):
            clauses.append("year = ?")
            params.append(year)

        text_term = predicate.get("text")
        doc_ids_by_text: Optional[set] = None
        if isinstance(text_term, str) and text_term:
            hits = self.grep(text_term, limit=1000000)
            doc_ids_by_text = {hit["doc_id"] for hit in hits}
            if not doc_ids_by_text:
                return []

        sql = "SELECT doc_id FROM documents"
        if clauses:
            sql += " WHERE " + " AND ".join(clauses)
        sql += " ORDER BY doc_id"
        with closing(self._connect_ro()) as db:
            rows = db.execute(sql, tuple(params)).fetchall()

        out: List[str] = []
        for row in rows:
            doc_id = row["doc_id"]
            if doc_ids_by_text is not None and doc_id not in doc_ids_by_text:
                continue
            out.append(doc_id)
            if isinstance(limit, int) and limit > 0 and len(out) >= limit:
                break
        return out

    def doc_meta(self, doc_id: str) -> Dict[str, Any]:
        with closing(self._connect_ro()) as db:
            row = db.execute(
                "SELECT doc_id,title,year,source,url,licence "
                "FROM documents WHERE doc_id=?",
                (doc_id,),
            ).fetchone()
        return dict(row) if row is not None else {}


# -- snippet / glob helpers -------------------------------------------------

_SNIPPET_PAD = 80


def _snippet(text: str, offset: int, length: int) -> str:
    """A grounded window around a match -- always a substring of ``text``."""
    start = max(0, offset - _SNIPPET_PAD)
    end = min(len(text), offset + length + _SNIPPET_PAD)
    return text[start:end]


def _escape_like(value: str) -> str:
    """Escape LIKE wildcards so a literal pattern matches literally."""
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _glob_match(path: str, glob: str) -> bool:
    """Match a virtual-FS path against a simple glob (``*`` segments supported)."""
    # fnmatch treats '*' greedily across '/', which is fine for our shallow,
    # fixed-depth paths (/papers/<id>/sections/<section>.lines).
    return fnmatch.fnmatchcase(path, glob)


# -- factory ----------------------------------------------------------------

_SINGLETON: Dict[str, CorpusIndex] = {}


def get_corpus_index(db_path: Optional[str] = None) -> CorpusIndex:
    """Return a :class:`CorpusIndex` chosen by ``CORPUS_INDEX_BACKEND``.

    - ``fts5`` (default) -> :class:`Fts5CorpusIndex` at ``db_path`` (or the
      ``CORPUS_INDEX_DB`` env, else an in-memory DB).
    - ``es`` -> raises ``NotImplementedError`` (see design doc section 2).

    A per-``db_path`` singleton is cached; clear it with
    :func:`reset_corpus_index` (test hook).
    """
    backend = (os.environ.get(_BACKEND_ENV) or "fts5").strip().lower()
    if backend == "es":
        raise NotImplementedError(
            "ES backend not implemented yet; see design doc section 2 "
            "(docs/20261008_CORPUS_FS_OPTION_B_DESIGN.md). "
            "Use CORPUS_INDEX_BACKEND=fts5 (the embedded, on-prem-safe default)."
        )
    if backend != "fts5":
        raise ValueError(
            "unknown CORPUS_INDEX_BACKEND={!r} (expected 'fts5' or 'es')".format(backend)
        )
    resolved = db_path or os.environ.get(_DEFAULT_DB_ENV) or ":memory:"
    key = "fts5::" + str(resolved)
    existing = _SINGLETON.get(key)
    if existing is None:
        existing = Fts5CorpusIndex(resolved)
        _SINGLETON[key] = existing
    return existing


def reset_corpus_index() -> None:
    """Drop the cached singletons (test hook)."""
    _SINGLETON.clear()
