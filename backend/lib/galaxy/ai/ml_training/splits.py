"""
Train / validation / test splitting for molecular datasets.

`scaffold` groups molecules by Bemis–Murcko scaffold (RDKit MurckoScaffold) and
assigns whole groups to one partition, so no scaffold is shared between train,
validation and test. Assignment follows the balanced scheme used by Chemprop:
groups larger than half the validation or test budget are placed first, then
the remaining groups; each group's order is shuffled with the seed, and groups
fill train, then validation, then test. Sizes therefore approximate the
requested fractions. Acyclic molecules share the empty scaffold and form one
group.

`random` is a seeded per-molecule shuffle.

Every split returns a SplitResult whose `method` names what was actually done;
trainers record it in their metadata instead of echoing the requested setting.
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any, Sequence

SCAFFOLD_METHOD = "bemis_murcko_scaffold"
RANDOM_METHOD = "random"


@dataclass
class SplitResult:
    method: str
    train: list[int]
    val: list[int]
    test: list[int]
    seed: int
    requested: str
    n_groups: int = 0
    details: dict[str, Any] = field(default_factory=dict)

    def metadata(self) -> dict[str, Any]:
        return {
            "requested": self.requested,
            "method": self.method,
            "seed": self.seed,
            "n_train": len(self.train),
            "n_val": len(self.val),
            "n_test": len(self.test),
            "n_scaffold_groups": self.n_groups,
            **self.details,
        }


def _target_sizes(n: int, val_frac: float, test_frac: float) -> tuple[int, int, int]:
    n_test = int(round(n * test_frac))
    n_val = int(round(n * val_frac))
    return n - n_val - n_test, n_val, n_test


def bemis_murcko_scaffold(smiles: str) -> str:
    """Canonical Bemis–Murcko scaffold SMILES ('' for acyclic molecules)."""
    from rdkit import Chem
    from rdkit.Chem.Scaffolds import MurckoScaffold

    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        raise ValueError(f"invalid SMILES for scaffold split: {smiles!r}")
    return MurckoScaffold.MurckoScaffoldSmiles(mol=mol, includeChirality=False)


def scaffold_split(smiles: Sequence[str], val_frac: float, test_frac: float,
                   seed: int) -> SplitResult:
    groups: dict[str, list[int]] = {}
    for i, smi in enumerate(smiles):
        groups.setdefault(bemis_murcko_scaffold(smi), []).append(i)

    n_train, n_val, n_test = _target_sizes(len(smiles), val_frac, test_frac)
    # Sort first so the result depends only on (data, seed), not on dict order.
    index_sets = [groups[k] for k in sorted(groups)]
    big = [s for s in index_sets if len(s) > n_val / 2 or len(s) > n_test / 2]
    small = [s for s in index_sets if not (len(s) > n_val / 2 or len(s) > n_test / 2)]
    rng = random.Random(seed)
    rng.shuffle(big)
    rng.shuffle(small)

    train: list[int] = []
    val: list[int] = []
    test: list[int] = []
    for s in big + small:
        if len(train) + len(s) <= n_train:
            train.extend(s)
        elif len(val) + len(s) <= n_val:
            val.extend(s)
        else:
            test.extend(s)
    return SplitResult(
        method=SCAFFOLD_METHOD, train=sorted(train), val=sorted(val), test=sorted(test),
        seed=seed, requested="scaffold", n_groups=len(groups),
        details={"target_sizes": [n_train, n_val, n_test]},
    )


def random_split(n: int, val_frac: float, test_frac: float, seed: int) -> SplitResult:
    order = list(range(n))
    random.Random(seed).shuffle(order)
    n_train, n_val, n_test = _target_sizes(n, val_frac, test_frac)
    return SplitResult(
        method=RANDOM_METHOD,
        train=sorted(order[:n_train]),
        val=sorted(order[n_train:n_train + n_val]),
        test=sorted(order[n_train + n_val:]),
        seed=seed, requested="random",
        details={"target_sizes": [n_train, n_val, n_test]},
    )


def split_dataset(smiles: Sequence[str], split: str, val_frac: float, test_frac: float,
                  seed: int) -> SplitResult:
    """Split by the DatasetSpec.split setting; raises for unknown settings."""
    if split == "scaffold":
        return scaffold_split(smiles, val_frac, test_frac, seed)
    if split == "random":
        return random_split(len(smiles), val_frac, test_frac, seed)
    raise ValueError(f"unsupported split '{split}'")
