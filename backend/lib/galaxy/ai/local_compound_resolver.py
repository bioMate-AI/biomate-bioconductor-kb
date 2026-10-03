"""Read-only ChEMBL SQLite mirror for the federated-query offline seam.

BIOMATE_CHEMBL_SQLITE points to a locally provisioned ChEMBL SQLite release.
No downloads, network fallback, or invented PubChem identifiers are performed.
"""
from pathlib import Path
from contextlib import closing
import sqlite3
from urllib.parse import parse_qs, urlsplit


def resolve(path, url, payload=None):
    parsed = urlsplit(url)
    if payload is not None or parsed.hostname != "www.ebi.ac.uk":
        return None
    if parsed.path.rstrip("/") != "/chembl/api/data/molecule/search":
        return None
    query = parse_qs(parsed.query).get("q", [""])[0].strip()
    if not query or len(query) > 500:
        return {"molecules": []}
    # One connection per request: federated_query runs sources on worker threads.
    with closing(sqlite3.connect(Path(path).resolve().as_uri() + "?mode=ro", uri=True)) as db:
        db.execute("PRAGMA query_only=ON")
        # Exact names and synonyms prevent silently substituting a related compound.
        rows = db.execute("""
            SELECT DISTINCT d.chembl_id, d.pref_name, s.canonical_smiles,
                            p.full_molformula, p.full_mwt
            FROM molecule_dictionary d
            LEFT JOIN compound_structures s ON s.molregno = d.molregno
            LEFT JOIN molecule_properties p ON p.molregno = d.molregno
            WHERE d.chembl_id = ? COLLATE NOCASE
               OR d.pref_name = ? COLLATE NOCASE
               OR d.molregno IN (
                   SELECT molregno FROM molecule_synonyms WHERE synonyms = ? COLLATE NOCASE
               )
            ORDER BY d.chembl_id LIMIT 5
        """, (query, query, query)).fetchall()
    return {"molecules": [
        {"molecule_chembl_id": cid, "pref_name": name,
         "molecule_structures": {"canonical_smiles": smiles},
         "molecule_properties": {"full_molformula": formula, "full_mwt": weight}}
        for cid, name, smiles, formula, weight in rows
    ]}
