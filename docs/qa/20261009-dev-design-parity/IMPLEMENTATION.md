# Dev design integration repair — 2026-10-09

Authority: `reference/claude_design/data_centroid_design_v2/dataui`, not the obsolete `?ui=v2` application switch.

Recovered DatasetObject Analyze and producing/consuming run navigation, and InstrumentsSection, from integration/consolidated-20261001. Reused the persisted ProjectDetail standing-instructions editor as a main Instructions pane. Connections now renders within PlatformLayout at /settings/connections, reusing the existing database/MCP forms and model provider settings, plus the real skill directory and restored instrument manager.

The project tree exposes Instructions, Chats, Files, Runs and individual chats; Files opens the existing DatasetObject hub. Composer and workflow panel now use the reference spacing, bounded width, single panel header, compact progress, and expand/close actions. Project instruction records are normalized into composer defaults.

Validation: TypeScript; 140 composer/workflow/dashboard tests; 4 data-hub tests; 21 connector/project tests. Headless Chrome against dev APIs verified Instructions editor open/cancel, main-pane width 1216px at viewport 1440px, all six Connections tabs, workflow expand/collapse and viewports 1100/1000/900/760px without browser errors. No workflow was submitted by the browser audit.

These repairs reconnect implemented features; they do not assert full pixel parity or fabricate the reference prototype's output-template functionality. The Connections directory retains declared metadata and the existing scope-preview controls.
