/**
 * Centralized frontend feature flags for staged rollouts.
 * Defaults are enabled in local/dev unless explicitly set to "false".
 */

export const UX_FEEDBACK_ENABLED = import.meta.env.VITE_ENABLE_UX_FEEDBACK !== "false";
export const UX_FEEDBACK_ADMIN_ENABLED =
  UX_FEEDBACK_ENABLED && import.meta.env.VITE_ENABLE_UX_FEEDBACK_ADMIN !== "false";
