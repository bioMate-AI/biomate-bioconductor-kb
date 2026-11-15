# 2026-11-14 23:51 — Host DNS / network reachability diagnosis

Workspace: `/Users/kky/biomate-nextphase-ci-fix`  
Related note: `docs/20261114_2349_DEV_DNS_OUTAGE.md` (peer agent `d0846a26` — IP pin / `--resolve` workaround).

## Verdict (this probe, ~23:52–23:55 CST)

| Check | Result |
|-------|--------|
| **AWS reachable** | **Y** |
| Sandbox-only failure? | **N** — default sandbox and `required_permissions: all` both succeeded |
| `HTTP(S)_PROXY` | unset |
| Transient prior outage | Likely **yes** — earlier timeouts to ATT / 8.8.8.8 / 1.1.1.1 / `52.42.49.175:443` not reproduced now |

## 1. AWS CLI

```text
aws sts get-caller-identity → Account 399683337364 (root) EXIT 0
aws ec2 describe-instances → OK (lists running fleet incl. BioMate-Production)
aws ssm send-command / get-command-invocation → OK on i-06696b0d91f4346e0
```

**SSM path remains viable.** Dev host: `i-06696b0d91f4346e0` / public `52.42.49.175` / tag `BioMate-Production` (galaxy container `biomate-galaxy-dev`).

## 2. Ping / curl known IPs

| Probe | Result |
|-------|--------|
| ICMP `1.1.1.1` | 0% loss (~15–18 ms) |
| HTTPS `https://1.1.1.1` | HTTP **301** (~80 ms) |
| HTTPS `https://8.8.8.8` | HTTP **302** (~65 ms) |
| HTTPS `https://52.42.49.175` (no SNI) | TLS cert name mismatch (expected); TCP+TLS up; `curl -k` → **200** |
| HTTPS `https://dev-public.biomate.ai/build-info.json` | **200** — `{"commit":"25a03a72c7efd5166c2d7001c44b89d75a04e503"}` |
| dig `@8.8.8.8` / `@1.1.1.1` / system / ATT `192.168.1.254` | all answer; `dev-public` → `52.42.49.175` |
| Flake recheck (5× ATT dig for `dev-public`) | all hit `52.42.49.175` |

EC2 instance metadata (`169.254.169.254`) N/A on laptop — skipped.

## 3. Sandbox vs `all`

Same probes worked under default allowlist/sandbox and with `required_permissions: all`. **This episode was not Cursor-sandbox-only.** Earlier total DNS failure was a host/LAN (or transient ATT resolver) outage that has since cleared; keep the `--resolve` / hosts-pin session workaround from `20261114_2349_…` for Playwright when ATT flakes again.

## 4. Impact

| Workstream | Status |
|------------|--------|
| **design-generate Playwright** | Treat as **BLOCKED / do not duplicate** — headless Playwright Chromium already live on host (`playwright_chromiumdev_profile-*`). Peer agents `d0846a26` / possibly `d13cc281` own that lane. |
| **REINVENT Batch** | Already **PASS** in earlier session when network worked (see reinvent remeasure docs; do **not** rebuild ECR). |
| Cheap API via IP | Viable without public DNS: `curl --resolve 'dev-public.biomate.ai:443:52.42.49.175' …` |

## 5. Cryo via SSM (`biomate-galaxy-dev` + frontend)

Inspected 2026-11-15 ~05:54Z UTC via SSM (no ECR rebuild, no Playwright).

### `movies_path` seed — **already fixed on DEV**

Deployed frontend file `/app/dist/public/demo/cold-start/cryo_inputs.json` contains:

- `movies_path`: `s3://biomate-cryo-data/empiar-10028/Micrographs/`
- `staged_movies_s3`: same prefix

Cold-start bundle context in shipped JS includes `Set movies_path=s3://biomate-cryo-data/empiar-10028/Micrographs/`.

### License / CryoSPARC env on `biomate-galaxy-dev`

| Var | State |
|-----|--------|
| `CRYOSPARC_LICENSE` | **SET** (len 36) |
| `CRYOSPARC_EMAIL` / `PASSWORD` / `SSH_KEY` | SET |
| `CRYOSPARC_MOVIES_S3` | `s3://biomate-cryo-data/empiar-10028/Micrographs` |
| `CRYOSPARC_DEFAULT_MOVIE_DIR` | `/home/ubuntu/biomate_movies/2b97383e3f` |
| `CRYOSPARC_HOST` | `100.54.207.255:30000` |
| `CRYOSPARC_INSTANCE_TYPE` | `g6.2xlarge` (`us-east-1`) |

### S3 data

Laptop AWS (root) `aws s3 ls s3://biomate-cryo-data/empiar-10028/Micrographs/` → movies present (`001_movie.mrcs` …). EC2 deploy role cannot `ListBucket` that prefix — irrelevant to Galaxy path that uses staged credentials / sync.

### Cryo blocker classification

| Item | Actionable code fix now? |
|------|---------------------------|
| Coldstart `BLOCKED_REQUIRED` for missing absolute `movies_path` | **No** — seed + catalog context already on DEV (`build-info` tip `25a03a72…`). |
| License missing in galaxy-dev | **No** — `CRYOSPARC_LICENSE` present. |
| End-to-end Confirm → GPU CryoSPARC run | **Still open product path** — needs live E2E / Confirm measurement (Playwright lane). Not a clear offline code bug without that measurement. |

**No code change shipped in this diagnosis pass** — root cause for the prior coldstart movies bind is already deployed; remaining risk is runtime/GPU Confirm, not another JSON seed patch.

## 6. Coordination

- Do **not** start a second design-generate Playwright run.
- Do **not** rebuild reinvent ECR.
- Prefer SSM / `--resolve` when ATT DNS flakes again.
- Lease: `NO_LEASE` observed during SSM inspect.

## Return summary

- **AWS reachable:** Y  
- **DNS:** recovered now (ATT + public resolvers + hostname OK); prior outage was transient host/LAN, not sandbox-only  
- **Cryo:** movies_path + license OK on galaxy-dev/frontend; remaining blocker = live Confirm/GPU E2E (defer to existing Playwright agent)  
- **Doc:** `docs/20261114_2351_HOST_DNS_NETWORK_OUTAGE.md`
