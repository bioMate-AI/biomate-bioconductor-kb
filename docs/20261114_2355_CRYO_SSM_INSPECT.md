# 2026-11-14 ~23:55 — Cryo SSM inspect (CMD recovery)

Instance: `i-06696b0d91f4346e0` · containers: `biomate-galaxy-dev` (healthy), `biomate-dev-frontend` (healthy)

## Commands

| CMD_ID | Status | Notes |
|--------|--------|-------|
| `8da60c90-2037-49b0-9de0-ad8e20fecdb1` | **Success** RC 0 | Original terminal-343815 inspect; local poll showed `ERR` (JSON parse under proxy), but re-fetch with `HTTP_PROXY` cleared returned full stdout |
| `14536cf2-cc2b-485e-b196-131799dcc1bc` | **Failed** RC 2 | One follow-up; heredoc/quoting broke mid-script after useful greps. Not re-run (coordinate with d13cc281 / 950c1ec2) |

## CMD result summary (`8da60c90…`)

- Galaxy + frontend up.
- `CRYOSPARC_*` env present on galaxy-dev (keys redacted in raw output): `LICENSE`, `HOST`, `EMAIL`, `PASSWORD`, `MOVIES_S3`, `DEFAULT_MOVIE_DIR`, `PROJECT_DIR`, AMI/region/instance, SSH.
- No `cryo_inputs.json` under `/app` in galaxy (expected — seed lives in **frontend** dist).
- Host `rg` missing → coldstart greps empty in original script.
- EC2 deploy role: `s3:ListBucket` **AccessDenied** on `biomate-cryo-data` (same as sibling note; not a Galaxy runtime blocker).

Partial `14536cf2…` before fail: galaxy code still treats `movies_path` as required; no empty-license signal before syntax error.

## License

**Y** — `CRYOSPARC_LICENSE` present on `biomate-galaxy-dev` (raw inspect shows key set; sibling SSM `docs/20261114_2351_HOST_DNS_NETWORK_OUTAGE.md` measured **len 36**). Not blocked for missing license.

## movies_path state

| Source | State |
|--------|--------|
| Repo `frontend/client/public/demo/cold-start/cryo_inputs.json` | `movies_path` + `staged_movies_s3` = `s3://biomate-cryo-data/empiar-10028/Micrographs/` |
| DEV frontend (sibling 2351) | Same absolute S3 URI in `/app/dist/public/demo/cold-start/cryo_inputs.json`; catalog context includes `Set movies_path=s3://…` |
| S3 fixtures (laptop AWS) | Prefix lists movies (`001_movie.mrcs` …) |
| Galaxy `/app` find | No `cryo_inputs.json` (OK — not the seed host) |

Coldstart `BLOCKED_REQUIRED` from missing absolute `movies_path` (per `docs/20261114_0900_NEXT_REINVENT_CRYO.md`) is **already remediated on DEV**.

## Blocker

**None for license / movies_path seed.** Remaining open item is live Confirm → CryoSPARC GPU E2E measurement (Playwright lane), not another seed/license patch.

## Coordination (not done here)

- Did **not** start GPU Batch.
- Did **not** rebuild reinvent ECR.
- Sibling agents d13cc281 / 950c1ec2 may own Confirm/GPU; prefer their lane over a second Cryo launch.
