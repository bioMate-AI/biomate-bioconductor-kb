"""
Self-contained tests for the de-novo generation loop wiring.

Exercises:
  * the Generator abstraction + honest naming (BRICS not learned, BioNeMo honest
    failure with NO fabricated molecules),
  * the closed generate -> predict -> score+select -> rank loop
    (DeNovoPipeline) with a FAKE generator + FAKE predictors, so no RDKit /
    sklearn / NVIDIA NIM is required for the wiring assertions,
  * that ADMET/affinity are IN-LOOP (fed to the GP) not post-hoc.

Run with:
    cd <repo root> && python backend/lib/galaxy/ai/drug_discovery/test_denovo_pipeline.py
"""
import os
import sys
import traceback

# Make the package importable when run directly from the repo root.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".."))

from backend.lib.galaxy.ai.drug_discovery.generators import (
    Generator, GenerationSpec, BricsGenerator, BioNeMoGenerator,
    Reinvent4Generator, get_generator,
)
from backend.lib.galaxy.ai.drug_discovery.denovo_pipeline import (
    DeNovoPipeline, ObjectiveSpec, LoopResult,
)


# ---------------------------------------------------------------------------
# Fakes — no external models, no network, no RDKit needed for the wiring test
# ---------------------------------------------------------------------------

# A pool of simple, real SMILES so the loop works with or without RDKit
# (BayesianOptimizer falls back to seeded random features if RDKit is absent).
GENERATED = [
    "CCO", "CCN", "CCC", "c1ccccc1", "c1ccncc1",
    "CC(=O)O", "CC(=O)N", "CCOC", "CCCO", "CCCN",
    "c1ccc(O)cc1", "c1ccc(N)cc1", "c1ccc(F)cc1", "c1ccc(Cl)cc1", "CCCCO",
]
SEED = [
    "C", "CC", "CCCC", "CCCCC", "c1cccnc1",
    "c1ccoc1", "CCN", "CCCC(=O)O", "c1ccc(Br)cc1", "CC(=O)OC",
]


class FakeGenerator(Generator):
    """Returns a fixed molecule list; records that propose() was called."""
    name = "fake_fixed_list"
    is_learned = True

    def __init__(self, molecules):
        super().__init__()
        self._molecules = list(molecules)
        self.called_with = None

    def propose(self, spec: GenerationSpec):
        self.called_with = spec
        self.last_status = {"ok": True, "reason": "ok",
                            "generator": self.name, "n_candidates": len(self._molecules)}
        return list(self._molecules)


def make_fake_predictor(offset: float):
    """
    Deterministic predictor: score = (len(smiles) mod 7)/7 + offset.

    Distinct per objective (via offset) so the GP sees two genuinely different
    objective columns.  Returns {smiles: value} — the same contract as a real
    affinity / ADMET model.
    """
    def _predict(smiles_list):
        return {s: ((len(s) % 7) / 7.0 + offset) for s in smiles_list}
    return _predict


# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

_PASS = 0
_FAIL = 0


def check(cond, msg):
    global _PASS, _FAIL
    if cond:
        _PASS += 1
        print(f"  PASS: {msg}")
    else:
        _FAIL += 1
        print(f"  FAIL: {msg}")


# ---------------------------------------------------------------------------
# Tests: generator abstraction / honesty
# ---------------------------------------------------------------------------

def test_generator_honesty():
    print("test_generator_honesty")
    brics = BricsGenerator()
    check(brics.is_learned is False, "BricsGenerator is NOT labelled as learned")
    check(brics.name == "rdkit_brics_enumeration",
          "BricsGenerator honestly named (not 'REINVENT4 RL')")

    bn = BioNeMoGenerator(model="genmol")
    check(bn.is_learned is True, "BioNeMoGenerator labelled as learned")
    check(get_generator("brics").name == "rdkit_brics_enumeration",
          "factory returns BRICS by default")
    try:
        get_generator("nope")
        check(False, "unknown generator kind should raise")
    except ValueError:
        check(True, "unknown generator kind raises ValueError")


def test_bionemo_honest_failure_no_fabrication():
    """
    With no reachable NIM (no client, no NVIDIA_API_KEY), BioNeMoGenerator must
    return [] and record the reason — NEVER fabricate molecules.
    """
    print("test_bionemo_honest_failure_no_fabrication")
    saved = os.environ.pop("NVIDIA_API_KEY", None)
    try:
        bn = BioNeMoGenerator(model="genmol")
        out = bn.propose(GenerationSpec(seed_smiles="c1ccccc1", n_molecules=5))
        check(out == [], "unreachable NIM yields ZERO molecules (no fabrication)")
        check(bn.last_status.get("ok") is False, "status records failure")
        check("reason" in bn.last_status, "status records a reason")
    finally:
        if saved is not None:
            os.environ["NVIDIA_API_KEY"] = saved


def test_bionemo_shape_with_fake_client():
    """
    Inject a fake client returning GenMol/MolMIM-shaped dicts; verify the
    generator normalises them to a flat SMILES list (correct shape) without
    inventing anything.
    """
    print("test_bionemo_shape_with_fake_client")

    class FakeClient:
        def genmol(self, smi, num_molecules=10, unique=True):
            return [{"smiles": "CCO", "score": 0.9},
                    {"smiles": "CCN", "score": 0.8}]

        def molmim(self, smi, num_molecules=10):
            return [{"sample": "c1ccccc1", "score": 0.7}]

    bn = BioNeMoGenerator(model="genmol", client=FakeClient())
    out = bn.propose(GenerationSpec(seed_smiles="CCO", n_molecules=2))
    check(set(out) >= {"CCO", "CCN"}, "GenMol dicts -> flat SMILES list")
    check(bn.last_status.get("ok") is True, "success status recorded")

    bn2 = BioNeMoGenerator(model="molmim", client=FakeClient())
    out2 = bn2.propose(GenerationSpec(seed_smiles="c1ccccc1", n_molecules=1))
    check(len(out2) == 1, "MolMIM 'sample' key normalised to SMILES")


# ---------------------------------------------------------------------------
# Tests: REINVENT4 generator (real learned generator; honesty contract)
# ---------------------------------------------------------------------------

def test_reinvent4_registered_and_learned():
    print("test_reinvent4_registered_and_learned")
    r = get_generator("reinvent4")
    check(isinstance(r, Reinvent4Generator), "factory returns Reinvent4Generator")
    check(r.is_learned is True, "REINVENT4 labelled as learned")
    check(r.name == "reinvent4", "REINVENT4 honestly named")
    check(r.model == "reinvent", "'reinvent4' == de-novo sampling mode")
    check(get_generator("reinvent4_mol2mol").model == "mol2mol",
          "'reinvent4_mol2mol' == analog/scaffold-hop mode")
    try:
        Reinvent4Generator(model="bogus")
        check(False, "bad model should raise")
    except ValueError:
        check(True, "unsupported model raises ValueError")


def test_reinvent4_honest_failure_no_fabrication():
    """
    With no reinvent CLI and no prior checkpoint present, Reinvent4Generator must
    return [] and record the reason — NEVER fabricate or enumerate molecules.
    """
    print("test_reinvent4_honest_failure_no_fabrication")
    # Point at a directory guaranteed to have no priors, and a CLI that can't
    # resolve, so both honesty branches are exercised.
    r = Reinvent4Generator(model="reinvent",
                           priors_dir="/nonexistent/reinvent4/priors",
                           cli="definitely-not-a-real-binary-xyz")
    out = r.propose(GenerationSpec(seed_smiles="c1ccccc1", n_molecules=5))
    check(out == [], "unavailable REINVENT4 yields ZERO molecules (no fabrication)")
    check(r.last_status.get("ok") is False, "status records failure")
    check("reason" in r.last_status, "status records a reason")


def test_reinvent4_mol2mol_requires_seed():
    """mol2mol mode without a seed must fail honestly (no de-novo silent fallback)."""
    print("test_reinvent4_mol2mol_requires_seed")
    # Force CLI+prior 'present' via monkeypatching so we reach the seed check.
    r = Reinvent4Generator(model="mol2mol")
    r._resolve_cli = lambda: ["reinvent"]          # pretend CLI resolves
    r._resolve_prior = lambda: "/tmp/fake.prior"   # pretend prior resolves
    out = r.propose(GenerationSpec(seed_smiles=None, n_molecules=5))
    check(out == [], "mol2mol without seed yields ZERO molecules")
    check(r.last_status.get("reason") == "mol2mol_requires_seed_smiles",
          "reason names the missing seed")


# ---------------------------------------------------------------------------
# Tests: closed loop wiring (fake generator + fake predictors)
# ---------------------------------------------------------------------------

def test_closed_loop_wiring(tmp_db):
    print("test_closed_loop_wiring")
    gen = FakeGenerator(GENERATED)
    objectives = [
        ObjectiveSpec("affinity", make_fake_predictor(0.0), direction="maximize"),
        ObjectiveSpec("admet", make_fake_predictor(0.2), direction="maximize"),
    ]
    pipe = DeNovoPipeline(
        campaign_id="test_denovo_loop",
        generator=gen,
        objectives=objectives,
        db_path=tmp_db,
        n_initial=8,
    )
    spec = GenerationSpec(seed_smiles="c1ccccc1", n_molecules=15, max_candidates=15)
    result = pipe.run_round(spec, seed_smiles=SEED, n_propose=5, diversity_weight=0.2)

    check(isinstance(result, LoopResult), "run_round returns a LoopResult")
    check(gen.called_with is spec, "generator.propose() was called with the spec")
    check(result.n_generated == len(GENERATED), "all generated molecules counted")
    check(result.proposal is not None, "a GP proposal was produced")
    check(result.n_scored == 5, "selected batch has the requested size")

    # Ranking assertions — proves affinity+admet were IN-LOOP (GP scored them).
    check(len(result.ranked) == 5, "ranked shortlist has 5 rows")
    check(all("affinity" in r and "admet" in r for r in result.ranked),
          "each ranked row carries BOTH in-loop objective scores")
    check(all("mean_score" in r for r in result.ranked), "each row has a mean_score")
    ranks = [r["rank"] for r in result.ranked]
    check(ranks == sorted(ranks) and ranks[0] == 1, "ranks are 1..N ascending")
    means = [r["mean_score"] for r in result.ranked]
    check(means == sorted(means, reverse=True),
          "shortlist is sorted by mean_score descending (ranked)")
    # Every proposed compound came from the generated library (closed loop).
    check(all(r["smiles"] in GENERATED for r in result.ranked),
          "ranked compounds all originate from the generator output")


def test_loop_reuses_bayesian_optimizer(tmp_db):
    """
    The loop must REUSE BayesianOptimizer (GP + HVI), not reimplement scoring.
    We assert the proposal carries optimizer-native fields (acquisition_values,
    pareto_front_smiles) that only the real optimizer produces.
    """
    print("test_loop_reuses_bayesian_optimizer")
    gen = FakeGenerator(GENERATED)
    objectives = [
        ObjectiveSpec("affinity", make_fake_predictor(0.0), direction="maximize"),
        ObjectiveSpec("tox", make_fake_predictor(0.1), direction="minimize"),
    ]
    pipe = DeNovoPipeline("test_reuse_bo", gen, objectives, db_path=tmp_db, n_initial=8)
    result = pipe.run_round(
        GenerationSpec(seed_smiles="c1ccccc1", n_molecules=15),
        seed_smiles=SEED, n_propose=4,
    )
    p = result.proposal
    check(p is not None, "proposal exists")
    check(hasattr(p, "acquisition_values") and len(p.acquisition_values) == 4,
          "optimizer-native acquisition_values present (HVI acquisition ran)")
    check(hasattr(p, "pareto_front_smiles"),
          "optimizer-native pareto_front_smiles present (Pareto logic ran)")
    check("tox" in p.scores, "minimize objective flowed through the GP")


def test_empty_generator_short_circuits(tmp_db):
    """A generator that yields nothing must not crash — honest empty result."""
    print("test_empty_generator_short_circuits")
    gen = FakeGenerator([])
    objectives = [ObjectiveSpec("affinity", make_fake_predictor(0.0))]
    pipe = DeNovoPipeline("test_empty", gen, objectives, db_path=tmp_db, n_initial=8)
    result = pipe.run_round(GenerationSpec(seed_smiles="CCO"), seed_smiles=SEED)
    check(result.n_generated == 0, "zero generated molecules reported")
    check(result.proposal is None, "no proposal when nothing generated")
    check(result.ranked == [], "empty ranked list")
    check(any("0 molecules" in n for n in result.notes), "note explains the empty run")


def test_insufficient_seed_short_circuits(tmp_db):
    """Fewer labelled seeds than n_initial -> honest short-circuit, no crash."""
    print("test_insufficient_seed_short_circuits")
    gen = FakeGenerator(GENERATED)
    objectives = [ObjectiveSpec("affinity", make_fake_predictor(0.0))]
    pipe = DeNovoPipeline("test_thin_seed", gen, objectives, db_path=tmp_db, n_initial=8)
    result = pipe.run_round(
        GenerationSpec(seed_smiles="CCO"), seed_smiles=["C", "CC", "CCC"],
    )
    check(result.proposal is None, "no proposal with too-few seeds")
    check(any("insufficient" in n for n in result.notes),
          "note explains insufficient seed compounds")


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def main():
    import tempfile

    # Generator-abstraction / honesty tests need no DB or heavy deps.
    for t in (test_generator_honesty,
              test_bionemo_honest_failure_no_fabrication,
              test_bionemo_shape_with_fake_client,
              test_reinvent4_registered_and_learned,
              test_reinvent4_honest_failure_no_fabrication,
              test_reinvent4_mol2mol_requires_seed):
        try:
            t()
        except Exception:
            global _FAIL
            _FAIL += 1
            print(f"  ERROR in {t.__name__}:")
            traceback.print_exc()

    # Closed-loop tests require numpy + sklearn (BayesianOptimizer). Skip
    # cleanly (not fail) if unavailable, since the honesty tests already cover
    # the abstraction.
    try:
        import numpy  # noqa: F401
        import sklearn  # noqa: F401
        have_bo = True
    except ImportError as exc:
        have_bo = False
        print(f"test_closed_loop_* SKIPPED (missing dep: {exc})")

    if have_bo:
        with tempfile.TemporaryDirectory() as d:
            db = os.path.join(d, "test.db")
            for t in (test_closed_loop_wiring,
                      test_loop_reuses_bayesian_optimizer,
                      test_empty_generator_short_circuits,
                      test_insufficient_seed_short_circuits):
                try:
                    t(db)
                except Exception:
                    _FAIL += 1
                    print(f"  ERROR in {t.__name__}:")
                    traceback.print_exc()

    print(f"\n{_PASS} passed, {_FAIL} failed")
    sys.exit(1 if _FAIL else 0)


if __name__ == "__main__":
    main()
