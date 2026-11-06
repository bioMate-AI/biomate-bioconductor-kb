# Connector sign-in and capability repair — 2026-10-09

## Changes prepared for deployment

The desktop connector now exchanges and rotates OAuth refresh tokens, persists the result in a mode-0600 credential file, and calls a scope-enforcing OAuth gateway. The gateway uses only the signed-in user's personal API key. Missing credentials fail closed; a revoked stored key is replaced when that user signs in again. The normal BioMate login verifier and JWT signing configuration are unchanged.

The installer registers its PKCE client, persists the returned client identifier, honors --auth-base, writes the credential-file path into host configuration, and correctly replaces an existing Codex configuration block including its environment section. Version 0.1.1 requires existing OAuth users to reconnect; personal API-key configurations remain supported.

The npm package advertises 19 tools. It describes the implemented planning, polling and Markdown export behavior rather than advertising instrument tools, automatic execution, PDF/DOCX or live progress notifications. This does not implement those unavailable capabilities. The Node session adapter preserves final workflow plans and clarifications and rejects incomplete/error responses.

Remote MCP bearer authentication will be enabled on dev with this release. Anonymous tool calls must fail; authenticated callers require their own stored account credential. Clients relying on anonymous access or shared credentials must reconnect. The remote MCP three-tool subset remains a separate surface from the npm adapter's 19 tools.

## Verification

- Real fixture-account login and consent through an isolated copy of the actual OAuth service, with the real BioMate backend.
- PKCE code exchange, refresh rotation, persistence across client restart, and rejection of the old refresh token passed.
- Existing owned-run retrieval passed through the candidate npm package and OAuth gateway.
- Insufficient-scope execution request rejected before workflow dispatch. No workflow launched.
- Revoked personal key rejected; reconnect replaced it and restored read access.
- Temporary personal keys revoked after testing; no secrets stored in evidence.
- Two gateway tests cover absent/expired bearer, missing scope, unknown tools, missing personal credentials and distinct per-user authorization headers.
- Installer: 20 tests passed; both TypeScript packages build; package contents inspected.
- Earlier session adapter validation: 1,676 application tests and live chat response parsing passed.
- Latest pre-deploy suite initially caught a concurrently edited pipeline error-display test; its current version passes in isolation. Final suite/typecheck results will be recorded before deployment.

Evidence: `qa/20261009-connector-workflows/compatibility/oauth-repair-proof.json` and the exact reviewed source patch `oauth-repair.patch`. Main repository source includes the matching /oauth/tools/:name proxy. Full package publication and deployed-service checks are still required before release is complete.

## Review and authorization

The first broad direct edit was rejected by automatic approval review. The patch was then built and tested in an isolated copy, reviewed file by file, and applied successfully using a source-hash-checked manifest. No live service changed during that process. The follow-up review allowed the exact tested source patch.

Pre-deploy expectations: health stays successful; unauthenticated /mcp returns 401; /oauth/tools rejects missing/expired tokens and missing scopes; the newly published npm client can sign in, refresh and read the existing fixture run. Rollback uses the existing sync deployment snapshots. This changes connector authentication, so previously anonymous remote clients need to sign in.

Final pre-deployment gate: TypeScript passed; full frontend suite passed 144 files / 1,718 tests, with 2 files / 7 tests skipped. The previously failing pipeline test passed in the complete rerun. Installer 0.1.1 explicitly defaults to the verified dev-public endpoint, documented as development; the broken production hostname is not silently presented as verified. The credential file is authoritative; the CLI no longer stores an immediately stale refresh-token copy in the OS keychain.

## Deployment and release progress

The dirty-tree safeguard stopped the first deployment before it changed the service. A clean sparse checkout of `7a2ae3e54` was created instead, preserving other ongoing edits. TypeScript passed there. The full suite's only failures were omitted cross-layer source/reference files; after including the committed backend and tutorial references and linking the existing catalog database, all 30 affected tests passed. Other tests in that full run passed.

Dev deployment completed healthy at 21:50 America/Chicago. Frontend image: `sha256:2d31ffe17505de5ac2a7ef298b3aa7bf074e2486b84c0f44b2072b74bb0e8753`. The running build revision was verified as `7a2ae3e54e694e8eaf1fe2439073dabbb71b8da7`. Remote MCP is healthy and returns 401 to unauthenticated requests. Connector contract smoke checks: zero failed, zero inconclusive. The existing migration replay again reported the already-existing users table; health and application smoke checks passed. No workflow/database layer was uploaded.

The deployed planning route returned a valid final response (1,571 characters) without executing a workflow. Real fixture-account OAuth login, PKCE exchange, refresh rotation, stale-refresh rejection, scoped write denial, owned-run retrieval and client restart all passed against the public deployed service. Evidence: `compatibility/session-deployed-proof.json` and `compatibility/oauth-deployed-proof.json`.

npm accepted both `@biomate/mcp-server@0.1.1` and `@biomate/connect@0.1.1` for public publication. Registry processing was still pending on the first installation attempt; final published-package verification remains to be recorded. The installer now builds as ESM, starts under Node 18, has no unused native keychain dependency, and excludes development tests from its package.

## Final published-package verification — passed

Both version 0.1.1 packages are now visible in npm. The actual published MCP package was installed into a fresh temporary directory and tested against the deployed dev service. All 14 checks passed, including login, PKCE, refresh rotation, old-refresh rejection, client restart, owned-run output inventory, Markdown report export, permission denial and test-key cleanup. Evidence records packageVersion 0.1.1 and the installed npm entry path.

The actual published installer starts successfully with --help. Its built source also starts under Node 18. Four additional live checks passed for personal API-key creation/use/revocation and denial after revocation with the published MCP client. Existing API-key users remain supported; existing OAuth users should reconnect with @biomate/connect@0.1.1 and restart their host.

Connector repository commits d7542d4 and d8ec0a6 were pushed to feat/instrument-actuation-dbtl. Main-repository repair/packaging commits are 7a2ae3e54, c2e58eac2 and f115bac85; the inherited GitHub workflow-scope restriction on pushing that branch remains separate from successful deployment and npm publication.

Scope: the 19-tool npm/desktop adapter and its OAuth gateway are verified as described above. This is not a certification of every tool/domain, ChatGPT Actions/WeChat UI flows, report editing, production deployment, or scientific interpretation. Recording remains subject to the separate scientific and client-specific tutorial gates.
