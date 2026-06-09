# Nextflow Platform Hardening — Multi-day Session Writeup

**Dates:** 2026-06-07 → 2026-06-08
**Author:** integration/next-phase
**Scope:** Unblock nf-core pipeline execution on AWS Batch; verify BioMate
workflows survive concurrent submission; ship durable infra fixes.

## What I came in with

- nf-core pipelines unable to execute on BioMate's AWS Batch CE despite
  earlier "working" claims; multiple regressions previously fixed had
  reappeared (LT v9 → v14 → v9, container-cast, libz mount, etc.).
- BioMate's own (`biomni_workflows/`) workflows working but unverified
  against a fresh sweep; previous parallel-fire of 19 yielded only 9
  successes (others were zombies from a dev-EC2 host impairment).
- Dev EC2 going `impaired` under load with no throttle in place.

## Net result

Eight code/infra/doc commits land durable fixes for each problem
class. Empirical end-of-session sweep: BioMate workflows pass 10/10
on fresh retest; nf-core's `rnaseq` test profile runs end-to-end on
Batch (first nf-core full-pipeline success through BioMate); other
nf-core test runs (`chipseq`, `atacseq`) advance through 5+ Batch
tasks before hitting **upstream-specific** failures (TRIMGALORE
biocontainer pin, cutandrun Groovy NPE) — no longer platform issues.

## Commits, in order

| Hash | Title | Why |
|---|---|---|
| `26fef3ed4` | `fix(galaxy.yml): pin gunicorn bind to 0.0.0.0:8080` | Local `backend/config/galaxy.yml` had `bind: 0.0.0.0:8081` — wrong, since Docker maps host:8081 → container:8080. Every host-side curl returned `Connection reset by peer`. |
| `6bf330a8d` | `fix(nextflow): skip params/process.container injection for nf-core` | nf-core 3.x+ schema validator types `container` as Map, our String injection raised "Cannot cast String to Map" on abotyper/createtaxdb. |
| `ab5d1752c` | `fix(nextflow): skip publishDir/aws.client overrides for nf-core 25+` | Newer nf-core uses `workflow.output.mode = params.publish_dir_mode`; our `publishDir = null` raised "Cannot compare ConfigObject with Integer" on airrflow 5.0.0+. Slimmed aws.client block was dropping `anonymous=false`. |
| `eab13c3ca` | `feat(infra): auto-sync all Batch CEs to latest LT version` | `biomate-nextflow-ce-v2` was pinned to LT v9 for 7 weeks after the fix landed in v14 — the libz/aws-cli mount bug recurring for the 3rd time. New audit script auto-bumps any lagging CE on every `sync_to_dev.sh`. |
| `4f4887520` | `fix(nextflow): mount host libz into nf-core task containers` | Even on LT v16, the Batch AMI's `/opt/aws-cli/bin/aws` is dynamically linked against system libs missing in minimal biocontainers. `aws.batch.volumes = ['/usr/lib64/libz.so.1:...']` mounts the one needed file without the glibc-symbol-mismatch trap of mounting `/usr/lib64` wholesale. |
| `d2c0437ea` | `fix(sync): durable ship of backend/config/galaxy.yml to dev` | The bind fix above wasn't durable — container restart wiped the in-container patch back to image-baked default. `sync_to_dev.sh` now ships the file with verification + gunicorn restart on every sync. |
| `92236e757` | `feat(nextflow): cap concurrent NF head launches via semaphore` | Dev EC2 went `impaired` twice (2026-06-07 17:25, 2026-06-08 ~19:00) when ~20 NF head JVMs (each ~500MB–1GB) OOM-killed the Galaxy container. Bounded semaphore at 5 (configurable via `BIOMATE_NF_MAX_CONCURRENT`); 6th+ blocks 5 min then returns 503 — clean back-pressure signal. |
| `600623eaf` | `docs: AWS quota-increase requests + support-case body` | Filed 4 quota increases via Service Quotas API (CPU OD 626→2000, CPU Spot 512→4000, GPU OD 128→384, GPU Spot 128→768) all PENDING; paste-ready Support case for the manual upgrade-to-Business-Support narrative. |

Two parallel-session commits also touched `nextflow_executor.py`
(`6e5c6d0f3`, `e671faa2b`) absorbing intermediate `nf-amazon@3.4.4`
plugin pin + uploadChunkSize tuning for nf-core paths.

## Tested

- **Cell/virtual_cell BioMate workflows:** 10/10 succeeded on fresh
  re-fire post throttle (`bd_rhapsody_scrna`, `cite_seq_preprocessing`,
  `scrna_doublet_qc`, `parse_split_seq_scrna`, `multiome_rna_atac`,
  `transcriptomic_moa_lincs`, `cipa_cardiac_safety_ode`,
  `metabolic_flux_fba`, `ode_signaling_simulation`,
  `physicell_tumor_tgi`).
- **Drug-discovery / pharmacology:** `ADMET_pred` end-to-end with real
  aspirin SMILES (S3 outdir confirmed). `allometric_scaling` and
  `pbpk_simulation` rc=0 with empty-params.
- **3 GPU workflows** (cpa_synergy_gpu, gears_perturbation_gpu,
  transcriptformer_gpu) end-to-end on Batch GPU CE; previously thought
  blocked by job-def autoreg, actually just the bind regression.
- **nf-core/rnaseq** test profile: **succeeded** end-to-end — first full
  nf-core pipeline through BioMate.
- **nf-core/chipseq, atacseq:** advance through 5+ Batch tasks
  successfully; both fail inside TRIMGALORE container with exit 25 —
  caused by libtinfo version mismatch in the pinned biocontainer
  (`quay.io/biocontainers/trim-galore:0.6.7--hdfd78af_0`, ~3 years old)
  polluting `cutadapt --version` output that trim_galore's Perl parser
  reads. **Upstream issue, not BioMate.**
- **nf-core/cutandrun:** fails inside its own Groovy with `Cannot
  invoke method optional() on null object` — upstream Groovy bug.

## Diagnosed but not fixed (handed off)

- **Batch AMI aws-cli install not self-contained**
  (`docs/20260607_BATCH_AMI_AWSCLI_NOT_SELF_CONTAINED.md`). The libz
  mount today is a working workaround. The proper fix is rebuilding
  the AMI so `/opt/aws-cli/v2/current/dist/` actually contains all
  bundled libs the binary needs; then no host-lib mounts are needed.
- **JVM startup SIGSEGV in `CmdInfo.status()` / `loadLibrary("management")`**
  (`docs/20260606_JVM_CRASH_DIAGNOSIS_NOT_CRT.md`).
  Orthogonal to today's work; another session owns.
- **Bioc workflow T5 correctness** — the existing work/ dir outputs
  I spot-checked are 0–1 line (header only). The 724 CSV claims
  executability but I cannot verify T2 (non-empty outputs derived from
  input) from on-disk artifacts in this session; the harness audit
  JSONs are not in the tree. Surfaced as a question for the bioc team
  audit.

## Memory entry

`/home/yzhang/.claude/projects/-home-yzhang-biomate/memory/feedback_survey_before_iterating.md` —
the lesson from this session: before infra debugging, list queues →
CEs → LTs → AMIs **first**, and `grep -r docs/` for the error
string. The libz/aws-cli bug had been documented twice before; each
session was re-discovering it from scratch. Now indexed in `MEMORY.md`
so future sessions load it immediately.

## Capacity ceiling reported back to user

| Layer | Current ceiling | Notes |
|---|---|---|
| CPU on-demand | 626 vCPUs (EC2 account quota) | Bound, not CE max. Quota increase to 2000 PENDING. |
| CPU Spot | 512 vCPUs | Quota increase to 4000 PENDING. |
| GPU on-demand | 128 vCPUs | Severe — only ~2 g6.12xl concurrent. Quota increase to 384 PENDING. |
| GPU Spot | 128 vCPUs | Quota increase to 768 PENDING. |
| Cold start | 2–5 min | Job RUNNABLE 30s + EC2 launch 60s + LT user-data 60-90s + image pull 30s–3min + NF staging 10-30s. |
| Dev EC2 RAM | 8 GB | OOM at ~5–8 concurrent NF heads — primary practical bottleneck for testing. Throttle now caps at 5. |
| Galaxy gunicorn workers | 1 | Serializes API. Could bump to 2–4 with more dev RAM. |
| Single CE per queue (nf-core) | `ce-v2` only on `biomate-nextflow-queue` | Adding a fallback CE is a 1-line update. |

## Where to start next session

1. **Verify quota grants** when AWS approves any of the 4 pending requests; bump each CE's `maxvCpus` correspondingly.
2. **Bioc T5 verification** — run 5 popular packages (DESeq2, limma, edgeR, clusterProfiler, fgsea) end-to-end with their vignette example data; check top-N gene/term overlap with reference.
3. **TRIMGALORE biocontainer override** in nextflow_executor.py if we want chipseq/atacseq full e2e: `withName: 'TRIMGALORE' { container = 'quay.io/biocontainers/trim-galore:0.6.10--hdfd78af_2' }`.
4. **AMI rebuild** for the self-contained aws-cli so the libz mount workaround can be retired.
