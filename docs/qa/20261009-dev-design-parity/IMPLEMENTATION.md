# Dev design integration repair — 2026-10-09

Authority: `reference/claude_design/data_centroid_design_v2/dataui`, not the obsolete `?ui=v2` application switch.

Recovered DatasetObject Analyze and producing/consuming run navigation, and InstrumentsSection, from integration/consolidated-20261001. Reused the persisted ProjectDetail standing-instructions editor as a main Instructions pane. Connections now renders within PlatformLayout at /settings/connections, reusing the existing database/MCP forms and model provider settings, plus the real skill directory and restored instrument manager.

The project tree exposes Instructions, Chats, Files, Runs and individual chats; Files opens the existing DatasetObject hub. Composer and workflow panel now use the reference spacing, bounded width, single panel header, compact progress, and expand/close actions. Project instruction records are normalized into composer defaults.

Validation: TypeScript; 140 composer/workflow/dashboard tests; 4 data-hub tests; 23 connector/project/instruction-submit tests. Headless Chrome against dev APIs verified Instructions editor open/cancel, main-pane width 1216px at viewport 1440px, all four primary Connections tabs plus private database and instrument managers, workflow expand/collapse and viewports 1100/1000/900/760px without browser errors. No workflow was submitted by the browser audit.

These repairs reconnect implemented features; they do not assert full pixel parity or fabricate the reference prototype's output-template functionality. The workspace Connections view uses compact connector rows with residency, four primary design tabs, and an Add connector action wired to the existing managers. Files, Models, and Design use PlatformLayout. Scope-preview controls remain only in the legacy modal; the workspace does not present them as functional connection settings.

Deployment provenance: the Docker build writes `/build-info.json` with the source commit passed by sync_to_dev.sh. The sync checks this public value against its checkout commit before advancing its success marker.

## Prepared cold-start datasets and Internal project

The dashboard previously seeded text only; the older MG example attached three bundled files, and that behavior was lost when the dashboard replaced it. This is an integration gap, not evidence that the datasets were never prepared.

- Data analysis → Try sample data exposes the MG tutorial plus five real public datasets previously validated in `docs/20261004_DEMO_DATA_VALIDATION.md` (metabolomics, ChIP-seq, histology, ATAC-seq, proteomics). MG loads all three files before filling the draft. The other five explicitly request their workflows' built-in demo defaults.
- Search & evidence → Internal prepares/reuses a user-owned `MG PBMC — sample data demo` project, uploads any missing counts/metadata/contrast files, selects the project, attaches the inputs, and fills an explicit draft. The examples ask about named data and groups, not an undefined scaffold or invented assay history.
- Project instructions identify the files as tutorial inputs and prohibit inferring completed assays/runs. No example automatically sends a chat or launches compute.
- Non-demo analysis examples are identified as requiring the user's inputs. Single-cell examples are not falsely advertised as having a built-in dataset.

Validation: 110 focused component/helper tests passed, TypeScript and production build passed. Browser test against the real dev API created project `3cd5292d-fcc4-4d78-8d41-53d6d3a5e77a`, verified three project files, explicit project ID in the draft, and zero chat POST requests. Test setup initially sent localhost Origin through the proxy and was rejected by CORS; correcting the preview request Origin resolved this without changing server security.
