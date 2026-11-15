"""
Self-contained tests for the REINVENT4 TRAINING backends (reinvent4_trainer.py):
generator fine-tuning (transfer_learning) + reinforcement learning
(staged_learning).

These assert the two things the deck slide 4 promises and that must be REAL:
  1. Transfer learning builds a valid run_type=transfer_learning config and,
     with no CLI/prior/data, fails HONESTLY (no fabricated checkpoint).
  2. Staged RL builds a run_type=staged_learning config with DAP, a
     MULTI-OBJECTIVE geometric-mean reward (affinity × SA × safety × QED) and an
     always-on diversity filter (reward-hacking suppression), and likewise fails
     honestly when REINVENT4 is unavailable.

No torch / reinvent / network needed: the config builders + honesty gating are
pure Python. The CLI invocation itself is x86-container-gated and is exercised by
the container smoke (backend/docker/reinvent4-nf/Dockerfile) + the Nextflow
workflow on AWS Batch, NOT here.

Run with:
    cd <repo root> && python backend/lib/galaxy/ai/drug_discovery/test_reinvent4_trainer.py
"""
import os
import sys
import tempfile
import traceback

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".."))


def _import_trainer():
    """
    Dual-root import so this runs BOTH from the repo root (as
    backend.lib.galaxy.ai.drug_discovery.reinvent4_trainer) AND inside the
    reinvent4-nf container (PYTHONPATH=/opt/biomate -> drug_discovery.
    reinvent4_trainer). Mirrors run_mpo_round.py / run_reinvent4_training.py.
    """
    errors = []
    for mod_root in ("backend.lib.galaxy.ai.drug_discovery", "drug_discovery"):
        try:
            return __import__(f"{mod_root}.reinvent4_trainer", fromlist=["*"])
        except Exception as exc:
            errors.append(f"{mod_root}: {exc}")
    raise ImportError("cannot import reinvent4_trainer: " + "; ".join(errors))


_t = _import_trainer()
Reinvent4TransferLearner = _t.Reinvent4TransferLearner
Reinvent4StagedLearner = _t.Reinvent4StagedLearner
RewardComponent = _t.RewardComponent
TrainerResult = _t.TrainerResult
default_multi_objective_reward = _t.default_multi_objective_reward
_component_block = _t._component_block
_REWARD_COMPONENTS = _t._REWARD_COMPONENTS

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
# Transfer learning (generator fine-tuning)
# ---------------------------------------------------------------------------

def test_transfer_config_is_valid_transfer_learning():
    print("test_transfer_config_is_valid_transfer_learning")
    tl = Reinvent4TransferLearner()
    with tempfile.TemporaryDirectory() as d:
        smi = os.path.join(d, "train.smi")
        with open(smi, "w") as fh:
            fh.write("CCO\nc1ccccc1\nCC(=O)O\n")
        out = os.path.join(d, "finetuned.model")
        cfg = tl._build_config(
            prior="/opt/reinvent4/priors/reinvent.prior",
            train_smiles_file=smi, output_model=out, logfile=out + ".log",
            epochs=5, batch_size=64, learning_rate=1e-4,
            sample_batch_size=64, validation_smiles_file=None,
        )
    check('run_type = "transfer_learning"' in cfg, "run_type is transfer_learning")
    check("input_model_file" in cfg and "output_model_file" in cfg,
          "config wires base prior -> new checkpoint (fine-tuning)")
    check("smiles_file" in cfg, "config trains on the partner SMILES file")
    check("num_epochs = 5" in cfg, "epochs honoured")
    # REINVENT4 pydantic rejects [logging] logfile= as extra_forbidden
    check("[logging]" not in cfg and "logfile" not in cfg,
          "TL config omits forbidden [logging] logfile key")


def test_transfer_honest_failure_no_fabrication():
    """No CLI + no prior -> ok=False; NEVER writes a fake checkpoint."""
    print("test_transfer_honest_failure_no_fabrication")
    with tempfile.TemporaryDirectory() as d:
        smi = os.path.join(d, "train.smi")
        with open(smi, "w") as fh:
            fh.write("CCO\n")
        out = os.path.join(d, "finetuned.model")
        tl = Reinvent4TransferLearner(
            priors_dir="/nonexistent/priors",
            cli="definitely-not-a-real-binary-xyz",
        )
        res = tl.train(train_smiles_file=smi, output_model=out, epochs=1)
        check(isinstance(res, TrainerResult), "returns a TrainerResult")
        check(res.ok is False, "unavailable REINVENT4 -> ok=False")
        check(res.reason == "reinvent4_cli_unavailable", "reason names missing CLI")
        check(res.checkpoint is None, "no checkpoint fabricated")
        check(not os.path.exists(out), "no checkpoint file written to disk")


def test_transfer_empty_training_data_fails_loudly():
    print("test_transfer_empty_training_data_fails_loudly")
    with tempfile.TemporaryDirectory() as d:
        empty = os.path.join(d, "empty.smi")
        open(empty, "w").close()
        out = os.path.join(d, "out.model")
        # Force CLI+prior 'present' so we reach the data check.
        tl = Reinvent4TransferLearner()
        tl._resolve_cli = lambda: ["reinvent"]
        tl._resolve_prior = lambda: "/tmp/fake.prior"
        res = tl.train(train_smiles_file=empty, output_model=out)
        check(res.ok is False, "empty training data -> ok=False")
        check(res.reason.startswith("train_smiles_missing_or_empty"),
              "reason names the empty data")


# ---------------------------------------------------------------------------
# Staged learning (RL, multi-objective, diversity filter)
# ---------------------------------------------------------------------------

def test_staged_config_is_dap_rl_multiobjective():
    print("test_staged_config_is_dap_rl_multiobjective")
    sl = Reinvent4StagedLearner()
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "rl.model")
        cfg = sl._build_config(
            prior="/opt/reinvent4/priors/reinvent.prior",
            agent="/opt/reinvent4/priors/reinvent.prior",
            output_model=out, logfile=out + ".csv",
            reward=default_multi_objective_reward(),
            n_steps=200, batch_size=128, sigma=128.0, learning_rate=1e-4,
            diversity_filter=True, diversity_bucket_size=25,
            min_score_for_filter=0.4,
        )
    check('run_type = "staged_learning"' in cfg, "run_type is staged_learning")
    check('type = "dap"' in cfg, "RL learning_strategy is DAP")
    check('type = "geometric_mean"' in cfg,
          "reward aggregated as a multi-objective geometric mean")
    check("[diversity_filter]" in cfg and "IdenticalMurckoScaffold" in cfg,
          "diversity filter ON (reward-hacking suppression)")
    # Multi-objective: affinity + SA + safety(herg) + QED all present as components.
    check("QED" in cfg, "QED component in reward")
    check("SAScore" in cfg, "SA component in reward")
    check("SlogP" in cfg, "hERG-safety surrogate component in reward")
    check("MolecularWeight" in cfg, "affinity-proxy component in reward")


def test_staged_reward_is_multiobjective_by_default():
    print("test_staged_reward_is_multiobjective_by_default")
    reward = default_multi_objective_reward()
    kinds = {c.kind for c in reward}
    check(len(reward) >= 3, "default reward has >=3 objectives (multi-objective)")
    check({"affinity", "sa", "herg_proxy"} <= kinds,
          "default reward = affinity-proxy x SA x safety (deck claim)")
    for c in reward:
        check(c.kind in _REWARD_COMPONENTS, f"reward component {c.kind!r} is real")


def test_staged_honest_failure_no_fabrication():
    print("test_staged_honest_failure_no_fabrication")
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "rl.model")
        sl = Reinvent4StagedLearner(
            priors_dir="/nonexistent/priors",
            cli="definitely-not-a-real-binary-xyz",
        )
        res = sl.train(output_model=out, n_steps=1)
        check(res.ok is False, "unavailable REINVENT4 -> ok=False")
        check(res.reason == "reinvent4_cli_unavailable", "reason names missing CLI")
        check(res.checkpoint is None, "no checkpoint fabricated")
        check(not os.path.exists(out), "no checkpoint file written")


def test_staged_rejects_unknown_reward_component():
    print("test_staged_rejects_unknown_reward_component")
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "rl.model")
        sl = Reinvent4StagedLearner()
        sl._resolve_cli = lambda: ["reinvent"]
        sl._resolve_prior = lambda: "/tmp/fake.prior"
        res = sl.train(output_model=out, reward=[RewardComponent("not_a_real_objective")])
        check(res.ok is False, "bogus reward component -> ok=False")
        check(res.reason.startswith("unknown_reward_component"),
              "reason names the bad component (validated BEFORE launch)")


def test_component_block_builds_for_every_registered_objective():
    print("test_component_block_builds_for_every_registered_objective")
    for kind in _REWARD_COMPONENTS:
        block = _component_block(RewardComponent(kind, weight=0.5))
        check("weight = 0.5" in block, f"{kind}: weight rendered")
        check("[[stage.scoring.component." in block, f"{kind}: valid component block")
    try:
        _component_block(RewardComponent("bogus"))
        check(False, "unknown component should raise")
    except ValueError:
        check(True, "unknown component raises ValueError")


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def main():
    for t in (
        test_transfer_config_is_valid_transfer_learning,
        test_transfer_honest_failure_no_fabrication,
        test_transfer_empty_training_data_fails_loudly,
        test_staged_config_is_dap_rl_multiobjective,
        test_staged_reward_is_multiobjective_by_default,
        test_staged_honest_failure_no_fabrication,
        test_staged_rejects_unknown_reward_component,
        test_component_block_builds_for_every_registered_objective,
    ):
        try:
            t()
        except Exception:
            global _FAIL
            _FAIL += 1
            print(f"  ERROR in {t.__name__}:")
            traceback.print_exc()

    print(f"\n{_PASS} passed, {_FAIL} failed")
    sys.exit(1 if _FAIL else 0)


if __name__ == "__main__":
    main()
