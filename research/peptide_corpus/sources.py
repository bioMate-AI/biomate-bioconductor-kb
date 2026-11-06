#!/usr/bin/env python3
"""sources.py — load each cyclic-peptide source into the ONE canonical schema (schema.new_record).

STATUS: CPU-only ETL (no GPU, no training). Each loader turns a source's native files into a list
of canonical records; the orchestrator (build_cyclic_corpus_v1.py) concatenates them, then the
4 fixes run as stages. Loaders are defensive: a missing source file is a *counted skip* (returns
[] with a warning), never a hard crash, so the pipeline runs on whatever subset is present locally
and reports exactly what it ingested.

DATA PROVENANCE (fix #3) is assigned HERE, at ingest, from what the source actually is:
  * CycPeptMPDB            -> conformer_provenance="none" (SMILES-only; the CSV has NO coords),
                              source_tier="none" for geometry BUT its measured permeability is a
                              real label (kept in labels[]). Structure must be GENERATED later.
  * CREMP                  -> conformer_provenance="xTB_CREMP" (GFN2-xTB ensembles).
  * CREMP measured subset  -> premium_eval flagged (the ~3,258 with measured passive permeability).
  * PepBDB / PepBench      -> conformer_provenance="PDB_experimental" (bound complexes w/ structure).
  * BindingDB-peptide      -> conformer_provenance="none" + affinity labels.
  * approved cyclic drugs  -> conformer_provenance="none" (SMILES) unless a PDB is attached.

Only the local CycPeptMPDB loader is exercised end-to-end here (the file is present at
data/raw/CycPeptMPDB_Peptide_All.csv). The other loaders are written to the KNOWN layout of the
S3 datasets (see collect_cyclic_datasets.sh) so that once those tarballs are pulled to a local
staging dir they parse without code changes; each is a thin, documented adapter.
"""
from __future__ import annotations

import ast
import csv
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

import schema

# Reuse the existing, validated CycPeptMPDB monomer classifier / parser from the sibling module.
_GZ_ATOM = Path(__file__).resolve().parent.parent / "guangzhou_all_atom"
if str(_GZ_ATOM) not in sys.path:
    sys.path.insert(0, str(_GZ_ATOM))

try:
    import cycpeptmpdb_to_pepglad as cyc  # reuse parse_entry / classify_monomer / _parse_monomers
    _HAVE_CYC = True
except Exception as e:  # pragma: no cover
    _HAVE_CYC = False
    _CYC_ERR = str(e)


def _warn(msg: str) -> None:
    print(f"[sources] {msg}", file=sys.stderr, flush=True)


# ---- CycPeptMPDB (local CSV; the one source guaranteed present) -------------------------------
def load_cycpeptmpdb(csv_path: Path, limit: Optional[int] = None) -> List[Dict[str, Any]]:
    """CycPeptMPDB -> canonical records. SMILES-rich / structure-poor: conformer_provenance='none',
    but the measured log Papp permeability is a real label kept in labels['permeability']."""
    csv_path = Path(csv_path)
    if not csv_path.exists():
        _warn(f"CycPeptMPDB CSV not found at {csv_path} — skipping (0 records).")
        return []
    if not _HAVE_CYC:
        _warn(f"cycpeptmpdb_to_pepglad import failed ({_CYC_ERR}); using inline minimal parser.")
    out: List[Dict[str, Any]] = []
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            if limit is not None and i >= limit:
                break
            smiles = (row.get("SMILES") or "").strip()
            if not smiles:
                continue
            helm = (row.get("HELM") or "").strip()
            seq_field = row.get("Sequence", "")
            if _HAVE_CYC:
                monomers = cyc._parse_monomers(seq_field)
                residues = []
                n_nme = n_daa = 0
                all_supported = True
                for tok in monomers:
                    parent, is_nme, is_daa, supported = cyc.classify_monomer(tok)
                    residues.append({"parent": parent, "nme": bool(is_nme),
                                     "d_amino": bool(is_daa), "raw": tok})
                    n_nme += int(bool(is_nme))
                    n_daa += int(bool(is_daa))
                    all_supported = all_supported and supported
                all_supported = bool(all_supported and monomers)
            else:
                try:
                    monomers = [str(x) for x in ast.literal_eval(seq_field)]
                except Exception:
                    monomers = [x for x in seq_field.split(".") if x]
                residues = []
                n_nme = n_daa = 0
                all_supported = None

            def _f(x):
                try:
                    return float(x)
                except (TypeError, ValueError):
                    return None

            labels: Dict[str, Any] = {}
            perm = _f(row.get("Permeability"))
            if perm is not None:
                labels["permeability"] = {"value": perm, "unit": "logPapp",
                                          "source": (row.get("Source") or "").strip()}
            for assay in ("PAMPA", "Caco2", "MDCK", "RRCK"):
                v = _f(row.get(assay))
                if v is not None:
                    labels[assay.lower()] = {"value": v, "unit": "logPapp", "source": assay}

            rec = schema.new_record(
                source="CycPeptMPDB",
                source_id=(row.get("Structurally_Unique_ID") or row.get("ID") or str(i)).strip(),
                smiles=smiles,
                helm=helm or None,
                sequence=monomers,
                residues=residues,
                conformer_provenance="none",     # NO coordinates in the CSV (fix #3)
                source_tier="none",              # geometry tier; label still counts
                labels=labels,
                is_cyclic=True,                  # CycPeptMPDB is a cyclic-peptide DB by construction
                n_nme=n_nme, n_daa=n_daa, all_supported=all_supported,
                extra={"orig_source": (row.get("Source") or "").strip(),
                       "monomer_length": row.get("Monomer_Length")},
            )
            out.append(rec)
    _warn(f"CycPeptMPDB: loaded {len(out)} records from {csv_path.name}")
    return out


# ---- CREMP (xTB conformer ensembles) ---------------------------------------------------------
def load_cremp(staging_dir: Path) -> List[Dict[str, Any]]:
    """CREMP -> canonical records, conformer_provenance='xTB_CREMP'. The ~3,258 entries with a
    *measured* passive permeability are flagged premium_eval.

    Expected local layout (once s3://.../cyclic_peptide/datasets/cremp*/ is pulled + extracted):
        <staging>/cremp/summary.csv           # one row per macrocycle: id, smiles, sequence, ...
        <staging>/cremp/measured_perm.csv      # id, permeability   (the ~3,258 subset)  [optional]
    The conformer *geometries* (pickles/xyz) are NOT loaded here — D0 only needs the molecule-level
    schema + provenance; M1 streams the per-molecule conformers separately (weight by molecule).
    """
    staging_dir = Path(staging_dir)
    summ = staging_dir / "cremp" / "summary.csv"
    if not summ.exists():
        _warn(f"CREMP summary not found at {summ} — skipping (pull s3 cremp_partial + extract). 0 records.")
        return []
    measured: Dict[str, float] = {}
    mp = staging_dir / "cremp" / "measured_perm.csv"
    if mp.exists():
        for r in csv.DictReader(open(mp)):
            try:
                measured[str(r.get("id"))] = float(r.get("permeability"))
            except (TypeError, ValueError):
                pass
    out: List[Dict[str, Any]] = []
    for r in csv.DictReader(open(summ)):
        sid = str(r.get("id") or r.get("name") or "")
        smiles = (r.get("smiles") or r.get("SMILES") or "").strip()
        if not smiles:
            continue
        seq = r.get("sequence") or ""
        try:
            monomers = [str(x) for x in ast.literal_eval(seq)] if seq.startswith("[") else \
                       [x for x in seq.split(".") if x]
        except Exception:
            monomers = [x for x in seq.split(".") if x]
        labels: Dict[str, Any] = {}
        is_premium = sid in measured
        if is_premium:
            labels["permeability"] = {"value": measured[sid], "unit": "logPapp", "source": "CREMP_measured"}
        rec = schema.new_record(
            source="CREMP", source_id=sid, smiles=smiles,
            sequence=monomers,
            conformer_provenance="xTB_CREMP", source_tier="xTB_CREMP",
            labels=labels, is_cyclic=True,
            extra={"premium_measured": is_premium},
        )
        rec["premium_eval"] = is_premium  # stage4 forces these into the frozen premium eval tier
        out.append(rec)
    _warn(f"CREMP: loaded {len(out)} records ({sum(1 for x in out if x['premium_eval'])} premium-measured)")
    return out


# ---- PepBDB / PepBench (bound complexes WITH experimental structure) --------------------------
def load_pepbdb(staging_dir: Path) -> List[Dict[str, Any]]:
    """PepBDB cyclic subset -> canonical records, conformer_provenance='PDB_experimental'.
    Expected: <staging>/pepbdb/pepbdb_cyclic_index.json  (list of {pdb_id, peptide_smiles/seq, ...}).
    These are the highest-value records (real receptor + experimental structure) — the generator's
    scarce resource. Kept for corpus completeness even though geometry files load in the model lane.
    """
    staging_dir = Path(staging_dir)
    idx = staging_dir / "pepbdb" / "pepbdb_cyclic_index.json"
    if not idx.exists():
        _warn(f"PepBDB cyclic index not found at {idx} — skipping. 0 records.")
        return []
    data = json.load(open(idx))
    entries = data if isinstance(data, list) else data.get("entries", [])
    out: List[Dict[str, Any]] = []
    for e in entries:
        smiles = (e.get("peptide_smiles") or e.get("smiles") or "").strip()
        rec = schema.new_record(
            source="PepBDB", source_id=str(e.get("pdb_id") or e.get("id") or ""),
            smiles=smiles, sequence=e.get("sequence") or [],
            conformer_provenance="PDB_experimental", source_tier="PDB_experimental",
            labels={}, is_cyclic=True,
            extra={"receptor": e.get("receptor"), "bound_complex": True, "pdb_id": e.get("pdb_id")},
        )
        out.append(rec)
    _warn(f"PepBDB: loaded {len(out)} cyclic-complex records")
    return out


# ---- BindingDB-peptide (affinity labels, SMILES) ---------------------------------------------
def load_bindingdb_peptide(staging_dir: Path) -> List[Dict[str, Any]]:
    """BindingDB peptide subset -> canonical records with affinity labels, conformer_provenance='none'.
    Expected: <staging>/bindingdb_peptide/bindingdb_peptide_subset.csv (smiles, target, ki/kd/ic50)."""
    staging_dir = Path(staging_dir)
    p = staging_dir / "bindingdb_peptide" / "bindingdb_peptide_subset.csv"
    if not p.exists():
        _warn(f"BindingDB-peptide subset not found at {p} — skipping. 0 records.")
        return []
    out: List[Dict[str, Any]] = []
    for i, r in enumerate(csv.DictReader(open(p))):
        smiles = (r.get("SMILES") or r.get("smiles") or "").strip()
        if not smiles:
            continue
        labels = {}
        for k in ("Ki", "Kd", "IC50", "EC50"):
            v = r.get(k) or r.get(k.lower())
            try:
                labels[k.lower()] = {"value": float(v), "unit": "nM", "source": "BindingDB"}
            except (TypeError, ValueError):
                pass
        out.append(schema.new_record(
            source="BindingDB_peptide", source_id=str(r.get("BindingDB_id") or i),
            smiles=smiles, conformer_provenance="none", source_tier="none",
            labels=labels, is_cyclic=None,  # cyclicity determined in stage2/ring check
            extra={"target": r.get("Target") or r.get("target")},
        ))
    _warn(f"BindingDB-peptide: loaded {len(out)} records")
    return out


# ---- approved cyclic peptide drugs (local CSV if present) -------------------------------------
def load_approved_drugs(gz_data_dir: Path) -> List[Dict[str, Any]]:
    """approved_cyclic_peptide_drugs.csv -> canonical records (SMILES-only unless a PDB attached)."""
    p = Path(gz_data_dir) / "approved_cyclic_peptide_drugs.csv"
    if not p.exists():
        _warn(f"approved cyclic drugs CSV not found at {p} — skipping. 0 records.")
        return []
    out: List[Dict[str, Any]] = []
    for i, r in enumerate(csv.DictReader(open(p))):
        smiles = (r.get("SMILES") or r.get("smiles") or r.get("canonical_smiles") or "").strip()
        if not smiles:
            continue
        out.append(schema.new_record(
            source="approved_cyclic_drugs",
            source_id=str(r.get("name") or r.get("drug") or i),
            smiles=smiles, conformer_provenance="none", source_tier="none",
            labels={}, is_cyclic=True,
            extra={"name": r.get("name") or r.get("drug"), "approved": True},
        ))
    _warn(f"approved cyclic drugs: loaded {len(out)} records")
    return out


# ---- registry: source_name -> loader(staging_dir/gz_data_dir) --------------------------------
def load_all(csv_path: Path, staging_dir: Optional[Path], gz_data_dir: Path,
             limit: Optional[int] = None) -> List[Dict[str, Any]]:
    """Load every available source into one list. Sources whose files are absent are counted skips."""
    records: List[Dict[str, Any]] = []
    records += load_cycpeptmpdb(csv_path, limit=limit)
    records += load_approved_drugs(gz_data_dir)
    if staging_dir is not None:
        records += load_cremp(staging_dir)
        records += load_pepbdb(staging_dir)
        records += load_bindingdb_peptide(staging_dir)
    else:
        _warn("no --staging dir given: CREMP/PepBDB/BindingDB skipped (pull those from S3 first).")
    return records
