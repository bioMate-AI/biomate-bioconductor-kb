# Navigation acceptance — 2026-11-07

Source review and focused local tests; not a deployed-browser acceptance claim.

| Surface/state | Exit and destination | Context behavior | Evidence/limitation |
|---|---|---|---|
| Settings | Parent-controlled Close/Escape | Parent owns return to originating project/chat | Actual component browser harness: 25 synthetic rows, 549px viewport / 2870px content; wheel and Home/End reach bottom (scrollTop2321), Close stays visible and Escape dismisses. Local only. |
| Connectors embedded | Persistent header Close | Calls parent onOpenChange(false); no browser-history navigation | Existing handler preserved; callback test passes |
| Connectors dialog | Radix close button/Escape | Closes only dialog | Existing DialogContent primitive |
| Add connector kinds | Persistent Cancel adding | Restores exact original connector tab and source subtab | Added state restoration test |
| Chosen database/MCP/skill/instrument setup | Back to connector kinds, Cancel adding, outer Close | Back reopens picker; Cancel restores source tab; connections remain stored | Added persistent navigation strip outside scrolling setup body |
| Directory scan | All connector kinds plus outer Cancel/Close | No attachment occurs just by leaving | Existing DirectoryScanFlow back callback; cancelling discards unsaved scan/form draft |
| Model-provider configuration from connector picker | Settings close/Escape then connector Back/Cancel | Connector origin retained in parent | Nested Settings modal needs browser focus/return verification |
| Import workflow | Radix close/Escape | Keeps project/chat parent mounted | WorkflowHistoryDialog; Settings return handled by root |
| Models registry detail loading | Back to registry | Clears selected model ID only | Fixed missing Back during pending fetch; focused test |
| Models registry detail loaded/error | Existing Back | Returns to registry without routing away | ModelObject/ModelObjectLoader |
| Files detail | Back in header | Clears selected dataset only; list/project remain mounted | DataHub passes setSelected(null) |
| Workflow/run panel | Existing header Close | Closes panel without deleting persisted run | ChatWithArtifacts passes handleClosePanelWorkflow |

No `history.back()` or reload-based exits were introduced. Saved connectors, experts, datasets and runs are untouched. Unsaved form drafts are not durable: explicit Cancel/Close may discard them; preserving drafts across route unmount would require a separate product decision and tests. The matrix distinguishes navigation continuity from persistence; successful network requests and actual deployed keyboard/focus behavior still require browser verification.

Settings layout evidence: `qa/20261107-hospital-readiness/settings-scroll-fixed-local.jpg`. Harness uses actual component/CSS, synthetic GET-only API fixtures, no dev credentials and no remote proxy. Deployed Settings remains on the preceding commit until the next approved sync.
