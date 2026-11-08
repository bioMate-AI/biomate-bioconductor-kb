"""K4 deterministic verification. A failing item is DISCARDED, never repaired."""
import hashlib, re
from rdkit import Chem
from rdkit.Chem import inchi
import seq2smiles

KINDS = ["example_compound", "sar_statement", "adme_permeability", "binding_mode", "design_rationale"]
FORMATS = ["sequence", "HELM", "SMILES", "name", "none"]
QMIN, QMAX = 6, 40

def norm(s):
    return " ".join((s or "").split())

def quote_in(quote, ntext):
    q = norm(quote)
    return bool(q) and q in ntext

def num_ok(act, quote, passage):
    if not act or act.get("value") in (None, "", "null"):
        return True
    hay = (norm(quote) + " " + passage).replace(",", "")
    s = str(act["value"]).strip().replace(",", "")
    cands = {s}
    try:
        f = float(s); cands |= {("%g" % f), str(int(f)) if f == int(f) else s}
    except ValueError:
        return False
    return any(re.search(r"(?<![\d.])" + re.escape(c) + r"(?![\d])", hay) for c in cands if c)

def verify(item, ntext, passage_norm):
    """Return (ok, reason, enrich) ; enrich holds parsed structure data when available."""
    enrich = {}
    if item.get("kind") not in KINDS:
        return False, "bad_kind", enrich
    st = item.get("statement") or ""
    if not (5 <= len(st) <= 400):
        return False, "statement_length", enrich
    q = norm(item.get("quote"))
    nw = len(q.split())
    if not (QMIN <= nw <= QMAX):
        return False, "quote_length", enrich
    if not quote_in(q, ntext):
        return False, "quote_not_in_patent_text", enrich
    act = item.get("activity")
    if act and not isinstance(act, dict):
        return False, "bad_activity", enrich
    if act and not num_ok(act, q, passage_norm):
        return False, "value_not_in_text", enrich
    ss = norm(item.get("structure_string") or "")
    fmt = item.get("structure_format") or "none"
    if fmt not in FORMATS:
        return False, "bad_format", enrich
    if ss:
        if ss not in passage_norm:
            return False, "structure_not_in_passage", enrich
        if fmt == "SMILES":
            m = Chem.MolFromSmiles(ss)
            if m is None:
                enrich["structure_status"] = "smiles_parse_fail"
            else:
                enrich.update(structure_status="ok", canonical_smiles=Chem.MolToSmiles(m), inchikey=inchi.MolToInchiKey(m))
        elif fmt == "sequence":
            try:
                smi, cyclo, n = seq2smiles.to_smiles(ss)
                m = Chem.MolFromSmiles(smi)
                enrich.update(structure_status="ok_cyclo_assumed" if cyclo else "ok_linear_only", canonical_smiles=smi, n_residues=n,
                              inchikey=inchi.MolToInchiKey(m))
            except seq2smiles.ConvertError as e:
                enrich["structure_status"] = "seq_convert_fail:" + str(e)[:60]
        else:
            enrich["structure_status"] = "not_converted_" + fmt
    return True, "", enrich

def item_id(patent, quote, statement):
    return hashlib.sha256(f"{patent}|{norm(quote)}|{norm(statement)}".encode()).hexdigest()[:16]
