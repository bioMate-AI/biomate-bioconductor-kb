# Bioconductor infra packages to mark non-runnable (2026-06-15)
4 generated "workflows" are INFRASTRUCTURE/IO/GUI/optimization packages with no input→analysis→
output contract (methodology skip category). They persistently exec_error and should NOT count as
runnable failures; mark runnable_status='skip_infra' or remove from the runnable index.
| package | kind |
|---|---|
| rawrr | vendor raw-MS file IO (.NET assembly) |
| lpsymphony | linear/integer programming solver |
| widgettools | Tcl/Tk GUI widget toolkit |
| ssrch | in-memory metadata string search |
DB demotion deferred to avoid clobbering concurrent DB writes.
