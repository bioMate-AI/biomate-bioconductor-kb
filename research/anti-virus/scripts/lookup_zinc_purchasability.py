#!/usr/bin/env python3
"""Look up ZINC catalog hits for top Vina SMILES (purchasability proxy)."""
from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"


def zinc_smiles_lookup(smiles: str, dist: int = 0) -> list[dict]:
    """Query ZINC CartBlanche by SMILES (dist=0 exact, try dist=3 analog fallback)."""

    def parse_tsv(text: str) -> list[dict]:
        text = text.strip()
        if not text or "no valid smiles" in text.lower() or text.lower().startswith("error"):
            return []
        lines = text.splitlines()
        if len(lines) < 2:
            return []
        header = lines[0].split("\t")
        out: list[dict] = []
        for line in lines[1:]:
            parts = line.split("\t")
            if len(parts) < len(header):
                continue
            out.append(dict(zip(header, parts)))
        return out

    def get_url(d: int) -> str:
        enc = urllib.parse.quote(smiles, safe="")
        return (
            f"https://cartblanche22.docking.org/smiles.txt"
            f":smiles={enc}&dist={d}&adist={d}&output_fields=zinc_id,smiles,catalogs,tranche"
        )

    def get_post(d: int) -> list[dict]:
        boundary = "----BioMateZincBoundary"
        body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="smiles-in"; filename="q.smi"\r\n'
            f"Content-Type: text/plain\r\n\r\n"
            f"{smiles}\r\n"
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="dist"\r\n\r\n'
            f"{d}\r\n"
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="adist"\r\n\r\n'
            f"{d}\r\n"
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="output_fields"\r\n\r\n'
            f"zinc_id,smiles,catalogs,tranche\r\n"
            f"--{boundary}--\r\n"
        ).encode()
        req = urllib.request.Request(
            "https://cartblanche22.docking.org/smiles.txt",
            data=body,
            headers={
                "User-Agent": "BioMate-zinc-lookup/1.0",
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            return parse_tsv(resp.read().decode("utf-8", errors="replace"))

    last_err: str | None = None
    for d in (dist, 3 if dist == 0 else dist):
        for attempt in ("get", "post"):
            try:
                if attempt == "get":
                    req = urllib.request.Request(
                        get_url(d), headers={"User-Agent": "BioMate-zinc-lookup/1.0"}
                    )
                    with urllib.request.urlopen(req, timeout=60) as resp:
                        hits = parse_tsv(resp.read().decode("utf-8", errors="replace"))
                else:
                    hits = get_post(d)
                if hits:
                    return hits
            except Exception as exc:
                last_err = str(exc)[:200]
    if last_err:
        raise RuntimeError(last_err)
    return []


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--publication-run", type=Path, default=DEFAULT_PUB)
    ap.add_argument("--top-n", type=int, default=5)
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()
    pub = args.publication_run.resolve()
    dock = json.loads(
        (pub / "zinc150_screen/vina/docking_autodock_vina_results.json").read_text(encoding="utf-8")
    )
    ok = [r for r in dock.get("results") or [] if r.get("best_affinity_kcal_mol") is not None]
    top = sorted(ok, key=lambda r: float(r["best_affinity_kcal_mol"]))[: args.top_n]

    rows: list[dict] = []
    for i, hit in enumerate(top, 1):
        sm = hit["smiles"]
        entry: dict = {
            "rank": i,
            "vina_kcal_mol": float(hit["best_affinity_kcal_mol"]),
            "smiles": sm,
            "zinc_hits": [],
            "in_catalog": False,
        }
        try:
            hits = zinc_smiles_lookup(sm)
            entry["zinc_hits"] = hits[:5]
            entry["in_catalog"] = len(hits) > 0
        except Exception as exc:
            entry["lookup_error"] = str(exc)[:200]
        rows.append(entry)

    payload = {
        "looked_up_at": datetime.now(timezone.utc).isoformat(),
        "source": "cartblanche22.docking.org smiles.txt dist=0",
        "top_n": args.top_n,
        "results": rows,
    }
    out = args.out or (pub / "zinc600_screen/ZINC600_TOP5_PURCHASABILITY.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    md_path = out.with_suffix(".md")
    lines = [
        f"# ZINC600 top-{args.top_n} purchasability lookup",
        "",
        f"_Updated: {payload['looked_up_at']}_",
        "",
        "_Note: local `zinc600_library.smi` contains SMILES only (no ZINC IDs). "
        "CartBlanche22 API may return HTTP 400 from some networks; retry manually or use the web UI at "
        "[cartblanche22.docking.org/search/smiles](https://cartblanche22.docking.org/search/smiles).",
        "",
        "| Rank | Vina | In ZINC? | ZINC ID(s) | SMILES |",
        "| ---: | ---: | --- | --- | --- |",
    ]
    for r in rows:
        ids = ", ".join(h.get("zinc_id", "") for h in r["zinc_hits"][:3]) or "—"
        cat = "yes" if r["in_catalog"] else ("api_error" if r.get("lookup_error") else "no")
        sm = r["smiles"][:40]
        lines.append(f"| {r['rank']} | {r['vina_kcal_mol']:.3f} | {cat} | {ids} | `{sm}` |")
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out}")
    print(f"Wrote {md_path}")


if __name__ == "__main__":
    main()
