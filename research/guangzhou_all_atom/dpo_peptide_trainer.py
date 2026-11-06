#!/usr/bin/env python3
"""dpo_peptide_trainer.py — the GENERATOR-POLICY DPO "close-back": consume (chosen, rejected)
preference pairs from ``dpo_pairs.py`` and fine-tune the PepGLAD LATENT-DIFFUSION generator so that
BOTH the wet-lab loop and the domain-expert instruction panel actually UPDATE the model.

============================================================================================================
WHY DIFFUSION-DPO (Wallace et al. 2023), NOT HuggingFace TRL DPOTrainer
============================================================================================================
``dpo_pairs.py`` calls its records "TRL-ready" and exposes ``to_trl_records()``. That is correct ONLY for a
sequence LANGUAGE model, where the DPO log-likelihood ratio log(pi_theta/pi_ref) is a sum of token log-probs
the LM returns directly. Our generator is NOT an autoregressive LM: it is a LATENT-DIFFUSION model
(``LDMPepDesign`` = a FROZEN ClosureAwareAutoEncoder + a trainable ``FullDPM`` diffusion, warm-started from
epoch-221; see m2c_train_ldm.py). A diffusion model does not expose a tractable sequence log-likelihood, so
TRL's ``DPOTrainer`` cannot be pointed at it. The correct alignment recipe is **Diffusion-DPO**, which
replaces the intractable log-likelihood with the model's own DENOISING (epsilon-prediction) loss as a
per-sample negative-log-likelihood proxy, under a SHARED noise/timestep per pair.

    Diffusion-DPO objective (Wallace et al., Eq. 14, adapted to this latent diffusion):

        L = - E_{(x_w, x_l), t, eps} log sigma( -beta * [
                  ( ||eps - eps_theta(x_w, t)||^2 - ||eps - eps_ref(x_w, t)||^2 )
                - ( ||eps - eps_theta(x_l, t)||^2 - ||eps - eps_ref(x_l, t)||^2 ) ] )

    where x_w / x_l are the CHOSEN / REJECTED designs' latents, eps_theta is the trainable POLICY diffusion,
    eps_ref is the FROZEN reference (same warm-start init), and ||eps - eps_*||^2 is exactly the per-sample
    denoising MSE that ``FullDPM.forward`` already returns (loss_dict['X'], loss_dict['H']). Minimizing L
    pushes the policy to LOWER its denoising loss on the chosen design and RAISE it on the rejected design,
    both measured relative to the frozen reference — i.e. to put more probability mass on preferred designs.

SHARED-NOISE / SHARED-TIMESTEP (the crux of Diffusion-DPO) — implemented WITHOUT touching vendored code:
``FullDPM.forward`` draws t (``torch.randint``) and the noise eps (``torch.randn`` inside ``add_noise``)
from the global RNG. By SNAPSHOTTING the RNG state and RESTORING it before each of the four forward passes
(policy|ref x chosen|rejected), all four passes see the IDENTICAL timestep t (same ``randint`` with the same
batch size) and, within a design, the IDENTICAL noise eps (same ``randn``). This is verified in
``selftest()`` (RNG-synced passes are bit-identical). It needs ZERO edits to the PepGLAD runtime — the
stock ``LDMPepDesign.forward`` / ``FullDPM.forward`` run unchanged.

PAIR -> LATENT PATH (how a dpo_pairs PairSet becomes a trainer batch)
--------------------------------------------------------------------
``dpo_pairs.PreferencePair`` carries ``chosen`` / ``rejected`` as design REPRESENTATION strings (SMILES or
sequence) plus ``chosen_id`` / ``rejected_id``. The diffusion needs FEATURIZED complexes (X,S,mask,...), not
strings. So the real run maps each design id to its featurized record in a stock PepGLAD ``CoDesignDataset``
mmap — exactly the format ``m2c_process_complexes.py`` produces and ``m2c_train_ldm.py`` trains on. The
LDMPepDesign then encodes each record to the v1-AE latent the SAME way m2c does (``self.autoencoder.encode``
under no_grad). See ``PairRecordLoader``. (For the VERIFY_SELECT stream the "designs" are the loop's own
generated+verified candidates; the loop writes their structures, which get featurized into the mmap.)

MODES
-----
  --selftest   : tiny REAL ``FullDPM`` + synthetic latent pairs, a few CPU steps. Verifies the loss computes,
                 is finite, DECREASES, the reference stays FROZEN, and the preference margin moves the right
                 way. No ckpts, no mmap, no GPU. This is the handed-back verification.
  (real run)   : build ``LDMPepDesign`` policy (warm-started diffusion + frozen v1 AE) + a frozen reference,
                 load a PairSet jsonl + its CoDesignDataset mmap, run Diffusion-DPO, emit a fine-tuned ckpt
                 (``torch.save(policy, out)``) for re-eval on the PepBDB-cyclic benchmark
                 (cyclic_benchmark_eval.sh). Launched by launch_dpo_peptide_trainer.sh on the baked AMI.

Design note: docs/20261002_GENERATOR_DPO_TRAINER_DESIGN.md.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime" / "PepGLAD"
for p in (str(RUNTIME), str(ROOT)):
    if p not in sys.path:
        sys.path.insert(0, p)

# Reduce CUDA fragmentation (same fix m2c/M1 use); harmless on CPU.
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

import torch
import torch.nn.functional as F


# =============================================================================================
# RNG snapshot / restore — shared (t, eps) across policy/ref and chosen/rejected per pair.
# =============================================================================================
def rng_snapshot() -> Tuple[torch.Tensor, Optional[list]]:
    cpu_state = torch.random.get_rng_state()
    cuda_state = torch.cuda.get_rng_state_all() if torch.cuda.is_available() else None
    return cpu_state, cuda_state


def rng_restore(state: Tuple[torch.Tensor, Optional[list]]) -> None:
    cpu_state, cuda_state = state
    torch.random.set_rng_state(cpu_state)
    if cuda_state is not None and torch.cuda.is_available():
        torch.cuda.set_rng_state_all(cuda_state)


# =============================================================================================
# Per-design denoising-loss adapters (the per-sample NLL proxy used by Diffusion-DPO).
# =============================================================================================
def denoise_loss_ldm(model, batch: Dict, _hw: float = 1.0) -> torch.Tensor:
    """Full generator path: LDMPepDesign.forward encodes X->latent via the FROZEN AE, then returns
    (loss, loss_dict) where loss = loss_H*self.h_loss_weight + loss_X (the combined denoising loss).
    We use that combined scalar as the per-design NLL proxy. One pair-element = one batch of designs."""
    loss, _loss_dict = model(**batch)
    return loss


def denoise_loss_dpm(model, latent_batch: Dict, hw: float = 1.0) -> torch.Tensor:
    """Self-test path: drive a bare FullDPM over synthetic latents. loss_dict['X']/['H'] are the same
    per-sample denoising MSE terms the real generator uses; combine them with the h-loss weight."""
    ld = model.forward(**latent_batch)
    loss = ld["X"]
    if not isinstance(ld["H"], int):
        loss = loss + hw * ld["H"]
    return loss


# =============================================================================================
# The Diffusion-DPO loss for ONE pair (chosen, rejected).
# =============================================================================================
@dataclass
class DPOStepMetrics:
    loss: float
    dpo_margin: float          # inside bracket; should DECREASE (go negative) as policy learns preference
    reward_margin: float       # -beta * dpo_margin; should INCREASE as policy learns preference
    gap_chosen: float          # (L_policy - L_ref) on chosen; should go NEGATIVE (policy denoises chosen better)
    gap_rejected: float        # (L_policy - L_ref) on rejected; should go POSITIVE
    Lp_chosen: float
    Lr_chosen: float
    Lp_rejected: float
    Lr_rejected: float


def diffusion_dpo_loss(
    policy, ref, chosen, rejected, *, beta: float,
    forward_fn: Callable, hw: float = 1.0,
) -> Tuple[torch.Tensor, DPOStepMetrics]:
    """Compute the Diffusion-DPO loss for one (chosen, rejected) pair.

    All four forward passes are RNG-synced to the SAME snapshot, so they share the timestep t, and within
    a design the policy and reference see the identical noise eps. The reference is evaluated under no_grad.
    """
    snap = rng_snapshot()

    rng_restore(snap)
    Lp_c = forward_fn(policy, chosen, hw)
    rng_restore(snap)
    with torch.no_grad():
        Lr_c = forward_fn(ref, chosen, hw)

    rng_restore(snap)
    Lp_r = forward_fn(policy, rejected, hw)
    rng_restore(snap)
    with torch.no_grad():
        Lr_r = forward_fn(ref, rejected, hw)

    gap_chosen = Lp_c - Lr_c            # want < 0 (policy better than ref on chosen)
    gap_rejected = Lp_r - Lr_r          # want > 0 (policy worse than ref on rejected)
    inside = gap_chosen - gap_rejected  # DPO bracket; want < 0
    loss = -F.logsigmoid(-beta * inside)

    metrics = DPOStepMetrics(
        loss=float(loss.detach()),
        dpo_margin=float(inside.detach()),
        reward_margin=float((-beta * inside).detach()),
        gap_chosen=float(gap_chosen.detach()),
        gap_rejected=float(gap_rejected.detach()),
        Lp_chosen=float(Lp_c.detach()), Lr_chosen=float(Lr_c.detach()),
        Lp_rejected=float(Lp_r.detach()), Lr_rejected=float(Lr_r.detach()),
    )
    return loss, metrics


# =============================================================================================
# Policy / reference construction.
# =============================================================================================
def make_reference(policy):
    """Deep-copy the policy into a FROZEN reference (same init), requires_grad=False, eval()."""
    ref = copy.deepcopy(policy)
    for p in ref.parameters():
        p.requires_grad = False
    ref.eval()
    return ref


def assert_reference_frozen(ref) -> None:
    trainable = [n for n, p in ref.named_parameters() if p.requires_grad]
    if trainable:
        raise RuntimeError(f"reference is NOT frozen: {len(trainable)} trainable params (e.g. {trainable[:3]})")


def build_ldm_policy(config_path: str, overrides: Optional[List[str]] = None):
    """Build the real generator policy: stock LDMPepDesign (frozen v1 AE) + warm-started diffusion.
    Reuses the verified m2c/2b construction (model build, warm-start, AE-frozen check). The ONLY trainable
    params are the diffusion (the AE is frozen inside LDMPepDesign.__init__)."""
    import yaml
    import m1_closure_ae  # noqa: F401  registers ClosureAwareAutoEncoder so torch.load can unpickle the v1 AE
    import models  # noqa: F401  registers LDMPepDesign / FullDPM / CoDesignDataset
    from utils import register as R
    from utils.config_utils import overwrite_values
    from m2_train_ldm import warm_start_diffusion, _assert_ae_frozen

    config = yaml.safe_load(open(config_path))
    if overrides:
        config = overwrite_values(config, overrides)

    model = R.construct(config["model"])          # loads + FREEZES the v1 AE inside __init__
    _assert_ae_frozen(model)
    warm_ckpt = config.get("warm_start_ldm_ckpt")
    if warm_ckpt:
        model = warm_start_diffusion(model, warm_ckpt)   # diffusion-only warm start; AE preserved
        _assert_ae_frozen(model)
    else:
        print("[dpo] WARNING no warm_start_ldm_ckpt — policy diffusion is fresh-init (not the epoch-221 prior)")
    return model


# =============================================================================================
# Data: PairSet (dpo_pairs) + CoDesignDataset mmap -> (chosen_batch, rejected_batch) stream.
# =============================================================================================
def load_pairset_jsonl(path: str) -> List[dict]:
    """Load a dpo_pairs PairSet jsonl (full-provenance lines written by PairSet.write_jsonl)."""
    pairs = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                pairs.append(json.loads(line))
    return pairs


class PairRecordLoader:
    """Map dpo_pairs preference pairs -> featurized (chosen_batch, rejected_batch) via a CoDesignDataset.

    The PairSet carries chosen_id/rejected_id; the mmap carries featurized complexes keyed by the same ids.
    This reuses the EXACT dataset + collate m2c trains on, so the policy encodes designs to the v1-AE latent
    identically to m2c. The mmap MUST have no cluster resampler (dynamic_idxs=identity), which the m2c config
    guarantees — so dataset[idx] corresponds to get_summary(idx)[0]."""

    def __init__(self, pairs: List[dict], dataset, device: str = "cpu"):
        self.device = device
        self.dataset = dataset
        # id -> dataset index (identity dynamic_idxs assumed; see docstring)
        self.id2idx: Dict[str, int] = {}
        for idx in range(len(dataset)):
            _id = dataset.get_summary(idx)[0]
            self.id2idx.setdefault(_id, idx)
        self.pairs = [p for p in pairs if p.get("chosen_id") in self.id2idx and p.get("rejected_id") in self.id2idx]
        n_drop = len(pairs) - len(self.pairs)
        if n_drop:
            print(f"[dpo] dropped {n_drop}/{len(pairs)} pairs whose chosen/rejected id is not in the mmap")
        if not self.pairs:
            raise RuntimeError(
                "no usable pairs: none of the PairSet chosen_id/rejected_id match ids in the mmap. "
                "The designs referenced by the PairSet must be featurized into the CoDesignDataset mmap first."
            )

    def _batch_for(self, _id: str) -> Dict:
        item = self.dataset[self.id2idx[_id]]
        batch = self.dataset.collate_fn([item])
        return {k: (v.to(self.device) if torch.is_tensor(v) else v) for k, v in batch.items()}

    def __len__(self):
        return len(self.pairs)

    def __iter__(self):
        for p in self.pairs:
            yield self._batch_for(p["chosen_id"]), self._batch_for(p["rejected_id"])


# =============================================================================================
# Training loop.
# =============================================================================================
@dataclass
class TrainResult:
    loss_trajectory: List[float] = field(default_factory=list)
    reward_margin_trajectory: List[float] = field(default_factory=list)
    dpo_margin_trajectory: List[float] = field(default_factory=list)
    step_metrics: List[dict] = field(default_factory=list)
    reference_frozen_ok: bool = False
    margin_moved_correctly: bool = False
    out_ckpt: Optional[str] = None


def train_dpo(
    policy, ref, pair_batches: List[Tuple[Dict, Dict]], *,
    beta: float, lr: float, steps: int, forward_fn: Callable, hw: float = 1.0,
    grad_clip: float = 1.0, log_every: int = 1, out_ckpt: Optional[str] = None,
) -> TrainResult:
    """Run Diffusion-DPO for ``steps`` optimizer steps over the preference pairs (cycled if fewer than steps).
    Only policy params with requires_grad=True are optimized (for LDMPepDesign that is the diffusion only)."""
    if steps <= 0 or beta <= 0 or lr <= 0:
        raise ValueError("steps, beta, and lr must be positive")
    assert_reference_frozen(ref)
    policy.train()
    ref.eval()

    trainable = [p for p in policy.parameters() if p.requires_grad]
    n_trainable = sum(p.numel() for p in trainable)
    print(f"[dpo] optimizing {n_trainable/1e6:.3f}M trainable policy params "
          f"(beta={beta} lr={lr} steps={steps} pairs={len(pair_batches)})")
    opt = torch.optim.AdamW(trainable, lr=lr)

    # Fingerprint a reference DIFFUSION param to PROVE the reference never updates (prefer eps_net/diffusion
    # so we check the sub-module that would train if it weren't frozen, not an already-frozen AE weight).
    ref_named = dict(ref.named_parameters())
    ref_param_name = next((n for n in ref_named if "eps_net" in n or "diffusion" in n), next(iter(ref_named)))
    ref_fingerprint = ref_named[ref_param_name].detach().clone()

    res = TrainResult()
    if not pair_batches:
        raise RuntimeError("no preference pairs to train on")

    for step in range(steps):
        chosen, rejected = pair_batches[step % len(pair_batches)]
        opt.zero_grad(set_to_none=True)
        loss, m = diffusion_dpo_loss(policy, ref, chosen, rejected, beta=beta, forward_fn=forward_fn, hw=hw)
        if not torch.isfinite(loss):
            raise RuntimeError(f"Nonfinite DPO loss at step {step}")
        loss.backward()
        grads = [p.grad for p in trainable if p.grad is not None]
        if not grads or any(not torch.isfinite(g).all() for g in grads):
            raise RuntimeError(f"Missing or nonfinite DPO gradients at step {step}")
        if grad_clip:
            torch.nn.utils.clip_grad_norm_(trainable, grad_clip)
        opt.step()

        res.loss_trajectory.append(m.loss)
        res.reward_margin_trajectory.append(m.reward_margin)
        res.dpo_margin_trajectory.append(m.dpo_margin)
        res.step_metrics.append(m.__dict__)
        if step % log_every == 0 or step == steps - 1:
            print(f"[dpo] step {step:3d}  loss={m.loss:.5f}  reward_margin={m.reward_margin:+.5f}  "
                  f"gap_chosen={m.gap_chosen:+.5f}  gap_rejected={m.gap_rejected:+.5f}")

    # verify the reference never moved
    res.reference_frozen_ok = torch.equal(ref_fingerprint, dict(ref.named_parameters())[ref_param_name].detach())
    print(f"[dpo] reference frozen-check on '{ref_param_name}': unchanged={res.reference_frozen_ok}")
    # margin moved the right way: reward margin trended up (policy increasingly prefers chosen)
    k = max(1, len(res.reward_margin_trajectory) // 4)
    first = sum(res.reward_margin_trajectory[:k]) / k
    last = sum(res.reward_margin_trajectory[-k:]) / k
    res.margin_moved_correctly = last > first

    if out_ckpt:
        Path(out_ckpt).parent.mkdir(parents=True, exist_ok=True)
        torch.save(policy, out_ckpt)   # same pickle format as epoch-221 / m2c ckpts -> loadable by eval
        res.out_ckpt = out_ckpt
        print(f"[dpo] saved fine-tuned policy ckpt -> {out_ckpt}")
    return res


# =============================================================================================
# Self-test — tiny REAL FullDPM + synthetic pairs; verify the loss mechanics on CPU.
# =============================================================================================
def _make_latent_sample(latent_size, n_channel, channel_nf, *, n_ctx=3, n_pep=4, seed=0, device="cpu"):
    g = torch.Generator().manual_seed(seed)
    N = n_ctx + n_pep
    mask = torch.zeros(N, dtype=torch.bool); mask[n_ctx:] = True
    return dict(
        H_0=torch.randn(N, latent_size, generator=g, device=device),
        X_0=torch.randn(N, n_channel, 3, generator=g, device=device),
        position_embedding=torch.randn(N, latent_size, generator=g, device=device),
        mask_generate=mask.to(device),
        lengths=torch.tensor([N], dtype=torch.long, device=device),
        atom_embeddings=torch.randn(N, n_channel, channel_nf, generator=g, device=device),
        atom_mask=torch.ones(N, n_channel, dtype=torch.bool, device=device),
    )


def selftest(beta: float = 1.0, lr: float = 2e-3, steps: int = 60, n_pairs: int = 4, seed: int = 0) -> dict:
    """Verification: build a tiny REAL FullDPM, make synthetic preference pairs, run Diffusion-DPO for a few
    CPU steps, and confirm the required properties. Returns a report dict (also printed).

    The tiny FullDPM is built with dropout=0 so the invariants are EXACT: with policy==ref the denoising
    losses match bit-for-bit under RNG-sync (no dropout nondeterminism), so the init DPO loss is exactly
    log(2). The real generator keeps the stock dropout=0.1 (regularization during training)."""
    import models  # noqa: F401
    from models.LDM.diffusion.dpm_full import FullDPM

    torch.manual_seed(seed)
    LAT, HID, NCH = 8, 16, 5
    CHNF = HID // 4

    policy = FullDPM(latent_size=LAT, hidden_size=HID, n_channel=NCH, num_steps=100,
                     n_layers=2, n_rbf=0, cutoff=3.0, dist_rbf=0, dropout=0.0)
    policy.eval()  # deterministic (dropout off anyway) for the invariant checks below
    ref = make_reference(policy)

    # --- mechanic checks against the REAL diffusion loss -------------------------------------------------
    s = _make_latent_sample(LAT, NCH, CHNF, seed=1)
    l0 = denoise_loss_dpm(policy, s)
    finite = bool(torch.isfinite(l0))
    snap = rng_snapshot(); a = denoise_loss_dpm(policy, s)
    rng_restore(snap);     b = denoise_loss_dpm(policy, s)
    rng_synced_identical = bool(torch.allclose(a, b))
    c = denoise_loss_dpm(policy, s)
    noise_is_real = not bool(torch.allclose(a, c))

    # one pair at init: policy==ref => gaps==0 => inside==0 => loss==log(2)
    chosen0 = _make_latent_sample(LAT, NCH, CHNF, seed=100)
    rejected0 = _make_latent_sample(LAT, NCH, CHNF, seed=200)
    _, m_init = diffusion_dpo_loss(policy, ref, chosen0, rejected0, beta=beta, forward_fn=denoise_loss_dpm)
    init_loss_is_log2 = abs(m_init.loss - 0.6931) < 1e-3  # sanity: at init policy==ref

    # --- actually train on a handful of synthetic pairs -------------------------------------------------
    pair_batches = [
        (_make_latent_sample(LAT, NCH, CHNF, seed=1000 + i),
         _make_latent_sample(LAT, NCH, CHNF, seed=2000 + i))
        for i in range(n_pairs)
    ]
    res = train_dpo(policy, ref, pair_batches, beta=beta, lr=lr, steps=steps,
                    forward_fn=denoise_loss_dpm, log_every=max(1, steps // 10))

    k = max(1, steps // 5)
    loss_first = sum(res.loss_trajectory[:k]) / k
    loss_last = sum(res.loss_trajectory[-k:]) / k

    report = {
        "mode": "selftest",
        "model": "real FullDPM (tiny)",
        "loss_finite": finite,
        "rng_synced_identical": rng_synced_identical,
        "noise_is_real_without_restore": noise_is_real,
        "init_loss_is_log2_(policy==ref)": init_loss_is_log2,
        "loss_first_quarter_mean": round(loss_first, 6),
        "loss_last_quarter_mean": round(loss_last, 6),
        "loss_decreased": loss_last < loss_first,
        "reward_margin_first": round(sum(res.reward_margin_trajectory[:k]) / k, 6),
        "reward_margin_last": round(sum(res.reward_margin_trajectory[-k:]) / k, 6),
        "margin_moved_correctly": res.margin_moved_correctly,
        "reference_frozen_ok": res.reference_frozen_ok,
        "loss_trajectory": [round(x, 5) for x in res.loss_trajectory],
        "reward_margin_trajectory": [round(x, 5) for x in res.reward_margin_trajectory],
    }
    report["ALL_CHECKS_PASS"] = all([
        finite, rng_synced_identical, noise_is_real, init_loss_is_log2,
        report["loss_decreased"], report["margin_moved_correctly"], report["reference_frozen_ok"],
    ])
    print("\n=== Diffusion-DPO self-test report ===")
    print(json.dumps({k2: v for k2, v in report.items()
                      if k2 not in ("loss_trajectory", "reward_margin_trajectory")}, indent=2))
    return report


# =============================================================================================
# CLI
# =============================================================================================
def main():
    ap = argparse.ArgumentParser(description="Diffusion-DPO fine-tune of the PepGLAD latent-diffusion generator.")
    ap.add_argument("--selftest", action="store_true",
                    help="run the CPU verification (tiny real FullDPM + synthetic pairs); no ckpts/mmap/GPU")
    # real-run inputs
    ap.add_argument("--pairs", type=str, help="dpo_pairs PairSet jsonl (full-provenance lines)")
    ap.add_argument("--config", type=str, default=str(ROOT / "m2c_ldm_finetune.yaml"),
                    help="LDM model config (reuses m2c model block for a 1:1 warm-start load)")
    ap.add_argument("--warm_start_ldm_ckpt", type=str, help="epoch-221 (or current m2c) LDM ckpt (diffusion warm-start)")
    ap.add_argument("--autoencoder_ckpt", type=str, help="frozen v1 AE ckpt")
    ap.add_argument("--mmap_dir", type=str, help="CoDesignDataset mmap holding the featurized designs")
    ap.add_argument("--specify_index", type=str, help="optional index.txt restricting the mmap records")
    ap.add_argument("--out", type=str, default=str(ROOT / "ckpts" / "dpo_peptide" / "dpo_policy.ckpt"))
    ap.add_argument("--report", type=str, help="write the run report JSON here")
    # hyperparameters
    ap.add_argument("--beta", type=float, default=2000.0,
                    help="DPO beta (Diffusion-DPO uses a large beta ~ 2000; see design note)")
    ap.add_argument("--lr", type=float, default=1e-6)
    ap.add_argument("--steps", type=int, default=200)
    ap.add_argument("--grad_clip", type=float, default=1.0)
    ap.add_argument("--gpu", type=int, default=-1, help="gpu id, -1 for cpu")
    args = ap.parse_args()

    if args.selftest:
        report = selftest()
        if args.report:
            Path(args.report).write_text(json.dumps(report, indent=2))
        sys.exit(0 if report["ALL_CHECKS_PASS"] else 1)

    # ---- real run ----
    if not (args.pairs and args.warm_start_ldm_ckpt and args.autoencoder_ckpt and args.mmap_dir):
        ap.error("real run needs --pairs, --warm_start_ldm_ckpt, --autoencoder_ckpt, --mmap_dir "
                 "(or use --selftest)")
    device = f"cuda:{args.gpu}" if args.gpu >= 0 and torch.cuda.is_available() else "cpu"

    overrides = [
        f"--warm_start_ldm_ckpt={args.warm_start_ldm_ckpt}",
        f"--model.autoencoder_ckpt={args.autoencoder_ckpt}",
    ]
    policy = build_ldm_policy(args.config, overrides).to(device)
    ref = make_reference(policy).to(device)

    import models  # noqa: F401
    from utils import register as R
    import yaml
    cfg = yaml.safe_load(open(args.config))
    ds_cfg = cfg["dataset"]["train"]
    ds_cfg["mmap_dir"] = args.mmap_dir
    if args.specify_index:
        ds_cfg["specify_index"] = args.specify_index
    dataset = R.construct(ds_cfg)

    pairs = load_pairset_jsonl(args.pairs)
    loader = PairRecordLoader(pairs, dataset, device=device)
    pair_batches = list(loader)

    res = train_dpo(policy, ref, pair_batches, beta=args.beta, lr=args.lr, steps=args.steps,
                    forward_fn=denoise_loss_ldm, grad_clip=args.grad_clip, out_ckpt=args.out)

    report = {
        "mode": "real",
        "n_pairs": len(pair_batches),
        "beta": args.beta, "lr": args.lr, "steps": args.steps,
        "loss_first": res.loss_trajectory[0] if res.loss_trajectory else None,
        "loss_last": res.loss_trajectory[-1] if res.loss_trajectory else None,
        "reference_frozen_ok": res.reference_frozen_ok,
        "margin_moved_correctly": res.margin_moved_correctly,
        "out_ckpt": res.out_ckpt,
        "loss_trajectory": res.loss_trajectory,
        "reward_margin_trajectory": res.reward_margin_trajectory,
    }
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("loss_trajectory", "reward_margin_trajectory")}, indent=2))
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
