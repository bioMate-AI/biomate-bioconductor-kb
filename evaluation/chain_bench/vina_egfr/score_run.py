#!/usr/bin/env python3
"""Score a docking_autodock_vina chain run against the EGFR bench labels.

Input formats (auto-detected by suffix):
  * .json : the workflow's docking_autodock_vina_results.json
            {"results":[{"smiles":..., "best_affinity_kcal_mol": -9.1, ...} | {"smiles":..., "error":...}]}
            (docking_autodock_vina/main.nf: results_list entries, written to
            docking_autodock_vina_results.json). Entries with "error" or without
            best_affinity_kcal_mol are unscored. The same file may hold a bare list of
            such entries or a chain "ranked hits" list with "smiles" + a score key.
  * .csv  : columns smiles + one of best_affinity_kcal_mol / affinity / score.
Score convention: Vina kcal/mol, MORE NEGATIVE = BETTER (rank ascending).

Labels: labels.csv (smiles,id,label,source). label 'reference' compounds were given to
the pharmacophore step and are EXCLUDED from scoring. Library compounds that have no
score are counted as unscored; unscored actives count as misses (ranked last).

Python 3.9 safe, stdlib only; rdkit is imported lazily for canonical-SMILES matching.
"""
import argparse, csv, json, math, os, random, sys

SCORE_KEYS = ("best_affinity_kcal_mol", "affinity_kcal_mol", "affinity", "score")


class ScoreError(Exception):
    pass


def _need(path, what):
    if not os.path.isfile(path):
        raise ScoreError("%s not found: %s" % (what, path))


def _canon_fn():
    try:
        from rdkit import Chem
    except Exception:
        return None

    def canon(s):
        m = Chem.MolFromSmiles(s)
        return Chem.MolToSmiles(m) if m is not None else None
    return canon


def read_labels(path):
    _need(path, "labels file")
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows or not {"smiles", "label"} <= set(rows[0]):
        raise ScoreError("labels file needs columns smiles,label: %s" % path)
    return rows


def read_scores(path):
    """Return list of (smiles, score_or_None)."""
    _need(path, "docking output")
    out = []
    if path.lower().endswith(".json"):
        with open(path) as f:
            data = json.load(f)
        entries = data.get("results") if isinstance(data, dict) else data
        if not isinstance(entries, list):
            raise ScoreError("json has no 'results' list: %s" % path)
        for e in entries:
            smi = e.get("smiles")
            if not smi:
                continue
            sc = None
            for k in SCORE_KEYS:
                if e.get(k) is not None and "error" not in e:
                    sc = float(e[k])
                    break
            out.append((smi, sc))
    else:
        with open(path, newline="") as f:
            for r in csv.DictReader(f):
                smi = r.get("smiles") or r.get("SMILES")
                if not smi:
                    raise ScoreError("csv needs a smiles column: %s" % path)
                sc = None
                for k in SCORE_KEYS:
                    if r.get(k) not in (None, ""):
                        sc = float(r[k])
                        break
                out.append((smi, sc))
    if not out:
        raise ScoreError("no docking entries found in %s" % path)
    return out


def auroc(scores, labels):
    """scores: higher = more active-like; labels 1/0. Ties get average rank."""
    n_pos = sum(labels)
    n_neg = len(labels) - n_pos
    if n_pos == 0 or n_neg == 0:
        raise ScoreError("need at least one active and one decoy to compute AUROC")
    order = sorted(range(len(scores)), key=lambda i: scores[i])
    ranks = [0.0] * len(scores)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and scores[order[j + 1]] == scores[order[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            ranks[order[k]] = avg
        i = j + 1
    rank_sum = sum(r for r, l in zip(ranks, labels) if l)
    return (rank_sum - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg)


def enrichment_factor(scores, labels, frac):
    """EF at top `frac` of the whole library (unscored compounds included, ranked last).
    Ties inside the cut are broken by input order (stable)."""
    n = len(labels)
    n_top = max(1, int(math.ceil(frac * n)))
    order = sorted(range(n), key=lambda i: -scores[i])
    hits = sum(labels[i] for i in order[:n_top])
    base = sum(labels) / float(n)
    return (hits / float(n_top)) / base if base else float("nan"), hits, n_top


def score_run(docking_path, labels_path, n_perm=1000, seed=0):
    labels = read_labels(labels_path)
    scored = read_scores(docking_path)
    canon = _canon_fn()
    by_exact = {}
    for smi, sc in scored:
        by_exact.setdefault(smi, sc)
    by_canon = {}
    if canon:
        for smi, sc in scored:
            c = canon(smi)
            if c:
                by_canon.setdefault(c, sc)
    lib = [r for r in labels if r["label"] in ("active", "decoy")]
    n_ref = sum(1 for r in labels if r["label"] == "reference")
    s, y, unscored = [], [], {"active": 0, "decoy": 0}
    for r in lib:
        sc = by_exact.get(r["smiles"])
        if sc is None and canon:
            c = canon(r["smiles"])
            sc = by_canon.get(c) if c else None
        is_act = r["label"] == "active"
        if sc is None:
            unscored["active" if is_act else "decoy"] += 1
            s.append(float("-inf"))          # ranked last: a miss
        else:
            s.append(-sc)                    # more negative kcal/mol = better
        y.append(1 if is_act else 0)
    n_scored = len(lib) - sum(unscored.values())
    if n_scored == 0:
        raise ScoreError("none of the %d library compounds matched a docking entry "
                         "(SMILES mismatch?)" % len(lib))
    # replace -inf by a finite floor so ranks/ties behave
    finite = [v for v in s if v != float("-inf")]
    floor = min(finite) - 1.0
    s = [floor if v == float("-inf") else v for v in s]
    obs = auroc(s, y)
    ef1, h1, n1 = enrichment_factor(s, y, 0.01)
    ef5, h5, n5 = enrichment_factor(s, y, 0.05)
    rng = random.Random(seed)
    ge = 0
    yy = list(y)
    for _ in range(n_perm):
        rng.shuffle(yy)
        if auroc(s, yy) >= obs:
            ge += 1
    p = (ge + 1) / float(n_perm + 1)
    return {
        "n_library_scored_set": len(lib), "n_reference_excluded": n_ref,
        "n_actives": sum(y), "n_decoys": len(y) - sum(y),
        "n_scored": n_scored, "n_unscored": sum(unscored.values()),
        "unscored_actives_counted_as_misses": unscored["active"],
        "unscored_decoys": unscored["decoy"],
        "auroc": round(obs, 4),
        "ef1pct": round(ef1, 3), "ef1pct_hits": h1, "ef1pct_n_top": n1,
        "ef5pct": round(ef5, 3), "ef5pct_hits": h5, "ef5pct_n_top": n5,
        "perm_p_value_auroc_ge_observed": round(p, 4), "n_permutations": n_perm,
        "random_baseline_auroc": 0.5,
    }


# ---------------------------------------------------------------- redocking RMSD
def _read_heavy_coords(path):
    """Heavy-atom (element, x, y, z) of the FIRST model/pose of a pdb/pdbqt/sdf/mol file."""
    _need(path, "pose/ligand file")
    atoms = []
    low = path.lower()
    with open(path) as f:
        lines = f.read().splitlines()
    if low.endswith((".sdf", ".mol")):
        counts = lines[3]
        na = int(counts[0:3])
        for ln in lines[4:4 + na]:
            el = ln[31:34].strip()
            if el.upper() != "H":
                atoms.append((el.capitalize(), float(ln[0:10]), float(ln[10:20]), float(ln[20:30])))
    else:
        for ln in lines:
            # Stop at the end of the first model only. PDBQT also has ENDROOT / ENDBRANCH records inside a pose,
            # so a bare startswith("END") cut every pose after its rigid root (10 of erlotinib's 29 heavy atoms).
            if (ln.startswith("ENDMDL") or ln.strip() == "END") and atoms:
                break
            if ln.startswith(("ATOM", "HETATM")):
                name = ln[12:16].strip()
                el = ln[76:78].strip() if len(ln) >= 78 else ""
                if low.endswith(".pdbqt"):
                    el = ln[77:79].strip() if len(ln) >= 79 else ""  # AD type, e.g. A, OA, NA, HD
                    el = {"A": "C", "OA": "O", "NA": "N", "SA": "S", "HD": "H", "HS": "H"}.get(el, el)
                if not el:
                    el = "".join(c for c in name if c.isalpha())[:1]
                el = el.capitalize()
                if el == "H" or name.upper().startswith("H") and el in ("", "H"):
                    continue
                atoms.append((el, float(ln[30:38]), float(ln[38:46]), float(ln[46:54])))
    if not atoms:
        raise ScoreError("no heavy atoms parsed from %s" % path)
    return atoms


def redock_rmsd(pose, crystal_ligand, mode="ordered"):
    """Heavy-atom RMSD (A) between a docked pose and the crystal ligand, NO re-alignment
    (both must be in the receptor frame).  Symmetry-naive.
      mode='ordered' : atom i of the pose pairs with atom i of the crystal ligand
                       (atom counts and element sequence must match).
      mode='nearest' : greedy same-element nearest-neighbour pairing; use when the pose
                       atom order differs from the crystal file.  Optimistic (greedy
                       matching can under-estimate RMSD) -- state this when reporting.
    Pass criterion in this bench: RMSD < 2.0 A."""
    a = _read_heavy_coords(pose)
    b = _read_heavy_coords(crystal_ligand)
    if len(a) != len(b):
        raise ScoreError("heavy atom count differs: pose %d vs crystal %d" % (len(a), len(b)))
    if mode == "ordered":
        if [x[0] for x in a] != [x[0] for x in b]:
            raise ScoreError("element order differs; use mode='nearest'")
        pairs = list(zip(a, b))
    elif mode == "nearest":
        free = list(b)
        pairs = []
        cand = sorted(((math.dist(p[1:], q[1:]) if hasattr(math, "dist") else
                        math.sqrt(sum((u - v) ** 2 for u, v in zip(p[1:], q[1:]))), i, j)
                       for i, p in enumerate(a) for j, q in enumerate(b) if p[0] == q[0]))
        ua, ub = set(), set()
        for _, i, j in cand:
            if i in ua or j in ub:
                continue
            ua.add(i); ub.add(j); pairs.append((a[i], b[j]))
        if len(pairs) != len(a):
            raise ScoreError("element composition differs between pose and crystal ligand")
    else:
        raise ScoreError("unknown mode %r" % mode)
    ss = sum((p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2 + (p[3] - q[3]) ** 2 for p, q in pairs)
    return math.sqrt(ss / len(pairs))


def to_markdown(res):
    L = ["# EGFR 1M17 bench score", ""]
    for k in ("auroc", "ef1pct", "ef5pct", "perm_p_value_auroc_ge_observed"):
        L.append("- %s: %s" % (k, res[k]))
    L.append("- scored %d / %d (unscored %d, of which actives-as-misses %d); reference excluded %d"
             % (res["n_scored"], res["n_library_scored_set"], res["n_unscored"],
                res["unscored_actives_counted_as_misses"], res["n_reference_excluded"]))
    L.append("- EF1%%: %d hits in top %d; EF5%%: %d hits in top %d"
             % (res["ef1pct_hits"], res["ef1pct_n_top"], res["ef5pct_hits"], res["ef5pct_n_top"]))
    if "redock_rmsd_A" in res:
        L.append("- redock RMSD: %.2f A (%s, criterion < 2.0 A, %s)"
                 % (res["redock_rmsd_A"], "PASS" if res["redock_pass"] else "FAIL", res["redock_mode"]))
    return "\n".join(L) + "\n"


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("docking_output", help="docking_autodock_vina_results.json or scores csv")
    ap.add_argument("--labels", default=os.path.join(here, "data", "labels.csv"))
    ap.add_argument("--pose", help="top pose pdbqt/sdf of the erlotinib redock")
    ap.add_argument("--crystal", default=os.path.join(here, "data", "erlotinib_crystal_ligand.pdb"))
    ap.add_argument("--rmsd-mode", default="nearest", choices=["ordered", "nearest"])
    ap.add_argument("--perms", type=int, default=1000)
    ap.add_argument("--out", default="score_report", help="output prefix (.json/.md)")
    a = ap.parse_args(argv)
    try:
        res = score_run(a.docking_output, a.labels, a.perms)
        if a.pose:
            r = redock_rmsd(a.pose, a.crystal, a.rmsd_mode)
            res.update(redock_rmsd_A=round(r, 3), redock_pass=r < 2.0, redock_mode=a.rmsd_mode)
    except ScoreError as e:
        print("ERROR:", e, file=sys.stderr)
        return 2
    with open(a.out + ".json", "w") as f:
        json.dump(res, f, indent=2)
    with open(a.out + ".md", "w") as f:
        f.write(to_markdown(res))
    print(to_markdown(res))
    return 0


if __name__ == "__main__":
    sys.exit(main())
