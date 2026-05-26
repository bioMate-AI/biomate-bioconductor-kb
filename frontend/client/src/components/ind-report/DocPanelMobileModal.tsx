/**
 * Mobile doc-panel modal — replaces the `alert("…stub")` FAB click on narrow
 * viewports (≤1024px) per ind-report.css media query.
 *
 * Wraps any children with a full-screen overlay and a close button. The page
 * mounts this with the existing IndDocPanel inside, so the same doc state
 * displays in both the desktop right panel and the mobile modal — no
 * duplicate rendering logic needed.
 */
import { ReactNode } from "react";
import { X } from "lucide-react";

export function DocPanelMobileModal({
  open,
  onClose,
  children,
}: {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
}) {
  if (!open) return null;
  return (
    <div
      className="ind-doc-mobile-overlay"
      style={{
        position: "fixed", inset: 0, zIndex: 70,
        background: "rgba(15, 23, 42, 0.55)",
        display: "flex", alignItems: "stretch", justifyContent: "stretch",
      }}
      onClick={onClose}
      role="dialog"
      aria-label="IND document panel"
      data-testid="ind-doc-mobile-modal"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          position: "relative",
          width: "100%", height: "100%",
          background: "white",
          overflowY: "auto",
          display: "flex", flexDirection: "column",
        }}
      >
        <button
          onClick={onClose}
          aria-label="Close document panel"
          style={{
            position: "sticky", top: 8, alignSelf: "flex-end",
            margin: "8px 12px", padding: "6px 10px",
            background: "var(--ind-bg-sub, #f5f5f5)", border: "1px solid var(--ind-border, #e5e7eb)",
            borderRadius: 6, cursor: "pointer", zIndex: 1,
            display: "flex", alignItems: "center", gap: 6, fontSize: 12,
          }}
        >
          <X size={14} /> Close
        </button>
        <div style={{ flex: 1, overflowY: "auto" }}>{children}</div>
      </div>
    </div>
  );
}
