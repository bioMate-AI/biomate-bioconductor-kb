/**
 * Density Map Viewer Component
 * Displays MRC/MAP density map files as orthogonal slices (XY, XZ, YZ planes)
 * with a slice-position slider and adjustable contrast.
 * Pure TypeScript/React — no external dependencies.
 *
 * Accepts a direct `src` URL (works from phase-card inline preview and
 * ChatOutputAttachments alike). Pass `galaxyOutputId` only when consuming a
 * legacy Galaxy output dataset — it constructs the download URL for you.
 */

import React, { useState, useEffect, useRef, useCallback } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Skeleton } from "@/components/ui/skeleton"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { AlertCircle, Download, Layers } from "lucide-react"

interface DensityMapViewerProps {
  /** Direct URL to fetch the binary MRC/MAP file. */
  src: string
  /** Display name shown in the card header. */
  name?: string
  /** File size in bytes (optional — shown as a badge when provided). */
  size?: number
  className?: string
}

interface MrcHeader {
  nx: number
  ny: number
  nz: number
  mode: number
  xlen: number
  ylen: number
  zlen: number
  dataOffset: number
  spacegroup: number
}

type Axis = 'z' | 'x' | 'y'

/** Canvas size to which slices are rendered (larger maps are downsampled) */
const CANVAS_SIZE = 512

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function parseMrcHeader(buf: ArrayBuffer): MrcHeader {
  const view = new DataView(buf)
  const nx = view.getInt32(0, true)
  const ny = view.getInt32(4, true)
  const nz = view.getInt32(8, true)
  const mode = view.getInt32(12, true)
  const xlen = view.getFloat32(96, true)
  const ylen = view.getFloat32(100, true)
  const zlen = view.getFloat32(104, true)
  // spacegroup: 0 = 2D images/stack, 1 = single 3D map, >1 = crystallographic
  const spacegroup = view.getInt32(88, true)
  const nsymbt = view.getInt32(196, true)
  const dataOffset = 1024 + nsymbt
  return { nx, ny, nz, mode, xlen, ylen, zlen, dataOffset, spacegroup }
}

/** A 2D image stack (class averages, particle stack) has spacegroup=0 and nz>1 */
function isImageStack(h: MrcHeader): boolean {
  return h.spacegroup === 0 && h.nz > 1
}

/**
 * Extract a 2D slice from the MRC data buffer.
 * Returns a Float32Array of `width * height` values normalised to [0, 1].
 */
function getSlice(
  buf: ArrayBuffer,
  header: MrcHeader,
  axis: Axis,
  index: number,
): { data: Float32Array; width: number; height: number } {
  const { nx, ny, nz, mode, dataOffset } = header
  const view = new DataView(buf)

  const readValue = (flatIdx: number): number => {
    if (mode === 2) {
      const byteOffset = dataOffset + flatIdx * 4
      if (byteOffset + 4 > buf.byteLength) return 0
      return view.getFloat32(byteOffset, true)
    } else if (mode === 1) {
      const byteOffset = dataOffset + flatIdx * 2
      if (byteOffset + 2 > buf.byteLength) return 0
      return view.getInt16(byteOffset, true)
    } else if (mode === 0) {
      const byteOffset = dataOffset + flatIdx
      if (byteOffset + 1 > buf.byteLength) return 0
      return view.getInt8(byteOffset)
    } else if (mode === 6) {
      const byteOffset = dataOffset + flatIdx * 2
      if (byteOffset + 2 > buf.byteLength) return 0
      return view.getUint16(byteOffset, true)
    }
    return 0
  }

  let width: number
  let height: number
  const raw: number[] = []

  if (axis === 'z') {
    const z = Math.max(0, Math.min(index, nz - 1))
    width = nx; height = ny
    for (let y = 0; y < ny; y++)
      for (let x = 0; x < nx; x++)
        raw.push(readValue(z * ny * nx + y * nx + x))
  } else if (axis === 'x') {
    const x = Math.max(0, Math.min(index, nx - 1))
    width = nz; height = ny
    for (let y = 0; y < ny; y++)
      for (let z = 0; z < nz; z++)
        raw.push(readValue(z * ny * nx + y * nx + x))
  } else {
    const y = Math.max(0, Math.min(index, ny - 1))
    width = nx; height = nz
    for (let z = 0; z < nz; z++)
      for (let x = 0; x < nx; x++)
        raw.push(readValue(z * ny * nx + y * nx + x))
  }

  let minVal = Infinity; let maxVal = -Infinity
  for (const v of raw) { if (v < minVal) minVal = v; if (v > maxVal) maxVal = v }
  const range = maxVal - minVal || 1
  const out = new Float32Array(raw.length)
  for (let i = 0; i < raw.length; i++) out[i] = (raw[i] - minVal) / range

  return { data: out, width, height }
}

/** Draw a float32 slice (values 0..1) to a 2D canvas, with contrast adjustment. */
function drawSliceToCanvas(
  canvas: HTMLCanvasElement,
  sliceData: Float32Array,
  srcWidth: number,
  srcHeight: number,
  contrast: number,
): void {
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  const offscreen = document.createElement('canvas')
  offscreen.width = srcWidth; offscreen.height = srcHeight
  const offCtx = offscreen.getContext('2d')
  if (!offCtx) return
  const imageData = offCtx.createImageData(srcWidth, srcHeight)
  const pixels = imageData.data
  const gamma = 1 / Math.max(contrast, 0.1)
  for (let i = 0; i < sliceData.length; i++) {
    const v = Math.min(1, Math.max(0, sliceData[i]))
    const bright = Math.round(Math.pow(v, gamma) * 255)
    const px = i * 4
    pixels[px] = bright; pixels[px + 1] = bright; pixels[px + 2] = bright; pixels[px + 3] = 255
  }
  offCtx.putImageData(imageData, 0, 0)
  ctx.clearRect(0, 0, canvas.width, canvas.height)
  ctx.drawImage(offscreen, 0, 0, canvas.width, canvas.height)
}

/** Render one MRC slice (by Z index) to an offscreen canvas and return a data URL */
function renderSliceToDataUrl(buf: ArrayBuffer, header: MrcHeader, z: number, thumbSize: number, contrast: number): string {
  const { data, width, height } = getSlice(buf, header, 'z', z)
  const offscreen = document.createElement('canvas')
  offscreen.width = thumbSize; offscreen.height = thumbSize
  drawSliceToCanvas(offscreen, data, width, height, contrast)
  return offscreen.toDataURL()
}

/** Montage grid for 2D class averages / particle stacks */
function MontageViewer({ arrayBuffer, header, name, contrast }: {
  arrayBuffer: ArrayBuffer; header: MrcHeader; name?: string; contrast: number
}) {
  const [selected, setSelected] = useState<number | null>(null)
  const THUMB = 96  // thumbnail size in pixels

  const thumbs = React.useMemo(() => {
    const out: string[] = []
    for (let z = 0; z < header.nz; z++) {
      out.push(renderSliceToDataUrl(arrayBuffer, header, z, THUMB, contrast))
    }
    return out
  }, [arrayBuffer, header, contrast])

  return (
    <div>
      <div className="text-xs text-muted-foreground mb-2 px-1">
        {header.nz} classes · {header.nx}×{header.ny} px · click to enlarge
      </div>
      {selected !== null && (
        <div className="mb-3 flex flex-col items-center gap-1">
          <img
            src={renderSliceToDataUrl(arrayBuffer, header, selected, 320, contrast)}
            alt={`Class ${selected + 1}`}
            className="border rounded"
            style={{ imageRendering: 'pixelated', width: 320, height: 320 }}
          />
          <span className="text-xs text-muted-foreground">Class {selected + 1}</span>
          <button className="text-xs underline text-blue-500" onClick={() => setSelected(null)}>← back to grid</button>
        </div>
      )}
      {selected === null && (
        <div style={{ display: 'grid', gridTemplateColumns: `repeat(auto-fill, ${THUMB}px)`, gap: 4, maxHeight: 480, overflowY: 'auto' }}>
          {thumbs.map((src, i) => (
            <div key={i} className="relative cursor-pointer group" onClick={() => setSelected(i)}>
              <img
                src={src}
                alt={`Class ${i + 1}`}
                style={{ width: THUMB, height: THUMB, imageRendering: 'pixelated', display: 'block' }}
                className="border border-muted group-hover:border-blue-400"
              />
              <span className="absolute bottom-0 left-0 text-[9px] bg-black/50 text-white px-0.5">{i + 1}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

export function DensityMapViewer({ src, name, size, className }: DensityMapViewerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [arrayBuffer, setArrayBuffer] = useState<ArrayBuffer | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [header, setHeader] = useState<MrcHeader | null>(null)
  const [activeAxis, setActiveAxis] = useState<Axis>('z')
  const [sliceZ, setSliceZ] = useState(0)
  const [sliceX, setSliceX] = useState(0)
  const [sliceY, setSliceY] = useState(0)
  const [contrast, setContrast] = useState(2)

  useEffect(() => {
    let cancelled = false
    setLoading(true); setError(null); setArrayBuffer(null); setHeader(null)
    fetch(src)
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.arrayBuffer()
      })
      .then(buf => {
        if (cancelled) return
        const h = parseMrcHeader(buf)
        setHeader(h)
        setSliceZ(Math.floor(h.nz / 2))
        setSliceX(Math.floor(h.nx / 2))
        setSliceY(Math.floor(h.ny / 2))
        setArrayBuffer(buf)
        setLoading(false)
      })
      .catch(err => {
        if (cancelled) return
        setError(`Failed to load density map: ${(err as Error).message}`)
        setLoading(false)
      })
    return () => { cancelled = true }
  }, [src])

  const renderSlice = useCallback(() => {
    if (!arrayBuffer || !header || !canvasRef.current) return
    const index = activeAxis === 'z' ? sliceZ : activeAxis === 'x' ? sliceX : sliceY
    const { data, width, height } = getSlice(arrayBuffer, header, activeAxis, index)
    drawSliceToCanvas(canvasRef.current, data, width, height, contrast)
  }, [arrayBuffer, header, activeAxis, sliceZ, sliceX, sliceY, contrast])

  useEffect(() => { renderSlice() }, [renderSlice])

  const currentIndex = activeAxis === 'z' ? sliceZ : activeAxis === 'x' ? sliceX : sliceY
  const totalSlices = header
    ? activeAxis === 'z' ? header.nz : activeAxis === 'x' ? header.nx : header.ny
    : 1

  const voxelSizeX = header && header.nx > 0 ? (header.xlen / header.nx).toFixed(2) : '—'
  const voxelSizeY = header && header.ny > 0 ? (header.ylen / header.ny).toFixed(2) : '—'
  const voxelSizeZ = header && header.nz > 0 ? (header.zlen / header.nz).toFixed(2) : '—'
  const axisLabels: Record<Axis, string> = { z: 'XY', x: 'YZ', y: 'XZ' }

  return (
    <Card className={className} data-testid="density-map-viewer">
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Layers className="h-5 w-5" />
              {name ?? 'Density Map'}
            </CardTitle>
            <CardDescription className="flex flex-wrap items-center gap-2 mt-1">
              {header && (
                <Badge variant="outline" className="text-xs">
                  {header.nx}×{header.ny}×{header.nz} voxels
                </Badge>
              )}
              {header && (
                <Badge variant="outline" className="text-xs">
                  {voxelSizeX}×{voxelSizeY}×{voxelSizeZ} Å/vox
                </Badge>
              )}
              {size != null && (
                <span className="text-xs text-muted-foreground">{formatBytes(size)}</span>
              )}
            </CardDescription>
          </div>
          <Button variant="outline" size="sm" onClick={() => window.open(src, '_blank')}>
            <Download className="h-4 w-4 mr-1" />
            Download
          </Button>
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {loading && (
          <div className="space-y-3">
            <Skeleton className="h-8 w-48" />
            <Skeleton className="h-[320px] w-full rounded" />
          </div>
        )}
        {error && (
          <div className="flex items-center gap-2 text-destructive text-sm">
            <AlertCircle className="h-5 w-5 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}
        {!loading && !error && header && isImageStack(header) && arrayBuffer && (
          <MontageViewer arrayBuffer={arrayBuffer} header={header} name={name} contrast={contrast} />
        )}
        {!loading && !error && header && !isImageStack(header) && (
          <>
            <Tabs value={activeAxis} onValueChange={(v) => setActiveAxis(v as Axis)}>
              <TabsList>
                <TabsTrigger value="z">XY plane</TabsTrigger>
                <TabsTrigger value="y">XZ plane</TabsTrigger>
                <TabsTrigger value="x">YZ plane</TabsTrigger>
              </TabsList>
            </Tabs>

            <div className="rounded border bg-black flex items-center justify-center overflow-hidden" style={{ height: `${CANVAS_SIZE}px` }}>
              <canvas
                ref={canvasRef}
                width={CANVAS_SIZE}
                height={CANVAS_SIZE}
                className="block"
                style={{ imageRendering: 'pixelated' }}
              />
            </div>

            <div className="space-y-1">
              <div className="flex items-center justify-between text-xs text-muted-foreground">
                <span>{axisLabels[activeAxis]} slice</span>
                <span>{currentIndex + 1} / {totalSlices}</span>
              </div>
              <input
                type="range" min={0} max={totalSlices - 1} value={currentIndex}
                onChange={(e) => {
                  const v = Number(e.target.value)
                  if (activeAxis === 'z') setSliceZ(v)
                  else if (activeAxis === 'x') setSliceX(v)
                  else setSliceY(v)
                }}
                className="w-full h-2 accent-primary cursor-pointer"
              />
            </div>

            <div className="space-y-1">
              <div className="flex items-center justify-between text-xs text-muted-foreground">
                <span>Contrast</span>
                <span>{contrast.toFixed(1)}×</span>
              </div>
              <input
                type="range" min={0.5} max={5} step={0.1} value={contrast}
                onChange={(e) => setContrast(Number(e.target.value))}
                className="w-full h-2 accent-primary cursor-pointer"
              />
            </div>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <div className="p-3 rounded-lg bg-muted/50">
                <p className="text-xs text-muted-foreground">Dimensions</p>
                <p className="text-sm font-semibold">{header.nx}×{header.ny}×{header.nz}</p>
              </div>
              <div className="p-3 rounded-lg bg-muted/50">
                <p className="text-xs text-muted-foreground">Voxel X</p>
                <p className="text-sm font-semibold">{voxelSizeX} Å</p>
              </div>
              <div className="p-3 rounded-lg bg-muted/50">
                <p className="text-xs text-muted-foreground">Voxel Y</p>
                <p className="text-sm font-semibold">{voxelSizeY} Å</p>
              </div>
              <div className="p-3 rounded-lg bg-muted/50">
                <p className="text-xs text-muted-foreground">Voxel Z</p>
                <p className="text-sm font-semibold">{voxelSizeZ} Å</p>
              </div>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}
