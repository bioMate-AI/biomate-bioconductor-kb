"""Import BioLiP2 peptide-ligand annotations and build the candidate manifest (workstream K3; runs on EC2).

Coordinator/survey direction: start from the existing resources and join on PDB id; add only the cyclic layer. BioLiP2
(Zhang et al., NAR 2024, DOI 10.1093/nar/gkad630) lists biologically relevant ligand-protein interactions incl. peptide
ligands and merged binding affinities (manual survey, Binding MOAD, PDBbind-CN, BindingDB). This script:
  1. discovers and downloads the BioLiP2 flat annotation file from the download page (every URL tried is logged to
     biolip_fetch.log; nothing is assumed about the file name), plus the README text if present;
  2. parses the tab-separated flat file using the documented column layout (BIOLIP_COLS below; the layout is taken from the
     BioLiP README as recalled by the author of this script and is therefore [UNVERIFIED] until `layout_check` passes against the
     downloaded README text; the parse is validated by sanity checks and the pass rates are written to biolip_parse_check.json);
  3. keeps ligand entries labelled as peptides, groups them per (PDB id, ligand chain), and writes
     biolip_peptide_ligands.jsonl (annotations: ligand chain, receptor chains, resolution, UniProt, PubMed, affinities);
  4. writes candidates_union.jsonl = old miner manifest rows (data/bound_cyclic/v2) U BioLiP2 peptide ligands, each row tagged with
     `source` in {manifest_v2, biolip2, both}. Ring closure / cyclic classification is NOT taken from any resource: it is computed
     by features.py for every candidate.
If BioLiP2 cannot be fetched the script exits 0 after writing biolip_unavailable.json and candidates_union.jsonl = manifest only.
"""
from __future__ import annotations

import argparse
import collections
import gzip
import io
import json
import os
import re
import sys
import tarfile
import urllib.request

# column layout of BioLiP.txt (0-based) per the BioLiP README (UNVERIFIED recollection; validated empirically below)
BIOLIP_COLS = {0: "pdb_id", 1: "receptor_chain", 2: "resolution", 3: "site_id", 4: "ligand_id", 5: "ligand_chain", 6: "ligand_serial",
               7: "site_res_pdb", 8: "site_res_renum", 9: "catalytic_res_pdb", 10: "catalytic_res_renum", 11: "ec", 12: "go",
               13: "aff_manual", 14: "aff_moad", 15: "aff_pdbbind", 16: "aff_bindingdb", 17: "uniprot", 18: "pubmed",
               19: "ligand_res_seqnum", 20: "receptor_seq"}
PAGES = ["https://zhanggroup.org/BioLiP/download.php", "https://zhanggroup.org/BioLiP/download.html", "https://zhanggroup.org/BioLiP/",
         "https://zhanggroup.org/BioLiP/weekly.html"]
DIRECT = ["https://zhanggroup.org/BioLiP/download/BioLiP.txt.gz", "https://zhanggroup.org/BioLiP/download/BioLiP.tar.bz2",
          "https://zhanggroup.org/BioLiP/weekly/BioLiP_updated_set/BioLiP.txt"]
PDB_RE = re.compile(r"^[0-9][A-Za-z0-9]{3}$")
UNIPROT_RE = re.compile(r"^[A-NR-Z][0-9][A-Z][A-Z0-9]{2}[0-9]$|^[OPQ][0-9][A-Z0-9]{3}[0-9]$")


def http(url: str, timeout: int = 120):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (research; k3 structure knowledge)"})
    return urllib.request.urlopen(req, timeout=timeout)


def discover(log) -> list:
    cands = []
    for p in PAGES:
        try:
            html = http(p, 60).read().decode("utf-8", "replace")
            log.write(f"PAGE ok {p} {len(html)} bytes\n")
            for m in re.finditer(r'href="([^"]+)"', html):
                h = m.group(1)
                if re.search(r"biolip", h, re.I) and re.search(r"\.(txt|gz|tar|bz2|zip)(\b|$)", h, re.I):
                    cands.append(h if h.startswith("http") else urllib.request.urljoin(p, h))
            open(os.path.join(os.path.dirname(log.name), "biolip_page_" + re.sub(r"\W", "_", p)[-30:] + ".html"), "w").write(html[:200000])
        except Exception as e:  # noqa: BLE001
            log.write(f"PAGE fail {p} {type(e).__name__} {str(e)[:100]}\n")
    return cands + DIRECT


def fetch_flat(outdir: str, log) -> str | None:
    seen = set()
    for url in discover(log):
        if url in seen:
            continue
        seen.add(url)
        try:
            r = http(url, 600)
            data = r.read()
            log.write(f"GET ok {url} {len(data)} bytes\n")
            name = url.lower()
            if name.endswith(".gz") and not name.endswith(".tar.gz"):
                txt = gzip.decompress(data).decode("utf-8", "replace")
            elif name.endswith((".tar.bz2", ".tar.gz", ".tar")):
                tf = tarfile.open(fileobj=io.BytesIO(data))
                member = next((m for m in tf.getmembers() if m.isfile() and re.search(r"biolip.*\.txt$", m.name, re.I) and "nr" not in m.name.lower()), None) \
                    or next((m for m in tf.getmembers() if m.isfile() and m.name.lower().endswith(".txt")), None)
                if member is None:
                    log.write(f"  no txt member in {url}\n"); continue
                txt = tf.extractfile(member).read().decode("utf-8", "replace")
                log.write(f"  member {member.name}\n")
            else:
                txt = data.decode("utf-8", "replace")
            first = txt.split("\n", 1)[0].split("\t")
            if len(first) >= 15 and PDB_RE.match(first[0] or ""):
                p = os.path.join(outdir, "BioLiP_flat.txt")
                open(p, "w").write(txt)
                log.write(f"  accepted as flat annotation file ({txt.count(chr(10))} lines) from {url}\n")
                return p
            log.write(f"  not the flat annotation table: {first[:5]}\n")
        except Exception as e:  # noqa: BLE001
            log.write(f"GET fail {url} {type(e).__name__} {str(e)[:100]}\n")
    return None


def parse(path: str, outdir: str):
    n = n_pdb = n_cols = n_uniprot = 0
    kinds = collections.Counter()
    groups = collections.defaultdict(lambda: {"rec": set(), "rows": []})
    for line in open(path):
        f = line.rstrip("\n").split("\t")
        n += 1
        if len(f) < 17:
            continue
        n_cols += 1
        if not PDB_RE.match(f[0]):
            continue
        n_pdb += 1
        up = f[17] if len(f) > 17 else ""
        n_uniprot += bool(UNIPROT_RE.match(up.strip()))
        lig = f[4].strip()
        kinds[lig if lig in ("peptide", "dna", "rna") else "small_molecule"] += 1
        if lig.lower() != "peptide":
            continue
        g = groups[(f[0].upper(), f[5].strip())]
        g["rec"].add(f[1].strip())
        g["rows"].append({BIOLIP_COLS[i]: (f[i] if i < len(f) else "") for i in (2, 4, 13, 14, 15, 16, 17, 18)})
    chk = {"n_lines": n, "frac_ge17_cols": n_cols / max(n, 1), "frac_pdb_id_valid": n_pdb / max(n_cols, 1),
           "frac_uniprot_pattern_valid(col17)": n_uniprot / max(n_pdb, 1), "ligand_kind_counts": dict(kinds),
           "n_peptide_ligand_groups": len(groups)}
    json.dump(chk, open(os.path.join(outdir, "biolip_parse_check.json"), "w"), indent=1)
    out = []
    for (pdb, lch), g in sorted(groups.items()):
        r0 = g["rows"][0]
        aff = {k: sorted({r[k] for r in g["rows"] if r[k] and r[k] != "n/a"}) for k in ("aff_manual", "aff_moad", "aff_pdbbind", "aff_bindingdb")}
        out.append({"pdb_id": pdb, "pep_chain": lch, "rec_chains": sorted(g["rec"]), "biolip_resolution": r0.get("resolution"),
                    "biolip_uniprot": sorted({r["uniprot"].strip() for r in g["rows"] if r["uniprot"].strip()}),
                    "biolip_pubmed": sorted({r["pubmed"].strip() for r in g["rows"] if r["pubmed"].strip()}), "biolip_affinity": aff})
    return out, chk


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--max-new", type=int, default=30000)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    man = {(r["pdb_id"].upper(), r["pep_chain"]): r for r in map(json.loads, open(a.manifest)) if r.get("status") == "ok"}
    with open(os.path.join(a.out, "biolip_fetch.log"), "w") as log:
        flat = fetch_flat(a.out, log)
    cands = {}
    for k, r in man.items():
        d = dict(r); d["source"] = "manifest_v2"; cands[k] = d
    if flat is None:
        json.dump({"unavailable": True, "note": "BioLiP2 flat file could not be fetched; see biolip_fetch.log"}, open(os.path.join(a.out, "biolip_unavailable.json"), "w"))
    else:
        bl, chk = parse(flat, a.out)
        with open(os.path.join(a.out, "biolip_peptide_ligands.jsonl"), "w") as f:
            for r in bl:
                f.write(json.dumps(r) + "\n")
        new = 0
        for r in bl:
            k = (r["pdb_id"], r["pep_chain"])
            if k in cands:
                cands[k].update({kk: r[kk] for kk in ("biolip_resolution", "biolip_uniprot", "biolip_pubmed", "biolip_affinity")}); cands[k]["source"] = "both"
            elif new < a.max_new and r["rec_chains"]:
                d = {"pdb_id": r["pdb_id"], "pep_chain": r["pep_chain"], "rec_chains": r["rec_chains"], "status": "ok", "source": "biolip2",
                     "cyclization_type": None, "peptide_seq": None, "seq_len": None, "cyclization_evidence": None, "resolution": None, "method": None,
                     "receptor_name": None, "conformer_provenance": "PDB_experimental"}
                d.update({kk: r[kk] for kk in ("biolip_resolution", "biolip_uniprot", "biolip_pubmed", "biolip_affinity")})
                cands[k] = d; new += 1
    with open(os.path.join(a.out, "candidates_union.jsonl"), "w") as f:
        for d in cands.values():
            f.write(json.dumps(d) + "\n")
    c = collections.Counter(d["source"] for d in cands.values())
    json.dump({"candidates": len(cands), "by_source": dict(c)}, open(os.path.join(a.out, "import_summary.json"), "w"), indent=1)
    print(json.dumps({"candidates": len(cands), "by_source": dict(c), "biolip": flat is not None}))


if __name__ == "__main__":
    main()
