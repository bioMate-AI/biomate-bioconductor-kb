#!/usr/bin/env python3
"""
register_gromacs_pmx_fep.py — idempotent registration of the gromacs_pmx_fep workflow
into galaxy_ai_tools.db so it is discoverable (search_workflow) and routable
(run_workflow), mirroring how openfe_rbfe is registered.

The DB is gitignored (lives on dev + S3), so THIS SCRIPT is the committed, reproducible
artifact: run it against the local DB for testing, and apply the same script on dev.

Usage:
    python3 register_gromacs_pmx_fep.py [--db PATH] [--check]
"""
from __future__ import annotations
import argparse
import json
import os
import sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "gromacs_pmx_fep"
DISPLAY = "GROMACS pmx Relative FEP (ΔΔG)"
FILENAME = "nfcore/gromacs_pmx_fep/main.nf"   # stub-tree path (unique)
DOMAIN = "drug_discovery"
CATEGORY = "Free Energy"
DOCKER = "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/gromacs-cuda:2024-cu12"
DESCRIPTION = (
    "Generic relative binding free energy (ΔΔG / FEP) for edges OpenFE cannot do — "
    "residue-mutation, peptide, cyclic-peptide and metal-bridged — via GROMACS + pmx. "
    "Companion to openfe_rbfe (small-molecule pairs); the composer routes an FEP request "
    "to whichever engine fits the edge. Runs as a transparent 5-step chain "
    "(define_edge → prepare → equilibrate → fep_production → analyze) that auto-advances "
    "between gates and halts at GPU-spend and QC (stability, cycle_closure) gates for "
    "explicit user go. Honesty contract: a step without its tools/GPU is held with null "
    "numerics, never a fabricated ΔΔG."
)
TAGS = ["FEP", "free energy perturbation", "relative binding free energy", "DDG",
        "pmx", "GROMACS", "residue mutation", "peptide", "cyclic peptide", "metal",
        "CaDA", "alchemical", "MBAR", "lead optimization"]
INPUT_TYPES = ["pdb"]
OUTPUT_TYPES = ["json"]


def _read(path: str) -> str:
    with open(os.path.join(HERE, path)) as fh:
        return fh.read()


def register(db_path: str) -> int:
    main_nf = _read("main.nf")
    try:
        params_schema = _read("nextflow_schema.json")
    except FileNotFoundError:
        params_schema = ""
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    cols = {r[1] for r in cur.execute("PRAGMA table_info(workflows)")}
    row = {
        "name": NAME,
        "filename": FILENAME,
        "description": DESCRIPTION,
        "tags": json.dumps(TAGS),
        "domain": DOMAIN,
        "workflow_json": main_nf,
        "step_count": 5,
        "tools_used": json.dumps(["gromacs", "pmx"]),
        "source": "biomate_native",
        "format": "nextflow",
        "executable": 1,
        "docker_image": DOCKER,
        "category": CATEGORY,
        "input_types": json.dumps(INPUT_TYPES),
        "output_types": json.dumps(OUTPUT_TYPES),
        "params_schema": params_schema,
    }
    row = {k: v for k, v in row.items() if k in cols}
    existing = cur.execute("SELECT id FROM workflows WHERE filename=? OR name=?",
                           (FILENAME, NAME)).fetchone()
    if existing:
        sets = ", ".join(f"{k}=?" for k in row if k != "name")
        cur.execute(f"UPDATE workflows SET {sets} WHERE id=?",
                    [v for k, v in row.items() if k != "name"] + [existing[0]])
        wid = existing[0]
        action = "updated"
    else:
        keys = ", ".join(row)
        qs = ", ".join("?" for _ in row)
        cur.execute(f"INSERT INTO workflows ({keys}) VALUES ({qs})", list(row.values()))
        wid = cur.lastrowid
        action = "inserted"
    con.commit()
    con.close()
    print(f"{action} workflow id={wid} name={NAME} filename={FILENAME}")
    return wid


def check(db_path: str) -> None:
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    r = cur.execute("SELECT id,name,filename,domain,format,executable,category FROM workflows "
                    "WHERE name=?", (NAME,)).fetchone()
    print("row:", r)
    # FTS discoverability (search_workflow uses workflows_fts)
    try:
        hits = cur.execute("SELECT name FROM workflows_fts WHERE workflows_fts MATCH ? LIMIT 5",
                           ("free energy perturbation cyclic peptide",)).fetchall()
        print("fts hits for 'free energy perturbation cyclic peptide':", [h[0] for h in hits])
    except sqlite3.OperationalError as e:
        print("fts check skipped:", e)
    con.close()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(HERE, "..", "..", "..", "database", "galaxy_ai_tools.db"))
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    dbp = os.path.abspath(a.db)
    if not a.check:
        register(dbp)
    check(dbp)
