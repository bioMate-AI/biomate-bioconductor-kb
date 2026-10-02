# Generator-Policy Diffusion-DPO "Close-Back" — Design + UniMoMo Port Scope

**Date:** 2026-10-02 · **Status:** trainer built + self-test passing (`research/guangzhou_all_atom/dpo_peptide_trainer.py`, committed `a6c37aa3d`); launcher re-pointed to the best in-house base (this doc). The referenced-but-missing design note (cited by the trainer docstring + `launch_dpo_peptide_trainer.sh`) — now written.

This is the **Learn** step of the DBTL loop for the peptide generator: take (chosen ≻ rejected) preference pairs from the `dpo_pairs.py` streams (VERIFY_SELECT verdicts now; ACTIVITY / EXPERT / wet-lab when wired) and fine-tune the generator **toward the preferred designs** — without a reward model, directly on preferences.

---

## Part 1 — Why Diffusion-DPO (not TRL DPO), and how the loss works

**TRL `DPOTrainer` does not apply.** TRL-DPO needs a tractable per-sequence log-likelihood `log π(y|x)` from an autoregressive LM. Our generator is a **latent diffusion model** (PepGLAD `LDMPepDesign` = frozen `ClosureAwareAutoEncoder` + trainable `FullDPM`); it has **no sequence log-likelihood**. So we use **Diffusion-DPO** (Wallace et al., 2023), which replaces `log π` with the **denoising loss** the diffusion model already computes.

**Loss (per preference pair):**

```
L = -log σ( -β [ (L_π(x_w) - L_ref(x_w)) - (L_π(x_l) - L_ref(x_l)) ] )
```

- `L(·)` = the model's **denoising NLL proxy** on a design = `loss_dict['total'] = loss_dict['H']·h_loss_weight + loss_dict['X']` — exactly what `FullDPM.forward` already returns. (No new network; the stock forward runs unchanged.)
- `x_w` = chosen (winner), `x_l` = rejected (loser).
- `π` = policy (trainable), `ref` = **frozen** copy of the warm-start.
- Minimizing `L` pushes the policy to **denoise the chosen design better** (lower loss) and the **rejected design worse** (higher loss), relative to the frozen reference.

**The RNG-sync trick (critical correctness point).** `FullDPM.forward` draws the timestep `t` (`torch.randint`) and the noise `ε` (`torch.randn` inside `add_noise`) from the global RNG. For the four forward passes `{policy|ref} × {chosen|rejected}` to be comparable, **all four must see the same `t` and the same `ε`**. We do this by **snapshotting the RNG state and restoring it before each pass** (`rng_snapshot` / `rng_restore`), so all four draw identical `randint`/`randn`. This is what makes the DPO margin meaningful rather than noise.

**Self-test (passing):** loss = log 2 at init (π = ref ⇒ zero margin ⇒ `-log σ(0)`); with a synthetic preference, loss 0.56 → 0.0, margin 0.41 → 44.1, and `assert_reference_frozen` holds (ref params never move).

**Warm-start = the BEST model, not the latest.** As of 2026-10-02 the launcher default (`WARM_LDM_S3`) is the **cyclic-FT 0.506** checkpoint (`pepglad-cyclicft-.../checkpoint/epoch59_step1920.ckpt`), **not** the epoch-221 base (0.291) and **not** the target-conditioned M2c (0.326). Rationale: the close-back must land on the best base so improvements compound on top of the strongest model, per `feedback_model_itself_must_be_sota`. Override `WARM_LDM_S3` for ablations (e.g. base-vs-close-back).

**Honest status of the signal (do not over-claim):** only **VERIFY_SELECT** pairs exist today (our A1/A2 select verdicts; expected roughly DockQ-neutral — they encode *our* ranking preference, not new ground truth). **ACTIVITY** (ChEMBL/ExCAPE) and **EXPERT** (patent-advanced, customer/wet-lab accept-reject, instruction-panel feedback) streams are **unwired/empty**. The close-back machine works; it is **not yet fed real preference signal**. See `feedback_model_itself_must_be_sota` (loop is "half-built").

---

## Part 2 — Porting the close-back to UniMoMo (the actual best base)

**Why port.** The best *in-house* base is cyclic-FT 0.506; the best base *overall* is **UniMoMo (~0.759 DockQ, oracle best-of-N on LNR-93 @ 100/target)** — public weights, a genuinely SOTA generator and target-conditioned co-design. For the close-back to improve the *best* model (user directive), it must ultimately fine-tune UniMoMo, not just the PepGLAD-family in-house checkpoints.

**The port is architecturally cheap — UniMoMo is the same model family.** Verified from the pulled repo:

| Piece | PepGLAD (current) | UniMoMo | Port impact |
|---|---|---|---|
| Generator | latent diffusion `FullDPM` | latent diffusion `models/LDM/ldm.py` (`self.diffusion`) | same family |
| Encoder | frozen `ClosureAwareAutoEncoder` | frozen `IterVAE` (`models/IterVAE/model.py`, `self.autoencoder`) | swap encode path |
| Forward return | `loss_dict['X']`, `['H']`, `h_loss_weight` | **identical**: `loss_dict['X']`, `['H']`, `['total']=H·h_loss_weight+X` | **drop-in** |
| Timestep/noise | `randint` t + `randn` ε (global RNG) | same diffusion-forward pattern | RNG-sync unchanged |

Because `LDM.forward` returns the **same `loss_dict` shape**, the Diffusion-DPO core in `dpo_peptide_trainer.py` — `diffusion_dpo_loss(forward_fn=…)`, `rng_snapshot/restore`, `make_reference`, `assert_reference_frozen` — is **architecture-agnostic and reused verbatim**. The trainer was already written forward-fn-agnostic for exactly this.

**What actually changes (the whole port):**
1. **`denoise_loss_unimomo(model, batch, hw)` adapter** — mirror of `denoise_loss_ldm`: call UniMoMo `LDM.forward(**batch)`, return `loss_dict['H']·hw + loss_dict['X']`. (≈ the existing adapter with UniMoMo's batch keys.)
2. **`build_unimomo_policy(config, ckpt)`** — load UniMoMo `LDM` + its `IterVAE` from the public ckpt; freeze the VAE (`assert_ae_frozen` analogue); the diffusion is the trainable policy.
3. **Design → latent encoding** — encode each pair's design through UniMoMo's `IterVAE` (its block/graph featurization), replacing the m2c `CoDesignDataset` → ClosureAwareAE path. This is the only non-trivial data-plumbing work (UniMoMo's unified "block" representation differs from m2c's).
4. **Launcher** — `launch_dpo_peptide_trainer_unimomo.sh`: UniMoMo conda env (same baked-AMI pattern + the `set +u`/`set -u` conda-activate guard — see the repro fix below), UniMoMo ckpt as `WARM_LDM_S3`, pairs re-encoded via IterVAE.

**Effort:** ~1 adapter + 1 policy-builder + 1 encoder-shim + 1 launcher. The hard part (Diffusion-DPO correctness, RNG-sync, frozen-ref) is **done and tested**. Est. small — days not weeks — but **gated on two preconditions**:

**Blockers / order of operations:**
1. **Reproduce 0.759 first.** Don't fine-tune a base we haven't verified. The reproduce run (`launch_unimomo_repro.sh`) **failed 2026-10-02** on `MKL_INTERFACE_LAYER: unbound variable` (conda `activate.d` under `set -u`) — **fixed** this session (wrap `conda activate` in `set +u`/`set -u`). Re-launch, confirm reproduced DockQ ≈ 0.759 at matched split/budget/aggregation (LNR-93, 100/target, oracle best-of-N) **before** porting.
2. **Real preference signal.** VERIFY_SELECT alone won't move SOTA. Wire ≥1 of: public ACTIVITY (ChEMBL/ExCAPE ETL), patent-EXPERT (SureChEMBL advanced≻abandoned), or the CRO wet-lab round / instruction-panel EXPERT stream. The port is pointless without pairs that encode real quality.

**Caveat carried from `project_cyclic_peptide_sota_reality`:** a fixed-100 re-ranker cannot beat UniMoMo's *oracle* best-of-N headline; DPO improves the **generator's draw distribution** (better pick-1 / better best-of-N at the same budget), which is the honest lever. Report the realistic pick-1 (`max*`) alongside oracle best-of-N.

---

## Pointers
- Trainer: `research/guangzhou_all_atom/dpo_peptide_trainer.py` (core, forward-fn-agnostic)
- Pair emitter: `research/guangzhou_all_atom/dpo_pairs.py` ("DOES NOT TRAIN" — streams only)
- Launcher (PepGLAD-family): `research/guangzhou_all_atom/launch_dpo_peptide_trainer.sh` (warm-start now cyclic-FT 0.506)
- Reproduce (UniMoMo base): `research/guangzhou_all_atom/launch_unimomo_repro.sh` (conda-activate `set -u` fix applied 2026-10-02)
- Program + eval framework: `docs/20261002_BEST_PEPTIDE_LLM_PROGRAM.md`, `docs/20261001_CYCLIC_PEPTIDE_SOTA_LANDSCAPE.md`
- Memory: `feedback_model_itself_must_be_sota`, `project_cyclic_peptide_sota_reality`
