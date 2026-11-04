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
from typing import Any, Optional, Sequence

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


KFOLD_METHOD = "stratified_kfold"
KFOLD_RANDOM_METHOD = "kfold"


@dataclass
class FoldResult:
    """One cross-validation fold: indices held out for validation and the rest."""
    fold: int
    train: list[int]
    val: list[int]


@dataclass
class KFoldResult:
    method: str
    k: int
    seed: int
    folds: list[FoldResult]
    stratified: bool

    def metadata(self) -> dict[str, Any]:
        return {
            "method": self.method,
            "k": self.k,
            "seed": self.seed,
            "stratified": self.stratified,
            "fold_val_sizes": [len(f.val) for f in self.folds],
        }


def kfold_split(n: int, k: int, seed: int,
                labels: Optional[Sequence[Any]] = None) -> KFoldResult:
    """Deterministic k-fold cross-validation partition of ``range(n)``.

    When ``labels`` are given the folds are STRATIFIED: each label's members are
    distributed round-robin across the k folds so every fold keeps (as close as
    integer counts allow) the dataset's class balance — the correct default for
    classification tasks such as subtype prediction. Without labels it is a plain
    seeded k-fold. Depends only on (n, k, seed, labels), never on input order.
    """
    if k < 2:
        raise ValueError(f"k-fold needs k >= 2, got {k}")
    if n < k:
        raise ValueError(f"cannot make {k} folds from {n} rows")
    rng = random.Random(seed)
    fold_of: dict[int, int] = {}
    if labels is not None:
        if len(labels) != n:
            raise ValueError(f"labels length {len(labels)} != n {n}")
        by_label: dict[Any, list[int]] = {}
        for i, y in enumerate(labels):
            by_label.setdefault(y, []).append(i)
        # Deterministic: sort groups by label key (fall back to str for mixed types).
        try:
            group_keys = sorted(by_label)
        except TypeError:
            group_keys = sorted(by_label, key=lambda v: str(v))
        for key in group_keys:
            idxs = by_label[key][:]
            rng.shuffle(idxs)
            for pos, i in enumerate(idxs):
                fold_of[i] = pos % k
        stratified = True
        method = KFOLD_METHOD
    else:
        order = list(range(n))
        rng.shuffle(order)
        for pos, i in enumerate(order):
            fold_of[i] = pos % k
        stratified = False
        method = KFOLD_RANDOM_METHOD
    folds: list[FoldResult] = []
    for f in range(k):
        val = sorted(i for i, fo in fold_of.items() if fo == f)
        train = sorted(i for i, fo in fold_of.items() if fo != f)
        folds.append(FoldResult(fold=f, train=train, val=val))
    return KFoldResult(method=method, k=k, seed=seed, folds=folds, stratified=stratified)
