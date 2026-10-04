#!/usr/bin/env python3
"""ON-INSTANCE extractor: per target, re-fold the top-K candidates with Boltz (cyclic prediction) and
emit candidates.jsonl records {id, candidates:[{cand,dockq,likelihood,scrmsd,confidence}]} for
selfconsistency_rerank.py. Runs inside refold_rerank_driver.sh (Boltz venv active).

VERIFIED locally: NONE of the Boltz/UniMoMo I/O below could be run locally (no Boltz, no UniMoMo repo).
It is grounded in Boltz's documented CLI + the eval-record schema seen in cyclic_eval_summary.py, but the
three ASSUMPTIONs are marked and the code FAILS LOUD (not silently) if they don't hold. Do DRY_RUN=1 for
one target per label and confirm candidates.jsonl looks right BEFORE the full 88x2xK run.

ASSUMPTIONS (confirm on first target):
  A2a  eval_report record = {"id", "DockQ":{"individual":[per-candidate...]}, ...}  (from cyclic_eval_summary)
  A2b  per-candidate likelihood/score is in the record (tried keys below) OR candidate order == likelihood
       rank (UniMoMo's max* = likelihood-selected, so a per-candidate score must exist somewhere).
  A1   candidate pose for (target,k) is  $CAND_GLOB/<target>/<k>.{pdb,cif}  with receptor+peptide chains.
"""
import os, re, json, glob, subprocess, sys, tempfile
sys.path.insert(0, os.environ.get("HERE", "."))
from scrmsd import scrmsd, read_ca   # verified locally

LABEL = os.environ["LABEL"]; DLABEL = os.environ["DLABEL"]; REP = os.environ["REP"]
TOPK = int(os.environ.get("TOPK", "25")); DRY = os.environ.get("DRY_RUN", "0") == "1"
CAND_GLOB = os.environ.get("CAND_GLOB", f"{DLABEL}/candidates")
AA3 = {'ALA':'A','ARG':'R','ASN':'N','ASP':'D','CYS':'C','GLN':'Q','GLU':'E','GLY':'G','HIS':'H','ILE':'I',
       'LEU':'L','LYS':'K','MET':'M','PHE':'F','PRO':'P','SER':'S','THR':'T','TRP':'W','TYR':'Y','VAL':'V'}
LLH_KEYS = ("likelihood", "llh", "logp", "log_prob", "score", "elbo")

def load_records(path):
    recs = []
    for ln in open(path):
        ln = ln.strip()
        if ln.startswith("{"):
            try: recs.append(json.loads(ln))
            except Exception: pass
    if not recs: sys.exit(f"FATAL(A2a): no JSON records in {path}")
    return recs

def per_candidate_dockq(rec):
    dq = rec.get("DockQ", {})
    ind = dq.get("individual")
    if not isinstance(ind, list) or not ind:
        sys.exit(f"FATAL(A2a): record {rec.get('id')} has no DockQ.individual list — confirm schema")
    return ind

def per_candidate_llh(rec, n):
    for k in LLH_KEYS:
        v = rec.get(k)
        if isinstance(v, list) and len(v) == n: return v
        m = rec.get(k) if isinstance(rec.get(k), dict) else None
        if m and isinstance(m.get("individual"), list) and len(m["individual"]) == n:
            return m["individual"]
    # A2b RESOLVED (verified on unimomo-cyclic-ft-20261004T042753Z): UniMoMo's eval_report stores the
    # per-candidate generator score as `individual_pmet` inside each metric dict (identical across all
    # metrics; the `max*`/`min*` fields are the pmet-selected picks). Confirmed argmax(pmet) candidate's
    # DockQ == DockQ["max*"], i.e. HIGHER pmet = the generator's own pick-1 — exactly the semantics
    # selfconsistency_rerank expects for `likelihood` (higher = more likely). Use it as the likelihood.
    for mk in ("DockQ", "AAR", "C_RMSD(CA)", "L_RMSD(CA)"):
        m = rec.get(mk)
        if isinstance(m, dict) and isinstance(m.get("individual_pmet"), list) and len(m["individual_pmet"]) == n:
            return m["individual_pmet"]
    # Last-resort fallback: candidate order == likelihood rank (best first). Flag once.
    sys.stderr.write(f"WARN(A2b): no per-candidate likelihood/pmet for {rec.get('id')}; assuming index order = likelihood rank\n")
    return list(range(n, 0, -1))   # higher = earlier index = more likely

def find_pose(target, k):
    for ext in ("pdb", "cif"):
        for pat in (f"{CAND_GLOB}/{target}/{k}.{ext}", f"{CAND_GLOB}/{target}_{k}.{ext}",
                    f"{CAND_GLOB}/{target}/cand_{k}.{ext}"):
            if os.path.exists(pat): return pat
    hits = glob.glob(f"{CAND_GLOB}/{target}*/*{k}.pdb") + glob.glob(f"{CAND_GLOB}/{target}*/*{k}.cif")
    return hits[0] if hits else None

def pose_seqs(pose):
    """Return (receptor_chain_id, receptor_seq, peptide_chain_id, peptide_seq) using CA parse + resn.
    Peptide = shortest chain."""
    seqs = {}
    for ln in open(pose):
        if ln.startswith(("ATOM", "HETATM")) and ln[12:16].strip() == "CA":
            ch = ln[21]; rn = ln[17:20].strip()
            seqs.setdefault(ch, []).append(AA3.get(rn, "X"))
    if len(seqs) < 2: sys.exit(f"FATAL(A1): pose {pose} has <2 chains; confirm receptor+peptide layout")
    pep = min(seqs, key=lambda c: len(seqs[c])); rec = max(seqs, key=lambda c: len(seqs[c]))
    return rec, "".join(seqs[rec]), pep, "".join(seqs[pep])

def boltz_refold(rec_seq, pep_seq, workdir):
    """Boltz-2 cyclic prediction of receptor+peptide. Returns (refold_pdb_path, confidence) or (None,None).
    Boltz CLI (documented): boltz predict <input.yaml> --out_dir <dir> --override ; cyclic via `cyclic: true`
    on the peptide chain. Confidence from Boltz's confidence_*.json (complex_iptm/iptm)."""
    y = os.path.join(workdir, "in.yaml")
    with open(y, "w") as f:                       # Boltz YAML input schema
        f.write("version: 1\nsequences:\n")
        f.write(f"  - protein:\n      id: R\n      sequence: {rec_seq}\n")
        f.write(f"  - protein:\n      id: P\n      sequence: {pep_seq}\n      cyclic: true\n")
    try:
        subprocess.run(["boltz", "predict", y, "--out_dir", workdir, "--override",
                        "--use_msa_server"], check=True, capture_output=True, timeout=1800)
    except Exception as e:
        sys.stderr.write(f"WARN boltz predict failed: {str(e)[:160]}\n"); return None, None
    pdbs = glob.glob(f"{workdir}/**/*.pdb", recursive=True) + glob.glob(f"{workdir}/**/*.cif", recursive=True)
    conf = None
    for cj in glob.glob(f"{workdir}/**/confidence*.json", recursive=True):
        try:
            cd = json.load(open(cj)); conf = cd.get("complex_iptm") or cd.get("iptm") or cd.get("confidence_score"); break
        except Exception: pass
    return (pdbs[0] if pdbs else None), conf

def main():
    recs = load_records(REP)
    if DRY: recs = recs[:1]
    for rec in recs:
        tid = rec["id"]; dq = per_candidate_dockq(rec); n = len(dq)
        llh = per_candidate_llh(rec, n)
        order = sorted(range(n), key=lambda i: -(llh[i] if i < len(llh) else 0))[:TOPK]
        cands = []
        for k in order:
            pose = find_pose(tid, k)
            if pose is None:
                sys.stderr.write(f"WARN(A1) no pose for {tid} cand {k}\n")
                cands.append({"cand": k, "dockq": dq[k], "likelihood": llh[k] if k < len(llh) else None,
                              "scrmsd": None, "confidence": None}); continue
            rc, rseq, pc, pseq = pose_seqs(pose)
            with tempfile.TemporaryDirectory() as wd:
                refold, conf = boltz_refold(rseq, pseq, wd)
                sc = None
                if refold:
                    try: sc = round(scrmsd(pose, refold, pep_chain=None, on="peptide"), 4)
                    except Exception as e: sys.stderr.write(f"WARN scrmsd {tid}/{k}: {str(e)[:120]}\n")
            cands.append({"cand": k, "dockq": dq[k], "likelihood": llh[k] if k < len(llh) else None,
                          "scrmsd": sc, "confidence": conf})
        print(json.dumps({"id": tid, "candidates": cands}))

if __name__ == "__main__":
    main()
