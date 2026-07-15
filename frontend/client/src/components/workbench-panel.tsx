/**
 * WorkbenchPanel — tab-bar wrapper around pinned step-output files.
 *
 * Stream-A platform. The Workbench is the "pinboard" surface from
 * reference/claude_design/design_handoff_wiki_canvas/Wiki-Canvas-Prototype.html:
 * a left sidebar of pinned files, a tab bar across the main pane, and an
 * optional 2-pane split for side-by-side comparison. Files are pinned via
 * the "Pin to Workbench" button on `step-output-preview.tsx` (any run
 * output file, any file type the existing dispatcher can render).
 *
 * Backend: frontend/server/workbench-routes.ts (commit 0ba50ee96).
 *   GET    /api/projects/:projectId/workbench/pins
 *   POST   /api/projects/:projectId/workbench/pins
 *   DELETE /api/projects/:projectId/workbench/pins/:pinId
 *
 * Route: /projects/:projectId/workbench (registered in App.tsx).
 *
 * Tiles reuse the existing `StepOutputPreview` renderer so every viewer
 * we already support (image, table, PDB, mmCIF, VCF, FASTA, density, …)
 * works in the workbench with no new code.
 */
import { useMemo, useState, useCallback } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { X, Pin, FileText, Columns2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { StepOutputPreview } from "@/components/step-output-preview";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";

export interface WorkbenchPin {
  id: number;
  runId: string;
  filePath: string;
  fileName: string;
  fileSize?: number;
  createdAt?: string;
}

interface WorkbenchPanelProps {
  projectId: string;
  onClose?: () => void;
}

const PALETTE = {
  bg: "#f5efe2",
  surface: "#fffdf7",
  ink: "#1e3a5f",
  inkSoft: "#4a5e7a",
  inkMute: "#8a93a1",
  rule: "#d5cdb8",
  green: "#7fb24a",
};

function inferExtension(fileName: string): string {
  const idx = fileName.lastIndexOf(".");
  if (idx < 0 || idx === fileName.length - 1) return "";
  return fileName.slice(idx + 1).toLowerCase();
}

function PinTile({ pin, onClose }: { pin: WorkbenchPin; onClose: () => void }) {
  const ext = inferExtension(pin.fileName);
  return (
    <div data-testid={`workbench-tile-${pin.id}`} className="h-full overflow-auto p-3">
      <StepOutputPreview
        runId={pin.runId}
        file={{ name: pin.fileName, path: pin.filePath, extension: ext }}
        onClose={onClose}
      />
    </div>
  );
}

export function WorkbenchPanel({ projectId, onClose }: WorkbenchPanelProps) {
  const { toast } = useToast();
  const qc = useQueryClient();

  // Local tab state — independent of server state. Tabs are opened by clicking
  // a sidebar item; the second pane is opened by double-clicking or by the
  // explicit "Split right" affordance.
  const [openTabIds, setOpenTabIds] = useState<number[]>([]);
  const [activeTabId, setActiveTabId] = useState<number | null>(null);
  const [splitPinId, setSplitPinId] = useState<number | null>(null);

  const pinsQueryKey = ["workbench-pins", projectId] as const;
  const pinsQuery = useQuery<{ pins: WorkbenchPin[] }>({
    queryKey: pinsQueryKey,
    queryFn: async () => {
      const res = await fetch(`/api/projects/${projectId}/workbench/pins`, {
        credentials: "include",
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res.json();
    },
    enabled: !!projectId,
  });

  const pins = pinsQuery.data?.pins ?? [];
  const pinsById = useMemo(() => {
    const m = new Map<number, WorkbenchPin>();
    for (const p of pins) m.set(p.id, p);
    return m;
  }, [pins]);

  const unpinMutation = useMutation({
    mutationFn: async (pinId: number) => {
      const res = await fetch(
        `/api/projects/${projectId}/workbench/pins/${pinId}`,
        { method: "DELETE", credentials: "include" },
      );
      if (!res.ok && res.status !== 204) {
        throw new Error(`HTTP ${res.status}`);
      }
      return pinId;
    },
    onSuccess: (pinId: number) => {
      qc.invalidateQueries({ queryKey: pinsQueryKey });
      setOpenTabIds((ids) => ids.filter((id) => id !== pinId));
      setActiveTabId((cur) => (cur === pinId ? null : cur));
      setSplitPinId((cur) => (cur === pinId ? null : cur));
      toast({ title: "Unpinned" });
    },
    onError: (e: any) => {
      toast({
        title: "Unpin failed",
        description: e?.message ?? "Could not remove pin",
        variant: "destructive",
      });
    },
  });

  const openPin = useCallback((pinId: number) => {
    setOpenTabIds((ids) => (ids.includes(pinId) ? ids : [...ids, pinId]));
    setActiveTabId(pinId);
  }, []);

  const splitOpen = useCallback((pinId: number) => {
    setSplitPinId(pinId);
    // Make sure the primary pane has something visible too.
    setActiveTabId((cur) => cur ?? pinId);
    setOpenTabIds((ids) => (ids.includes(pinId) ? ids : [...ids, pinId]));
  }, []);

  const closeTab = useCallback((pinId: number) => {
    setOpenTabIds((ids) => ids.filter((id) => id !== pinId));
    setActiveTabId((cur) => {
      if (cur !== pinId) return cur;
      const remaining = openTabIds.filter((id) => id !== pinId);
      return remaining.length > 0 ? remaining[remaining.length - 1] : null;
    });
    setSplitPinId((cur) => (cur === pinId ? null : cur));
  }, [openTabIds]);

  const activePin = activeTabId != null ? pinsById.get(activeTabId) ?? null : null;
  const splitPin = splitPinId != null ? pinsById.get(splitPinId) ?? null : null;

  return (
    <div
      data-testid="workbench-panel"
      style={{
        minHeight: "100vh",
        background: PALETTE.bg,
        color: PALETTE.ink,
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* Header */}
      <header
        style={{
          padding: "16px 24px",
          borderBottom: `1px solid ${PALETTE.rule}`,
          background: PALETTE.surface,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
        }}
      >
        <div>
          <h1 style={{ fontSize: 20, fontWeight: 700, margin: 0, letterSpacing: "-0.02em" }}>
            Workbench
          </h1>
          <p style={{ margin: "4px 0 0", fontSize: 12, color: PALETTE.inkMute }}>
            Pinned outputs from this project — open as tabs, compare side-by-side.
          </p>
        </div>
        {onClose && (
          <Button variant="ghost" size="sm" onClick={onClose} aria-label="Close workbench">
            <X className="h-4 w-4" />
          </Button>
        )}
      </header>

      {/* Body: sidebar + main */}
      <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
        {/* Sidebar */}
        <aside
          data-testid="workbench-sidebar"
          style={{
            width: 220,
            minWidth: 220,
            borderRight: `1px solid ${PALETTE.rule}`,
            background: PALETTE.surface,
            overflowY: "auto",
          }}
        >
          <div style={{ padding: "12px 14px 6px", fontSize: 11, color: PALETTE.inkMute, textTransform: "uppercase", letterSpacing: "0.06em" }}>
            Pinned files {pins.length > 0 && `(${pins.length})`}
          </div>
          {pinsQuery.isLoading ? (
            <div data-testid="workbench-loading" style={{ padding: 14, fontSize: 12, color: PALETTE.inkMute }}>
              Loading…
            </div>
          ) : pinsQuery.isError ? (
            <div data-testid="workbench-error" style={{ padding: 14, fontSize: 12, color: "#b85a4a" }}>
              Failed to load pins.
            </div>
          ) : pins.length === 0 ? (
            <div data-testid="workbench-empty" style={{ padding: 14, fontSize: 12, color: PALETTE.inkSoft, lineHeight: 1.5 }}>
              No pinned files yet. Use the <strong>“Pin to Workbench”</strong>{" "}
              button on any output file in a run to start.
            </div>
          ) : (
            <ul style={{ listStyle: "none", margin: 0, padding: "4px 0" }}>
              {pins.map((pin) => {
                const ext = inferExtension(pin.fileName);
                const active = activeTabId === pin.id || splitPinId === pin.id;
                return (
                  <li key={pin.id}>
                    <div
                      data-testid={`workbench-pin-${pin.id}`}
                      onClick={() => openPin(pin.id)}
                      onDoubleClick={() => splitOpen(pin.id)}
                      className={cn(
                        "group flex items-center gap-1.5 cursor-pointer transition-colors",
                      )}
                      style={{
                        padding: "8px 14px",
                        background: active ? "#e3efd2" : "transparent",
                        borderLeft: active ? `3px solid ${PALETTE.green}` : "3px solid transparent",
                      }}
                    >
                      <FileText className="h-3.5 w-3.5 shrink-0" style={{ color: PALETTE.inkMute }} />
                      <div style={{ minWidth: 0, flex: 1 }}>
                        <div
                          title={pin.fileName}
                          style={{
                            fontSize: 12,
                            fontWeight: 500,
                            whiteSpace: "nowrap",
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            color: PALETTE.ink,
                          }}
                        >
                          {pin.fileName}
                        </div>
                        {ext && (
                          <div
                            data-testid={`workbench-pin-${pin.id}-ext`}
                            style={{
                              display: "inline-block",
                              marginTop: 2,
                              fontSize: 10,
                              fontFamily: "monospace",
                              color: PALETTE.inkMute,
                              background: PALETTE.bg,
                              padding: "1px 5px",
                              borderRadius: 3,
                            }}
                          >
                            {ext}
                          </div>
                        )}
                      </div>
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          splitOpen(pin.id);
                        }}
                        title="Open in second pane"
                        aria-label="Split right"
                        data-testid={`workbench-pin-${pin.id}-split`}
                        className="opacity-0 group-hover:opacity-100 transition-opacity"
                        style={{ background: "transparent", border: "none", padding: 2, cursor: "pointer", color: PALETTE.inkMute }}
                      >
                        <Columns2 className="h-3.5 w-3.5" />
                      </button>
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          unpinMutation.mutate(pin.id);
                        }}
                        title="Unpin"
                        aria-label="Unpin"
                        data-testid={`workbench-pin-${pin.id}-unpin`}
                        className="opacity-0 group-hover:opacity-100 transition-opacity"
                        style={{ background: "transparent", border: "none", padding: 2, cursor: "pointer", color: PALETTE.inkMute }}
                      >
                        <X className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </aside>

        {/* Main: tab bar + panes */}
        <main style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column" }}>
          {/* Tab bar */}
          <div
            data-testid="workbench-tabbar"
            style={{
              display: "flex",
              alignItems: "center",
              gap: 2,
              padding: "6px 10px",
              borderBottom: `1px solid ${PALETTE.rule}`,
              background: PALETTE.surface,
              minHeight: 38,
              overflowX: "auto",
            }}
          >
            {openTabIds.length === 0 ? (
              <span style={{ fontSize: 12, color: PALETTE.inkMute, padding: "0 8px" }}>
                Click a pinned file to open it as a tab.
              </span>
            ) : (
              openTabIds.map((id) => {
                const pin = pinsById.get(id);
                if (!pin) return null;
                const isActive = id === activeTabId;
                return (
                  <div
                    key={id}
                    data-testid={`workbench-tab-${id}`}
                    onClick={() => setActiveTabId(id)}
                    className={cn("flex items-center gap-1.5 cursor-pointer text-xs")}
                    style={{
                      padding: "6px 10px",
                      borderRadius: "6px 6px 0 0",
                      background: isActive ? PALETTE.bg : "transparent",
                      border: `1px solid ${isActive ? PALETTE.rule : "transparent"}`,
                      borderBottom: "none",
                      color: isActive ? PALETTE.ink : PALETTE.inkSoft,
                      fontWeight: isActive ? 600 : 400,
                    }}
                  >
                    <Pin className="h-3 w-3" />
                    <span style={{ maxWidth: 160, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                      {pin.fileName}
                    </span>
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); closeTab(id); }}
                      aria-label="Close tab"
                      data-testid={`workbench-tab-${id}-close`}
                      style={{ background: "transparent", border: "none", padding: 0, cursor: "pointer", color: PALETTE.inkMute }}
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </div>
                );
              })
            )}
          </div>

          {/* Panes (1 or 2) */}
          <div
            data-testid="workbench-panes"
            style={{ flex: 1, minHeight: 0, display: "flex", background: PALETTE.bg }}
          >
            <div
              data-testid="workbench-pane-primary"
              style={{
                flex: 1,
                minWidth: 0,
                overflow: "hidden",
                borderRight: splitPin ? `1px solid ${PALETTE.rule}` : "none",
                background: PALETTE.surface,
              }}
            >
              {activePin ? (
                <PinTile pin={activePin} onClose={() => closeTab(activePin.id)} />
              ) : (
                <div
                  data-testid="workbench-pane-empty"
                  style={{ padding: 32, fontSize: 13, color: PALETTE.inkMute }}
                >
                  Select a pinned file from the sidebar to view it here.
                </div>
              )}
            </div>
            {splitPin && (
              <div
                data-testid="workbench-pane-split"
                style={{ flex: 1, minWidth: 0, overflow: "hidden", background: PALETTE.surface }}
              >
                <PinTile pin={splitPin} onClose={() => setSplitPinId(null)} />
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  );
}

export default WorkbenchPanel;
