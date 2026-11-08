"""ligands.csv: SMILES only where the structure is unambiguous.
Tier A: SMILES retrieved from PubChem PUG REST by compound name; CID + InChIKey recorded (see data/pubchem_lookup.json,
        saved verbatim from the REST responses).
Tier B: built by me from the printed name with a stated convention (NOT retrieved) - linear peptides from the one-letter
        sequence (L-amino acids, free N- and C-termini, as RDKit MolFromSequence); c(RGDfV) from the PubChem cyclo(RGDfK) SMILES by
        replacing the Lys side chain by Val. These are flagged and a sensitivity run excludes them.
Everything else: empty SMILES (excluded from structure models)."""
import csv, json, urllib.parse, urllib.request
from pathlib import Path
from rdkit import Chem
from rdkit.Chem import rdMolDescriptors
HERE = Path(__file__).parent
PUBCHEM = {  # ligand -> PubChem name query
    "Cilengitide": "cilengitide", "Eptifibatide": "eptifibatide", "Tirofiban": "tirofiban",
    "ATN161": "ATN161", "GR144053": "GR144053", "c(RGDfK)": "cyclo(RGDfK)", "c(RGDyK)": "cyclo(Arg-Gly-Asp-D-Tyr-Lys)",
}
LINEAR = ["RGD", "RGDS", "GRGD", "GRGDS", "GRGDSP", "GRGDSPK", "GRGDNP", "GRGDTP"]


def lookup():
    cache = HERE / "data" / "pubchem_lookup.json"
    if cache.exists():
        return json.load(open(cache))
    res = {}
    for lig, q in PUBCHEM.items():
        url = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/" + urllib.parse.quote(q) + "/property/SMILES,MolecularFormula,InChIKey/JSON"
        res[lig] = dict(query=q, url=url, response=json.load(urllib.request.urlopen(url)))
    json.dump(res, open(cache, "w"), indent=1)
    return res


def main():
    kapp = []
    seen = set()
    for r in csv.DictReader(open(HERE / "matrix.csv")):
        if r["ligand_id"] not in seen:
            seen.add(r["ligand_id"]); kapp.append((r["ligand_id"], r["source"]))
    pc = lookup()
    rows = []
    for lig, src in kapp:
        d = dict(ligand_id=lig, source=src, smiles="", tier="", pubchem_cid="", formula="", provenance="no unambiguous structure; excluded from structure models")
        if lig in pc:
            p = pc[lig]["response"]["PropertyTable"]["Properties"][0]
            d.update(smiles=p["SMILES"], tier="A", pubchem_cid=p["CID"], formula=p["MolecularFormula"],
                     provenance=f"PubChem PUG REST name query '{pc[lig]['query']}' -> CID {p['CID']} (InChIKey {p['InChIKey']})")
        elif lig in LINEAR and src == "kapp2017":
            m = Chem.MolFromSequence(lig)
            d.update(smiles=Chem.MolToSmiles(m), tier="B", provenance=f"built from sequence {lig} by RDKit MolFromSequence (L-aa, free termini; termini/stereo not stated in the paper = assumption)")
        elif lig == "c(RGDfV)" and src == "kapp2017":
            k = pc["c(RGDfK)"]["response"]["PropertyTable"]["Properties"][0]["SMILES"]
            assert k.count("CCCCN)") == 1 and "CCCCN)" in k
            smi = k.replace("CCCCN)", "C(C)C)")
            m = Chem.MolFromSmiles(smi); assert m is not None
            d.update(smiles=Chem.MolToSmiles(m), tier="B", provenance="derived from PubChem cyclo(RGDfK) SMILES (CID 10196873) by substituting Lys side chain with Val (cyclo(Arg-Gly-Asp-D-Phe-Val)); stereo inherited, not independently verified")
        if d["smiles"]:
            m = Chem.MolFromSmiles(d["smiles"]); assert m is not None, lig
            d["formula"] = rdMolDescriptors.CalcMolFormula(m)
        rows.append(d)
    with open(HERE / "ligands.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
    print(len(rows), "ligand rows;", sum(bool(r["smiles"]) for r in rows), "with SMILES")
main()
