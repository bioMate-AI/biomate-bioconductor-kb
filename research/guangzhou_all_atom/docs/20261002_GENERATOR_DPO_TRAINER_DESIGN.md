# Generator-Policy DPO Trainer — Design Note (2026-10-02)

**The "close-back" that makes the wet-lab loop AND the domain-expert instruction panel actually update the
peptide generator.** `dpo_pairs.py` emits `(chosen, rejected)` preference pairs; this is the trainer that
consumes them and fine-tunes the generator so preferred designs get more probability mass.

- Trainer: `dpo_peptide_trainer.py`
- Launcher: `launch_dpo_peptide_trainer.sh` (baked AMI `ami-06e366a5b89d12344`, `/opt/pepglad-venv`)
- Input emitter: `dpo_pairs.py` (unchanged)
- Verification: `python3 dpo_peptide_trainer.py --selftest` → **ALL_CHECKS_PASS = true** (see §5)

---

## 1. Why Diffusion-DPO, NOT HuggingFace TRL `DPOTrainer`

`dpo_pairs.py` describes its records as "TRL-ready" and exposes `to_trl_records()` →
`{prompt, chosen, rejected}`. **That contract is correct only for a sequence LANGUAGE model.** TRL's
`DPOTrainer` computes the DPO log-ratio `log(π_θ/π_ref)` as a sum of per-token log-probabilities that an
autoregressive LM returns directly.

**Our generator is not an LM.** Confirmed by reading the code:

- `m2c_train_ldm.py` trains `LDMPepDesign` = **a frozen `ClosureAwareAutoEncoder` + a trainable `FullDPM`
  latent diffusion**, warm-started from the epoch-221 diffusion (`models/LDM/ldm.py`,
  `models/LDM/diffusion/dpm_full.py`).
- `LDMPepDesign.forward` encodes `X → (H, Z)` with the frozen AE under `no_grad`, then trains **only the
  diffusion** to denoise that latent (`ldm.py:76-132`). The objective is an ε-prediction MSE
  (`FullDPM.forward` → `loss_dict['X']`, `loss_dict['H']`), **not** a sequence likelihood.

A diffusion model has **no tractable sequence log-likelihood**, so TRL cannot be pointed at it. The correct
alignment recipe is **Diffusion-DPO** (Wallace et al. 2023, *Diffusion Model Alignment Using Direct
Preference Optimization*), which substitutes the model's own **denoising loss** for the intractable
log-likelihood, under a shared noise/timestep per pair.

> `dpo_pairs.py` itself anticipates this: its docstring says "the frozen epoch-221 prior and the DPO
> fine-tune (`dpo_peptide_trainer.py`, not built here) consume this module's output." The `to_trl_records()`
> helper remains valid if we ever train a *sequence* prior; for the diffusion generator we use the
> full-provenance jsonl path instead.

---

## 2. The loss

Diffusion-DPO objective (Wallace et al. Eq. 14), adapted to this latent diffusion:

```
L = - E_{(x_w,x_l), t, ε} log σ( -β · [
          ( ||ε - ε_θ(x_w, t)||²  -  ||ε - ε_ref(x_w, t)||² )
        - ( ||ε - ε_θ(x_l, t)||²  -  ||ε - ε_ref(x_l, t)||² ) ] )
```

- `x_w` / `x_l` = the CHOSEN / REJECTED designs' **latents** (via the frozen AE).
- `ε_θ` = trainable **policy** diffusion; `ε_ref` = **frozen reference** (same warm-start init).
- `||ε - ε_*||²` = exactly the per-sample denoising MSE `FullDPM.forward` already returns. For
  `LDMPepDesign` we use the combined scalar it returns, `loss = loss_H·h_loss_weight + loss_X`
  (`denoise_loss_ldm`).

Define per-design gaps:
```
gap_chosen   = L_policy(x_w) - L_ref(x_w)     # want < 0  (policy denoises chosen better than ref)
gap_rejected = L_policy(x_l) - L_ref(x_l)     # want > 0  (policy denoises rejected worse than ref)
inside       = gap_chosen - gap_rejected      # the DPO bracket; want < 0
loss         = -log σ(-β · inside)
reward_margin = -β · inside                   # want to INCREASE over training
```
Minimizing `L` pushes the policy to lower its denoising loss on preferred designs and raise it on
dispreferred ones, both relative to the frozen reference — i.e. shift probability mass toward preferred
designs. (`diffusion_dpo_loss` in `dpo_peptide_trainer.py`.)

### Shared noise / shared timestep — implemented with ZERO edits to the PepGLAD runtime

Diffusion-DPO requires the policy and the reference to see the **same** timestep `t` and the **same** noise
`ε` for a given design (otherwise the MSE difference is dominated by noise, not by the two networks).
`FullDPM.forward` accepts an explicit `t` and draws `ε` via `torch.randn` inside `add_noise`. We
**snapshot the RNG state and restore it before each of the four forward passes** (policy|ref × chosen|rejected).
Because `batch_size = 1` per design, `torch.randint(...)` yields the identical `t` across all four passes, and
`torch.randn(...)` yields the identical `ε` within each design. The stock `LDMPepDesign.forward` /
`FullDPM.forward` run unchanged — no vendored file is touched. (`rng_snapshot` / `rng_restore`.)

This is verified empirically (§5): RNG-synced passes are bit-identical, and with `policy == ref` at init the
loss is exactly `log 2` (because `inside == 0`).

### β and lr

Diffusion-DPO uses a **large β (~2000)** because the per-sample denoising-MSE differences are tiny in
absolute terms; β rescales them into a useful logit. We default `--beta 2000 --lr 1e-6` for the real LDM run
(low lr protects the warm-started prior, matching the m2c fine-tune philosophy). The self-test uses a small
β/lr on a tiny model purely to produce a readable trajectory.

---

## 3. The pair → latent path

`dpo_pairs.PreferencePair` carries `chosen`/`rejected` as design **representation strings** (SMILES/sequence)
plus `chosen_id`/`rejected_id`. The diffusion needs **featurized complexes** `(X, S, mask, position_ids,
lengths, atom_mask, L)`, not strings. The path:

1. The loop's generated + verified designs are written out as structures and **featurized into a stock
   PepGLAD `CoDesignDataset` mmap** — the exact format `m2c_process_complexes.py` produces and
   `m2c_train_ldm.py` trains on.
2. `PairRecordLoader` builds an `id → dataset-index` map (`CoDesignDataset.get_summary(idx)[0]`) and, for each
   pair, collates the chosen and rejected records into single-design batches via the stock `collate_fn`.
3. `LDMPepDesign.forward` encodes each batch to the **v1-AE latent** under `no_grad` — identical to how m2c
   encodes. The diffusion denoising loss on that latent is the Diffusion-DPO per-sample term.

The mmap must have **no cluster resampler** (so `dynamic_idxs` is identity and `dataset[idx]` matches
`get_summary(idx)`), which the m2c config already guarantees.

---

## 4. How it plugs into `dpo_pairs.py` and emits a ckpt for re-eval

- **Input:** a `PairSet` written by `PairSet.write_jsonl(path)` (full-provenance lines). `load_pairset_jsonl`
  reads `{prompt, chosen, rejected, chosen_id, rejected_id, stream, ...}`. Verified round-trip:
  `dpo_pairs.emit_pairs(...).write_jsonl()` → `load_pairset_jsonl()` preserves all required keys.
- **Output:** `torch.save(policy, out)` writes the fine-tuned `LDMPepDesign` in the **same pickle format as
  epoch-221 / m2c** checkpoints. It is directly loadable by `cyclic_benchmark_eval.sh` /
  `launch_cyclic_benchmark_eval.sh` for a PepBDB-cyclic DockQ re-eval against the 0.403 PepGLAD reference and
  the current m2c number — closing the loop: *pairs → DPO fine-tune → benchmark → next round of pairs.*

The full closed loop:

```
VERIFY_SELECT / ACTIVITY / EXPERT  →  dpo_pairs.emit_pairs  →  PairSet.jsonl
        ↓
dpo_peptide_trainer.py (Diffusion-DPO)  →  dpo_policy.ckpt
        ↓
launch_cyclic_benchmark_eval.sh (PepBDB-cyclic DockQ)  →  score vs 0.403 / current m2c
        ↓
(next generation round uses the updated generator; new verdicts → new pairs)
```

---

## 5. Verification (CPU, no full run)

`python3 dpo_peptide_trainer.py --selftest` builds a **tiny REAL `FullDPM`** (the actual GNN diffusion, not a
mock), makes 4 synthetic preference pairs, and runs Diffusion-DPO for 60 CPU steps.

| Check | Result |
|---|---|
| Denoising loss finite | ✅ true |
| RNG-synced passes bit-identical (shared t + ε) | ✅ true |
| Noise is real without restore (sanity) | ✅ true |
| `policy == ref` at init ⇒ loss == log 2 | ✅ true |
| Loss decreased (first-quarter 0.562 → last-quarter 0.0) | ✅ true |
| Preference margin moved correctly (reward margin 0.41 → 44.1) | ✅ true |
| Reference stayed FROZEN (param fingerprint unchanged) | ✅ true |
| **ALL_CHECKS_PASS** | ✅ **true** |

Loss trajectory (head): `0.734, 0.698, 0.637, 0.729, 0.946, 0.491, 0.635, 0.164, 0.696, 0.431, 0.144, 0.443, …`
— starts at `log 2 ≈ 0.693` (no preference), descends toward 0 as the policy learns to denoise chosen better
than rejected. `gap_chosen` trends negative and `gap_rejected` trends strongly positive, i.e. the preference
direction is correct. The trajectory is noisy step-to-step (4 fixed pairs, tiny model, SGD) but the
first→last-quarter means confirm the trend.

> The self-test drives the **real** `FullDPM.forward` (the same denoising loss used in training), so it
> verifies the Diffusion-DPO loss mechanics against production code — only the model size and the pairs are
> synthetic. It needs no GPU, no checkpoints, and no mmap.

**Local dependency note:** the PepGLAD GNN stack needs `torch_scatter` (+ `biopython`). On the baked AMI these
are in `/opt/pepglad-venv`. For the local self-test they were installed from the PyG CPU wheel index
(`torch_scatter==2.1.2` for torch 2.2.x) + `biopython`.

---

## 6. What real preference data it needs to run for real

The trainer needs two things the self-test stubs: (a) a real `PairSet.jsonl`, and (b) a `CoDesignDataset`
mmap of the **featurized designs** those pairs reference (so `chosen_id`/`rejected_id` resolve to structures
the AE can encode).

**Streams available now (`dpo_pairs.py`):**

| Stream | Source | Available now? |
|---|---|---|
| `VERIFY_SELECT` | This loop's own A1 verify + A2 select verdicts (`peptide_verify.py` / `peptide_select.py`) — selected/Pareto designs (chosen) vs gated-out/dominated designs (rejected) | **Yes** — generated every generation round that produces verdicts. This is the stream to run first. Requires the round's designs to be featurized into an mmap. |
| `ACTIVITY` | Measured active ≻ inactive from public bioactivity DBs (ExCAPE/ChEMBL/PubChem inactives) | **Partially** — the `ExemplarPair` contract exists; the ETL (and featurized structures for the compounds) must be wired. Most useful for small-molecule priors; for peptides, needs bound structures. |
| `EXPERT` | Advanced ≻ abandoned (SureChEMBL ⋈ ChEMBL max_phase within-patent hard negatives) **+ the customer's accept/reject logs** — i.e. the **domain-expert instruction panel** and **wet-lab** feedback | **Not yet** — this is the crown-jewel moat stream. It becomes available when the instruction panel / wet-lab logs are plumbed into `ExemplarPair`s. The trainer already accepts it uniformly (same schema). |

**Practical first real run:** take one generation round's `VERIFY_SELECT` verdicts →
`dpo_pairs.emit_pairs(verified_pool=…, selection_result=…, gate_rejected_ids=…)` → `write_jsonl`; featurize
that round's designs into an mmap; then `launch_dpo_peptide_trainer.sh` with `WARM_LDM_S3` = the current m2c
ckpt (so DPO closes back on the newest generator), followed by `launch_cyclic_benchmark_eval.sh` on the
emitted `dpo_policy.ckpt`.

The EXPERT stream (instruction panel + wet-lab) is the highest-value data and the whole reason the trainer
exists — it is schema-ready today and plugs in with no trainer changes the moment that feedback is logged as
`ExemplarPair`s.
