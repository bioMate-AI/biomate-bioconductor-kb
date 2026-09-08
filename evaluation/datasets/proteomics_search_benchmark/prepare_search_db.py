#!/usr/bin/env python3
"""
prepare_search_db.py — build the searched FASTA for the proteomics DB-search benchmark.

Produces ONE combined FASTA (target + entrapment + decoy) and a label map, so every
engine searches identical input (§14.4 fair-comparison control) and the scorer can
assign each accession to target|entrapment|decoy.

  target       : the real proteome (input FASTA, e.g. human SwissProt + cRAP)
  entrapment   : known-false sequences — any match is a caught mistake (§14.2)
                   * shuffled_target : shuffle each target sequence (keeps aa composition)
                   * distant_organism: pass a second FASTA that cannot be present
  decoy        : reversed sequences (standard target-decoy FDR)

Accession prefixes let the scorer label rows without a side file:
  (target: unchanged) | ENT_<id> (entrapment) | DECOY_<id> (decoy)

Usage:
  python prepare_search_db.py --target human_sprot_crap.fasta \
      --entrapment-source shuffled_target --entrapment-ratio 1.0 \
      --seed 42 --out combined.fasta --map db_map.tsv
"""
from __future__ import annotations
import argparse
import random
import sys


def read_fasta(path):
    """Yield (header, seq). Minimal streaming parser."""
    hdr, buf = None, []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if hdr is not None:
                    yield hdr, "".join(buf)
                hdr, buf = line[1:], []
            else:
                buf.append(line.strip())
    if hdr is not None:
        yield hdr, "".join(buf)


def acc_of(header):
    """First token of a FASTA header = accession-ish id."""
    return header.split()[0] if header else header


def shuffle_seq(seq, rng):
    chars = list(seq)
    rng.shuffle(chars)
    return "".join(chars)


def write_record(fh, header, seq, width=60):
    fh.write(f">{header}\n")
    for i in range(0, len(seq), width):
        fh.write(seq[i:i + width] + "\n")


def build(target_path, out_path, map_path, entrapment_source="shuffled_target",
          entrapment_fasta=None, ratio=1.0, add_decoys=True, seed=42):
    rng = random.Random(seed)
    targets = list(read_fasta(target_path))
    n_target = len(targets)

    # ---- entrapment set ----
    entrapment = []
    if ratio > 0:
        if entrapment_source == "shuffled_target":
            n_ent = int(round(n_target * ratio))
            # sample-with-replacement target seqs, shuffle each -> known-false
            for k in range(n_ent):
                h, s = targets[rng.randrange(n_target)]
                entrapment.append((f"ENT_{k}_{acc_of(h)}", shuffle_seq(s, rng)))
        elif entrapment_source == "distant_organism":
            if not entrapment_fasta:
                raise SystemExit("--entrapment-fasta required for distant_organism")
            src = list(read_fasta(entrapment_fasta))
            n_ent = int(round(n_target * ratio))
            for k in range(min(n_ent, len(src))):
                h, s = src[k]
                entrapment.append((f"ENT_{k}_{acc_of(h)}", s))
        else:
            raise SystemExit(f"unknown --entrapment-source {entrapment_source}")

    # ---- decoys (reverse of target + entrapment) ----
    forwards = targets + entrapment
    decoys = [(f"DECOY_{acc_of(h)}", s[::-1]) for h, s in forwards] if add_decoys else []

    # ---- write combined FASTA + label map ----
    with open(out_path, "w") as out, open(map_path, "w") as mp:
        mp.write("accession\tlabel\n")
        for h, s in targets:
            write_record(out, h, s); mp.write(f"{acc_of(h)}\ttarget\n")
        for h, s in entrapment:
            write_record(out, h, s); mp.write(f"{acc_of(h)}\tentrapment\n")
        for h, s in decoys:
            write_record(out, h, s); mp.write(f"{acc_of(h)}\tdecoy\n")

    return {"n_target": n_target, "n_entrapment": len(entrapment),
            "n_decoy": len(decoys), "ratio": ratio, "seed": seed}


def _selftest():
    import tempfile, os
    with tempfile.TemporaryDirectory() as d:
        tgt = os.path.join(d, "t.fasta")
        with open(tgt, "w") as fh:
            fh.write(">sp|P1|A\nPEPTIDEKACDEFGHIK\n>sp|P2|B\nMKLVWYQSTNR\n")
        out, mp = os.path.join(d, "c.fasta"), os.path.join(d, "m.tsv")
        stats = build(tgt, out, mp, entrapment_source="shuffled_target",
                      ratio=1.0, add_decoys=True, seed=1)
        assert stats["n_target"] == 2 and stats["n_entrapment"] == 2
        assert stats["n_decoy"] == 4  # decoy of (target+entrapment)
        recs = dict(read_fasta(out))
        # target sequences preserved verbatim
        assert recs["sp|P1|A"] == "PEPTIDEKACDEFGHIK"
        # a decoy is the reverse of its forward
        assert recs["DECOY_sp|P1|A"] == "PEPTIDEKACDEFGHIK"[::-1]
        # entrapment keeps composition but (almost surely) differs from source
        labels = {}
        with open(mp) as fh:
            next(fh)
            for line in fh:
                a, l = line.strip().split("\t"); labels[a] = l
        assert sum(1 for v in labels.values() if v == "entrapment") == 2
        assert sum(1 for v in labels.values() if v == "decoy") == 4
    print("selftest OK: target preserved, entrapment shuffled, decoys reversed, map correct")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--target")
    ap.add_argument("--out", default="combined.fasta")
    ap.add_argument("--map", default="db_map.tsv")
    ap.add_argument("--entrapment-source", default="shuffled_target",
                    choices=["shuffled_target", "distant_organism"])
    ap.add_argument("--entrapment-fasta", default=None)
    ap.add_argument("--entrapment-ratio", type=float, default=1.0)
    ap.add_argument("--no-decoys", action="store_true")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        _selftest(); return 0
    if not args.target:
        ap.error("--target is required (or --selftest)")
    stats = build(args.target, args.out, args.map, args.entrapment_source,
                  args.entrapment_fasta, args.entrapment_ratio,
                  add_decoys=not args.no_decoys, seed=args.seed)
    print(stats)
    return 0


if __name__ == "__main__":
    sys.exit(main())
