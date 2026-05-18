"""Particle stack loading — MRCS/MRC files.

EMPIAR particles are typically stored as multi-page MRCS files referenced from
a RELION star file via `_rlnImageName = <index>@<file.mrcs>` (1-based indexing).

This module reads MRC headers, mmaps the data, and exposes a Dataset that yields
(image, idx) tuples suitable for torch DataLoader.
"""

from __future__ import annotations

import os
import struct
from pathlib import Path
from typing import Iterable

import numpy as np
import torch


# MRC header is 1024 bytes (256 int32 words). We only need a few fields.
_HEADER_BYTES = 1024
_DTYPE_TABLE = {
    0: np.int8,
    1: np.int16,
    2: np.float32,
    6: np.uint16,
    12: np.float16,
}


def _read_mrc_header(path: Path) -> dict:
    with open(path, "rb") as f:
        head = f.read(_HEADER_BYTES)
    nx, ny, nz = struct.unpack("<3i", head[0:12])
    mode = struct.unpack("<i", head[12:16])[0]
    nxstart, nystart, nzstart = struct.unpack("<3i", head[16:28])
    mx, my, mz = struct.unpack("<3i", head[28:40])
    xlen, ylen, zlen = struct.unpack("<3f", head[40:52])
    apix_x = xlen / mx if mx else 1.0
    return {
        "nx": nx, "ny": ny, "nz": nz,
        "mode": mode,
        "apix": float(apix_x),
        "shape": (nz, ny, nx),
    }


class MRCSStack:
    """Lightweight mmap-backed reader for a single .mrcs file."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.header = _read_mrc_header(self.path)
        dtype = _DTYPE_TABLE.get(self.header["mode"])
        if dtype is None:
            raise ValueError(f"Unsupported MRC mode {self.header['mode']} in {self.path}")
        self.dtype = dtype
        self.nz, self.ny, self.nx = self.header["shape"]
        self.bytes_per_frame = self.ny * self.nx * np.dtype(dtype).itemsize
        # Memory-map data region (skip 1024-byte header)
        self._mmap = np.memmap(
            self.path, dtype=dtype, mode="r",
            offset=_HEADER_BYTES,
            shape=(self.nz, self.ny, self.nx),
        )

    def __len__(self) -> int:
        return self.nz

    def get(self, idx: int) -> np.ndarray:
        """Read a single frame (0-based)."""
        if idx < 0 or idx >= self.nz:
            raise IndexError(idx)
        return np.array(self._mmap[idx])  # copy out of mmap so caller can free file later


class ParticleDataset(torch.utils.data.Dataset):
    """Particle dataset backed by one or more MRCS files.

    Each particle is identified by (mrcs_path, frame_idx). The map can be built
    manually or from a RELION star's `_rlnImageName` column.

    Parameters
    ----------
    image_specs : list of (mrcs_path, frame_idx_0based)
    apix        : pixel size for downstream rendering (overrides MRC header if given)
    transform   : optional callable(np.ndarray) → np.ndarray applied to each image
    """

    def __init__(
        self,
        image_specs: list[tuple[str | Path, int]],
        apix: float | None = None,
        transform=None,
    ):
        self.specs = [(str(p), int(i)) for p, i in image_specs]
        self.transform = transform
        # Cache MRCSStack handles
        self._stacks: dict[str, MRCSStack] = {}
        # Infer apix from first stack if not given
        if apix is None:
            first = self._get_stack(self.specs[0][0])
            apix = first.header["apix"]
        self.apix = float(apix)

    def _get_stack(self, path: str) -> MRCSStack:
        if path not in self._stacks:
            self._stacks[path] = MRCSStack(path)
        return self._stacks[path]

    def __len__(self) -> int:
        return len(self.specs)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, int]:
        path, frame = self.specs[idx]
        st = self._get_stack(path)
        img = st.get(frame).astype(np.float32)
        if self.transform is not None:
            img = self.transform(img)
        return torch.from_numpy(np.ascontiguousarray(img)), idx


def specs_from_star_image_name(image_names: Iterable[str], base_dir: str | Path | None = None) -> list[tuple[str, int]]:
    """Parse RELION `_rlnImageName` strings (`'NNNN@path/to/file.mrcs'`, 1-based)
    into the (path, frame_idx_0based) specs used by ParticleDataset.
    """
    out = []
    for s in image_names:
        s = str(s).strip()
        if "@" not in s:
            raise ValueError(f"Bad rlnImageName format: {s}")
        idx_str, path = s.split("@", 1)
        frame = int(idx_str) - 1            # RELION is 1-based
        if base_dir is not None and not os.path.isabs(path):
            path = str(Path(base_dir) / path)
        out.append((path, frame))
    return out


__all__ = ["MRCSStack", "ParticleDataset", "specs_from_star_image_name"]
