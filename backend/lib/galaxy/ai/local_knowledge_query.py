"""Bounded, read-only retrieval from BioMate's existing tool/workflow catalogue."""
import re
import sqlite3
from pathlib import Path


def query_knowledge(db_path, query, limit=5):
    if not isinstance(query, str) or not query.strip() or len(query) > 500:
        raise ValueError('Query must contain 1–500 characters')
    if not isinstance(limit, int) or not 1 <= limit <= 10:
        raise ValueError('Limit must be between 1 and 10')
    stop = {'the', 'a', 'an', 'for', 'and', 'or', 'to', 'of', 'in', 'use', 'please', 'tool', 'tools', 'workflow', 'workflows'}
    words = list(dict.fromkeys(w.lower() for w in re.findall(r'[\w-]+', query) if len(w) > 1 and w.lower() not in stop))[:12]
    if not words:
        return {'tools': [], 'workflows': [], 'source': 'local_knowledge_database'}
    match = ' OR '.join('"' + w + '"' for w in words)
    uri = Path(db_path).resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(uri, uri=True, timeout=5) as db:
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA query_only=ON')
        tools = db.execute('''SELECT t.tool_id,t.name,t.category,t.description,t.parameters,
            t.inputs,t.outputs,t.citations,t.availability_status FROM tools t
            JOIN tools_fts ON tools_fts.tool_id=t.tool_id WHERE tools_fts MATCH ?
            ORDER BY bm25(tools_fts),t.id LIMIT ?''', (match, limit)).fetchall()
        workflows = db.execute('''SELECT w.id,w.name,w.filename,w.description,w.domain,
            w.input_types,w.output_types,w.params_schema,w.executable,w.real_exec_status
            FROM workflows w JOIN workflows_fts ON workflows_fts.rowid=w.id
            WHERE workflows_fts MATCH ? ORDER BY bm25(workflows_fts),w.id LIMIT ?''', (match, limit)).fetchall()
    def bounded(rows):
        records = []
        for row in rows:
            record = dict(row)
            clipped = [key for key, value in record.items() if isinstance(value, str) and len(value) > 3000]
            record = {key: value[:3000] if isinstance(value, str) else value for key, value in record.items()}
            record['truncated_fields'] = clipped
            records.append(record)
        return records
    return {'tools': bounded(tools), 'workflows': bounded(workflows),
            'source': 'local_knowledge_database',
            'execution_verified': False,
            'note': 'Catalogue records are retrieval evidence; availability and successful execution require separate checks.'}
