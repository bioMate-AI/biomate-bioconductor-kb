# BioMate skill compatibility implementation

Date: 2026-10-29

The first implementation slice accepts standard Markdown skill metadata while preserving existing BioMate expert packs. It adds owner-scoped instruction imports and prevents a missing personal credential from selecting the shared admin account's private packs. Complete executable-package installation remains outside this slice.

## Changes

- Expert metadata uses safe YAML parsing, including folded descriptions, block lists, BOM and CRLF. Standard name/description skills do not require BioMate-specific triggers. Legacy trigger-only packs remain supported.
- Expert discovery accepts both flat Markdown and nested SKILL.md directories. The research loader accepts a configured `BIOMATE_RESEARCH_SKILLS_DIR`, current upstream layouts and legacy category mappings, with package-root and reference-path checks.
- Custom imports are instruction-only, capped at 256 KB, content-hashed and stored in a numeric owner namespace. Atomic create-once publication prevents overwrites and partially written files appearing in the catalogue. An existing name returns a conflict rather than replacing a pack.
- Private overlays are reconstructed per request, leaving the shared catalogue unchanged and avoiding process-local stale upload caches. Private skill IDs cannot collide with built-in IDs. Owned deletion cannot delete built-ins or another owner's packs.
- Storage uses `BIOMATE_USER_SKILLS_DIR` when configured, otherwise a hidden directory under Galaxy's configured file storage. Confirm that storage is persistent in the target deployment; no arbitrary source-code directory is used for uploads.
- Frontend upload/delete routes require authentication and a personal Galaxy key. Listing, detection and prompt construction include private packs only with the server-established personal-key context. A shared proxy fallback requests only the shared catalogue.
- Explicit selection failures now stop activation with a readable error instead of silently omitting the selected instructions. Automatic detection remains best-effort.

## Validation

Local filesystem/parser tests: **17 passed** after parallel review. They cover standard and legacy metadata, bundled expert packs, nested discovery, current research layouts, owner isolation, unchanged built-ins, duplicate and concurrent imports, worker refresh, owned deletion, malformed metadata/title rejection before publication, path traversal and symlink escapes. Both loaders now share the strict parser.

Frontend full regression suite before the last review fixes: **1,978 passed, 31 existing skips, 172 files**. TypeScript passed. The hardened scientific chat harness now has **11 passing parser/assertion tests**, including exact target-score rows and streamed/persisted reply equality. A final combined regression run remains necessary.

An isolated direct-to-dev Python 3.9 preflight imported the exact three changed modules, passed the then-current 14 tests and exercised native private upload/list/block/delete handlers with owner isolation, duplicate conflicts and anonymous rejection. SSM command: `58185c9c-69a7-4472-8236-7e95a3e9ae7f`. No deployed source was changed. The initially proposed S3 staging transfer was rejected before execution; the approved alternative transferred directly to the verified dev instance and used a cleaned temporary directory. The latest parser-review changes still need the frozen-source runtime gate.

Parallel review also found a pre-MFA authorization gap in optionalAuth: signed MFA-challenge tokens could reach private catalogue reads. The middleware now leaves those tokens anonymous before user lookup. The new behavioral suite reproduced two pre-fix failures; afterward **25 tests passed** across the focused middleware, skill-access and auth-service suites. This is not a live HTTP private-skill journey.

These checks do not prove the import UI, executable packages, team/project sharing or a deployed private-skill journey. There is no new skill import UI in this slice. Deployment remains incomplete.

## Scientific reply audit follow-up

The earlier citation deployment `b6ca37fc8` completed healthy. A real two-turn dev journey used the existing fixture account, one disposable project, actual target/review tools and no Batch workflow. The project was deleted afterward. The captured result is `docs/qa/20261029-scientific-chat-live-final.json`.

The harness initially passed structural checks, but output inspection failed scientific acceptance: target identification returned actual BRAF/NRAS/TP53 scores, while the final reply denied execution. The citation guard had substituted an earlier literature answer that did not know the tool had run. Review prose also needs claim-level scrutiny; valid numbering does not validate prevalence, preclinical-to-clinical generalization or duplicate references.

The local draft gives completed target evidence its own reply artifact, preserving returned targets, scores, tiers, channel failures and conflicts. Tool events are captured even without an external callback. The hardened harness binds every known target to its actual rank/score/tier/conflict and checks streamed versus persisted content.

Parallel review identified unresolved production orchestration gaps: pre-tool narration can stream before the guard activates; mixed review prose can contradict a completed target artifact; and repeated/error/no-evidence target calls need per-call ownership instead of retaining the last successful result. These are blockers to deploying the draft as a complete fix. The earlier structural pass is not scientific acceptance.

## Remaining work

1. Complete runtime preflight, review the final diff and verify the dev deployment and private upload/list/select/delete journey.
2. Add the compact user import/detail UI, including instruction-only status, owner, version/hash and dependency limitations.
3. Implement package manifests, reviewed scripts/assets, runtime/dependency resolution, revision management and explicit project/team sharing. Do not equate Markdown import with these capabilities.
4. Run realistic manuscript, editable-slide and publication-figure cases with numerical, citation and rendered-output review before enabling those packages by default.

No third-party repository or model service was installed or enabled. The implementation is a foundation for the integration plan in `20261029_RESEARCH_AND_PUBLICATION_SKILL_COMPATIBILITY_AUDIT.md`, not completion of every phase.
