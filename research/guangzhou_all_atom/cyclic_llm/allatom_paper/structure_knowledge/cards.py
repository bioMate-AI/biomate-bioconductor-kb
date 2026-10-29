"""Target cards (workstream K3; runs on EC2). One structured card per target_kb target (+ extra targets by RCSB text search).

For each target the REFERENCE structure is the PDB id named in target_kb/<t>.json `receptor_structure` (first PDB-id-like token,
e.g. '5O45 chain A ...', '4IRZ - needs prep'); its UniProt accessions come from RCSB (not from memory). Library complexes whose
receptor shares >= 1 UniProt accession with the reference are the card's structural matches. Cards say 'no structure available'
explicitly when the library has no cyclic-peptide complex for the target. Binding-mode numbers are computed from the matched
complexes (medians), never asserted; paper DOIs are the RCSB primary-citation DOIs (metadata only: `paper_opened` is false unless
a human/agent opened the paper and recorded it in `papers_opened.json`).
usage: python cards.py --library library_v1.jsonl --targets-dir TARGET_KB_DIR --out cards_v1.json [--extra "grpr=gastrin-releasing peptide receptor"]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import statistics as st
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rcsb_meta as M  # noqa: E402

PDB_TOKEN = re.compile(r"\b([0-9][A-Za-z0-9]{3})\b")
SKIP_FILES = ("dpo", "generated", "neural", "loop_result", "induced")


def ref_pdb(receptor_structure) -> str | None:
    s = receptor_structure if isinstance(receptor_structure, str) else json.dumps(receptor_structure)
    for m in PDB_TOKEN.finditer(s):
        t = m.group(1).upper()
        if re.search(r"[A-Z]", t) and re.search(r"[0-9]", t):
            return t
    return None


def entry_uniprot(e: dict) -> list:
    out = set()
    for pe in e.get("polymer_entities") or []:
        for r in ((pe.get("rcsb_polymer_entity_container_identifiers") or {}).get("reference_sequence_identifiers") or []):
            if r.get("database_name") == "UniProt":
                out.add(r["database_accession"])
    return sorted(out)


STOP_TOKENS = {"receptor", "human", "protein", "chain", "subunit", "complex", "and", "the", "ectodomain", "domain"}


def entity_table(meta: dict) -> list:
    out = []
    for pe in (meta or {}).get("polymer_entities") or []:
        ci = pe.get("rcsb_polymer_entity_container_identifiers") or {}
        seq = ((pe.get("entity_poly") or {}).get("pdbx_seq_one_letter_code_can")) or ""
        out.append({"desc": (pe.get("rcsb_polymer_entity") or {}).get("pdbx_description") or "", "chains": ci.get("auth_asym_ids") or [],
                    "uniprot": sorted({r["database_accession"] for r in (ci.get("reference_sequence_identifiers") or []) if r.get("database_name") == "UniProt"}),
                    "length": len(seq.replace("\n", "")), "seq": seq.replace("\n", "")})
    return out


def _norm(x: str) -> str:
    return re.sub(r"[^a-z0-9]", "", x.lower())


def select_accessions(meta: dict, name: str) -> tuple:
    """UniProt accessions of the polymer entities that best match the target name (entity-level token score), not of every entity
    in the reference entry (which would pull in antibodies, albumin, beta2-microglobulin ...). Returns (accessions, method)."""
    toks = [t for t in re.split(r"[^A-Za-z0-9]+", name) if len(t) >= 3 and t.lower() not in STOP_TOKENS]
    ents = [e for e in entity_table(meta) if e["uniprot"] and e["length"] > 40]
    best, sel = 0, []
    for e in ents:
        sc = sum(1 for t in toks if _norm(t) and _norm(t) in _norm(e["desc"]))
        if sc > best:
            best, sel = sc, [e]
        elif sc == best and sc > 0:
            sel.append(e)
    if best > 0:
        return sorted({u for e in sel for u in e["uniprot"]}), f"entity-name match (score {best}; tokens {toks[:6]})"
    return sorted({u for e in ents for u in e["uniprot"]}), "AMBIGUOUS: no entity description matched the target name; all protein entities used"


def median(xs):
    xs = [x for x in xs if x is not None]
    return float(st.median(xs)) if xs else None


def card_for(name: str, label: str, ref_id: str | None, lib: list, ref_meta: dict | None, extra_ids=None, note: str = "", name_for_match: str | None = None, accs_override=None) -> dict:
    card = {"target": name, "label": label, "reference_pdb": ref_id, "note": note, "retrieved_utc": time.strftime("%FT%TZ", time.gmtime())}
    accs: list = []
    if ref_meta:
        accs, card["accession_method"] = select_accessions(ref_meta, name_for_match or label)
        cit = ref_meta.get("rcsb_primary_citation") or {}
        card["reference"] = {"title": (ref_meta.get("struct") or {}).get("title"), "method": ((ref_meta.get("exptl") or [{}])[0]).get("method"),
                             "resolution": ((ref_meta.get("rcsb_entry_info") or {}).get("resolution_combined") or [None])[0],
                             "doi": cit.get("pdbx_database_id_DOI"), "pubmed": cit.get("pdbx_database_id_PubMed"), "year": cit.get("year"),
                             "citation_title": cit.get("title"), "paper_opened": False,
                             "polymer_descriptions": sorted({(pe.get("rcsb_polymer_entity") or {}).get("pdbx_description", "") for pe in ref_meta.get("polymer_entities") or []})}
    if accs_override:
        accs = sorted(accs_override); card["accession_method"] = "from RCSB entries found by text search (entity-name match)"
    card["receptor_uniprot"] = accs
    ids = {i.upper() for i in (extra_ids or [])}
    # a library complex matches when its receptor carries ALL of the target's selected accessions (heterodimers: both subunits)
    matches = [r for r in lib if (accs and set(accs) <= set(r["receptor_uniprot"])) or r["pdb_id"].upper() in ids]
    card["n_cyclic_complexes"] = len(matches)
    card["structure_status"] = "cyclic-peptide complexes available" if matches else "NO cyclic-peptide complex in the library for this target"
    if not matches:
        card["flag"] = "no structure available: binding mode unknown from experiment; any prior for this target is transferred from other targets"
        return card
    matches.sort(key=lambda r: (r["resolution_rcsb"] if r["resolution_rcsb"] is not None else 99.0, -r["contacts_total"]))
    card["templates"] = [{"pdb_id": r["pdb_id"], "pep_chain": r["pep_chain"], "seq": r["seq"], "closure": r["primary_cyclisation"], "ring_residues": r["ring_residues"],
                          "resolution": r["resolution_rcsb"], "method": r["method"], "contacts": r["contacts_total"], "hbonds": r["hbond_rec_total"],
                          "salt_bridges": r["salt_total"], "hydrophobic": r["hydrophobic_total"], "metal_contacts": r["metal_contacts"],
                          "buried_sasa": r["buried_sasa_total"], "n_d": r["n_d"], "n_nme": r["n_nme"], "beta_turns": r["beta_turns"],
                          "hotspots_entry_numbering": r["hotspots"], "doi": r["doi"], "pubmed": r["pubmed"], "title": r["title"],
                          "affinity": r["affinity"][:3], "paper_opened": False} for r in matches[:10]]
    card["binding_mode_summary"] = {
        "n_templates": len(matches), "closures": sorted({r["primary_cyclisation"] for r in matches}),
        "median_ring_residues": median([r["ring_residues"] for r in matches]), "median_contacts": median([r["contacts_total"] for r in matches]),
        "median_hbonds": median([r["hbond_rec_total"] for r in matches]), "median_salt_bridges": median([r["salt_total"] for r in matches]),
        "median_buried_sasa_A2": median([r["buried_sasa_total"] for r in matches]),
        "median_buried_apolar_fraction": median([r["buried_sasa_apolar"] / r["buried_sasa_total"] for r in matches if r["buried_sasa_total"]]),
        "frac_with_D": sum(r["n_d"] > 0 for r in matches) / len(matches), "frac_with_NMe": sum(r["n_nme"] > 0 for r in matches) / len(matches),
        "frac_with_metal_contact": sum(r["metal_contacts"] > 0 for r in matches) / len(matches),
        "turns_seen": sorted({t.split(":")[0] for r in matches for t in r["beta_turns"]}),
        "caveat": "residue numbering differs between entries; hotspot lists are per entry, not harmonised across entries"}
    return card


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--library", required=True); ap.add_argument("--targets-dir", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--extra", action="append", default=[], help="label=free text query for RCSB text search")
    a = ap.parse_args()
    lib = [json.loads(l) for l in open(a.library)]
    cards = []
    refs = {}
    for f in sorted(glob.glob(os.path.join(a.targets_dir, "*.json"))):
        if any(s in os.path.basename(f) for s in SKIP_FILES):
            continue
        d = json.load(open(f))
        if not isinstance(d, dict) or "receptor_structure" not in d:
            continue
        refs[os.path.basename(f)[:-5]] = (d, ref_pdb(d["receptor_structure"]))
    metas = M.fetch_all(sorted({p for _, p in refs.values() if p}))
    for key, (d, pid) in refs.items():
        cards.append(card_for(key, d.get("name", key), pid, lib, metas.get(pid) if pid else None,
                              note=("reference structure parsed from target_kb receptor_structure: " + json.dumps(d["receptor_structure"])[:120]),
                              name_for_match=f"{key} {d.get('name', '')}"))
    for ex in a.extra:
        label, q = ex.split("=", 1)
        try:
            ids = M.text_search(q, 60)
        except Exception as e:  # noqa: BLE001
            ids = []
        em = M.fetch_all(ids[:50]) if ids else {}
        accs, ligs = set(), []
        for pid_, e in em.items():
            sel, how = select_accessions(e, q)
            if not how.startswith("AMBIGUOUS"):
                accs |= set(sel)
            for ent in entity_table(e):
                if 3 <= ent["length"] <= 40:
                    ligs.append({"pdb_id": pid_, "chains": ent["chains"], "desc": ent["desc"], "seq": ent["seq"]})
        c = card_for(label, q, None, lib, None, extra_ids=ids, accs_override=sorted(accs),
                     note=f"found {len(ids)} RCSB entries by full-text search '{q}'; accessions selected by entity-name match: {sorted(accs)[:10]}")
        c["short_peptide_entities_in_found_entries"] = ligs[:40]
        c["text_search_entries"] = ids[:50]
        cards.append(c)
    json.dump(cards, open(a.out, "w"), indent=1)
    print(json.dumps({"n_cards": len(cards), "n_with_structure": sum(1 for c in cards if c["n_cyclic_complexes"] > 0)}))


if __name__ == "__main__":
    main()
