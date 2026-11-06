#!/usr/bin/env python3
"""m1_peptide_dataset.py — PeptideOnlyCoDesignDataset: the root-cause fix that lets the vendored
PepGLAD AutoEncoderTrainer consume PEPTIDE-ONLY (no-receptor) records like CREMP.

WHY THIS EXISTS (the verified bug — traced, not assumed)
  The stock data.codesign.CoDesignDataset is written for peptide-PROTEIN complexes. Its __getitem__
  does:
      pocket_idx = [int(i) for i in self._properties[idx][-1].split(',')]
  For a peptide-only record the pocket column is the empty string, so `"".split(',')` -> ['']
  and `int('')` raises ValueError. The dataset therefore CANNOT read peptide-only records — this
  affects both the CREMP dataset (prep_cremp_dataset.py) and the existing
  cycpeptmpdb_to_pepglad.build_dataset output. Per CLAUDE.md (fix root cause, no caller workaround),
  the fix belongs in a dataset subclass, not in a hack around the trainer.

  It also fixes the off-by-one in CoDesignDataset._lengths for peptide-only records
  (`len(''.split(',')) == 1`, over-counting the residue length by 1).

WHAT IT REUSES vs. CHANGES
  * Subclasses CoDesignDataset — inherits mmap I/O, collate_fn, resampler, ShapeDataset compatibility.
  * Overrides ONLY the two places that assume a receptor+pocket: _lengths (constructor) and
    __getitem__. The featurization math (X/S/atom_mask padding to MAX_N_ATOM=14, mask=all-generate) is
    copied verbatim from CoDesignDataset so a peptide-only item is byte-identical to what the AE would
    have seen for the ligand half of a complex.
  * Registered under a NEW name 'PeptideOnlyCoDesignDataset' (utils.register asserts on dup names).
    The M1 config points its dataset.class at this; nothing in the production path changes.

The AutoEncoder already supports peptide-only geometry: with no receptor every residue has mask=1,
so encode()/decode() reconstruct the whole peptide and prepare_inputs makes all edges context edges.
Verified against models/autoencoder/model.py (forward/encode/decode/prepare_inputs).

IMPORT-TO-REGISTER: importing this module registers the class in utils.register._NAMESPACE. The M1
entrypoint (m1_train_ae.py) imports it before train.create_dataset runs.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Optional

# vendored PepGLAD importable
_RUNTIME = Path(__file__).resolve().parent / "runtime" / "PepGLAD"
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import numpy as np
import torch

from utils import register as R
from utils.const import sidechain_atoms
from data.format import VOCAB, Block
from data.codesign import CoDesignDataset


@R.register("PeptideOnlyCoDesignDataset")
class PeptideOnlyCoDesignDataset(CoDesignDataset):
    """CoDesignDataset for records shaped ([], lig_blocks) — a peptide with no receptor/pocket."""

    def __init__(
        self,
        mmap_dir: str,
        backbone_only: bool,
        specify_data: Optional[str] = None,
        specify_index: Optional[str] = None,
        padding_collate: bool = False,
        cluster: Optional[str] = None,
        use_covariance_matrix: bool = False,
    ) -> None:
        super().__init__(
            mmap_dir, backbone_only, specify_data, specify_index,
            padding_collate, cluster, use_covariance_matrix,
        )
        # Fix _lengths for peptide-only: length is exactly the #ligand residues (prop[1]); the parent
        # adds len(pocket.split(',')) which is 1 for an empty pocket string (off-by-one).
        self._lengths = [int(prop[1]) for prop in self._properties]

    def get_summary(self, idx: int):
        # No receptor chain / pocket for peptide-only; keep the tuple shape the parent returns.
        props = self._properties[idx]
        _id = self._indexes[idx][0].split(".")[0]
        ref_pdb = os.path.join(self.mmap_dir, "..", "pdbs", _id + ".pdb")
        return _id, ref_pdb, props[4], props[5]

    def __getitem__(self, idx: int):
        idx = self.dynamic_idxs[idx]
        rec_blocks, lig_blocks = super(CoDesignDataset, self).__getitem__(idx)  # MMAPDataset.__getitem__

        # Peptide-only: there is no receptor and no pocket. All residues are the ligand (mask=1).
        # (If a receptor is ever present we still handle it, but pocket_idx defaults to "no pocket".)
        pocket_col = self._properties[idx][-1]
        if rec_blocks and pocket_col.strip():
            pocket_idx = [int(i) for i in pocket_col.split(",")]
            rec_position_ids = [i + 1 for i, _ in enumerate(rec_blocks)]
            rec_blocks = [rec_blocks[i] for i in pocket_idx]
            rec_position_ids = [rec_position_ids[i] for i in pocket_idx]
            rec_blocks = [Block.from_tuple(t) for t in rec_blocks]
        else:
            rec_blocks, rec_position_ids = [], []

        lig_blocks = [Block.from_tuple(t) for t in lig_blocks]

        mask = [0 for _ in rec_blocks] + [1 for _ in lig_blocks]
        position_ids = rec_position_ids + [i + 1 for i, _ in enumerate(lig_blocks)]

        X, S, atom_mask = [], [], []
        for block in rec_blocks + lig_blocks:
            symbol = VOCAB.abrv_to_symbol(block.abrv)
            atom2coord = {unit.name: unit.get_coord() for unit in block.units}
            bb_pos = np.mean(list(atom2coord.values()), axis=0).tolist()
            coords, coord_mask = [], []
            for atom_name in VOCAB.backbone_atoms + sidechain_atoms.get(symbol, []):
                if atom_name in atom2coord:
                    coords.append(atom2coord[atom_name]); coord_mask.append(1)
                else:
                    coords.append(bb_pos); coord_mask.append(0)
            for _ in range(self.MAX_N_ATOM - len(coords)):
                coords.append(bb_pos); coord_mask.append(0)
            X.append(coords); S.append(VOCAB.symbol_to_idx(symbol)); atom_mask.append(coord_mask)

        X = torch.tensor(X, dtype=torch.float)
        atom_mask = torch.tensor(atom_mask, dtype=torch.bool)
        mask = torch.tensor(mask, dtype=torch.bool)
        if self.backbone_only:
            X, atom_mask = X[:, :4], atom_mask[:, :4]

        item = {
            "X": X,
            "S": torch.tensor(S, dtype=torch.long),
            "position_ids": torch.tensor(position_ids, dtype=torch.long),
            "mask": mask,
            "atom_mask": atom_mask,
            "lengths": len(S),
        }
        return item
