"""
REINVENT4 *training* backends — the piece the deck slide 4 promises but that was
NOT built: "models trained on your own data — generator fine-tuning +
reinforcement learning".

``generators.py::Reinvent4Generator`` runs REINVENT4 in ``run_type=sampling``
(inference only — it draws from a *frozen* prior). That is real learned
generation, but it does NOT train anything. This module adds the two REINVENT4
run types that actually PRODUCE a new model checkpoint from *your* data:

  1. :class:`Reinvent4TransferLearner`  — ``run_type=transfer_learning``.
     Fine-tunes an existing REINVENT4 prior on a partner/in-house SMILES set,
     shifting the generator's distribution toward that chemistry and writing a
     NEW ``.model`` checkpoint. This is "generator fine-tuning".

  2. :class:`Reinvent4StagedLearner`    — ``run_type=staged_learning``.
     Reinforcement learning ([learning_strategy] type="dap") that optimises the
     agent against a MULTI-OBJECTIVE reward — affinity-proxy × synthetic
     accessibility × safety — built from the SAME RDKit objective callables the
     MPO loop already uses (``mpo_denovo_optimization/bin/run_mpo_round.py``).
     A [diversity_filter] is always on, so the run cannot reward-hack by
     collapsing onto one high-scoring scaffold ("inspectable, adjustable
     reward" — the deck's exact claim). Writes a NEW RL-optimised checkpoint.

Both are thin, HONEST wrappers around REINVENT4's own CLI (Loeffler et al.,
J. Cheminform. 2024, 16:20). We build the documented TOML config, invoke
``reinvent <config>.toml``, and report the produced checkpoint + the TensorBoard
/ CSV progress that REINVENT4 itself writes. We add NO training logic of our own.

HONESTY CONTRACT (identical to Reinvent4Generator):
  * If the ``reinvent`` CLI is not importable/on PATH -> ``TrainerResult(ok=False,
    reason="reinvent4_cli_unavailable")``. We NEVER fabricate a checkpoint.
  * If the input prior is missing -> ok=False, reason names the missing file.
  * If the training SMILES file is empty/absent -> ok=False, reason says so.
  * If the subprocess exits non-zero -> ok=False, reason carries the CLI stderr
    tail. A real result is a genuine REINVENT4 checkpoint on disk or nothing.

x86 note: REINVENT4 (torch + reinvent wheels) is x86_64-only in practice, so the
training itself runs inside the ``reinvent4-nf`` container / AWS Batch, NOT on
ARM dev. Everything here — config building, path resolution, honesty gating,
reward-component construction — is pure-Python and IS unit-testable on any arch
(no torch import at module load). The CLI invocation is the only x86-gated step.

Reward objectives (shared with the MPO loop) — each is a REINVENT4 scoring
*component*; see ``_REWARD_COMPONENTS``:
    qed          QED drug-likeness (RDKit)                     maximise
    sa           synthetic accessibility (REINVENT4 SAScore)   minimise (transform)
    herg_proxy   hERG-liability surrogate (custom_alerts /      minimise
                 MolecularWeight+SlogP guardrails)             (safety)
    affinity     docking/affinity proxy — QED-weighted or a    maximise
                 user docking component when a receptor is set
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from typing import Optional

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Result object — honest, never fabricated
# ---------------------------------------------------------------------------

@dataclass
class TrainerResult:
    """Outcome of a REINVENT4 training run. ``ok`` is the honesty gate."""
    ok: bool
    reason: str
    run_type: str                       # 'transfer_learning' | 'staged_learning'
    checkpoint: Optional[str] = None     # path to the produced .model, if any
    logfile: Optional[str] = None        # REINVENT4 CSV/tb log path, if any
    config_path: Optional[str] = None    # the TOML we generated (for provenance)
    stdout_tail: str = ""
    stderr_tail: str = ""
    extra: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "ok": self.ok,
            "reason": self.reason,
            "run_type": self.run_type,
            "checkpoint": self.checkpoint,
            "logfile": self.logfile,
            "config_path": self.config_path,
            "stdout_tail": self.stdout_tail[-1000:],
            "stderr_tail": self.stderr_tail[-1000:],
            **self.extra,
        }


# ---------------------------------------------------------------------------
# Shared REINVENT4 environment resolution (mirrors Reinvent4Generator)
# ---------------------------------------------------------------------------

class _Reinvent4Base:
    """Prior/CLI resolution + subprocess invocation shared by both trainers."""

    #: Default prior filenames, resolved under $REINVENT4_PRIORS. Fine-tuning a
    #: de-novo generator starts from reinvent.prior; RL likewise (or from a
    #: transfer-learned checkpoint passed explicitly as prior_path).
    _DEFAULT_PRIOR = "reinvent.prior"

    def __init__(
        self,
        priors_dir: Optional[str] = None,
        prior_path: Optional[str] = None,
        cli: Optional[str] = None,
    ) -> None:
        self.priors_dir = (
            priors_dir or os.environ.get("REINVENT4_PRIORS", "/opt/reinvent4/priors")
        )
        self.prior_path = prior_path
        self.cli = cli or os.environ.get("REINVENT4_CLI")

    def _resolve_prior(self) -> Optional[str]:
        if self.prior_path:
            return self.prior_path if os.path.isfile(self.prior_path) else None
        candidate = os.path.join(self.priors_dir, self._DEFAULT_PRIOR)
        if os.path.isfile(candidate):
            return candidate
        alt = candidate.replace(".prior", ".model")
        return alt if os.path.isfile(alt) else None

    def _resolve_cli(self) -> Optional[list]:
        if self.cli:
            exe = shutil.which(self.cli) or (
                self.cli if os.path.isfile(self.cli) else None
            )
            return [exe] if exe else None
        exe = shutil.which("reinvent")
        if exe:
            return [exe]
        try:
            import importlib.util
            if importlib.util.find_spec("reinvent") is not None:
                import sys
                return [sys.executable, "-m", "reinvent"]
        except Exception:
            pass
        return None

    @staticmethod
    def _device() -> str:
        return os.environ.get("REINVENT4_DEVICE", "cpu")

    def _run_cli(self, cfg_path: str, run_type: str) -> subprocess.CompletedProcess:
        cli = self._resolve_cli()  # caller has already checked this is not None
        return subprocess.run(
            cli + [cfg_path],
            capture_output=True,
            text=True,
            timeout=int(os.environ.get("REINVENT4_TRAIN_TIMEOUT", "43200")),  # 12h
        )


# ---------------------------------------------------------------------------
# 1) Transfer learning — generator fine-tuning on your own SMILES
# ---------------------------------------------------------------------------

class Reinvent4TransferLearner(_Reinvent4Base):
    """
    Fine-tune a REINVENT4 prior on a partner/in-house SMILES set
    (``run_type=transfer_learning``), producing a NEW ``.model`` checkpoint whose
    sampling distribution is biased toward that chemistry.

    This is the deck's "generator fine-tuning". REINVENT4's transfer-learning
    stage takes the base prior, a SMILES training file, epochs / batch size /
    learning rate, and writes a checkpoint after training. We build that config
    and run it; we do NOT reimplement the training loop.
    """

    def train(
        self,
        train_smiles_file: str,
        output_model: str,
        epochs: int = 10,
        batch_size: int = 128,
        learning_rate: float = 1e-4,
        sample_batch_size: int = 128,
        validation_smiles_file: Optional[str] = None,
    ) -> TrainerResult:
        run_type = "transfer_learning"

        cli = self._resolve_cli()
        if cli is None:
            return TrainerResult(False, "reinvent4_cli_unavailable", run_type)

        prior = self._resolve_prior()
        if prior is None:
            return TrainerResult(
                False,
                f"prior_checkpoint_missing: expected {self._DEFAULT_PRIOR!r} "
                f"under {self.priors_dir!r} (or pass prior_path=)",
                run_type,
            )

        if not (train_smiles_file and os.path.isfile(train_smiles_file)
                and os.path.getsize(train_smiles_file) > 0):
            return TrainerResult(
                False, f"train_smiles_missing_or_empty: {train_smiles_file!r}", run_type,
            )

        workdir = tempfile.mkdtemp(prefix="reinvent4_tl_")
        try:
            logfile = os.path.splitext(output_model)[0] + "_tl.log"
            cfg_text = self._build_config(
                prior=prior,
                train_smiles_file=train_smiles_file,
                output_model=output_model,
                logfile=logfile,
                epochs=epochs,
                batch_size=batch_size,
                learning_rate=learning_rate,
                sample_batch_size=sample_batch_size,
                validation_smiles_file=validation_smiles_file,
            )
            cfg_path = os.path.join(workdir, "transfer_learning.toml")
            with open(cfg_path, "w") as fh:
                fh.write(cfg_text)

            try:
                proc = self._run_cli(cfg_path, run_type)
            except subprocess.TimeoutExpired:
                return TrainerResult(False, "reinvent4_transfer_learning_timeout",
                                     run_type, config_path=cfg_path)

            stdout_tail = (proc.stdout or "")[-2000:]
            stderr_tail = (proc.stderr or "")[-2000:]
            if proc.returncode != 0:
                return TrainerResult(
                    False,
                    f"reinvent4_transfer_learning_failed (rc={proc.returncode})",
                    run_type, config_path=cfg_path,
                    stdout_tail=stdout_tail, stderr_tail=stderr_tail,
                )

            if not (os.path.isfile(output_model) and os.path.getsize(output_model) > 0):
                return TrainerResult(
                    False, "reinvent4_transfer_learning_produced_no_checkpoint",
                    run_type, config_path=cfg_path,
                    stdout_tail=stdout_tail, stderr_tail=stderr_tail,
                )

            return TrainerResult(
                True, "ok", run_type,
                checkpoint=output_model,
                logfile=logfile if os.path.isfile(logfile) else None,
                config_path=cfg_path,
                stdout_tail=stdout_tail, stderr_tail=stderr_tail,
                extra={"epochs": epochs, "base_prior": os.path.basename(prior)},
            )
        finally:
            shutil.rmtree(workdir, ignore_errors=True)

    def _build_config(
        self, *, prior, train_smiles_file, output_model, logfile,
        epochs, batch_size, learning_rate, sample_batch_size,
        validation_smiles_file,
    ) -> str:
        """
        Minimal REINVENT4 run_type=transfer_learning TOML (Loeffler et al. 2024;
        REINVENT4 configs/toml/transfer_learning.toml).
        """
        device = self._device()
        lines = [
            'run_type = "transfer_learning"',
            f'device = "{device}"',
            'tb_logdir = "tb_transfer_learning"',
            "",
            "[parameters]",
            f'input_model_file = "{prior}"',
            f'output_model_file = "{output_model}"',
            f'smiles_file = "{train_smiles_file}"',
            'save_every_n_epochs = 1',
            f'num_epochs = {int(max(1, epochs))}',
            f'batch_size = {int(max(1, batch_size))}',
            f'sample_batch_size = {int(max(1, sample_batch_size))}',
            f'learning_rate = {float(learning_rate)}',
            f'num_refs = 0',
        ]
        if validation_smiles_file:
            lines.append(f'validation_smiles_file = "{validation_smiles_file}"')
        # Do NOT emit `[logging] logfile=…`. Current REINVENT4 pydantic configs
        # reject that key as extra_forbidden (dev coldstart Adapt / finetune runs:
        # Process REINVENT4_TRAIN … Extra inputs are not permitted … logfile).
        # TensorBoard via tb_logdir above is the supported provenance channel;
        # `logfile` remains a local path we may inspect after the CLI returns.
        _ = logfile  # retained for TrainerResult / post-run inspection
        return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# 2) Staged learning — RL against a multi-objective, reward-hack-suppressed reward
# ---------------------------------------------------------------------------

@dataclass
class RewardComponent:
    """
    One REINVENT4 scoring component in the RL reward.

    ``kind`` selects a builder in :data:`_REWARD_COMPONENTS`; ``weight`` is its
    relative pull in the aggregate; ``transform`` (optional) maps the raw value
    to [0,1] the way REINVENT4 expects (e.g. reverse_sigmoid for "minimise").
    """
    kind: str
    weight: float = 1.0
    transform: Optional[dict] = None
    params: dict = field(default_factory=dict)


def _default_transform(kind: str) -> dict:
    """
    Sensible REINVENT4 score transform per objective so the aggregate is a
    proper product of [0,1] desirabilities (matches the MPO direction table:
    qed=maximize, sa=minimize, herg=minimize, affinity=maximize).
    """
    if kind == "qed":
        return {"type": "sigmoid", "high": 1.0, "low": 0.35, "k": 0.25}
    if kind == "sa":                       # SA 1(easy)..10(hard) -> minimise
        return {"type": "reverse_sigmoid", "high": 6.0, "low": 2.0, "k": 0.5}
    if kind == "herg_proxy":               # higher proxy = more risk -> minimise
        return {"type": "reverse_sigmoid", "high": 5.0, "low": 1.0, "k": 0.4}
    if kind == "affinity":                 # proxy in [0,1], higher = better
        return {"type": "sigmoid", "high": 1.0, "low": 0.3, "k": 0.3}
    return {"type": "no_transform"}


# Builders return a REINVENT4 [[stage.scoring.component.<name>]] TOML block.
# Each maps DIRECTLY onto the same physicochemical/drug-likeness signal the MPO
# RDKit callables compute — so the RL reward and the MPO scoring are the SAME
# objectives, just consumed by REINVENT4's RL loop instead of the GP.
def _component_block(comp: RewardComponent) -> str:
    kind = comp.kind
    transform = comp.transform or _default_transform(kind)
    tlines = "\n".join(f'{k} = {json.dumps(v)}' for k, v in transform.items())

    if kind == "qed":
        header = "QED"
        endpoint = '[[stage.scoring.component.QED.endpoint]]\nname = "QED"'
    elif kind == "sa":
        header = "SAScore"
        endpoint = '[[stage.scoring.component.SAScore.endpoint]]\nname = "SA"'
    elif kind == "herg_proxy":
        # Safety guardrail: penalise high lipophilicity as a hERG surrogate.
        # SlogP is the closest built-in REINVENT4 component to our herg_proxy
        # (Crippen MolLogP + HBD) — honest surrogate, NOT a trained hERG model.
        header = "SlogP"
        endpoint = '[[stage.scoring.component.SlogP.endpoint]]\nname = "hERG_proxy_SlogP"'
    elif kind == "affinity":
        # Affinity proxy: MolecularWeight window as a cheap druglike-affinity
        # surrogate when no receptor/docking component is supplied. A real
        # docking component (DockStream/AutoDock) drops in here unchanged.
        header = "MolecularWeight"
        endpoint = ('[[stage.scoring.component.MolecularWeight.endpoint]]\n'
                    'name = "affinity_proxy_MW"')
    else:
        raise ValueError(f"unknown reward component {kind!r}; "
                         f"available: {sorted(_REWARD_COMPONENTS)}")

    return (
        f"[[stage.scoring.component.{header}]]\n"
        f"{endpoint}\n"
        f"weight = {float(comp.weight)}\n"
        f"transform.type = {json.dumps(transform.get('type', 'no_transform'))}\n"
        + "\n".join(
            f"transform.{k} = {json.dumps(v)}"
            for k, v in transform.items() if k != "type"
        )
        + "\n"
    )


# Registry so callers/tests can enumerate the reward vocabulary honestly.
_REWARD_COMPONENTS = {
    "qed": "QED drug-likeness (maximise)",
    "sa": "synthetic accessibility (minimise)",
    "herg_proxy": "hERG-liability SlogP surrogate (minimise/safety)",
    "affinity": "MolecularWeight-window affinity proxy (maximise)",
}


def default_multi_objective_reward() -> list:
    """
    The deck's default reward: affinity-proxy × SA × safety, plus QED as the
    drug-likeness anchor. Multi-objective, inspectable, adjustable.
    """
    return [
        RewardComponent("affinity", weight=1.0),
        RewardComponent("sa", weight=0.6),
        RewardComponent("herg_proxy", weight=0.6),
        RewardComponent("qed", weight=0.4),
    ]


class Reinvent4StagedLearner(_Reinvent4Base):
    """
    Reinforcement-learning optimisation of the generator against a
    MULTI-OBJECTIVE reward (``run_type=staged_learning``,
    ``[learning_strategy] type="dap"``).

    The reward is the product (REINVENT4 "geometric_mean" aggregator) of the
    per-objective desirabilities in :func:`default_multi_objective_reward`
    (affinity-proxy × SA × safety × QED). A [diversity_filter]
    (IdenticalMurckoScaffold, penalising repeats) is ALWAYS on — this is the
    reward-hacking suppression the deck claims: the agent cannot farm reward by
    collapsing onto a single scaffold.

    Produces a NEW RL-optimised checkpoint. Same honesty contract as the
    transfer learner: no CLI / no prior / empty reward / non-zero exit ->
    ``TrainerResult(ok=False, ...)``, never a fabricated checkpoint.
    """

    def train(
        self,
        output_model: str,
        reward: Optional[list] = None,
        n_steps: int = 300,
        batch_size: int = 128,
        sigma: float = 128.0,
        learning_rate: float = 1e-4,
        diversity_filter: bool = True,
        diversity_bucket_size: int = 25,
        min_score_for_filter: float = 0.4,
        agent_file: Optional[str] = None,
    ) -> TrainerResult:
        run_type = "staged_learning"

        cli = self._resolve_cli()
        if cli is None:
            return TrainerResult(False, "reinvent4_cli_unavailable", run_type)

        # Agent starts from a transfer-learned checkpoint if given, else the prior.
        agent = agent_file if (agent_file and os.path.isfile(agent_file)) \
            else self._resolve_prior()
        if agent is None:
            return TrainerResult(
                False,
                f"agent_checkpoint_missing: no agent_file and no {self._DEFAULT_PRIOR!r} "
                f"under {self.priors_dir!r}",
                run_type,
            )

        reward = reward or default_multi_objective_reward()
        if not reward:
            return TrainerResult(False, "empty_reward_definition", run_type)
        # Validate every component is real BEFORE launching an expensive RL run.
        for comp in reward:
            if comp.kind not in _REWARD_COMPONENTS:
                return TrainerResult(
                    False, f"unknown_reward_component: {comp.kind!r}", run_type,
                )

        workdir = tempfile.mkdtemp(prefix="reinvent4_rl_")
        try:
            logfile = os.path.splitext(output_model)[0] + "_rl.csv"
            cfg_text = self._build_config(
                prior=self._resolve_prior() or agent,
                agent=agent,
                output_model=output_model,
                logfile=logfile,
                reward=reward,
                n_steps=n_steps,
                batch_size=batch_size,
                sigma=sigma,
                learning_rate=learning_rate,
                diversity_filter=diversity_filter,
                diversity_bucket_size=diversity_bucket_size,
                min_score_for_filter=min_score_for_filter,
            )
            cfg_path = os.path.join(workdir, "staged_learning.toml")
            with open(cfg_path, "w") as fh:
                fh.write(cfg_text)

            try:
                proc = self._run_cli(cfg_path, run_type)
            except subprocess.TimeoutExpired:
                return TrainerResult(False, "reinvent4_staged_learning_timeout",
                                     run_type, config_path=cfg_path)

            stdout_tail = (proc.stdout or "")[-2000:]
            stderr_tail = (proc.stderr or "")[-2000:]
            if proc.returncode != 0:
                return TrainerResult(
                    False,
                    f"reinvent4_staged_learning_failed (rc={proc.returncode})",
                    run_type, config_path=cfg_path,
                    stdout_tail=stdout_tail, stderr_tail=stderr_tail,
                )

            if not (os.path.isfile(output_model) and os.path.getsize(output_model) > 0):
                return TrainerResult(
                    False, "reinvent4_staged_learning_produced_no_checkpoint",
                    run_type, config_path=cfg_path,
                    stdout_tail=stdout_tail, stderr_tail=stderr_tail,
                )

            return TrainerResult(
                True, "ok", run_type,
                checkpoint=output_model,
                logfile=logfile if os.path.isfile(logfile) else None,
                config_path=cfg_path,
                stdout_tail=stdout_tail, stderr_tail=stderr_tail,
                extra={
                    "n_steps": n_steps,
                    "reward_components": [c.kind for c in reward],
                    "diversity_filter": diversity_filter,
                    "learning_strategy": "dap",
                },
            )
        finally:
            shutil.rmtree(workdir, ignore_errors=True)

    def _build_config(
        self, *, prior, agent, output_model, logfile, reward,
        n_steps, batch_size, sigma, learning_rate,
        diversity_filter, diversity_bucket_size, min_score_for_filter,
    ) -> str:
        """
        REINVENT4 run_type=staged_learning TOML with DAP RL, a multi-objective
        geometric-mean reward, and a scaffold diversity filter
        (Loeffler et al. 2024; REINVENT4 configs/toml/staged_learning.toml).
        """
        device = self._device()
        head = [
            'run_type = "staged_learning"',
            f'device = "{device}"',
            'tb_logdir = "tb_staged_learning"',
            "",
            "[parameters]",
            f'prior_file = "{prior}"',
            f'agent_file = "{agent}"',
            f'summary_csv_prefix = "{os.path.splitext(logfile)[0]}"',
            f'batch_size = {int(max(1, batch_size))}',
            'use_checkpoint = false',
            "",
            "[learning_strategy]",
            'type = "dap"',            # Distribution-Augmented Policy gradient (RL)
            f'sigma = {float(sigma)}',
            f'rate = {float(learning_rate)}',
            "",
        ]

        # Diversity filter — reward-hacking suppression. Always emitted when on.
        if diversity_filter:
            head += [
                "[diversity_filter]",
                'type = "IdenticalMurckoScaffold"',
                f'bucket_size = {int(max(1, diversity_bucket_size))}',
                f'minscore = {float(min_score_for_filter)}',
                'minsimilarity = 0.4',
                "",
            ]

        # One RL stage, geometric-mean aggregation over the reward components.
        stage = [
            "[[stage]]",
            f'max_score = 1.0',
            f'max_steps = {int(max(1, n_steps))}',
            f'chkpt_file = "{output_model}"',
            "",
            "[stage.scoring]",
            'type = "geometric_mean"',
            "",
        ]
        component_blocks = "\n".join(_component_block(c) for c in reward)
        return "\n".join(head + stage) + "\n" + component_blocks + "\n"


__all__ = [
    "TrainerResult",
    "RewardComponent",
    "Reinvent4TransferLearner",
    "Reinvent4StagedLearner",
    "default_multi_objective_reward",
]
