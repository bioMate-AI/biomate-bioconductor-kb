/**
 * Centralized frontend feature flags for staged rollouts.
 * Defaults are enabled in local/dev unless explicitly set to "false".
 */

export const UX_FEEDBACK_ENABLED = import.meta.env.VITE_ENABLE_UX_FEEDBACK !== "false";
export const UX_FEEDBACK_ADMIN_ENABLED =
  UX_FEEDBACK_ENABLED && import.meta.env.VITE_ENABLE_UX_FEEDBACK_ADMIN !== "false";

/** IND Report module — PAUSED (2026-11-04). Off unless VITE_ENABLE_IND_REPORT === "true".
 *  Every IND entry point keys off this one switch so nothing IND-related renders or calls
 *  /api/ind-report while paused: the sidebar entry, the /ind-report page route, chat's
 *  "Generate IND" handoff chip (ADMET/PBPK runs) and chat's "roll into IND project"
 *  affordance (which otherwise queried /api/ind-report/projects on every completed run).
 *  The backend and proxies are kept so the module can be re-enabled intact. */
export const IND_REPORT_ENABLED = import.meta.env.VITE_ENABLE_IND_REPORT === "true";

