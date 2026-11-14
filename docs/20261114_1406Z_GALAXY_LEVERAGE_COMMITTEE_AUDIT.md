# Galaxy leverage arc — summary + committee audit

**File stamp:** `20261114_1406Z` (UTC)  
**Branch:** `devline/ds-audit-20261112`  
**Live tip at audit start:** `0b63d793` (matched `/build-info.json`)  
**Scope:** Deep Galaxy leverage (folder/samplesheet/deferred/FTP/datatype/repro pack) + E2E `BASE_URL` class

---

## What we have done so far

### Product (user-facing)

| Capability | Status | Key commits / evidence |
|------------|--------|------------------------|
| Folder → **all files** as Analysis + Models input | **Have** | `6555d0e392`; E2E `folder-attach-all-files.e2e.ts` |
| FASTQ folder → **samplesheet as one** Analysis input | **Have** | `82524c3839`; live samplesheet **201** → one chip |
| Deferred / large URL import in chat + Data Hub | **Have** (UX) | `82524c3839` |
| Deferred **materialize on Confirm & Run** | **Have** (wiring restored in this audit) | Module `94ae1391d5` / restore `0b63d793`; **routes re-wired 2026-11-14** after committee found merge drop |
| Public FTP/HTTP → project file | **Have** (SaaS path) | `82524c3839` Data Hub `RemoteSourcePicker` |
| Perception → Confirm & Run **datatype gate** | **Have** | `82524c3839` `perceptionMismatch` → `isPrereqBlocked` |
| **Reproducibility pack** zip | **Have** | `3e8b2db292` → live via `0b63d793`; `GET /api/runs/:id/reproducibility-pack` |
| Chat file UX (group by chat, size, hover date) | **Have** | earlier in arc |
| CN LLM region policy + voice env | **Have** | prior session track |

### Test / ops hygiene

| Item | Status |
|------|--------|
| E2E fixture login honors `BASE_URL` | Fixed `a0d9191c17` |
| Shared `_e2e-base-url.ts` precedence | `b8094567ee` class close; partially merge-dropped; **re-closed in this audit** |
| Folder/samplesheet live E2E | PASS on prior tips (`d6f5517b` / BASE_URL-only evidence `20956dfb84`) |
| Sync process | Ancestry + one-writer; tip `0b63d793` was healthy sync |

### Peer work landed on same tip (not this arc’s feature work)

Findings-class metrics-first, clarify panel-open, CryoSPARC license / Run Manager digs — merged via sync ancestry.

---

## What’s still open

### High-value product (checklist)

1. **Pre-run cost estimate badge** — honesty redesign (historical/prior); do **not** uncomment static table / fake 503 defaults  
2. **Inline estimate vs actual** run cost strip  
3. **BAM/VCF/(h5ad) viewers** without Interactive Tools (IGV.js-class)  
4. Datatype **auto-converters** before Batch  
5. Workflow **landings** / shareable pre-filled run links  
6. Storage **archive/purge** for abandoned S3  
7. In-app run-complete / QC **notifications**  
8. Honest `.ga` → Galaxy-engine (or clear Nextflow-only labeling)

### Residual / follow-on from this audit (nice)

- FTP `public-data/{filename}` collision risk; unique destination keys  
- On-prem relative fetch URLs vs `import-url` absolute requirement  
- Datatype gate overbreadth for generic param name `input`  
- Dedicated live E2E: FTP browse→import + deferred materialize → 409 fail-closed  
- Repro pack: optional completed-only gate; redact sensitive params from zip

---

## Committee audit (2026-11-14)

Two parallel reviews (capability committee + Bugbot-style security/correctness) agreed:

### MUST-FIX (found at tip `0b63d793`)

| ID | Finding | Disposition |
|----|---------|-------------|
| **M1** | `deferred-materialize.ts` restored but **not called** from Nextflow execute — silent Batch launch with bare HDA ids | **Fixed** — re-applied fail-closed block before `stageLocalFilesForBatch` (409 `deferred_materialize_failed`) |
| **M2** | Staging UUID-only regex dropped hex Galaxy ids after materialize | **Fixed** — `stageLocalFilesForBatch` resolves any key present in `_uuidFilePaths` |
| **M3** | `POST /api/datasets/:id/materialize` **unauthenticated** + admin `galaxyAPIProxy` | **Fixed** — `authenticateToken` + `userProxy(req)` |
| **M4** | Deferred create did not push session `deferred: true` hints; clients send `filename` | **Fixed** — session hint + `name \|\| filename` |
| **M5** | Many e2e specs still `BIOMATE_URL \|\|` only after merge drop | **Fixed** — migrated specs to `resolveE2eBaseUrl`; CI gate `_e2e-base-url-class.test.ts` |

### Pass (committee)

- Folder → all files; samplesheet-as-one; HDCA reject for Nextflow; datatype gate (with N4 caveat); repro pack **auth** via `resolveAuthorizedRun`

### Auth regression guards added

- `run-output-route-auth.test.ts`: repro-pack + repro-record; materialize auth; execute-path materialize-before-stage ordering

---

## Test plan executed in this audit fix

1. Unit: `deferred-materialize.test.ts`, `reproducibility-pack.test.ts`  
2. Wiring: `run-output-route-auth.test.ts`, `e2e/_e2e-base-url-class.test.ts`  
3. `npx tsc --noEmit -p frontend`  
4. Live E2E: `folder-attach-all-files.e2e.ts` with `BASE_URL=https://dev-public.biomate.ai` only  
5. Live probes: materialize unauth → 401; repro-pack unauth → 401  
6. Sync to dev after green local gates (ancestry merge if tip moved)

---

## Related docs

- `docs/20261113_GALAXY_COVERAGE_CHECKLIST.md`  
- `docs/20261113_GALAXY_LEVERAGE_DEEP_SESSION.md`  
- `docs/20261113_E2E_BASE_URL_PRECEDENCE_AUDIT.md`  
- `docs/20261113_COMMIT_PR_SYNC_PROCESS.md`
