# BioMate client trial: implementation and training scope

User correction, 12 September 2026: work on BioMate, not the IND model. Maximum 32B local LLM; earliest practical client trial remains the objective.

The product target is the main BioMate assistant: understand a scientist's request, retrieve available tools and knowledge, choose/parameterize a workflow, operate through existing execution controls, recover from errors and explain verified results.

| BioMate capability | Catalog tasks | Acceptance evidence |
|---|---|---|
| Intent, constraints, scientific values and clarification | T01–T03 | Correct intent; exact identifiers/units; no execution when only explanation is requested |
| Conversation continuity | T04 | Preserve dataset, parameters, corrections and previous failures across turns |
| Knowledge/tool retrieval and selection | T05, T26 | Appropriate available tool/workflow, grounded in current retrieved cards |
| Parameters, prerequisites and workflow composition/editing | T06–T11 | Schema-valid parameters, preserved explicit choices, compatible inputs and runnable workflow |
| Agent/tool execution | T12–T13 | Actual tool calls and observations, authorization enforced, bounded recovery |
| Scientific evidence and uploaded content | T14–T17 | Supported claims and citations; enable modalities only after their local integration passes |
| Failure diagnosis and repair | T18–T19 | Correctly linked failure, plausible repair, verified rerun outcome |
| Results, methods reports and notebook | T20–T21, T24–T25 | Numerical/artifact correctness; distinguish failed, completed-without-outputs and verified success |

T27/T28 support offline knowledge maintenance and evaluation, not IND training. Training sources are BioMate incident logs, corrections, commits, tool/workflow knowledge and verified teacher trajectories through these flows. The new episode preparation gate requires a task ID and rejects T22/T23.

IND narrative drafting, regulatory audits, regulatory adapters and regulatory DPO collectors are outside this work. Their earlier audit findings remain historical documentation; they are not part of this release or training plan. The changes made to the regulatory DPO collector have been removed.

Existing implementation is chiefly BioMate code: `GalaxyAssistant`, its tool loop and history handler, shared lightweight generation, workflow helpers, frontend/backend local inference and BioMate episode preparation. It is not a trained or client-accepted model. After GPU Spot failures, the user selected Spot or CPU with S3 backups. Qwen3.8-27B Q4_K_M now serves on CPU Spot; live diagnostics and recovery verification are in progress. See IMPLEMENTATION_STATUS.md for current evidence.
