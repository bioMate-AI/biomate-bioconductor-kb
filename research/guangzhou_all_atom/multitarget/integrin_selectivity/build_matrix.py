"""Build matrix.csv (long format) from the transcribed Kapp 2017 tables and the XML tables of
Quigley 2023 / Tomassi 2021. All numbers are copied verbatim from the sources; nothing is computed
except pIC50 = 9 - log10(IC50 nM)."""
import csv, math, re, sys
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).parent
INTEGRINS = ["avb3", "avb5", "avb6", "avb8", "a5b1", "aIIbb3"]
VAL = re.compile(r"^\s*(>)?\s*([0-9.]+)\s*(?:±\s*([0-9.]+))?\s*$")


def parse_value(s):
    """'13.7 ± 0.3' -> (13.7, 0.3, '='); '> 10000' -> (10000, None, '>'); 'n.d.' -> None"""
    s = s.strip().replace(" ", " ")
    if s.lower().rstrip(".") in ("n.d", "nd", "", "-"):
        return None
    m = VAL.match(s)
    if not m:
        raise ValueError(f"unparseable value {s!r}")
    return float(m.group(2)), (float(m.group(3)) if m.group(3) else None), (">" if m.group(1) else "=")


def kapp_rows():
    out = []
    for tid, fn in (("Table 1", "kapp2017_table1_transcribed.tsv"), ("Table 2", "kapp2017_table2_transcribed.tsv")):
        with open(HERE / "data" / fn, encoding="utf-8") as f:
            rd = csv.DictReader(f, delimiter="\t")
            for i, r in enumerate(rd, 1):
                for ig in INTEGRINS:
                    v = parse_value(r[ig])
                    if v is None:
                        continue
                    out.append(dict(ligand=r["ligand"].rstrip("*"), source="kapp2017", integrin=ig, ic50_nM=v[0],
                                    sd=v[1], sd_kind="SD(as printed ±)", censor=v[2], table=tid, row=i,
                                    verbatim=r[ig].strip()))
    return out


def _cells(tr):
    return [("".join(c.itertext())).strip() for c in tr]


def quigley_rows():
    root = ET.parse(HERE / "src_raw" / "quigley2023_PMC10718521.xml").getroot()
    tw = [w for w in root.iter("table-wrap") if w.get("id") == "tab1"][0]
    rows = [_cells(tr) for tr in tw.iter("tr")]
    out, i = [], 0
    for r in rows:
        m = re.match(r"^(FF|YF|FY|YY)\b", r[0])
        if not m or len(r) < 5:
            continue
        i += 1
        name = m.group(1)
        for ig, cell in zip(["avb6", "avb8", "avb3", "a5b1"], r[1:5]):
            mm = re.match(r"^([0-9.]+)\s*\(([0-9.]+)[–-]([0-9.]+)\)$", cell)
            if not mm:
                raise ValueError((name, ig, cell))
            out.append(dict(ligand=f"Quigley_{name}", source="quigley2023", integrin=ig, ic50_nM=float(mm.group(1)),
                            sd=None, sd_kind="95%CI printed (not used)", censor="=", table="Table 1", row=i,
                            verbatim=cell))
    return out


def tomassi_rows():
    root = ET.parse(HERE / "src_raw" / "tomassi2021_PMC8279406.xml").getroot()
    tw = [w for w in root.iter("table-wrap") if w.get("id") == "tbl1"][0]
    rows = [_cells(tr) for tr in tw.iter("tr")]
    out = []
    data = [r for r in rows if r and (r[0] in list("123456") or r[0].startswith("cilengitide") or r[0].startswith("RTDLDSLRT"))]
    for i, r in enumerate(data, 1):
        if r[0] in list("123456"):
            name, vals = f"Tomassi_cmpd{r[0]}", r[2:6]
        elif r[0].startswith("cilengitide"):
            name, vals = "Cilengitide@tomassi2021", r[1:5]
        else:
            name, vals = "RTDLDSLRT@tomassi2021", r[1:5]
        for ig, cell in zip(["avb6", "avb8", "avb3", "a5b1"], vals):
            v = parse_value(cell)
            if v is None:
                continue
            out.append(dict(ligand=name, source="tomassi2021", integrin=ig, ic50_nM=v[0], sd=v[1],
                            sd_kind="SD(as printed ±)", censor=v[2], table="Table 1", row=i, verbatim=cell))
    return out


def build():
    rows = kapp_rows() + quigley_rows() + tomassi_rows()
    for r in rows:
        r["pIC50"] = round(9 - math.log10(r["ic50_nM"]), 4)
        r["ligand_id"] = r["ligand"]
    return rows


if __name__ == "__main__":
    rows = build()
    cols = ["ligand_id", "ligand", "source", "integrin", "ic50_nM", "unit", "censor", "pIC50", "sd", "sd_kind", "table", "row", "verbatim"]
    with open(HERE / "matrix.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in rows:
            r["unit"] = "nM"
            w.writerow({c: r.get(c, "") for c in cols})
    print(len(rows), "cells written")
