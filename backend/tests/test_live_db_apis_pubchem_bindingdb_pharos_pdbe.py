#!/usr/bin/env python3
"""Standalone live-API harness for the four new query_database handlers
(_query_pubchem, _query_bindingdb, _query_pharos, _query_pdbe).

Binds each unbound method to a minimal fake `self` that provides a real
`_http_get_json` (same impl as AIAssistant) and a pass-through `_cached_fetch`,
then calls each handler against the LIVE public API and asserts a well-formed
response. Prints PASS/FAIL per source.

Run:  python3 backend/tests/test_live_db_apis_pubchem_bindingdb_pharos_pdbe.py
"""
import sys
import os
import types

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(REPO, "backend", "lib"))

from galaxy.ai.ai_assistant import AIAssistant  # noqa: E402


class FakeSelf:
    """Minimal stand-in exposing the two collaborators the handlers use."""

    def _cached_fetch(self, key, fetch):
        return fetch()

    # Reuse the real HTTP helper unmodified.
    _http_get_json = AIAssistant._http_get_json


def _bind(method_name):
    fake = FakeSelf()
    return types.MethodType(getattr(AIAssistant, method_name), fake)


def check(label, ok, detail):
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {label}: {detail}")
    return ok


def main():
    results = []

    # 1. PubChem — lookup
    q = _bind("_query_pubchem")
    r = q("aspirin", operation="lookup")
    ok = (r.get("source") == "pubchem" and r.get("results")
          and r["results"][0].get("cid") == 2244
          and r["results"][0].get("formula") == "C9H8O4"
          and r["results"][0].get("smiles"))
    results.append(check("pubchem.lookup(aspirin)", ok,
                         f"cid={r.get('results', [{}])[0].get('cid')} "
                         f"formula={r.get('results', [{}])[0].get('formula')} "
                         f"mw={r.get('results', [{}])[0].get('mw')}"))

    # 1b. PubChem — similarity
    q = _bind("_query_pubchem")
    r = q("CC(=O)OC1=CC=CC=C1C(=O)O", operation="similarity")
    ok = (r.get("source") == "pubchem" and r.get("search") == "similarity_2d"
          and len(r.get("results", [])) > 0
          and all("cid" in x for x in r["results"]))
    results.append(check("pubchem.similarity(aspirin SMILES)", ok,
                         f"{len(r.get('results', []))} hits"))

    # 2. BindingDB — affinities for EGFR (P00533)
    q = _bind("_query_bindingdb")
    r = q("P00533", operation="lookup")
    ok = (r.get("source") == "bindingdb" and r.get("results")
          and r["results"][0].get("affinity_type") in ("Ki", "Kd", "IC50", "EC50")
          and r["results"][0].get("smiles")
          and r["results"][0].get("affinity_nM") is not None)
    _first = (r.get("results") or [{}])[0]
    results.append(check("bindingdb.lookup(P00533)", ok,
                         f"{len(r.get('results', []))} affinities; "
                         f"first={_first.get('affinity_type')}="
                         f"{_first.get('affinity_nM')}nM"))

    # 3. Pharos — EGFR target dev level
    q = _bind("_query_pharos")
    r = q("EGFR", operation="lookup")
    ok = (r.get("source") == "pharos"
          and r.get("tdl") in ("Tclin", "Tchem", "Tbio", "Tdark")
          and r.get("symbol") == "EGFR"
          and r.get("family"))
    results.append(check("pharos.lookup(EGFR)", ok,
                         f"tdl={r.get('tdl')} fam={r.get('family')} "
                         f"drugs={r.get('drug_count')} ligands={r.get('ligand_count')}"))

    # 4a. PDBe — summary + ligands for 4hhb
    q = _bind("_query_pdbe")
    r = q("4hhb", operation="lookup")
    ok = (r.get("source") == "pdbe" and r.get("pdb_id") == "4HHB"
          and r.get("title") and r.get("ligands")
          and any(l.get("chem_comp_id") == "HEM" for l in r.get("ligands", [])))
    results.append(check("pdbe.lookup(4hhb)", ok,
                         f"title={(r.get('title') or '')[:40]!r} "
                         f"ligands={[l.get('chem_comp_id') for l in r.get('ligands', [])]}"))

    # 4b. PDBe — best structures for UniProt P00533
    q = _bind("_query_pdbe")
    r = q("P00533", operation="lookup")
    ok = (r.get("source") == "pdbe" and r.get("uniprot") == "P00533"
          and r.get("best_structures")
          and r["best_structures"][0].get("pdb_id"))
    results.append(check("pdbe.lookup(P00533 uniprot)", ok,
                         f"{len(r.get('best_structures', []))} best structures; "
                         f"first={r.get('best_structures', [{}])[0].get('pdb_id')}"))

    passed = sum(1 for x in results if x)
    total = len(results)
    print(f"\n=== {passed}/{total} checks passed ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
