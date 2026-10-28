# Exact file-to-chat handoff and simpler workflow controls

Analyze previously generated a prompt containing only the display filename and asking for workflow selection. That did not attach the file reference and manufactured an analysis goal even for documentation. Use in chat now carries the project and exact project-file ID. The composer verifies access using the existing project file URL endpoint, displays the reference chip and leaves the query empty. Nothing is sent automatically; a reference-only composer waits for a question. The existing authorized server resolver receives datasetReferences on send and resolves the exact project file to its S3 input.

Output-location controls are removed from rendering at the user's request. Execution automatically passes the project destination when a project exists; standalone chats omit the override and use managed storage. Backend support for other destinations remains intact.

The progress row inherited column layout from global message CSS despite its inline flex display. Explicit row direction, left alignment, wrapping and bounded content remove the vertical diamond/status/text stack; the diamond is removed. Fold controls also enforce a horizontal layout. This does not claim all premature workflow routing or interactive viewer errors are solved.

Review expectations: opening a file in chat creates no request, leaves an empty composer, and includes the exact file ID only when the user sends a question. Missing or unauthorized files show a linking error. Workflow settings show no output-location choice; project execution retains its project ID. Historical and new progress messages use compact rows at narrow and wide sizes. Validation pending.
