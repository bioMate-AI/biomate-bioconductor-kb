/**
 * Structure Viewer Component
 * Displays PDB and mmCIF molecular structure files using 3Dmol.js (npm package)
 * Supports ribbon/cartoon view, colour by chain, colour by spectrum (B-factor/pLDDT)
 */

import { useState, useEffect, useRef } from "react"
import * as $3Dmol from "3dmol"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Skeleton } from "@/components/ui/skeleton"
import { AlertCircle, Download, Box } from "lucide-react"
import type { OutputDataset } from "@shared/schema"

interface ThreeDMolViewer {
  addModel: (data: string, format: string) => void
  setStyle: (sel: object, style: object) => void
  addSurface?: (type: number, style: object) => void
  zoomTo: () => void
  render: () => void
  resize: () => void
  zoom: (factor: number) => void
  rotate: (angle: number, axis: string) => void
  clear: () => void
}

type StyleMode = 'cartoon' | 'stick' | 'sphere' | 'line'
type ColorScheme = 'spectrum' | 'chain' | 'residue' | 'white'

interface StructureViewerProps {
  output: OutputDataset
  className?: string
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export function StructureViewer({ output, className }: StructureViewerProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const viewerRef = useRef<ThreeDMolViewer | null>(null)

  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [style, setStyle] = useState<StyleMode>('cartoon')
  const [colorScheme, setColorScheme] = useState<ColorScheme>('spectrum')

  const ext = output.extension?.toLowerCase() ?? ''
  const format = ext === 'cif' || ext === 'mmcif' ? 'cif' : 'pdb'
  const formatLabel = format === 'cif' ? 'mmCIF' : 'PDB'

  // Fetch structure data and initialise viewer
  useEffect(() => {
    if (!containerRef.current) return

    let cancelled = false
    setLoading(true)
    setError(null)

    // Destroy any previous viewer so re-renders start clean
    if (viewerRef.current) {
      try { viewerRef.current.clear() } catch (_) { /* ignore */ }
      viewerRef.current = null
    }
    // Clear the container's DOM children
    if (containerRef.current) {
      containerRef.current.innerHTML = ''
    }

    fetch(`/api/outputs/${output.id}/display`)
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.text()
      })
      .then(data => {
        if (cancelled || !containerRef.current) return

        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const viewer = ($3Dmol as any).createViewer(containerRef.current, {
          backgroundColor: 'white',
          antialias: true,
        })
        viewerRef.current = viewer
        viewer.addModel(data, format)
        applyStyle(viewer, style, colorScheme)
        viewer.zoomTo()
        viewer.render()
        setLoading(false)
      })
      .catch(err => {
        if (cancelled) return
        setError(`Failed to load structure: ${(err as Error).message}`)
        setLoading(false)
      })

    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [output.id])

  // Step 3: Re-apply style/colour whenever controls change (no reload required)
  useEffect(() => {
    if (!viewerRef.current) return
    applyStyle(viewerRef.current, style, colorScheme)
    viewerRef.current.render()
  }, [style, colorScheme])

  return (
    <Card className={className}>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Box className="h-5 w-5" />
              {output.name}
            </CardTitle>
            <CardDescription className="flex items-center gap-2 mt-1">
              <Badge variant="outline" className="text-xs">{formatLabel}</Badge>
              {output.size != null && (
                <span className="text-xs text-muted-foreground">{formatBytes(output.size)}</span>
              )}
            </CardDescription>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={() => window.open(`/api/outputs/${output.id}/download`, '_blank')}
          >
            <Download className="h-4 w-4 mr-1" />
            Download
          </Button>
        </div>
      </CardHeader>

      <CardContent className="space-y-3">
        {/* Controls */}
        <div className="flex flex-wrap gap-3">
          {/* Style selector */}
          <div className="flex items-center gap-1">
            <span className="text-xs text-muted-foreground mr-1">Style:</span>
            {(['cartoon', 'stick', 'sphere', 'line'] as StyleMode[]).map(s => (
              <Button
                key={s}
                variant={style === s ? 'default' : 'outline'}
                size="sm"
                className="h-7 text-xs px-2"
                onClick={() => setStyle(s)}
              >
                {s.charAt(0).toUpperCase() + s.slice(1)}
              </Button>
            ))}
          </div>

          {/* Color scheme selector */}
          <div className="flex items-center gap-1">
            <span className="text-xs text-muted-foreground mr-1">Color:</span>
            {([
              ['spectrum', 'Spectrum'],
              ['chain', 'By Chain'],
              ['residue', 'By Residue'],
              ['white', 'White'],
            ] as [ColorScheme, string][]).map(([scheme, label]) => (
              <Button
                key={scheme}
                variant={colorScheme === scheme ? 'default' : 'outline'}
                size="sm"
                className="h-7 text-xs px-2"
                onClick={() => setColorScheme(scheme)}
              >
                {label}
              </Button>
            ))}
          </div>
        </div>

        {/* Viewer container */}
        <div className="relative w-full rounded border bg-white" style={{ height: '400px' }}>
          {loading && (
            <div className="absolute inset-0 flex flex-col gap-3 items-center justify-center bg-white rounded z-10">
              <Skeleton className="h-48 w-full rounded" />
              <p className="text-xs text-muted-foreground">Loading structure…</p>
            </div>
          )}
          {error && (
            <div className="absolute inset-0 flex items-center justify-center z-10">
              <div className="flex items-center gap-2 text-destructive text-sm">
                <AlertCircle className="h-5 w-5 flex-shrink-0" />
                <span>{error}</span>
              </div>
            </div>
          )}
          <div
            ref={containerRef}
            className="w-full h-full"
            style={{ visibility: loading || error ? 'hidden' : 'visible' }}
          />
        </div>

        <p className="text-xs text-muted-foreground">
          Drag to rotate · Scroll to zoom · Right-click drag to translate
        </p>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function applyStyle(viewer: ThreeDMolViewer, style: StyleMode, colorScheme: ColorScheme): void {
  const colorSpec = buildColorSpec(colorScheme)

  if (style === 'cartoon') {
    viewer.setStyle({}, { cartoon: colorSpec })
  } else if (style === 'stick') {
    viewer.setStyle({}, { stick: colorSpec })
  } else if (style === 'sphere') {
    viewer.setStyle({}, { sphere: colorSpec })
  } else {
    // 'line'
    viewer.setStyle({}, { line: colorSpec })
  }
}

function buildColorSpec(colorScheme: ColorScheme): Record<string, unknown> {
  switch (colorScheme) {
    case 'spectrum':
      return { colorscheme: 'spectrum' }
    case 'chain':
      return { colorscheme: 'chain' }
    case 'residue':
      return { colorscheme: 'amino' }
    case 'white':
      return { color: 'white' }
  }
}
