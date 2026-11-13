# input_kinds enrichment diagnosis (2026-11-13)

## Verdict

**Do not sync `/Users/kky/biomate` → DEV.** The hypothesis that biomate holds a
more-populated `input_kinds` catalog than biomate-review is **false** for
non-null counts, and biomate is a **smaller** catalog (4200 vs 4233 workflows).

Review already had the Nov-5 classifier pass (~4167/4168). Syncing review→DEV
correctly left the **non-null count** at 4167; digests still differed
(in-place value edits in the review lineage). biomate’s later re-labelling
fills some NULL/`[]` gaps and changes many values, but was never copied into
review — and is not a drop-in replacement for DEV.

## Comparison (input_kinds)

| DB | MD5 | workflows | non-null/non-empty | of which `[]` | meaningful | notes |
|---|---|---:|---:|---:|---:|---|
| biomate-review / panelfix | `194f6596…` | **4233** | **4167** | 291 | 3876 | intended catalog |
| biomate current | `134274d0…` | 4200 | 3906 | 0 | **3906** | different lineage; missing 34 review-only ids |
| biomate `bak-20261112-inputkinds` | `77c70a97…` | 4200 | — | — | — | **no `input_kinds` column** (misnamed bak) |
| biomate `bak-20261113-correction` / `pre-llm` | … | 4200 | 1859 | 0 | 1859 | mid-pass |
| biomate `bak-20261113-pre-llm-apply` | … | 4200 | 1642 | 0 | 1642 | mid-pass |
| DEV bak `…122218` (pre review-sync) | `2e24e549…` | 4227 | 4167 | (review-like) | — | digest `e8ca16de…` |
| DEV after review sync (verified earlier) | `194f6596…` | 4233 | 4167 | 291 | 3876 | digest matched review `9899d12a…` |
| **DEV live now** | `20c12c91…` | 4233 | **1662** | 0 | 1662 | **regressed**; values match biomate style (e.g. rnaseq=`["counts_matrix","fastq"]`, chipseq filled) |

## What the sync report meant

`input_kinds | 4167 | yes` meant: **same non-null count**, but **content digest
changed** old-DEV `e8ca16de…` → review `9899d12a…`. That is review-lineage
in-place enrichment, not “column still empty.”

Empty on review (66 NULL/blank) are mostly: Bioconductor utility rows the
classifier left null, some nf-core pipelines (`chipseq`, `atacseq`, …), and
recent high-id rows (14665–14674). 291 further rows are intentional LLM `[]`
(“cannot determine”), counted as non-null.

## biomate vs review (shared ids)

- biomate meaningful & review not: **74** (includes `nf-core/chipseq`, spatial_*, several Bioconductor)
- review meaningful & biomate not: **21**
- shared ids with different nonempty values: **~1088**
- ids only in review: **34** (would be lost if biomate were synced wholesale)

Gap-fill merge (copy biomate only where review is null/`[]`): **+74** meaningful
→ ~3950 meaningful on the 4233-row review catalog. That is the safe enrichment
path if desired — not replacing the DB with biomate.

## Who populates `input_kinds`

`backend/lib/galaxy/ai/chain_composer/input_kinds_classifier.py` (LLM classify +
`--apply <db>`). Original bulk label: commit `339ef76b9` (~4167/4168). Not part
of ordinary indexing; new rows stay null until a classifier pass is re-run /
applied.

## Live DEV regression (separate incident)

At **2026-11-13 12:46 UTC**, host DB moved from review `194f6596…` (349323264 B)
to `20c12c91…` (350388224 B). Populated `input_kinds` fell **4167 → 1662**.
Sample values match **biomate** labelling, not review. A concurrent
`biomate-nextphase-ci-fix` sync (`251d42fa…`, 4200 rows) logged FTS failure and
claimed it did **not** upload; something still rewrote the host file ~1 minute
later. **No bak of `194f6596…` remains on DEV** (only pre-sync `2e24e549…`).
Local panelfix/review still hold `194f6596…`.

### Restore (2026-11-13 ~13:50–14:30 UTC) — DONE

DB-only restore via `scripts/sync_to_dev.sh` from panelfix
(`BIOMATE_EMERGENCY_DEPLOY_REASON` for ancestry; sync-marker pinned to HEAD so
`frontend/backend/workflows=false`, `db=true`):

| | md5 | size | workflows | input_kinds non-null |
|---|---|---:|---:|---:|
| **BEFORE** (clobbered) | `20c12c91…` | 350388224 | 4233 | 1662 |
| **AFTER** (verified live) | `194f6596…` | 349323264 | 4233 | **4167** (291 `[]`) |

- Pre-restore bak of the clobbered file:
  `/opt/biomate/galaxy_db/galaxy_ai_tools.db.bak_20261113_135051`
  (350388224 B = `20c12c91…`)
- Host + container md5 both `194f6596…` after Galaxy restart + health OK.
- Do **not** ship biomate `134274d0…`. Gap-fill (+74) still optional, not done.

### What wrote `20c12c91…` (do not re-clobber)

**Not a wholesale DB upload from nextphase.** Log
`/tmp/biomate_sync_pr398_20261113T123643Z.log`:

- `06:37:23` — nextphase saw `local=251d42fa…` vs `dev=194f6596…`, set `db=true`
- `06:45:18` — **FTS integrity-check FAILED** → `galaxy_ai_tools.db NOT uploaded`
- Same sync still deployed **backend code** (`backend=true`) including
  `UnifiedWorkflowSearch._self_heal_input_kinds` (`dae044efa9` /
  `feat/example-routing-fixes-20261112` lineage in nextphase)

That self-heal **mutates the live gitignored catalog on schema init**: it
(re)labels every row with `input_kinds_method IS NULL` or `'rule'`, then
stamps `ai_meta.rule_input_kinds_version`. Review catalog has **no**
`input_kinds_method` column / no `ai_meta` → every row is fair game → in-place
rewrite to rule-based kinds (~1662 non-null, biomate-style) → md5 `20c12c91…`.

**Guard:** do not redeploy nextphase (or any tree with `_self_heal_input_kinds`)
onto DEV while the restored review catalog is live, unless the heal is gated to
never overwrite LLM/`[]` review rows (or the restored DB is stamped so the heal
is a no-op). Panelfix does **not** contain this self-heal today.

## Recommended actions

1. ~~**Restore DEV** from panelfix/review `194f6596…` (DB-only sync)~~ **DONE**
   (2026-11-13; bak `…bak_20261113_135051`).
2. Optional: **gap-fill merge** — UPDATE review rows from biomate where review
   `input_kinds` is NULL/`[]` and biomate is meaningful (~74 rows); re-sync.
3. Optional: re-run `input_kinds_classifier` on remaining empties / new high ids;
   `--apply` into review; re-sync.
4. ~~Investigate what wrote `20c12c91…`~~ **DONE** — nextphase code-path
   `_self_heal_input_kinds` after FTS-blocked DB sync (see above).

## Fix (2026-11-13) — gate `_self_heal_input_kinds`

**Owning tree:** `/Users/kky/biomate-nextphase-ci-fix` (`backend/lib/galaxy/ai/unified_workflow_search.py`).
Panelfix / review / biomate do **not** contain this heal today (`rg` only hits nextphase + this doc).

**Root cause:** On schema init the heal selected every row with `input_kinds_method IS NULL OR 'rule'` and **rewrote** `input_kinds` in place. Review/DEV catalogs carry LLM/classifier labels with **no** `input_kinds_method` provenance → every row looked like fair game → mass rewrite (~4167 → ~1662 rule-style kinds) even when the DB file upload was skipped (FTS fail).

**Gate behavior (default = safe):**
- **Fill-only:** label only `NULL` / whitespace / literal `null` rows; stamp `input_kinds_method='rule'` on those fills.
- **Never** overwrite meaningful non-empty `input_kinds` (including null-method classifier rows).
- **Never** overwrite intentional JSON `[]` (“cannot determine”) unless `BIOMATE_INPUT_KINDS_FILL_EMPTY_ARRAY=1`.
- **Never** touch `input_kinds_method='llm'`.
- **Destructive** recompute of null-method / `rule` rows only when `BIOMATE_INPUT_KINDS_DESTRUCTIVE_HEAL=1` (ops opt-in; unset on normal deploy).
- Version marker `ai_meta.rule_input_kinds_version` still short-circuits repeat inits (no mass rewrite on every search startup).

**Test:** `backend/tests/test_input_kinds_self_heal.py` — `test_populated_catalog_is_not_mass_overwritten` + `test_empty_bracket_rows_left_alone_in_fill_only` prove review-style seeds and intentional `[]` survive init.

**DEV sync:** **Not from panelfix** (panelfix has no heal to ship). Pick up this gate on the **nextphase** deploy path (`scripts/sync_to_dev.sh` from `biomate-nextphase-ci-fix` / PR398 lineage) **before** any further nextphase backend deploy that would restart Galaxy against the restored `194f6596…` catalog. Until then, avoid redeploying unguarded nextphase backend onto DEV.

**DEV deploy (2026-11-13 ~15:00–15:52 UTC):** gated fill-only heal shipped on nextphase tip `4328dbf2` / commit `e6603814` (live code has `BIOMATE_INPUT_KINDS_DESTRUCTIVE_HEAL` + fill-only); first gated restart still filled review `[]` → md5 `19d817bb` / non_null 3930; re-restored review lineage with `ai_meta.rule_input_kinds_version=2` pre-stamped (upload md5 `c26e5e58…`) so heal is a no-op — post-check **4167** non_null / **3876** meaningful, gate present, marker `2` (live md5 `df4ced2f…` after embed rebuild; not byte-identical to pristine `194f6596…`).

## Follow-up (2026-11-13) — fill-only must not treat `[]` as empty

**Bug:** The first fill-only gate treated JSON `[]` like NULL/blank (`TRIM(input_kinds)='[]'` in the SELECT/UPDATE). On the restored review catalog those ~291 `[]` rows are intentional LLM/classifier output (“cannot determine”), not missing labels. First gated Galaxy restart filled them → non_null **4167→3930**, md5 `19d817bb…`. Recovery: re-upload review lineage + stamp `rule_input_kinds_version=2` so heal short-circuits.

**Fix:** Fill-only eligibility is **NULL / whitespace / literal `null` only**. JSON `[]` is left alone unless ops set `BIOMATE_INPUT_KINDS_FILL_EMPTY_ARRAY=1`. Defense-in-depth via `_input_kinds_is_empty(..., treat_empty_array_as_empty=False)` default. Unit test `test_empty_bracket_rows_left_alone_in_fill_only` proves `[]` survives while NULL still fills.
