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

/** Directory connector — requires BIOMATE_CONNECTOR_SCAN_ROOTS (on-prem/self-host only;
 *  the hosted cloud cannot reach a user's paths, so every scan is refused). Hidden by
 *  default so users never see a connector that can't work here; a self-host deployment
 *  turns it on with VITE_ENABLE_CONNECTOR_DIRECTORY=true. */
export const CONNECTOR_DIRECTORY_ENABLED = import.meta.env.VITE_ENABLE_CONNECTOR_DIRECTORY === "true";

/** Instrument connectors — client/deployment-dependent (the watcher + health checks reach
 *  LAN devices or a local output folder, which the hosted cloud cannot). Hidden by default
 *  so users aren't shown a connector that can't work here; a self-host deployment turns it
 *  on with VITE_ENABLE_CONNECTOR_INSTRUMENTS=true. */
export const CONNECTOR_INSTRUMENTS_ENABLED = import.meta.env.VITE_ENABLE_CONNECTOR_INSTRUMENTS === "true";

