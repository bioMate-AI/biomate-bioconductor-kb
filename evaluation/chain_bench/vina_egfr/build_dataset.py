"""Rebuild the EGFR bench dataset: actives from BindingDB, property-matched decoys from ZINC250k.

Usage: python build_dataset.py [cache_dir]      (needs network + rdkit; ~28 MB downloaded to cache_dir)

Why not ChEMBL / DUD-E (the first-choice sources)?  On 2026-11-01 the ChEMBL REST API returned
HTTP 500 for every endpoint, including /status (the service-unavailable page), for >30 min, and
dude.docking.org timed out (ZINC15 substance search sits behind a captcha).  Fallbacks:
  actives : BindingDB REST getLigandsByUniprots (UniProt P00533 = EGFR, cutoff 100 nM),
            affinity_type == IC50, numeric value <= 100 nM (no '<'/'>' qualifiers), median per molecule.
  decoys  : ZINC250k (250k ZINC-derived drug-like molecules, Gomez-Bombarelli et al. 2018,
            github.com/aspuru-guzik-group/chemical_vae) matched on MW/logP/HBD/HBA/rotatable bonds
            (RDKit) to each active, and required to be topologically dissimilar from EVERY known
            EGFR active (Morgan2 Tanimoto < 0.35), as DUD-E does.
"""
import csv, json, os, random, re, statistics, sys, urllib.request
from datetime import date
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem, Crippen, DataStructs, Descriptors, Lipinski, rdMolDescriptors
from rdkit.Chem.MolStandardize import rdMolStandardize

RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, ".cache")
BDB_URL = ("https://bindingdb.org/rest/getLigandsByUniprots?uniprot=P00533&cutoff=100"
           "&response=application/json")
ZINC_URL = ("https://raw.githubusercontent.com/aspuru-guzik-group/chemical_vae/main/models/"
            "zinc_properties/250k_rndm_zinc_drugs_clean_3.csv")
SEED = 20261101
N_ACTIVES = 55
N_REFERENCE = 5
DECOYS_PER_ACTIVE = 5          # cap so the library stays ~330 (docking runs on dev)
TOL = {"mw": 25.0, "logp": 0.7, "hbd": 1, "hba": 1, "rotb": 2}
MAX_SIM_TO_ANY_ACTIVE = 0.35
APPROVED = {"erlotinib": "AAKJLRGGTJKAMG", "gefitinib": "XGALLCVXEZPNRQ", "lapatinib": "BCFGMOOMADDAQU",
            "afatinib": "ULXXDDBFHOBEHA", "osimertinib": "DUYJMQONPNNFPI"}   # InChIKey first block


def fetch(url, name):
    os.makedirs(CACHE, exist_ok=True)
    p = os.path.join(CACHE, name)
    if not os.path.exists(p):
        urllib.request.urlretrieve(url, p)
    return p


def canon(smi):
    m = Chem.MolFromSmiles(smi)
    if m is None:
        return None
    m = rdMolStandardize.LargestFragmentChooser().choose(m)
    return m


def props(m):
    return dict(mw=Descriptors.MolWt(m), logp=Crippen.MolLogP(m), hbd=Lipinski.NumHDonors(m),
                hba=Lipinski.NumHAcceptors(m), rotb=rdMolDescriptors.CalcNumRotatableBonds(m))


fp = lambda m: AllChem.GetMorganFingerprintAsBitVect(m, 2, 2048)


def main():
    rnd = random.Random(SEED)
    raw = json.load(open(fetch(BDB_URL, "bindingdb_egfr.json")))["getLindsByUniprotsResponse"]["affinities"]
    per = {}
    n_ic50 = 0
    for a in raw:
        if a["query"] != "Epidermal growth factor receptor" or a["affinity_type"] != "IC50":
            continue
        if not re.fullmatch(r"\d+(\.\d+)?", a["affinity"].strip()):
            continue
        v = float(a["affinity"])
        if v > 100:
            continue
        n_ic50 += 1
        per.setdefault(a["monomerid"], dict(smiles=a["smile"], vals=[], pmids=set()))
        per[a["monomerid"]]["vals"].append(v)
        per[a["monomerid"]]["pmids"].add(a.get("pmid") or "")
    acts, seen_conn = [], set()
    for mid, e in per.items():
        m = canon(e["smiles"])
        is_appr = m is not None and Chem.MolToInchiKey(m)[:14] in APPROVED.values()
        if m is None or (not is_appr and (not (250 <= Descriptors.MolWt(m) <= 500) or m.GetNumHeavyAtoms() > 38)):
            continue          # approved drugs are exempt from the size window
        ikc = Chem.MolToInchiKey(m)[:14]
        if ikc in seen_conn:      # collapse stereo/salt variants of one connectivity
            continue
        seen_conn.add(ikc)
        acts.append(dict(id="BDBM%s" % mid, mol=m, smiles=Chem.MolToSmiles(m), ik=Chem.MolToInchiKey(m),
                         ic50=statistics.median(e["vals"]), n=len(e["vals"]), fp=fp(m),
                         pmids=sorted(p for p in e["pmids"] if p)[:3]))
    print("EGFR IC50<=100nM records", n_ic50, "unique molecules passing filters", len(acts))
    allact_fps = [a["fp"] for a in acts]

    pick = [a for a in acts if a["ik"][:14] in APPROVED.values()]
    found = {n for n, k in APPROVED.items() if any(a["ik"][:14] == k for a in pick)}
    print("approved drugs present:", sorted(found), "missing:", sorted(set(APPROVED) - found))
    rest = [a for a in acts if a not in pick]
    rnd.shuffle(rest)
    rest = rest[:600]                       # cheap MaxMin over a seeded random subset
    while len(pick) < N_ACTIVES and rest:
        best = max(rest, key=lambda r: min(1 - DataStructs.TanimotoSimilarity(r["fp"], p["fp"]) for p in pick))
        pick.append(best); rest.remove(best)
    pick_ik = {a["ik"] for a in pick}; all_ik = {a["ik"] for a in acts}
    pick_smi = {a["smiles"] for a in acts}

    # decoy pool from ZINC250k
    pool = []
    with open(fetch(ZINC_URL, "zinc250k.csv")) as f:
        for row in csv.DictReader(f):
            pool.append(row["smiles"].strip())
    rnd.shuffle(pool)
    pool = pool[:90000]
    cand = []
    for s in pool:
        m = canon(s)
        if m is None:
            continue
        smi = Chem.MolToSmiles(m)
        ik = Chem.MolToInchiKey(m)
        if ik in all_ik or smi in pick_smi:
            continue
        cand.append(dict(smiles=smi, ik=ik, mol=m, p=props(m)))
    print("decoy candidates", len(cand))
    decoys, used = [], set()
    for a in pick:
        pa = props(a["mol"])
        ok = [d for d in cand if d["ik"] not in used
              and all(abs(d["p"][k] - pa[k]) <= TOL[k] for k in TOL)]
        rnd.shuffle(ok)
        got = 0
        for d in ok:
            if got >= DECOYS_PER_ACTIVE:
                break
            d.setdefault("fp", fp(d["mol"]))
            if max(DataStructs.BulkTanimotoSimilarity(d["fp"], allact_fps)) >= MAX_SIM_TO_ANY_ACTIVE:
                continue
            used.add(d["ik"]); d["matched_to"] = a["id"]; decoys.append(d); got += 1
        if got < DECOYS_PER_ACTIVE:
            print("only", got, "decoys for", a["id"])
    assert not ({d["ik"] for d in decoys} & all_ik)

    # reference actives: 5 non-approved, so the 5 approved drugs stay in the test set
    non_appr = [a for a in pick if a["ik"][:14] not in APPROVED.values()]
    ref_ids = {a["id"] for a in rnd.sample(non_appr, N_REFERENCE)}
    lib = []
    for a in pick:
        lib.append(dict(smiles=a["smiles"], id=a["id"], label="reference" if a["id"] in ref_ids else "active",
                        source="BindingDB P00533 IC50 median %.3g nM (n=%d) pmid=%s" % (a["ic50"], a["n"], ";".join(a["pmids"]))))
    for i, d in enumerate(decoys):
        d["id"] = "ZDEC%04d" % i
        lib.append(dict(smiles=d["smiles"], id=d["id"], label="decoy",
                        source="ZINC250k; matched_to=%s" % d["matched_to"]))
    assert len({l["smiles"] for l in lib}) == len(lib)
    assert len({Chem.MolToInchiKey(Chem.MolFromSmiles(l["smiles"])) for l in lib}) == len(lib)
    rnd.shuffle(lib)
    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, "labels.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, ["smiles", "id", "label", "source"]); w.writeheader(); w.writerows(lib)

    def wr(name, items):
        with open(os.path.join(DATA, name), "w") as f:
            f.write("".join("%s %s\n" % (s, i) for s, i in items))
    # library.smi / reference_actives.smi: bare SMILES, one per line (ids live in labels.csv) so the
    # chain's smiles_file_to_json_list handoff needs no column parsing
    def wr_bare(name, smis):
        with open(os.path.join(DATA, name), "w") as f:
            f.write("".join(s + "\n" for s in smis))
    wr_bare("library.smi", [l["smiles"] for l in lib if l["label"] != "reference"])
    wr_bare("reference_actives.smi", [l["smiles"] for l in lib if l["label"] == "reference"])
    wr("actives.smi", [(l["smiles"], l["id"] + "|" + l["source"].replace(" ", "_")) for l in lib if l["label"] != "decoy"])
    wr("decoys.smi", [(d["smiles"], d["id"]) for d in decoys])
    names = {a["ik"][:14]: n for n, a in ((n, a) for a in pick for n, k in APPROVED.items() if a["ik"][:14] == k)}
    stats = dict(query_date=str(date.today()), seed=SEED, n_actives_total=len(pick), n_reference=len(ref_ids),
                 n_test_actives=len(pick) - len(ref_ids), n_decoys=len(decoys), tolerances=TOL,
                 max_tanimoto_decoy_to_any_known_active=MAX_SIM_TO_ANY_ACTIVE,
                 decoys_per_active_cap=DECOYS_PER_ACTIVE, ic50_records_le_100nM=n_ic50,
                 unique_candidate_actives=len(acts), approved_present=sorted(found),
                 approved_ids={n: a["id"] for a in pick for n, k in APPROVED.items() if a["ik"][:14] == k},
                 reference_ids=sorted(ref_ids), decoy_candidates=len(cand))
    json.dump(stats, open(os.path.join(DATA, "_build_stats.json"), "w"), indent=1)
    print(json.dumps(stats))


main()
