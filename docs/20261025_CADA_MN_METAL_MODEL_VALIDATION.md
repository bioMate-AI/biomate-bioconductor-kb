# CaDA-Mn metal-model validation — the FEP complex leg never had a metal at the binding site

**2026-10-25.** Requested step: validate the CaDA-Mn model before any further FEP work. Result: the first
measurement fails, and the failure is a build bug, not a force-field question. No GPU was spent; everything
below was measured from artifacts already on S3 (`avb6-fep-ctrl-build1/equil_out/complex/{em,nvt,npt}.gro`) and
the build inputs (`preflight-1792465588/in/`).

## 1. Finding
In the production complex leg, **all three CaDA-Mn were free ions in bulk water — from the first EM structure
onward.** (Minimum-image / triclinic PBC applied; the dodecahedral box is 14.2 × 14.2 × 10.0 nm.)

| structure | Mn → nearest receptor atom | Mn → nearest peptide atom | protein/ligand O < 3.0 Å | waters < 2.8 Å |
|---|---|---|---|---|
| em.gro  | 33.1 – 36.3 Å | 62 – 70 Å | 0 / 0 / 0 | 6 / 5 / 6 |
| nvt.gro | 34.7 – 35.6 Å | — | 0 / 0 / 0 | 6 / 6 / 6 |
| npt.gro | 30.7 – 37.1 Å | 62 – 67 Å | 0 / 0 / 0 | 6 / 6 / 6 |

Meanwhile the ligand Asp (ASP1071) is H-bonded to **Ser720/Ser722 (OD–OG 2.65–2.82 Å)** — the DxSxS serines
that coordinate the MIDAS metal. The pocket is metal-free. The earlier "equilibration acceptance"
(`20261021_AVB6_FEP_EQUILIBRATION_ACCEPTANCE.md`, "dynamically validated") checked **only the peptide
head-to-tail amide geometry**; it never measured the metal. The CaDA cage itself is intact in the files
(7 atoms/residue: MN + D1–D6), so this is a *placement* failure, not a cage failure.

## 2. Root cause (confirmed quantitatively)
`fep/preflight/build_fep_setup.sh` (old lines 204–215): `gmx editconf -f hconf.pdb -o box.gro -c -d 1.2 -bt dodecahedron`
**rigidly translates every atom** to centre the system, and **only afterwards** appended the Mn atoms using the
raw, un-translated `mn_cada.pdb` coordinates.

- Receptor (1069 CA matched, input vs `em.gro`): **pure rigid translation (108.2, 108.1, 50.3) Å, |t| = 161 Å,
  residual std 0.14 Å** (box-vector wraps removed by lattice reduction).
- Mn centres in `em.gro` = their input coordinates (differences < 1.1 Å, or exactly one box vector).
- Applying the *receptor's* translation to the Mn puts them 2.1–2.9 Å from carboxylate/carbonyl O, and Mn3 next
  to the ligand Asp — i.e. the intended geometry.
- The preflight script (`preflight_in_container.sh:133-148`) appends Mn **before** `editconf`, so it is not affected;
  this was a single instance in the production builder.

## 3. What this invalidates (and what it does not)
- **Invalidated:** "CaDA-Mn model + CHARMM36m + 12-λ BAR pipeline reproduces …" (controls doc §6c) — the complex leg
  ran with no metal in the site. "Setup dynamically validated and scientifically ready" (acceptance doc) — the metal was
  never measured. Any statement that the control edge exercised, or was insensitive to, the metal model.
- **Not established either way:** whether the −0.18 vs measured −0.95 kcal/mol miss is *caused* by the missing metal. The
  edge perturbs Tyr→Phe away from the metal, but the binding mode in a metal-free pocket differs from the metal-bound
  one, so the miss cannot be attributed in either direction until the system is rebuilt correctly.
- **Still unvalidated:** the CaDA-Mn force field itself in dynamics (Mn–O distances, cage stability, coordination number
  under MD). This finding means that question has not been asked yet, not that it failed.

## 4. Fix + class guard (this commit)
1. **`build_fep_setup.sh`**: convert `hconf.pdb → conf_in.gro` (no translation), **append the 21 CaDA-Mn atoms there**,
   then run `editconf -c`, so receptor + peptide + metals are translated together. (Solvent leg unaffected — no Mn.)
2. **Build-time gate** (inline, pure Python): every Mn centre must have ≥ 2 protein/ligand O within 3.0 Å *before*
   EM, else `MN_SITE_FAIL`, exit 28, and **no `FEP_INPUTS_READY` sentinel** is written. A < 1.8 Å contact is a WARN
   (known cofold clash, §5).
3. **`fep/validate_mn_coordination.py`** (new): the measurement the acceptance skipped. Triclinic min-image; per-Mn
   status UNBOUND / CLASH / OK, ligand-contact flag, JSON output; `--mode post` makes a clash a hard FAIL. Exit 2 on fail.

### Tests run (no GPU, no gmx)
| test | expected | observed |
|---|---|---|
| validator on real em / nvt / npt | FAIL 3/3 UNBOUND | **FAIL 3/3 UNBOUND** (exit 2) |
| validator, synthetic control (Mn shifted by the measured receptor vector) | not UNBOUND | Mn1 OK, Mn2 OK (min 1.89 Å), Mn3 CLASH (1.75 Å to Glu818 OE2); exit 0 in `pre`, would be 2 in `post` |
| extracted build gate, **fixed** order (input pose) | Mn1/2 OK, Mn3 warn | **OK / OK / CLASH(warn) 0.82 Å; exit 0** |
| extracted build gate, **old** order | UNBOUND ×3, abort | **UNBOUND ×3 (79–99 Å); exit 1** |
| `bash -n build_fep_setup.sh` | clean | clean |

Not tested locally: `gmx editconf` itself (no GROMACS here). The premise that `pdb2gmx`/pmx leave coordinates
untranslated is supported by the measured 0.14 Å residual (the only translation is the single rigid one), but the
first real rebuild is the confirmation — see predictions below.

## 5. Known risk the fix will expose: the cofold pose is clashed at the MIDAS metal
In the (correctly framed) input pose: **Mn1** 2.10 / 2.14 / 2.25 / 2.48 Å (four O) and **Mn2** 2.18 / 2.19 / 2.33 /
2.57 Å are well placed. **Mn3, the metal next to the ligand Asp, is 0.82 Å from Asp4 OD2 and 1.40 Å from Glu223 OE2**
(Ser125 OG 2.27 Å). Two carboxylate oxygens ~2 Å apart is a pose-level overlap, not just a metal-placement error —
the same 0.81 Å artifact documented for the Boltz Trivehexin pose. A stiff, charged CaDA cage (centre ε = 53.7 kJ/mol)
starting there may fail EM or distort the peptide. Do **not** "nudge" Mn3 by hand: choose between (a) a staged,
restrained relaxation (soft EM with Mn–O distance restraints at ~2.1 Å), (b) re-posing from a real
metal-bound structure (8TCG / 4UM9 / 9XMM), (c) a metal-aware re-cofold. Decision belongs to the next step.

**Predictions for the rebuild** (written before running, per repo rule): gate prints Mn1 OK, Mn2 OK, Mn3 CLASH(warn);
EM either converges with a displaced Asp/Glu (then `--mode post` decides) or fails in grompp/EM — a failure here is
informative, not a regression. If the gate prints UNBOUND anywhere, the frame assumption is wrong and the build must
not proceed.

### 5b. Relaxation design (implemented, opt-in) — decision taken: restrained relaxation first
Chosen over re-posing because it is the cheapest test and reuses the existing pipeline; re-posing from 8TCG/4UM9/9XMM stays
the fallback if the relaxed site does not hold unrestrained.
- **Build (`build_fep_setup.sh`, complex leg):** after genion, append an `#ifdef MN_RESTRAIN` block of soft harmonic Mn…O
  bonds (`[ intermolecular_interactions ] [ bonds ]`, type 6, kb = 2000 kJ/mol/nm², global atom indices) for every protein/ligand
  O within 2.7 Å of a Mn in the input frame. **Per-pair b0 = clamp(input distance, 0.205, 0.240 nm)**: contacts already in the
  physical window feel zero force; only clashed or stretched ones are pulled to the window edge. Production tprs never define
  `MN_RESTRAIN`, so production topologies are unchanged.
- **Build-time proof:** an extra `grompp` with `define = -DMN_RESTRAIN` must succeed (`complex_EM_RESTR_TPR_OK`), else exit 30 —
  a bad index or syntax error is caught on the CPU box, not in a GPU job.
- **Equil (`fep_batch.py --equil --mn-restrain`):** defines `MN_RESTRAIN` in em/nvt/npt for the complex leg only; outputs go to
  `equil_out*_mnrestr/` and never clobber an unrestrained run.
- **Dispatch guard:** a real submit for the complex leg is **refused** unless `in/complex/mn_site_gate.txt` exists (written only
  when every Mn passed the pre-EM gate). Verified: a submit attempt on `avb6-fep-ctrl-build1` is refused before any job exists.
- **Launcher:** `build_fep_inputs.sh` now defaults to `RUN_ID=avb6-fep-ctrl-build2` and refuses to overwrite a run that already has
  `FEP_INPUTS_READY` (override: new `RUN_ID=` or `FORCE=1`). `avb6-fep-ctrl-build1` is preserved as the record of the metal-free run.
- **Restraints are not a validation.** A restrained run proves only that the site can be assembled without blowing up. The metal model
  is validated only by an **unrestrained** continuation that keeps coordination (still to be built — to-do 4b).

**Local test of the generator** (extracted verbatim from the script, run on the real input-frame structure): 14 restraint pairs for
3 Mn — **Mn1: 6, Mn2: 5, Mn3: 3** — every index verified to be an (Mn centre → O) pair; Mn3's two clashed contacts get b0 = 0.205 nm,
in-window contacts keep b0 = their input distance (0.210–0.240). *Correction to my own earlier note:* I had expected 4/4/3 because I
had read only the four nearest O per Mn; the 2.7 Å rule also picks up Asp238 OD2 / Asp230 OD1 (Mn1) and Asp349 OD1 (Mn2).

## 6. To-do (ordered; items 2+ need an explicit go because they spend spot compute)
1. ✅ Root-cause fix + gate + validator + tests (this commit).
2. **Pick the Mn3 relaxation strategy (§5)** — design decision, no compute.
3. Rebuild the complex leg (CPU preflight on Batch) → read the `MN_SITE` lines → confirm predictions above.
4a. Re-equilibrate **with** `--mn-restrain` (bonded CaDA, small dt) → inspect em/nvt/npt with `validate_mn_coordination.py`.
4b. **Unrestrained continuation (NOT YET BUILT)** → `--mode post`, ≥ 1 ns: per-Mn Mn–O(protein/ligand) distances 2.0–2.6 Å, coordination number, cage M–D / angles. Acceptance
   = every Mn keeps ≥ 2 protein/ligand O for the whole run and the cage holds. **This is the actual metal-model validation.**
5. Only then re-run the YY→FF control against the measured **−0.95 kcal/mol**, and the metal-perturbing Asp→Ala edge
   (`EDGE_MUTS='P 2 ALA'`, already stubbed). Report sign **and** magnitude; no "recovered ≈0" framing.
6. Verify the metal identities/occupancy for the *measured* assay (the Quigley ELISA buffer) before assigning 3×Mn;
   the committee review noted MIDAS/ADMIDAS/SyMBS are typically Mn/Mg-Ca/Ca depending on conditions — **unverified here**.
7. Make the live FEP path honour the same readiness rule: `fep_production.py` has no `MDRUN_CMD_READY` guard (guard lives
   only in the superseded `fep_batch.py`); require a passing `--mode post` result before any production window is submitted.
8. Sampling: production fan-out is independent λ windows (not HREX) at 0.5 ns/window; analytic BAR error only.
9. Annotate the acceptance doc (done in this commit) and keep the controls-doc §6c correction consistent with §3 above.

### Carried over from the session (not part of this validation)
- αvβ6 selectivity is still `pending` in `score.py`; Tier-B (FF 2494× over αvβ3, etc.) is the measured target for it.
- CRO panelB contains no RGD (0/12) and fails our own gate; PD-L1 panelA 0/10 — do not order without re-gating.
- Availability model shipped (`peptide_availability.py`, LODO ρ ≈ 0.40); next optional upgrades are position-aware features
  and a second dataset for robustness. It is informational only for surface targets.
- Cyclic-LLM manuscript: the display-selector result is circular (abundance null); the FEP wording has been corrected twice
  (−0.95 measured; and now: the control ran on a metal-free pocket).

## 7. Runbook (what needs you vs. what I can run)
Only EC2 launches need you (the in-session agent cannot call `run-instances`); I can submit the Batch job and read S3.
1. **You:** `! bash research/guangzhou_all_atom/fep/build_fep_inputs.sh` — spot CPU, self-terminates ≤ 90 min, writes `…/avb6-fep-ctrl-build2/`.
2. **Me:** read `…/build2/fepbuild_stdout.txt`. **Predictions (written before running):**
   `MN_SITE res=1 … OK`, `res=2 … OK`, `res=3 … CLASH(warn) minO=0.82`; `MN_RESTR_OK pairs=14 for 3 Mn`; `complex_EM_RESTR_TPR_OK`;
   `FEP_INPUTS_READY`. Any `MN_UNBOUND` means the frame assumption is wrong → stop. Any `MN_RESTR_GROMPP_FAIL` = restraint syntax/index
   problem → fix on CPU, no GPU spent.
3. **Me (after your go, spot GPU):** `python3 cyclic_llm/fep_batch.py --equil --legs=complex --mn-restrain --run-id=avb6-fep-ctrl-build2 --submit`.

## 8. Rebuild result (build2, 2026-10-25) — predictions confirmed; fix verified on the real artifact
Run `avb6-fep-ctrl-build2` (spot c6i.2xlarge, launched by the user). `fepbuild_stdout.txt`, against the predictions written in §7:

| prediction (written before) | observed |
|---|---|
| Mn1 OK, Mn2 OK, Mn3 CLASH(warn) 0.82 Å | `res=1 OK minO 2.10` · `res=2 OK minO 2.19` · `res=3 CLASH(warn) minO 0.82` |
| `MN_RESTR_OK pairs=14` | `pairs=14 for 3 Mn (b0 window 0.205-0.240 nm, kb=2000)` |
| restraint block parses | `complex_EM_RESTR_TPR_OK` |
| sentinel + gate marker | `FEP_INPUTS_READY`, `in/complex/mn_site_gate.txt` staged |

The pre-EM gate runs *before* `editconf -c`, so it cannot by itself show that centring moves the Mn with the receptor. That was checked
on the **final** `in/complex/ionized.gro` (after centring, solvation, genion) with `fep/validate_mn_coordination.py --mode pre`:
Mn1 6 O within 3 Å (min 2.10 Å), Mn2 6 O (2.19 Å), Mn3 4 O (**0.82 Å, ligand contact = True**, Asp1071 OD2 / Glu818 OE2 1.41 Å / Ser720 OG 2.27 Å);
**0/3 failing** — versus 3/3 UNBOUND for build1. So the frame fix holds end-to-end. (System is 204,981 atoms vs 204,942 in build1: the box is
now centred on receptor+peptide+Mn, so the water/ion count differs slightly.)

Still true: `grompp` succeeding does **not** show EM converges from the 0.82 Å Mn3 clash. The restrained equilibration is the first
step that tests that; the unrestrained run (`fep_batch.py --mn-validate`, built, not run) is the metal-model test. Neither has been submitted.
