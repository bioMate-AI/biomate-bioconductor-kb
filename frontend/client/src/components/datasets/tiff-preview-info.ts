/**
 * What a TIFF preview PNG shows — the server's `X-Preview-Info` header (JSON, written by
 * backend galaxy/ai/tiff_preview.py and passed through GET /api/projects/:id/files/:fileId/preview.png)
 * — and the one-line caption the dataset panel prints under the picture, e.g.
 * "first of 3 pages · 16-bit, contrast stretched · 512 × 512 px".
 */
import { t } from "@/lib/i18n"

export interface TiffPreviewInfo {
  seriesCount?: number
  series?: number
  planeCount?: number
  plane?: number
  shape?: number[]
  axes?: string
  dtype?: string
  channels?: number
  channelsShown?: number
  level?: number
  levelCount?: number
  /** Size of the PNG drawn (≤ 1024 on the long side). */
  width?: number
  height?: number
  stretch?: { percentiles?: number[]; low?: (number | null)[]; high?: (number | null)[] } | null
  constant?: boolean
  notes?: string[]
}

/** Formats the preview is drawn for (the profiler's format ext). */
export const TIFF_FORMATS = new Set(["tiff", "tif", "ome.tiff", "ome.tif", "btf", "tf8", "bigtiff"])
/** Names that are TIFF (used only while no profiler format is known). */
export const TIFF_NAME = /\.(tiff?|btf|tf8)$/i

export function isTiff(name: string, format?: string): boolean {
  return format ? TIFF_FORMATS.has(format.toLowerCase()) : TIFF_NAME.test(name)
}

/** The parsed header, or null when absent / not an object. */
export function parseTiffPreviewInfo(header: string | null): TiffPreviewInfo | null {
  if (!header) return null
  try {
    const v = JSON.parse(header)
    return v && typeof v === "object" && !Array.isArray(v) ? (v as TiffPreviewInfo) : null
  } catch {
    return null
  }
}

const int = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) ? v : null)

function dtypeLabel(dtype: string | undefined): string | null {
  const m = /^(u?int|float|complex)(\d+)$/.exec(dtype ?? "")
  if (dtype === "bool") return t("dataset_obj.preview_tiff_binary")
  if (!m) return null
  const [, base, bits] = m
  if (base === "uint") return t("dataset_obj.preview_tiff_bits", { bits })
  if (base === "int") return t("dataset_obj.preview_tiff_bits_signed", { bits })
  return t("dataset_obj.preview_tiff_bits_float", { bits: base === "complex" ? String(Number(bits) / 2) : bits })
}

/** The caption under a TIFF preview: which page / series / channel is drawn, the stored bit depth
 *  and whether contrast was stretched, the original size, and the pyramid level when one was used. */
export function tiffCaption(info: TiffPreviewInfo | null): string {
  if (!info) return ""
  const parts: string[] = []
  const planes = int(info.planeCount), plane = int(info.plane) ?? 0
  if (planes && planes > 1) {
    parts.push(plane === 0 ? t("dataset_obj.preview_tiff_first_page", { n: planes })
      : t("dataset_obj.preview_tiff_page", { k: plane + 1, n: planes }))
  }
  const sc = int(info.seriesCount)
  if (sc && sc > 1) parts.push(t("dataset_obj.preview_tiff_series", { k: (int(info.series) ?? 0) + 1, n: sc }))
  const ch = int(info.channels)
  if (ch && ch > 3 && int(info.channelsShown) === 1) parts.push(t("dataset_obj.preview_tiff_channel_first", { n: ch }))
  const depth = [dtypeLabel(info.dtype), info.stretch ? t("dataset_obj.preview_tiff_stretched") : null,
    info.constant ? t("dataset_obj.preview_tiff_constant") : null].filter(Boolean).join(", ")
  if (depth) parts.push(depth)
  const shape = Array.isArray(info.shape) ? info.shape : []
  const axes = typeof info.axes === "string" ? info.axes : ""
  const y = shape[axes.indexOf("Y")], x = shape[axes.indexOf("X")]
  if (axes.includes("Y") && axes.includes("X") && int(x) && int(y)) parts.push(t("dataset_obj.preview_tiff_size", { w: x, h: y }))
  const lc = int(info.levelCount), lv = int(info.level)
  if (lc && lc > 1 && lv) parts.push(t("dataset_obj.preview_tiff_pyramid", { k: lv + 1, n: lc }))
  return parts.join(" · ")
}
