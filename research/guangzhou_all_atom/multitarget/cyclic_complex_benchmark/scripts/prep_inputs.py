"""Build co-folding inputs + ground-truth structure + metadata for one manifest complex.

Outputs (per complex_id) in OUT/<complex_id>/:
  boltz.yaml        Boltz-2 input (receptor chains A,B,..; peptide chain Z; cyclic flag / bond constraints / CCD modifications)
  chai.fasta        Chai-1 FASTA (CCD residues in parentheses)       [+ chai_restraints.csv when closures are expressible]
  native.pdb        ground truth (polymer chains only, heavy atoms, first altloc), chains renamed A..,Z, residues numbered by label_seq_id
  meta.json         chain map, peptide residues (ccd per position), closures (pos/atom pairs), expressibility notes

Single-letter chain ids are used for BOTH the prediction and the ground truth, so no chain-mapping search is needed at scoring time.
No ground-truth coordinates are given to the model (sequence + closure topology only).
"""
import csv, gzip, io, json, os, sys, urllib.request, re
import gemmi

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STD = {"ALA": "A", "ARG": "R", "ASN": "N", "ASP": "D", "CYS": "C", "GLN": "Q", "GLU": "E", "GLY": "G", "HIS": "H", "ILE": "I",
       "LEU": "L", "LYS": "K", "MET": "M", "PHE": "F", "PRO": "P", "SER": "S", "THR": "T", "TRP": "W", "TYR": "Y", "VAL": "V"}
CLOSURE_RE = re.compile(r"^(\d+):([A-Z0-9]+)\.([A-Z0-9']+)-(\d+):([A-Z0-9]+)\.([A-Z0-9']+)$")
# ideal closure-bond lengths (A) by atom-element pair, used for ring-validity (tolerance +/-0.3 A, see PREREG)
IDEAL = {("S", "S"): 2.03, ("C", "N"): 1.33, ("C", "S"): 1.82, ("C", "C"): 1.54, ("C", "O"): 1.36}


def load_manifest():
    return list(csv.DictReader(open(os.path.join(HERE, "manifest.csv"))))


def fetch_cif(pdb, cache):
    os.makedirs(cache, exist_ok=True)
    fn = os.path.join(cache, f"{pdb}.cif")
    if not os.path.exists(fn):
        raw = urllib.request.urlopen(f"https://files.rcsb.org/download/{pdb}.cif.gz", timeout=120).read()
        open(fn, "w").write(gzip.decompress(raw).decode())
    return fn


def parse_closures(s):
    out = []
    for part in s.split(";"):
        m = CLOSURE_RE.match(part.strip())
        if not m:
            raise ValueError(f"unparseable closure {part!r}")
        p1, c1, a1, p2, c2, a2 = m.groups()
        out.append(dict(pos1=int(p1), ccd1=c1, atom1=a1, pos2=int(p2), ccd2=c2, atom2=a2))
    return out


def one_letter(ccd):
    if ccd in STD:
        return STD[ccd]
    t = gemmi.find_tabulated_residue(ccd)
    if t is not None and t.is_amino_acid() and t.one_letter_code.strip():
        return t.one_letter_code.upper()
    return "X"


def classify_closure(cl, plen):
    """head-to-tail amide if it joins N of residue 1 and C of the last residue."""
    s = {(cl["pos1"], cl["atom1"]), (cl["pos2"], cl["atom2"])}
    return "h2t" if s == {(1, "N"), (plen, "C")} else "other"


def build(row, cache, outdir):
    cid = row["complex_id"]
    st = gemmi.read_structure(fetch_cif(row["pdb_id"], cache))
    st.setup_entities()
    st.remove_alternative_conformations()
    st.remove_hydrogens()
    model = st[0]
    pep_auth = row["peptide_chain"]
    rec_auth = row["receptor_chains"].split(";")
    pep_ch = model.find_chain(pep_auth)
    notes = []
    ents = {e.name: e for e in st.entities}
    pep_ent = ents[pep_ch[0].entity_id]
    pep_comps = list(pep_ent.full_sequence)
    mlist = row["peptide_ccd_list"].split("-")
    if [c for c in pep_comps] != mlist:
        notes.append(f"entity full_sequence != manifest ccd list; using manifest")
        pep_comps = mlist
    plen = len(pep_comps)
    closures = parse_closures(row["closures"])
    h2t = any(classify_closure(c, plen) == "h2t" for c in closures)
    other = [c for c in closures if classify_closure(c, plen) != "h2t"]
    # chain map
    cmap = {}
    letters = "ABCDEFGHIJKLMNOPQRSTUVWXY"
    for i, ra in enumerate(rec_auth):
        cmap[ra] = letters[i]
    cmap[pep_auth] = "Z"
    # receptor sequences
    rec_seq = {}
    for ra in rec_auth:
        ch = model.find_chain(ra)
        ent = ents[ch[0].entity_id]
        rec_seq[cmap[ra]] = "".join(one_letter(x) for x in ent.full_sequence)
    # peptide
    pep_seq = "".join(one_letter(c) for c in pep_comps)
    mods = [(i + 1, c) for i, c in enumerate(pep_comps) if c not in STD]
    # ---- Boltz YAML ----
    # ALWAYS emit strings as JSON-quoted scalars (valid YAML). Unquoted, YAML types them: CCD '004' -> int 4 ("CCD component 4 not found",
    # 14/40 pilot complexes failed this way, silently skipped by Boltz with rc 0), and NO/ON/Y/NULL-like tokens -> bool/None.
    q = json.dumps
    y = ["version: 1", "sequences:"]
    for cid_, seq in rec_seq.items():
        y += [f"  - protein:", f"      id: {q(str(cid_))}", f"      sequence: {q(seq)}"]
    y += ["  - protein:", "      id: Z", f"      sequence: {q(pep_seq)}", "      msa: empty"]
    if h2t:
        y += ["      cyclic: true"]
    if mods:
        y += ["      modifications:"]
        for p, c in mods:
            y += [f"        - position: {p}", f"          ccd: {q(str(c))}"]
    if other:
        y += ["constraints:"]
        for c in other:
            y += ["  - bond:", f"      atom1: [Z, {c['pos1']}, {c['atom1']}]", f"      atom2: [Z, {c['pos2']}, {c['atom2']}]"]
    os.makedirs(os.path.join(outdir, cid), exist_ok=True)
    open(os.path.join(outdir, cid, "boltz.yaml"), "w").write("\n".join(y) + "\n")
    # ---- Chai FASTA (CCD in parentheses); restraints written by prep_chai (needs atom naming), see meta ----
    def chai_seq(comps):
        return "".join(STD_LETTER(c) if c in STD else f"({c})" for c in comps)
    def STD_LETTER(c): return STD[c]
    fa = []
    for ra in rec_auth:
        ent = ents[model.find_chain(ra)[0].entity_id]
        fa += [f">protein|name={cmap[ra]}", "".join(STD[x] if x in STD else (one_letter(x) if one_letter(x) != "X" else "X") for x in ent.full_sequence)]
    fa += [">protein|name=Z", chai_seq(pep_comps)]
    open(os.path.join(outdir, cid, "chai.fasta"), "w").write("\n".join(fa) + "\n")
    # ---- native ----
    nst = gemmi.Structure()
    nst.spacegroup_hm = "P 1"
    nm = gemmi.Model("1")
    for auth, new in cmap.items():
        src = model.find_chain(auth)
        nc = gemmi.Chain(new)
        for r in src:
            if r.het_flag == "H" and r.name not in {x for x in pep_comps}:
                continue
            if r.label_seq is None:
                continue
            nr = gemmi.Residue()
            nr.name = r.name
            nr.seqid = gemmi.SeqId(int(r.label_seq), " ")
            nr.het_flag = "A"
            for a in r:
                if a.element.name == "H":
                    continue
                nr.add_atom(a)
            nc.add_residue(nr)
        nm.add_chain(nc)
    nst.add_model(nm)
    nst.setup_entities()
    buf = nst.make_pdb_string()
    open(os.path.join(outdir, cid, "native.pdb"), "w").write("".join(l for l in buf.splitlines(True) if not l.startswith(("ANISOU", "CRYST1"))))
    meta = dict(complex_id=cid, pdb_id=row["pdb_id"], chain_map=cmap, receptor_chains=list(rec_seq), peptide_chain="Z", peptide_ccds=pep_comps,
                peptide_seq=pep_seq, rec_seq=rec_seq, cyclic_flag=h2t, closures=closures, cyclisation_type=row["cyclisation_type"],
                modifications=[{"position": p, "ccd": c} for p, c in mods], notes=notes, set=row["set"],
                receptor_cluster40=row["receptor_cluster40"], runnable_strict=row["runnable_strict"], runnable_ccd=row["runnable_ccd"])
    json.dump(meta, open(os.path.join(outdir, cid, "meta.json"), "w"), indent=1)
    return meta


if __name__ == "__main__":
    ids = sys.argv[3:]
    rows = {r["complex_id"]: r for r in load_manifest()}
    for i in ids:
        m = build(rows[i], sys.argv[1], sys.argv[2])
        print(i, "ok", m["peptide_seq"], m["cyclic_flag"], [c["atom1"] + "-" + c["atom2"] for c in m["closures"]], m["notes"])
