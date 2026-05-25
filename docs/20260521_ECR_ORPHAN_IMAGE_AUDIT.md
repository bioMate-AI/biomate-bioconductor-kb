# 2026-05-21 — ECR orphan image audit (the small "split" images)

Follow-up to `docs/20260413_ECR_IMAGE_RATIONALIZATION.md` P1/P2: that doc
flagged 6 ECR repos pushed 2026-02-05 (`biomni-cloning`, `biomni-crispr`,
`biomni-synbio`, `biomni-systems`, `biomni-structural`,
`biomni-microbiology`) with **unknown contents**. The doc explicitly
deferred the audit ("Do not delete without auditing contents first. Run
`docker run --rm <uri> pip list`").

Today I ran that audit. Results are surprising — most of the small
images are **skeletons**, not the populated domain images the
rationalization plan assumed.

---

## Audit methodology

1. `aws ecr describe-images` for each repo — confirm tags (`x86`,
   `arm64`, `latest`) and push timestamps.
2. `docker pull` each image via ECR; install qemu binfmt
   (`tonistiigi/binfmt`) so x86 manifests run on arm64 host.
3. `docker run --rm --entrypoint='' <img> python3 -c "..."` to dump
   the full `pkg_resources.working_set`, then filter for domain-relevant
   packages.

Note: these images don't include `bash` (their `CMD` is `[bash]` but the
binary isn't present — they're built directly `FROM python:3.11-slim`
without an explicit shell install). `--entrypoint=''` plus `python3`
direct execution is required.

---

## Results table

| Image | Size | Total pkgs | Domain-relevant packages found | Intended (per 2026-04-13 doc) | Verdict |
|---|---|---|---|---|---|
| `biomni-cloning` | 121 MB | 26 | `biopython 1.86`, `numpy 2.4.2`, `scipy 1.17.0` | codon-tools, restriction enzymes | ❌ **Skeleton** — only base BioPython |
| `biomni-crispr` | 142 MB | 29 | `biopython 1.86`, `numpy 2.4.2`, `scipy`, `pandas 3.0.0` | CRISPResso2, mageck, sgRNA design | ❌ **Skeleton** — no CRISPR tools |
| `biomni-synbio` | 257 MB | 25 | `biopython 1.86`, `python-libsbml 5.21.0`, `numpy`, `scipy`, `pandas` | ViennaRNA, codon-tools, synbio libs | ⚠️ Mostly skeleton — only `python-libsbml` is a synbio-relevant addition |
| `biomni-structural` | 307 MB | 31 | `biopython 1.86`, **`prody 2.6.1`**, `numpy`, `scipy`, `pandas` | fpocket, vina+meeko, gemmi, openbabel | ⚠️ Has `prody` (protein dynamics analyzer) — useful BUT **no docking tools** |
| `biomni-systems` | 292 MB | 50 | `biopython`, **`cobra 0.30.0` + `optlang 1.8.3` + `swiglpk 5.0.13` + `python-libsbml 5.21.0`**, `numpy`, `scipy`, `pandas`, `pydantic`, `rich` | RNA design, circuit simulation | ✅ **Real image** — proper FBA / metabolic-modeling stack |
| `biomni-microbiology` | 168 MB (Feb tag) / 500 MB (April tag) | not inspected | manifest is unusual (multiple `None`-tag entries 2026-04-07 + 2026-04-08) | Kraken2, MetaPhlAn, HUMAnN | ⚠️ Recently re-pushed; needs deeper inspection |

The Feb 2026 batch (`cloning`, `crispr`, `synbio`, `systems`, `structural`)
was a **single build session** — all 5 pushed within a 5-minute window
(14:24-14:29 UTC), all using `python:3.11-slim` base + minimal pip
installs. Looks like the colleague stood up the ECR repos and got the
**skeleton structure** in place, intending to add real domain tools
later — but the follow-up never happened.

---

## What's actually safe to use today

| Image | Use it for | Confidence |
|---|---|---|
| `biomni-systems:x86` | `systems_biology/` workflows that do FBA, metabolic flux, cobra-based simulation | High — real cobra/optlang stack, ready to use |
| `biomni-structural:x86` | Workflows that do structural analysis but NOT docking (prody-based PDB analysis, NMA, dihedral measurements) | Medium — has prody, but most structural workflows want docking → use `biomni-structure-to-drug` instead |
| `biomni-cloning:x86`, `biomni-crispr:x86`, `biomni-synbio:x86` | NOT yet — would break workflows expecting CRISPResso2, restriction libs, ViennaRNA. Either populate first or keep workflows on `biomni-tools`. | Don't swap |
| `biomni-tools:x86` (today's numpy<2 rebuild) | Cheminformatics, pharma, drug discovery, anything needing RDKit/Vina/Meeko/ViennaRNA/DeepPurpose | High |

---

## Today's pilot

Switching one `systems_biology` workflow from `biomni-tools` →
`biomni-systems` to validate the swap end-to-end on AWS Batch. If the
chosen workflow only needs `cobra + numpy + scipy + pandas`, the 292 MB
image should pull in ~3-5 s (vs `biomni-tools` 3.4 GB which takes 30-60 s
on a cold worker). Big cold-start win when it works.

If the swap fails because the workflow secretly uses something only in
`biomni-tools` (e.g. an `import` that the skeleton image lacks), we
revert and note that workflow needs to stay on `biomni-tools`.

---

## Recommendation for the rationalization doc

Update Section 5 (Phase 2 — Intended Split) of
`docs/20260413_ECR_IMAGE_RATIONALIZATION.md` to reflect:

- `biomni-systems` is the only currently-populated small image.
- `biomni-structural` is partially populated (prody only, no docking).
- `biomni-cloning`, `biomni-crispr`, `biomni-synbio` are skeletons; no
  workflow should reference them until they're populated.
- The full domain split is **not a swap-the-container-string job** for
  4 of the 5 images — it's a **build-the-image** job. Estimate per
  image: ~1-2 hours of work to identify the domain packages, write the
  Dockerfile, smoke-test, and push.
- `biomni-microbiology`'s April 2026 re-push is the most recent —
  could be a real attempt; needs separate inspection.

---

## Open questions

1. Did the colleague have a script/branch with the domain-package
   manifests for cloning/crispr/synbio that just wasn't run to
   completion? Worth asking before re-writing from scratch.
2. `biomni-microbiology` has a 500 MB layer pushed 2026-04-07 — is it
   actually populated or another skeleton? Needs the same `pip list`
   inspection (the manifest was unusual in `describe-images` output).
