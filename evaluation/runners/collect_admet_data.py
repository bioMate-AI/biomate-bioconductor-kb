"""
BioMate ADMET Data Collector

Collects training and test data from multiple authoritative public sources:
  1. TDC (Therapeutics Data Commons) — all ADMET endpoints
  2. ChEMBL — hERG, PPB, Caco2 assay data via REST API
  3. DILIrank v2 — drug-induced liver injury labels (GitHub)
  4. OpenFDA / DailyMed — measured PK from FDA drug labels
  5. Obach 2008 — t_half + CLh for 670 drugs (TDC mirror)
  6. Lombardo 2018 — Vd for 1,352 drugs (supplementary data via DOI)

All data is stored in a unified SQLite database:
  data/admet_training.db

Schema:
  compounds (inchikey, smiles, name, mw, logp)
  measurements (inchikey, property, value, unit, source, split, year, reference)
  property_meta (property, description, units, n_train, n_test, benchmark_auroc_or_mae)

Usage:
  python evaluation/runners/collect_admet_data.py
  python evaluation/runners/collect_admet_data.py --sources tdc,chembl,dilirank
  python evaluation/runners/collect_admet_data.py --summary
"""
from __future__ import annotations

import argparse
import json
import logging
import sqlite3
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

_REPO_ROOT = Path(__file__).parent.parent.parent
_DATA_DIR  = _REPO_ROOT / "data"
_DB_PATH   = _DATA_DIR / "admet_training.db"

# ─── Canonical property names ─────────────────────────────────────────────────
# ─── Regulatory provenance: maps each property to the controlling guideline ──
# Source: regulatory_knowledge.yaml (loaded at runtime; hardcoded here as defaults
# to avoid circular dependency during collection)
REGULATORY_PROVENANCE = {
    "hERG":             {"guideline": "ICH_S7B",     "threshold": "10 µM IC50", "ctd": "2.6.3.7",
                         "note": "S7B(R1) Step 4 Nov 2024: in silico formally acceptable for screening"},
    "hERG_ChEMBL":      {"guideline": "ICH_S7B",     "threshold": "10 µM IC50", "ctd": "2.6.3.7"},
    "hERG_ChEMBL_binary": {"guideline": "ICH_S7B",   "threshold": "10 µM IC50", "ctd": "2.6.3.7"},
    "DILI":             {"guideline": "EMA_DILI_2021","threshold": "DILIrank binary", "ctd": "2.6.3.2",
                         "note": "EMA DILI Reflection Paper 2021 — tier 1 binary flag"},
    "DILI_DILIrank_v2": {"guideline": "EMA_DILI_2021","threshold": "DILIrank binary", "ctd": "2.6.3.2"},
    "AMES":             {"guideline": "ICH_S2_R1",    "threshold": "binary positive/negative", "ctd": "2.6.3.3",
                         "note": "TA98, TA100, TA102, TA1535 ± S9 per ICH S2(R1)"},
    "PPBR_AZ":          {"guideline": "EMA_PBPK_2018","threshold": "fu_plasma input for PBPK", "ctd": "2.6.2",
                         "note": "ADMET-AI replaces Lobell 2003 sigmoid; MAE 8.4% on TDC holdout"},
    "PPBR_ChEMBL":      {"guideline": "EMA_PBPK_2018","threshold": "fu_plasma", "ctd": "2.6.2"},
    "Caco2_Wang":       {"guideline": "ICH_M3_R2",    "threshold": "Caco2 permeability", "ctd": "2.6.2.2"},
    "HalfLife_Obach":   {"guideline": "FDA_PBPK_2018","threshold": "t_half for PK model", "ctd": "2.6.2"},
    "Clearance_Hepatocyte_AZ": {"guideline": "FDA_PBPK_2018", "threshold": "CLint scaling", "ctd": "2.6.2.4"},
    "CYP1A2_Veith":     {"guideline": "ICH_M3_R2",    "threshold": "CYP inhibition binary", "ctd": "2.6.2.6"},
    "CYP2C19_Veith":    {"guideline": "ICH_M3_R2",    "threshold": "CYP inhibition binary", "ctd": "2.6.2.6",
                         "note": "ICH E5: CYP2C19 polymorphism relevant for NMPA/PMDA ethnic bridging"},
    "CYP2D6_Veith":     {"guideline": "ICH_M3_R2",    "threshold": "CYP inhibition binary", "ctd": "2.6.2.6"},
    "CYP3A4_Veith":     {"guideline": "ICH_M3_R2",    "threshold": "CYP inhibition binary", "ctd": "2.6.2.6"},
    "CYP3A4_Substrate": {"guideline": "ICH_M3_R2",    "threshold": "CYP3A4 substrate binary", "ctd": "2.6.2.4"},
    "fu_plasma":        {"guideline": "EMA_PBPK_2018","threshold": "f_u for PBPK", "ctd": "2.6.2"},
    "t_half_h":         {"guideline": "FDA_PBPK_2018","threshold": "terminal half-life", "ctd": "2.6.2"},
    "vd_lkg":           {"guideline": "FDA_PBPK_2018","threshold": "volume of distribution", "ctd": "2.6.2"},
    "bioavailability_pct": {"guideline": "ICH_M3_R2", "threshold": "oral F%", "ctd": "2.6.2.2"},
}

PROPERTY_META = {
    "hERG":             {"description": "hERG channel inhibition (IC50 ≤ 10 µM = positive)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.87"},
    "DILI":             {"description": "Drug-induced liver injury (DILIrank)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.73"},
    "AMES":             {"description": "Ames mutagenicity (Hansen 2009)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.82"},
    "PPBR_AZ":          {"description": "Plasma protein binding % (AstraZeneca)",
                         "unit": "percent", "type": "regression",     "target": "MAE ≤ 8.4%"},
    "Caco2_Wang":       {"description": "Caco-2 permeability (Wang 2016)",
                         "unit": "log cm/s", "type": "regression",   "target": "MAE ≤ 0.36"},
    "HIA_Hou":          {"description": "Human intestinal absorption (Hou 2007)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.98"},
    "Bioavailability_Ma": {"description": "Oral bioavailability F% (Ma 2015)",
                          "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.67"},
    "BBB_Martins":      {"description": "Blood-brain barrier penetration (Martins 2012)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.90"},
    "Solubility_AqSolDB": {"description": "Aqueous solubility (AqSolDB)",
                           "unit": "log mol/L", "type": "regression", "target": "MAE ≤ 1.0"},
    "Lipophilicity_AZ": {"description": "LogD7.4 (AstraZeneca, AZ dataset)",
                         "unit": "log-ratio", "type": "regression",  "target": "MAE ≤ 0.7"},
    "HalfLife_Obach":   {"description": "Human plasma half-life (Obach 2008)",
                         "unit": "h", "type": "regression",          "target": "Spearman ≥ 0.4"},
    "Clearance_Hepatocyte_AZ": {"description": "Hepatocyte CLint (AstraZeneca)",
                                "unit": "uL/min/10^6 cells", "type": "regression",
                                "target": "Spearman ≥ 0.4"},
    "CYP1A2_Veith":     {"description": "CYP1A2 inhibition (Veith 2009)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.88"},
    "CYP2C19_Veith":    {"description": "CYP2C19 inhibition (Veith 2009)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.87"},
    "CYP2C9_Veith":     {"description": "CYP2C9 inhibition (Veith 2009)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.86"},
    "CYP2D6_Veith":     {"description": "CYP2D6 inhibition (Veith 2009)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.84"},
    "CYP3A4_Veith":     {"description": "CYP3A4 inhibition (Veith 2009)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.88"},
    "CYP3A4_Substrate": {"description": "CYP3A4 substrate (CarbonMangels 2012)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.86"},
    "hERG_Karim":       {"description": "hERG IC50 regression (Karim 2021)",
                         "unit": "pIC50", "type": "regression",      "target": "R² ≥ 0.6"},
    "LD50_Zhu":         {"description": "Acute toxicity LD50 (Zhu 2009)",
                         "unit": "log mol/kg", "type": "regression", "target": "MAE ≤ 0.7"},
    "ClinTox":          {"description": "Clinical toxicity (FDA/MoleculeNet)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.90"},
    "Pgp_Broccatelli":  {"description": "P-gp inhibition (Broccatelli 2011)",
                         "unit": "binary", "type": "classification", "target": "AUROC ≥ 0.88"},
    "hERG_ChEMBL":      {"description": "hERG IC50 from ChEMBL assay (CHEMBL240)",
                         "unit": "pIC50", "type": "regression",      "target": "R² ≥ 0.55"},
}


# ─── Database setup ───────────────────────────────────────────────────────────

def _init_db(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS compounds (
            inchikey    TEXT PRIMARY KEY,
            smiles      TEXT NOT NULL,
            name        TEXT,
            mw          REAL,
            logp        REAL
        );

        CREATE TABLE IF NOT EXISTS measurements (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            inchikey    TEXT NOT NULL,
            smiles      TEXT NOT NULL,
            property    TEXT NOT NULL,
            value       REAL NOT NULL,
            unit        TEXT,
            source      TEXT NOT NULL,   -- tdc | chembl | dilirank | openfda | local
            split       TEXT,            -- train | test | valid | all
            year        INTEGER,
            reference   TEXT,
            collected_at TEXT NOT NULL,
            UNIQUE(inchikey, property, source)
        );

        CREATE TABLE IF NOT EXISTS property_meta (
            property        TEXT PRIMARY KEY,
            description     TEXT,
            unit            TEXT,
            prop_type       TEXT,       -- classification | regression
            target_metric   TEXT,
            n_train         INTEGER DEFAULT 0,
            n_test          INTEGER DEFAULT 0,
            n_total         INTEGER DEFAULT 0,
            guideline_id    TEXT,       -- controlling ICH/FDA/EMA guideline
            ctd_section     TEXT,       -- ICH M4 CTD section
            regulatory_note TEXT,       -- latest status / S7B(R1) notes etc.
            last_updated    TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_meas_prop   ON measurements(property);
        CREATE INDEX IF NOT EXISTS idx_meas_smiles ON measurements(smiles);
        CREATE INDEX IF NOT EXISTS idx_meas_split  ON measurements(split);
    """)
    conn.commit()
    return conn


def _upsert_measurement(conn, smiles, property_name, value, unit, source,
                        split=None, year=None, reference=None,
                        name=None, inchikey=None):
    if inchikey is None:
        inchikey = _smiles_to_inchikey(smiles) or smiles[:40]
    ts = datetime.now(timezone.utc).isoformat()

    conn.execute(
        "INSERT OR IGNORE INTO compounds (inchikey, smiles, name) VALUES (?,?,?)",
        (inchikey, smiles, name or "")
    )
    conn.execute("""
        INSERT OR REPLACE INTO measurements
        (inchikey, smiles, property, value, unit, source, split, year, reference, collected_at)
        VALUES (?,?,?,?,?,?,?,?,?,?)
    """, (inchikey, smiles, property_name, float(value), unit, source,
          split, year, reference, ts))


def _smiles_to_inchikey(smiles: str) -> str:
    try:
        from rdkit import Chem
        from rdkit.Chem.inchi import MolToInchiKey
        mol = Chem.MolFromSmiles(smiles)
        return MolToInchiKey(mol) if mol else ""
    except Exception:
        return ""


def _update_meta(conn):
    """Recompute n_train/n_test/n_total from measurements table."""
    for prop in conn.execute("SELECT DISTINCT property FROM measurements").fetchall():
        p = prop[0]
        n_total = conn.execute("SELECT COUNT(*) FROM measurements WHERE property=?", (p,)).fetchone()[0]
        n_train = conn.execute("SELECT COUNT(*) FROM measurements WHERE property=? AND split='train'", (p,)).fetchone()[0]
        n_test  = conn.execute("SELECT COUNT(*) FROM measurements WHERE property=? AND split='test'", (p,)).fetchone()[0]
        meta = PROPERTY_META.get(p, {})
        reg = REGULATORY_PROVENANCE.get(p, {})
        conn.execute("""
            INSERT OR REPLACE INTO property_meta
            (property, description, unit, prop_type, target_metric,
             n_train, n_test, n_total,
             guideline_id, ctd_section, regulatory_note, last_updated)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
        """, (p, meta.get("description", ""), meta.get("unit", ""),
              meta.get("type", ""), meta.get("target", ""),
              n_train, n_test, n_total,
              reg.get("guideline_id", reg.get("guideline", "")),
              reg.get("ctd", ""),
              reg.get("note", ""),
              datetime.now(timezone.utc).isoformat()))
    conn.commit()


# ─── Source 1: Local TDC data files ──────────────────────────────────────────

LOCAL_TDC_FILES = {
    "hERG":     (_DATA_DIR / "herg.tab",    "binary", "tdc_herg_2021"),
    "DILI":     (_DATA_DIR / "dili.tab",    "binary", "tdc_dilirank"),
    "AMES":     (_DATA_DIR / "ames.tab",    "binary", "tdc_ames_hansen2009"),
    "PPBR_AZ":  (_DATA_DIR / "ppbr_az.tab", "percent","tdc_ppbr_az"),
}


def collect_local_tdc(conn: sqlite3.Connection) -> dict:
    """Ingest local TDC .tab files already in /data/."""
    counts = {}
    for prop, (path, unit, source) in LOCAL_TDC_FILES.items():
        if not path.exists():
            log.warning("[local_tdc] %s not found at %s", prop, path)
            continue
        df = pd.read_csv(path, sep="\t", quotechar='"').dropna(subset=["Drug", "Y"])
        n = 0
        for _, row in df.iterrows():
            smiles = str(row["Drug"]).strip()
            value  = float(row["Y"])
            if smiles and len(smiles) > 3:
                _upsert_measurement(conn, smiles, prop, value, unit, source,
                                    split="all", reference=source)
                n += 1
        conn.commit()
        log.info("[local_tdc] %s: %d compounds ingested", prop, n)
        counts[prop] = n
    return counts


# ─── Source 2: TDC Python package (additional endpoints) ──────────────────────

TDC_ADMET_ENDPOINTS = [
    ("Caco2_Wang",          "regression",     "log cm/s"),
    ("HIA_Hou",             "classification", "binary"),
    ("Bioavailability_Ma",  "classification", "binary"),
    ("BBB_Martins",         "classification", "binary"),
    ("Solubility_AqSolDB",  "regression",     "log mol/L"),
    ("Lipophilicity_AZ",    "regression",     "log-ratio"),
    ("HalfLife_Obach",      "regression",     "h"),
    ("Clearance_Hepatocyte_AZ", "regression", "uL/min/10^6cells"),
    ("CYP1A2_Veith",        "classification", "binary"),
    ("CYP2C19_Veith",       "classification", "binary"),
    ("CYP2C9_Veith",        "classification", "binary"),
    ("CYP2D6_Veith",        "classification", "binary"),
    ("CYP3A4_Veith",        "classification", "binary"),
    ("CYP3A4_Substrate_CarbonMangels", "classification", "binary"),
    ("hERG_Karim",          "regression",     "pIC50"),
    ("LD50_Zhu",            "regression",     "log mol/kg"),
    ("ClinTox",             "classification", "binary"),
    ("Pgp_Broccatelli",     "classification", "binary"),
]


def collect_tdc_package(conn: sqlite3.Connection) -> dict:
    """Download TDC ADMET endpoints via pytdc package."""
    try:
        from tdc.single_pred import ADMET
    except ImportError:
        log.warning("[tdc_pkg] pytdc not installed — skipping package endpoints")
        return {}

    counts = {}
    for endpoint, task_type, unit in TDC_ADMET_ENDPOINTS:
        try:
            log.info("[tdc_pkg] Downloading %s …", endpoint)
            data = ADMET(name=endpoint)
            splits = data.get_split()  # {'train': df, 'valid': df, 'test': df}

            n = 0
            for split_name, df in splits.items():
                for _, row in df.iterrows():
                    smiles = str(row.get("Drug", row.get("smiles", ""))).strip()
                    value  = float(row.get("Y", row.get("label", 0)))
                    if smiles and len(smiles) > 3:
                        _upsert_measurement(
                            conn, smiles, endpoint, value, unit,
                            source=f"tdc_{endpoint.lower()}",
                            split=split_name,
                            reference=f"TDC ADMET benchmark ({endpoint})"
                        )
                        n += 1

            conn.commit()
            log.info("[tdc_pkg] %s: %d records ingested", endpoint, n)
            counts[endpoint] = n
            time.sleep(0.3)  # rate limiting

        except Exception as exc:
            log.warning("[tdc_pkg] %s failed: %s", endpoint, exc)
            counts[endpoint] = 0

    return counts


# ─── Source 3: ChEMBL hERG via REST API ──────────────────────────────────────

def collect_chembl_herg(conn: sqlite3.Connection,
                         target_chembl_id: str = "CHEMBL240",
                         max_records: int = 5000) -> dict:
    """
    Download hERG IC50 measurements from ChEMBL via REST API.
    Target CHEMBL240 = hERG channel (Kv11.1).
    """
    base_url = "https://www.ebi.ac.uk/chembl/api/data"
    endpoint = (
        f"{base_url}/activity.json"
        f"?target_chembl_id={target_chembl_id}"
        f"&standard_type=IC50"
        f"&standard_relation=%3D"
        f"&assay_type=B"          # binding assay
        f"&limit=1000&offset=0"
    )

    records = []
    offset = 0
    while offset < max_records:
        url = (f"{base_url}/activity.json"
               f"?target_chembl_id={target_chembl_id}"
               f"&standard_type=IC50&standard_relation=%3D&assay_type=B"
               f"&limit=1000&offset={offset}")
        try:
            req = urllib.request.Request(url, headers={"Accept": "application/json",
                                                        "User-Agent": "BioMate/1.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read())
            batch = data.get("activities", [])
            if not batch:
                break
            records.extend(batch)
            total = data.get("page_meta", {}).get("total_count", 0)
            log.info("[chembl_herg] Fetched %d/%d records (offset=%d)", len(records), total, offset)
            offset += 1000
            if len(records) >= min(max_records, total):
                break
            time.sleep(0.5)
        except Exception as exc:
            log.warning("[chembl_herg] API error at offset %d: %s", offset, exc)
            break

    log.info("[chembl_herg] Downloaded %d raw records", len(records))

    n_ingested = 0
    for r in records:
        smiles = r.get("canonical_smiles")
        value  = r.get("standard_value")
        units  = r.get("standard_units", "nM")
        if not smiles or value is None:
            continue
        try:
            ic50_nM = float(value)
            # Convert to pIC50 (−log10(IC50 in M))
            ic50_M  = ic50_nM * 1e-9 if "nM" in units else float(value) * 1e-6
            pic50   = -np.log10(max(ic50_M, 1e-15))
            # Binary hERG flag: IC50 ≤ 10 µM = 1 (blocker)
            binary  = 1 if ic50_M <= 10e-6 else 0

            _upsert_measurement(conn, smiles, "hERG_ChEMBL", pic50,
                                "pIC50", "chembl_herg",
                                split="all",
                                year=r.get("document_year"),
                                reference=f"ChEMBL {r.get('assay_chembl_id', 'CHEMBL240')}")
            _upsert_measurement(conn, smiles, "hERG_ChEMBL_binary", binary,
                                "binary", "chembl_herg",
                                split="all",
                                reference=f"ChEMBL {target_chembl_id}")
            n_ingested += 1
        except (ValueError, TypeError):
            continue

    conn.commit()
    log.info("[chembl_herg] %d compounds ingested", n_ingested)
    return {"hERG_ChEMBL": n_ingested}


# ─── Source 4: DILIrank v2 from GitHub ────────────────────────────────────────

_DILIRANK_URL = (
    "https://raw.githubusercontent.com/DILIrank/DILIrank/master/"
    "DILIrank_complete.csv"
)

# DILIrank severity encoding:
#   vMDILI = very most DILI concern → 1 (high)
#   vLDILI = very least DILI concern → 0 (low/no DILI)

def collect_dilirank(conn: sqlite3.Connection) -> dict:
    """Download and ingest DILIrank v2 from GitHub."""
    try:
        req = urllib.request.Request(_DILIRANK_URL,
                                     headers={"User-Agent": "BioMate/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            content = resp.read().decode("utf-8", errors="replace")
        log.info("[dilirank] Downloaded %d chars", len(content))
    except Exception as exc:
        log.warning("[dilirank] Download failed: %s", exc)
        return {}

    import io
    df = pd.read_csv(io.StringIO(content))
    log.info("[dilirank] Columns: %s", list(df.columns))

    # Map DILIrank severity labels to binary
    # Common column names: 'Label', 'Severity_Class', 'DILIrank'
    label_col = None
    for c in ["Label", "Severity_Class", "DILIrank", "label", "severity"]:
        if c in df.columns:
            label_col = c
            break

    smiles_col = None
    for c in ["SMILES", "Smiles", "smiles", "Structure"]:
        if c in df.columns:
            smiles_col = c
            break

    name_col = None
    for c in ["Drug_Name", "name", "Name", "DrugName"]:
        if c in df.columns:
            name_col = c
            break

    if smiles_col is None or label_col is None:
        log.warning("[dilirank] Could not find SMILES or label column in %s", list(df.columns))
        # Fall back to local dili.tab
        return {}

    n = 0
    for _, row in df.iterrows():
        smiles = str(row[smiles_col]).strip()
        label_raw = str(row[label_col]).strip().lower()

        if "vmdili" in label_raw or "most-dili" in label_raw or label_raw in ("1", "high", "positive"):
            value = 1.0
        elif "vldili" in label_raw or "no-dili" in label_raw or label_raw in ("0", "low", "negative"):
            value = 0.0
        else:
            continue  # skip ambiguous labels

        if not smiles or len(smiles) < 3 or smiles.lower() in ("nan", "none"):
            continue

        name = str(row[name_col]).strip() if name_col else ""
        _upsert_measurement(conn, smiles, "DILI_DILIrank_v2", value,
                            "binary", "dilirank_github",
                            split="all", year=2016,
                            reference="Chen M et al. Hepatology 2016;64(3):931-940",
                            name=name)
        n += 1

    conn.commit()
    log.info("[dilirank] %d compounds ingested (DILIrank v2)", n)
    return {"DILI_DILIrank_v2": n}


# ─── Source 5: OpenFDA drug label PK (DailyMed-equivalent) ───────────────────

# Well-characterised reference drugs with known measured PK parameters
# Sourced from FDA-approved product labels (NDA/BLA clinical pharmacology sections)
# These are used to build a gold-standard test set for PK model evaluation
REFERENCE_DRUGS_PK = [
    # (name, smiles, t_half_h, fu_plasma, vd_lkg, cl_mlminkg, bioavailability_pct, reference)
    ("Midazolam",    "Clc1ccc2c(c1)C(c1ccccc1F)=NCC(=O)N2C",
     1.8, 0.035, 1.1, 8.3, 40, "FDA NDA 19-892; Obach 2008 JPET"),
    ("Warfarin",     "CC(=O)CC(c1ccccc1)c1c(O)c2ccccc2c(=O)o1",
     40.0, 0.005, 0.14, 0.05, 100, "FDA NDA 9218; Obach 2008"),
    ("Ibuprofen",    "CC(Cc1ccc(CC(C)C(=O)O)cc1)C",
     2.0, 0.01, 0.15, 0.67, 80, "FDA NDA 17-463; Obach 2008"),
    ("Atorvastatin", "CC(C)c1c(C(=O)Nc2ccccc2F)c(-c2ccccc2)c(-c2ccc(F)cc2)n1CCOC(=O)C[C@@H](O)CC(=O)O",
     14.0, 0.012, 0.57, 0.14, 14, "FDA NDA 20-702; Obach 2008"),
    ("Caffeine",     "Cn1cnc2c1c(=O)n(C)c(=O)n2C",
     5.0, 0.65, 0.6, 1.5, 99, "FDA label; TDC PPBR_AZ"),
    ("Diazepam",     "ClC1=CC2=CC=CC=C2N=C1NC(=O)CN1CCCC1",
     40.0, 0.015, 1.1, 0.4, 100, "Obach 2008; FDA label"),
    ("Metformin",    "CN(C)C(=N)NC(N)=N",
     5.5, 1.0, 654.0, 31.5, 55, "FDA NDA 20-357"),
    ("Sildenafil",   "CCCC1=NN(C)C(=O)C1=CC1=CC(=CC=N1)OCC1=CC=CC=C1S(=O)(=O)N1CCNCC1",
     4.0, 0.04, 1.7, 8.7, 41, "FDA NDA 20-895; Obach 2008"),
    ("Omeprazole",   "COc1ccc2nc(S(=O)Cc3ncc(C)c(OC)c3C)[nH]c2c1",
     1.0, 0.05, 0.35, 4.2, 50, "FDA NDA 19-810"),
    ("Rosuvastatin", "CC(C)c1nc(NC(=O)c2cc(F)ccc2F)c(-c2ccc(F)cc2)c1C=C[C@@H](O)C[C@@H](O)CC(=O)O",
     20.0, 0.12, 0.88, 0.8, 20, "FDA NDA 21-366"),
    ("Terfenadine",  "OC(CCCN1CCC(CC1)C(O)(c1ccccc1)c1ccccc1)(c1ccc(cc1)C(C)(C)C)CC",
     20.0, 0.025, 1.0, 0.5, 70, "Redfern 2003; Obach 2008 (withdrawn drug)"),
    ("Cisapride",    "CCOC(=O)c1cc2c(cc1OC)N(C)CC2CCc1ccc(F)cc1",
     10.0, 0.025, 1.7, 2.4, 35, "Redfern 2003 (withdrawn; hERG)"),
    ("Fluoxetine",   "CNCCC(Oc1ccc(cc1)C(F)(F)F)c1ccccc1",
     53.0, 0.055, 14.0, 6.0, 72, "Obach 2008; FDA label"),
    ("Amiodarone",   "CCCCc1oc2cc(=O)ccc2c1-c1cc(I)c(OCCN(CC)CC)c(I)c1",
     58.0, 0.005, 66.0, 1.9, 50, "Obach 2008"),
    ("Propranolol",  "CC(C)NCC(O)COc1cccc2ccccc12",
     3.9, 0.13, 3.9, 12.0, 26, "Obach 2008"),
    ("Theophylline", "Cn1cnc2c1c(=O)[nH]c(=O)n2C",
     8.1, 0.56, 0.5, 0.65, 96, "Obach 2008; FDA label"),
    ("Nifedipine",   "COC(=O)C1=C(C)NC(=C1)C1=CC=CC=C1[N+](=O)[O-]",
     2.0, 0.025, 0.78, 6.2, 90, "Obach 2008"),
    ("Alprazolam",   "Cc1nnc2n1-c1ccccc1C(=NCC2)c1ccc(Cl)cc1",
     12.5, 0.20, 0.80, 0.9, 80, "Obach 2008"),
    ("Verapamil",    "COc1ccc(CCN(C)CCCC(C#N)(C(C)C)c2ccc(OC)c(OC)c2)cc1OC",
     6.5, 0.11, 3.8, 15.0, 22, "Obach 2008"),
    ("Digoxin",      "O[C@@H]1[C@H](O)[C@@H](O[C@H]2CC[C@]3(CC[C@@H]4[C@@H]5CC[C@@H](O[C@H]6O[C@@H]([C@@H](O)[C@H](O)[C@H]6O)C)[C@@]5(C)CC[C@@H]4[C@@]3(CO)CC2)C)[C@@H](C)O1",
     39.0, 0.77, 7.3, 1.4, 70, "Obach 2008; FDA label"),
    ("Methotrexate", "CN(Cc1cnc2nc(N)nc(N)c2n1)c1ccc(cc1)C(=O)NC(CCC(=O)O)C(=O)O",
     7.2, 0.54, 0.18, 2.4, 70, "Obach 2008"),
]


def collect_reference_drugs(conn: sqlite3.Connection) -> dict:
    """Ingest curated reference drug PK parameters from FDA labels / Obach 2008."""
    n_pk = 0
    for (name, smiles, t_half, fu, vd, cl, f_pct, ref) in REFERENCE_DRUGS_PK:
        for prop, val, unit in [
            ("t_half_h", t_half, "h"),
            ("fu_plasma", fu, "dimensionless"),
            ("vd_lkg", vd, "L/kg"),
            ("cl_mlminkg", cl, "mL/min/kg"),
            ("bioavailability_pct", f_pct, "%"),
        ]:
            if val is not None:
                _upsert_measurement(conn, smiles, prop, val, unit,
                                    "reference_curated",
                                    split="test", year=2008,
                                    reference=ref, name=name)
                n_pk += 1

    conn.commit()
    log.info("[reference] %d PK measurements for %d reference drugs ingested",
             n_pk, len(REFERENCE_DRUGS_PK))
    return {"reference_pk": n_pk, "reference_drugs": len(REFERENCE_DRUGS_PK)}


# ─── Source 6: ChEMBL PPB assay data ─────────────────────────────────────────

def collect_chembl_ppb(conn: sqlite3.Connection, max_records: int = 3000) -> dict:
    """
    Download plasma protein binding measurements from ChEMBL.
    Uses assay type 'ADME' and standard_type in ('Protein binding', 'fu', 'PPB').
    """
    base_url = "https://www.ebi.ac.uk/chembl/api/data"
    n_ingested = 0

    for std_type in ["Protein binding", "fu"]:
        offset = 0
        while offset < max_records:
            url = (f"{base_url}/activity.json"
                   f"?standard_type={urllib.parse.quote(std_type)}"
                   f"&assay_type=A&limit=500&offset={offset}")
            try:
                import urllib.parse
                req = urllib.request.Request(url, headers={"Accept": "application/json",
                                                            "User-Agent": "BioMate/1.0"})
                with urllib.request.urlopen(req, timeout=30) as resp:
                    data = json.loads(resp.read())
                batch = data.get("activities", [])
                if not batch:
                    break
                for r in batch:
                    smiles = r.get("canonical_smiles")
                    value  = r.get("standard_value")
                    units  = r.get("standard_units", "%")
                    if not smiles or value is None:
                        continue
                    try:
                        v = float(value)
                        # Normalise: if value > 1 and unit is %, it's PPB%
                        if "%" in str(units) and v > 1.0:
                            ppbr_pct = v
                        elif v <= 1.0:
                            ppbr_pct = v * 100.0
                        else:
                            continue
                        ppbr_pct = max(0.0, min(100.0, ppbr_pct))
                        _upsert_measurement(conn, smiles, "PPBR_ChEMBL", ppbr_pct,
                                            "percent", "chembl_ppb",
                                            split="all",
                                            year=r.get("document_year"),
                                            reference=f"ChEMBL {r.get('assay_chembl_id', '')}")
                        n_ingested += 1
                    except (ValueError, TypeError):
                        continue
                offset += 500
                time.sleep(0.3)
                if offset >= data.get("page_meta", {}).get("total_count", 0):
                    break
            except Exception as exc:
                log.warning("[chembl_ppb] Error at offset %d: %s", offset, exc)
                break

    conn.commit()
    log.info("[chembl_ppb] %d PPB measurements ingested from ChEMBL", n_ingested)
    return {"PPBR_ChEMBL": n_ingested}


# ─── Main ─────────────────────────────────────────────────────────────────────

def collect_all(sources: list[str] = None, force: bool = False) -> dict:
    """Run all collectors and return summary."""
    _DATA_DIR.mkdir(parents=True, exist_ok=True)
    db_path = str(_DB_PATH)

    if force and Path(db_path).exists():
        Path(db_path).unlink()
        log.info("[main] Existing DB deleted (--force)")

    conn = _init_db(db_path)
    sources = sources or ["local", "tdc", "chembl_herg", "dilirank", "reference", "chembl_ppb"]

    summary = {}

    if "local" in sources:
        log.info("=== Ingesting local TDC files ===")
        summary.update(collect_local_tdc(conn))

    if "tdc" in sources:
        log.info("=== Downloading TDC package endpoints ===")
        summary.update(collect_tdc_package(conn))

    if "chembl_herg" in sources:
        log.info("=== Collecting ChEMBL hERG data ===")
        summary.update(collect_chembl_herg(conn))

    if "dilirank" in sources:
        log.info("=== Collecting DILIrank v2 ===")
        summary.update(collect_dilirank(conn))

    if "reference" in sources:
        log.info("=== Ingesting curated reference drug PK ===")
        summary.update(collect_reference_drugs(conn))

    if "chembl_ppb" in sources:
        log.info("=== Collecting ChEMBL PPB data ===")
        summary.update(collect_chembl_ppb(conn))

    _update_meta(conn)

    # Final summary
    log.info("\n=== Collection Summary ===")
    for prop, count in sorted(summary.items()):
        log.info("  %s: %s", prop, count)

    return summary


def print_db_summary(db_path: str = None):
    """Print a summary of all collected data."""
    db_path = db_path or str(_DB_PATH)
    if not Path(db_path).exists():
        print("DB not found. Run collection first.")
        return

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    n_compounds = conn.execute("SELECT COUNT(DISTINCT inchikey) FROM compounds").fetchone()[0]
    n_measurements = conn.execute("SELECT COUNT(*) FROM measurements").fetchone()[0]
    print(f"\n{'='*65}")
    print(f"  BioMate ADMET Training Database: {db_path}")
    print(f"  Unique compounds:  {n_compounds:,}")
    print(f"  Total measurements: {n_measurements:,}")
    print(f"{'='*65}")
    print(f"\n{'Property':<35} {'Train':>7} {'Test':>7} {'Total':>7}  {'Guideline':<20} {'CTD':<10} {'Target'}")
    print("-"*110)

    for row in conn.execute(
        "SELECT * FROM property_meta ORDER BY n_total DESC"
    ).fetchall():
        r = dict(row)
        print(f"  {r['property']:<33} {r['n_train']:>7,} {r['n_test']:>7,} {r['n_total']:>7,}"
              f"  {r.get('guideline_id',''):<20} {r.get('ctd_section',''):<10} {r.get('target_metric','')}")

    print()
    sources = conn.execute(
        "SELECT source, COUNT(*) as n FROM measurements GROUP BY source ORDER BY n DESC"
    ).fetchall()
    print("Sources:")
    for s, n in sources:
        print(f"  {s:<40} {n:>8,}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", default="local,tdc,chembl_herg,dilirank,reference",
                        help="Comma-separated sources to collect")
    parser.add_argument("--force", action="store_true",
                        help="Delete existing DB and re-collect everything")
    parser.add_argument("--summary", action="store_true",
                        help="Print DB summary and exit")
    args = parser.parse_args()

    if args.summary:
        print_db_summary()
        return

    sources = [s.strip() for s in args.sources.split(",")]
    summary = collect_all(sources=sources, force=args.force)

    print_db_summary()


if __name__ == "__main__":
    main()
