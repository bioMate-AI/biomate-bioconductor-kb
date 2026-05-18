"""Particle pose parsing — RELION/cryoSPARC star, cryoDRGN pkl.

Output convention (matches forward_model.render_particle):
  - R : (B, 3, 3) rotation matrix mapping rest-frame coords → particle-frame
  - t : (B, 2)    image-plane shift in Å (centering correction)

RELION star uses ZYZ Euler convention (rot, tilt, psi) in degrees, with shifts
in pixels via _rlnOriginXAngst / _rlnOriginYAngst (or rlnOriginX/Y * pixel size for v3.0).
"""

from __future__ import annotations

import math
import pickle
import re
from pathlib import Path
from typing import Optional

import numpy as np
import torch

from .forward_model import euler_zyz_to_matrix


# ──────────────────────────────────────────────────────────────────────────────
# STAR file parser (RELION 3.1 dict-of-arrays format)
# ──────────────────────────────────────────────────────────────────────────────

def parse_star(star_path: str | Path) -> dict[str, np.ndarray]:
    """Return a dict of column-name → 1-D ndarray for the first data block.

    Handles RELION 3.1 multi-block files by taking the data_particles block if present,
    otherwise the first data block encountered.
    """
    path = Path(star_path)
    text = path.read_text()
    # Find blocks
    blocks = re.split(r"\ndata_", text)
    # First entry is preamble, rest are blocks (without the "data_" prefix)
    chosen = None
    for blk in blocks[1:]:
        name = blk.split(None, 1)[0]
        if "particles" in name.lower():
            chosen = blk
            break
    if chosen is None:
        chosen = blocks[1] if len(blocks) > 1 else blocks[0]

    # Within block: find "loop_" then column names then data rows
    m = re.search(r"loop_\s*((?:_[^\n]+\n)+)((?:.+\n?)+)", chosen)
    if m is None:
        raise ValueError(f"No loop_ block found in {path}")
    cols_block = m.group(1)
    rows_block = m.group(2)

    col_names = []
    for line in cols_block.strip().splitlines():
        parts = line.strip().split()
        if not parts or not parts[0].startswith("_"):
            continue
        col_names.append(parts[0].lstrip("_"))

    # Parse rows (whitespace-separated)
    data = {c: [] for c in col_names}
    for line in rows_block.splitlines():
        s = line.strip()
        if not s or s.startswith("data_") or s.startswith("loop_") or s.startswith("_"):
            continue
        parts = s.split()
        if len(parts) < len(col_names):
            continue
        for c, v in zip(col_names, parts):
            data[c].append(v)

    # Cast numerics
    out: dict[str, np.ndarray] = {}
    for c, vals in data.items():
        try:
            out[c] = np.array(vals, dtype=np.float64)
        except ValueError:
            out[c] = np.array(vals, dtype=object)
    return out


def poses_from_star(
    star_path: str | Path,
    pixel_size_angstrom: float | None = None,
    indices: np.ndarray | None = None,
) -> tuple[torch.Tensor, torch.Tensor]:
    """Build (R, t) tensors from a RELION particles star file.

    Parameters
    ----------
    star_path : path
    pixel_size_angstrom : if provided, used to convert pixel-based shifts to Å.
        If None, prefers `_rlnOriginXAngst`/`_rlnOriginYAngst` (already in Å).
    indices : optional 1-D array selecting a subset of particles.
    """
    cols = parse_star(star_path)
    rot  = cols.get("rlnAngleRot")
    tilt = cols.get("rlnAngleTilt")
    psi  = cols.get("rlnAnglePsi")
    if rot is None or tilt is None or psi is None:
        raise KeyError("Star file missing one of rlnAngleRot/Tilt/Psi")

    # Shifts: prefer Angst, fall back to pixel × Apix
    if "rlnOriginXAngst" in cols and "rlnOriginYAngst" in cols:
        tx = cols["rlnOriginXAngst"].astype(np.float64)
        ty = cols["rlnOriginYAngst"].astype(np.float64)
    elif "rlnOriginX" in cols and "rlnOriginY" in cols:
        if pixel_size_angstrom is None:
            raise ValueError("Star file uses pixel-based shifts; pass pixel_size_angstrom")
        tx = cols["rlnOriginX"].astype(np.float64) * pixel_size_angstrom
        ty = cols["rlnOriginY"].astype(np.float64) * pixel_size_angstrom
    else:
        tx = np.zeros(len(rot))
        ty = np.zeros(len(rot))

    rot = np.asarray(rot, dtype=np.float64)
    tilt = np.asarray(tilt, dtype=np.float64)
    psi = np.asarray(psi, dtype=np.float64)

    if indices is not None:
        rot, tilt, psi, tx, ty = rot[indices], tilt[indices], psi[indices], tx[indices], ty[indices]

    deg = math.pi / 180.0
    R = euler_zyz_to_matrix(
        torch.tensor(rot * deg, dtype=torch.float32),
        torch.tensor(tilt * deg, dtype=torch.float32),
        torch.tensor(psi * deg, dtype=torch.float32),
    )
    t = torch.tensor(np.stack([tx, ty], axis=-1), dtype=torch.float32)
    return R, t


def ctf_params_from_star(
    star_path: str | Path,
    indices: np.ndarray | None = None,
) -> dict[str, torch.Tensor]:
    """Extract per-particle CTF parameters as torch tensors.

    Returns a dict with keys: defocus_u, defocus_v, astig_angle_deg,
    voltage_kV, cs_mm, amp_contrast, phase_shift_deg, all shape (B,).
    """
    cols = parse_star(star_path)
    df_u = cols.get("rlnDefocusU")
    df_v = cols.get("rlnDefocusV", df_u)
    ast  = cols.get("rlnDefocusAngle", np.zeros_like(df_u) if df_u is not None else None)
    kv   = cols.get("rlnVoltage", np.full_like(df_u, 300.0) if df_u is not None else None)
    cs   = cols.get("rlnSphericalAberration", np.full_like(df_u, 2.0) if df_u is not None else None)
    w    = cols.get("rlnAmplitudeContrast", np.full_like(df_u, 0.1) if df_u is not None else None)
    ph   = cols.get("rlnPhaseShift", np.zeros_like(df_u) if df_u is not None else None)

    if df_u is None:
        raise KeyError("Star file missing _rlnDefocusU")

    arrs = {
        "defocus_u": df_u,
        "defocus_v": df_v,
        "astig_angle_deg": ast,
        "voltage_kV": kv,
        "cs_mm": cs,
        "amp_contrast": w,
        "phase_shift_deg": ph,
    }
    if indices is not None:
        arrs = {k: v[indices] for k, v in arrs.items()}
    return {k: torch.tensor(np.asarray(v, dtype=np.float64), dtype=torch.float32) for k, v in arrs.items()}


# ──────────────────────────────────────────────────────────────────────────────
# cryoDRGN pose pkl (rotations as (N, 3, 3), translations as (N, 2) in pixel units)
# ──────────────────────────────────────────────────────────────────────────────

def poses_from_cryodrgn(pose_pkl: str | Path, pixel_size_angstrom: float) -> tuple[torch.Tensor, torch.Tensor]:
    """Load (R, t) from cryoDRGN-style pose pkl.

    cryoDRGN stores (rots, trans) where rots is (N, 3, 3) and trans is (N, 2) in
    fractional image coords (range ~[-0.5, 0.5]). We rescale trans to Å using D × Apix.
    Note: the caller must know D (box size); we return raw fractional shifts here
    and let the caller scale, or — if pixel_size_angstrom is given — we leave
    fractional and the renderer can multiply by D later.

    For convenience we return shifts in Å assuming the caller will pass through D
    via the renderer's apix. The fractional → Å conversion is t_A = frac * D * apix,
    so we leave that conversion to the calling code that has D.
    """
    with open(pose_pkl, "rb") as f:
        raw = pickle.load(f)
    if isinstance(raw, (list, tuple)) and len(raw) >= 2:
        rots, trans = np.asarray(raw[0]), np.asarray(raw[1])
    elif isinstance(raw, dict):
        rots, trans = np.asarray(raw["rots"]), np.asarray(raw["trans"])
    else:
        raise ValueError(f"Unrecognised cryoDRGN pose format in {pose_pkl}")
    if rots.ndim != 3 or rots.shape[1:] != (3, 3):
        raise ValueError(f"rots must be (N, 3, 3); got {rots.shape}")
    if trans.ndim != 2 or trans.shape[1] != 2:
        raise ValueError(f"trans must be (N, 2); got {trans.shape}")
    R = torch.tensor(rots, dtype=torch.float32)
    # Fractional pixel shifts — leave for caller to convert; here we just store raw
    t = torch.tensor(trans, dtype=torch.float32)
    return R, t


__all__ = ["parse_star", "poses_from_star", "ctf_params_from_star", "poses_from_cryodrgn"]
