import { useCallback, useEffect, useRef, useState } from "react"
import { tOr } from "@/lib/i18n"

/** Width of the Data page file tree, in px — user-resizable and remembered (founder: the fixed
 *  280 px column truncated file names). Applied as the CSS var --data-hub-tree-w, which only the
 *  two-pane (wide) layout uses; stacked layouts ignore it. */
const KEY = "biomate.dataHub.treeWidth"
export const TREE_MIN_PX = 220
export const TREE_MAX_PX = 640
const DEFAULT_PX = 280

export function clampTreeWidth(px: number): number {
  if (!Number.isFinite(px)) return DEFAULT_PX
  return Math.round(Math.min(TREE_MAX_PX, Math.max(TREE_MIN_PX, px)))
}

export function useTreeWidth(): [number, (px: number) => void] {
  const [w, setW] = useState<number>(() => {
    try {
      const v = Number(localStorage.getItem(KEY))
      return Number.isFinite(v) && v > 0 ? clampTreeWidth(v) : DEFAULT_PX
    } catch { return DEFAULT_PX }
  })
  const set = useCallback((px: number) => {
    const c = clampTreeWidth(px)
    setW(c)
    try { localStorage.setItem(KEY, String(c)) } catch { /* private mode */ }
  }, [])
  return [w, set]
}

/** Vertical drag handle on the tree pane's right edge (pointer drag + Arrow keys). */
export function PaneResizeHandle({ width, onWidth }: { width: number; onWidth: (px: number) => void }) {
  const start = useRef<{ x: number; w: number } | null>(null)
  const [dragging, setDragging] = useState(false)
  useEffect(() => {
    if (!dragging) return
    const move = (e: PointerEvent) => {
      if (start.current && Number.isFinite(e.clientX)) onWidth(start.current.w + (e.clientX - start.current.x))
    }
    const up = () => { start.current = null; setDragging(false) }
    window.addEventListener("pointermove", move)
    window.addEventListener("pointerup", up)
    return () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up) }
  }, [dragging, onWidth])
  return (
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label={tOr("data_hub.resize_tree", "Resize the file list")}
      aria-valuemin={TREE_MIN_PX}
      aria-valuemax={TREE_MAX_PX}
      aria-valuenow={width}
      tabIndex={0}
      data-testid="data-hub-resize-handle"
      className={"data-hub-resize-handle" + (dragging ? " is-dragging" : "")}
      onPointerDown={(e) => { e.preventDefault(); start.current = { x: e.clientX, w: width }; setDragging(true) }}
      onKeyDown={(e) => {
        if (e.key === "ArrowLeft") { e.preventDefault(); onWidth(width - 16) }
        if (e.key === "ArrowRight") { e.preventDefault(); onWidth(width + 16) }
      }}
      onDoubleClick={() => onWidth(DEFAULT_PX)}
    />
  )
}
