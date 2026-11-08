"""Assemble manifest.csv from the cache of per-entry interface analysis (run from the work dir).
Usage: python build_manifest.py <work_dir> <mmseqs_bin> <out_dir>"""
import json, glob, csv, subprocess, sys, os, collections
work, MM, out = sys.argv[1:4]
CUTOFF = "2023-10-01"; STRICT = "2025-07-01"
STD = {"ALA":"A","ARG":"R","ASN":"N","ASP":"D","CYS":"C","GLN":"Q","GLU":"E","GLY":"G","HIS":"H","ILE":"I","LEU":"L","LYS":"K","MET":"M","PHE":"F","PRO":"P","SER":"S","THR":"T","TRP":"W","TYR":"Y","VAL":"V"}
gq = {e["rcsb_id"]: e for e in json.load(open(f"{work}/pool_graphql.json"))}
rows = []
for f in sorted(glob.glob(f"{work}/cache/*.json")):
    for r in json.load(open(f))["res"]:
        if r["n_iface_res"] >= 5 and not r.get("interchain_cov"): rows.append(r)
# one row per (entry, peptide entity): chain with the largest interface
best = {}
copies = collections.Counter()
for r in rows:
    copies[r["entity"]] += 1
    if r["entity"] not in best or r["n_iface_res"] > best[r["entity"]]["n_iface_res"]: best[r["entity"]] = r
man = []
for ent, r in sorted(best.items()):
    g = gq[ent]; e = g["entry"]
    comps = r["pep_comps"]
    if not comps: continue
    nonc = [c for c in comps if c not in STD]
    seq = "".join(STD.get(c, "X") for c in comps)
    # receptor: chains in contact; primary = entity with most contact atoms
    ec = collections.Counter()
    for ch, n in r["rec_chain_contacts"].items(): ec[r["rec_entity"][ch]] += n
    prim = ec.most_common(1)[0][0]
    prim_chain = [ch for ch in r["rec_chain_contacts"] if r["rec_entity"][ch] == prim][0]
    rseq = "".join(r["rec_seqs"][prim_chain])
    rec_chains = [ch for ch in r["rec_chain_contacts"] if r["rec_chain_contacts"][ch] >= 10]
    if prim_chain not in rec_chains: rec_chains.append(prim_chain)
    cl = r["closures"]; L = r["L"]
    def canon(i): return comps[i-1] in STD
    # expressibility in Boltz-2 (bond constraint: canonical residues + CCD ligands only; cyclic flag for head-to-tail)
    reasons = []
    for (a, b, kind, a1, a2, c1, c2) in cl:
        if kind == "head_to_tail_amide" and a <= 2 and b >= L-1: continue
        if not (canon(a) and canon(b)): reasons.append(f"closure {a}-{b} ({kind}) involves non-canonical residue")
    if r["closure_types"] == "head_to_tail_amide" and len(cl) == 1: pass
    runnable_strict = (not nonc) and not reasons
    runnable_ccd = not reasons   # NCAAs as CCD 'modifications', closures between canonical residues only
    if nonc and not reasons: pass
    rd = e["rcsb_accession_info"]["deposit_date"][:10]
    man.append(dict(
        complex_id=ent, pdb_id=ent.split("_")[0], peptide_entity=ent.split("_")[1],
        peptide_chain=r["auth"], n_peptide_copies_in_AU=copies[ent],
        receptor_chains=";".join(rec_chains), primary_receptor_chain=prim_chain,
        receptor_len=len(rseq), peptide_len=L, peptide_seq=seq, peptide_ccd_list="-".join(comps),
        noncanonical_ccds=";".join(sorted(set(nonc))), n_noncanonical=len(nonc),
        cyclisation_type=r["closure_types"], ring_class=r["ring_class"],
        closures=";".join(f"{a}:{c1}.{a1}-{b}:{c2}.{a2}" for (a,b,k,a1,a2,c1,c2) in cl),
        resolution=e["rcsb_entry_info"]["resolution_combined"][0], method=e["rcsb_entry_info"]["experimental_method"],
        deposit_date=rd, deposit_year=rd[:4], n_iface_res_5A=r["n_iface_res"],
        set="post" if rd >= CUTOFF else "pre", post_2025_07=int(rd >= STRICT),
        runnable_ccd=int(runnable_ccd), runnable_strict=int(runnable_strict),
        runnable_note="; ".join(reasons), _rseq=rseq))
# --- clustering via MMseqs2
def cluster(seqs, ident, cov, extra=()):
    d = f"{work}/mm_{ident}"; os.makedirs(d, exist_ok=True)
    fa = f"{d}/in.fa"
    uniq = {}
    for i, s in enumerate(seqs): uniq.setdefault(s, f"s{len(uniq)}")
    with open(fa, "w") as fh:
        for s, n in uniq.items(): fh.write(f">{n}\n{s}\n")
    subprocess.run([MM, "easy-cluster", fa, f"{d}/res", f"{d}/tmp", "--min-seq-id", str(ident), "-c", str(cov), "--cov-mode", "0", "-v", "1", *extra], check=True, capture_output=True)
    rep = {}
    for line in open(f"{d}/res_cluster.tsv"):
        a, b = line.split()[:2]; rep[b] = a
    return [rep[uniq[s]] for s in seqs]
rc = cluster([m["_rseq"] for m in man], 0.4, 0.8)
pc = cluster([m["peptide_seq"].replace("X", "A") if False else m["peptide_seq"] for m in man], 0.6, 0.8, ("-s", "8", "--spaced-kmer-mode", "0", "--kmer-per-seq", "100"))
cm = {}
for m, a, b in zip(man, rc, pc):
    m["receptor_cluster40"] = "R" + a[1:]; m["peptide_cluster60"] = "P" + b[1:]
# mark peptides with NCAA 'X' in clustering as caveat
for m in man:
    m["peptide_seq_has_X"] = int("X" in m["peptide_seq"])
pre_clusters = {m["receptor_cluster40"] for m in man if m["set"] == "pre"}
for m in man: m["receptor_cluster_also_in_pre_set"] = int(m["receptor_cluster40"] in pre_clusters)
# representative per receptor cluster WITHIN each set: best resolution
for st in ("pre", "post"):
    seen = {}
    for m in sorted([m for m in man if m["set"] == st], key=lambda m: (m["receptor_cluster40"], m["runnable_ccd"] == 0, m["resolution"], m["pdb_id"])):
        seen.setdefault(m["receptor_cluster40"], m["complex_id"])
    for m in man:
        if m["set"] == st: m["nr_rep_in_set"] = int(seen[m["receptor_cluster40"]] == m["complex_id"])
for m in man: m.pop("_rseq")
os.makedirs(out, exist_ok=True)
cols = list(man[0].keys())
with open(f"{out}/manifest.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols); w.writeheader(); w.writerows(man)
print(len(man), "rows")
