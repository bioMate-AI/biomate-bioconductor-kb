/**
 * Annotation Viewer Component
 * Displays BED, GFF, and GTF genomic annotation files with filtering and statistics
 */

import { useState, useMemo } from "react"
import { useQuery } from "@tanstack/react-query"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Skeleton } from "@/components/ui/skeleton"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import {
  Download,
  Filter,
  Search,
  AlertCircle,
  MapPin,
  ArrowUpDown,
  Layers,
} from "lucide-react"
import type { OutputDataset } from "@shared/schema"

interface AnnotationViewerProps {
  output: OutputDataset
  className?: string
}

interface AnnotationFeature {
  chrom: string
  start: number
  end: number
  name: string
  score?: number
  strand?: '+' | '-' | '.'
  featureType?: string // For GFF/GTF: gene, exon, CDS, etc.
  source?: string
  attributes?: Record<string, string>
}

interface AnnotationData {
  format: 'bed' | 'gff' | 'gtf'
  features: AnnotationFeature[]
  stats: {
    totalFeatures: number
    chromosomes: string[]
    featureTypes: { type: string; count: number }[]
    avgLength: number
    totalBases: number
    plusStrand: number
    minusStrand: number
  }
}

export function AnnotationViewer({ output, className }: AnnotationViewerProps) {
  const [searchTerm, setSearchTerm] = useState("")
  const [filterChrom, setFilterChrom] = useState<string>("all")
  const [filterType, setFilterType] = useState<string>("all")
  const [filterStrand, setFilterStrand] = useState<string>("all")
  const [sortField, setSortField] = useState<"start" | "length">("start")
  const [sortAsc, setSortAsc] = useState(true)

  const format = output.extension.toLowerCase().replace('.', '')

  const { data, isLoading, error } = useQuery<AnnotationData>({
    queryKey: ['annotation', output.id],
    queryFn: async () => {
      const response = await fetch(`/api/outputs/${output.id}/parse?format=${format}&limit=1000`)
      if (!response.ok) throw new Error('Failed to parse annotation file')
      return response.json()
    },
  })

  // Filter and sort features
  const filteredFeatures = useMemo(() => {
    if (!data?.features) return []

    let result = [...data.features]

    // Apply chromosome filter
    if (filterChrom !== "all") {
      result = result.filter(f => f.chrom === filterChrom)
    }

    // Apply feature type filter (GFF/GTF)
    if (filterType !== "all") {
      result = result.filter(f => f.featureType === filterType)
    }

    // Apply strand filter
    if (filterStrand !== "all") {
      result = result.filter(f => f.strand === filterStrand)
    }

    // Apply search
    if (searchTerm) {
      const term = searchTerm.toLowerCase()
      result = result.filter(f =>
        f.name.toLowerCase().includes(term) ||
        f.chrom.toLowerCase().includes(term) ||
        (f.attributes?.gene_name?.toLowerCase().includes(term)) ||
        (f.attributes?.gene_id?.toLowerCase().includes(term))
      )
    }

    // Sort
    result.sort((a, b) => {
      if (sortField === "start") {
        const chromCompare = a.chrom.localeCompare(b.chrom)
        if (chromCompare !== 0) return sortAsc ? chromCompare : -chromCompare
        return sortAsc ? a.start - b.start : b.start - a.start
      } else {
        const lenA = a.end - a.start
        const lenB = b.end - b.start
        return sortAsc ? lenA - lenB : lenB - lenA
      }
    })

    return result
  }, [data?.features, filterChrom, filterType, filterStrand, searchTerm, sortField, sortAsc])

  const getStrandColor = (strand?: string): string => {
    switch (strand) {
      case '+': return 'text-blue-600'
      case '-': return 'text-red-600'
      default: return 'text-gray-400'
    }
  }

  const getFeatureTypeColor = (type?: string): string => {
    if (!type) return 'bg-gray-100 text-gray-800'
    switch (type.toLowerCase()) {
      case 'gene': return 'bg-blue-100 text-blue-800'
      case 'exon': return 'bg-green-100 text-green-800'
      case 'cds': return 'bg-purple-100 text-purple-800'
      case 'mrna':
      case 'transcript': return 'bg-amber-100 text-amber-800'
      case 'utr':
      case '5utr':
      case '3utr': return 'bg-pink-100 text-pink-800'
      default: return 'bg-gray-100 text-gray-800'
    }
  }

  const formatPosition = (start: number, end: number): string => {
    return `${start.toLocaleString()}-${end.toLocaleString()}`
  }

  const formatLength = (start: number, end: number): string => {
    const len = end - start
    if (len >= 1e6) return `${(len / 1e6).toFixed(2)} Mb`
    if (len >= 1e3) return `${(len / 1e3).toFixed(2)} kb`
    return `${len} bp`
  }

  if (isLoading) {
    return (
      <Card className={className}>
        <CardHeader>
          <Skeleton className="h-6 w-48" />
          <Skeleton className="h-4 w-32" />
        </CardHeader>
        <CardContent>
          <Skeleton className="h-64 w-full" />
        </CardContent>
      </Card>
    )
  }

  if (error) {
    return (
      <Card className={className}>
        <CardContent className="pt-6">
          <div className="flex items-center gap-2 text-destructive">
            <AlertCircle className="h-5 w-5" />
            <span>Failed to load annotation file: {(error as Error).message}</span>
          </div>
        </CardContent>
      </Card>
    )
  }

  if (!data) return null

  return (
    <Card className={className}>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Layers className="h-5 w-5" />
              {output.name}
            </CardTitle>
            <CardDescription>
              {data.format.toUpperCase()} •
              {data.stats.totalFeatures.toLocaleString()} features •
              {data.stats.chromosomes.length} chromosomes
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
      <CardContent className="space-y-4">
        {/* Statistics */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div className="p-3 rounded-lg bg-muted/50">
            <p className="text-xs text-muted-foreground">Features</p>
            <p className="text-lg font-semibold">{data.stats.totalFeatures.toLocaleString()}</p>
          </div>
          <div className="p-3 rounded-lg bg-muted/50">
            <p className="text-xs text-muted-foreground">Avg Length</p>
            <p className="text-lg font-semibold">{data.stats.avgLength.toLocaleString()} bp</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-50">
            <p className="text-xs text-blue-600">+ Strand</p>
            <p className="text-lg font-semibold text-blue-700">{data.stats.plusStrand.toLocaleString()}</p>
          </div>
          <div className="p-3 rounded-lg bg-red-50">
            <p className="text-xs text-red-600">- Strand</p>
            <p className="text-lg font-semibold text-red-700">{data.stats.minusStrand.toLocaleString()}</p>
          </div>
        </div>

        {/* Feature Type Distribution (for GFF/GTF) */}
        {data.stats.featureTypes.length > 0 && (
          <div className="space-y-2">
            <h4 className="text-sm font-medium">Feature Types</h4>
            <div className="flex flex-wrap gap-2">
              {data.stats.featureTypes.slice(0, 10).map(({ type, count }) => (
                <Badge key={type} variant="secondary" className={getFeatureTypeColor(type)}>
                  {type}: {count.toLocaleString()}
                </Badge>
              ))}
            </div>
          </div>
        )}

        {/* Filters */}
        <div className="flex flex-wrap gap-3">
          <div className="flex-1 min-w-[200px]">
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search features..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="pl-9"
              />
            </div>
          </div>
          <Select value={filterChrom} onValueChange={setFilterChrom}>
            <SelectTrigger className="w-[140px]">
              <Filter className="h-4 w-4 mr-2" />
              <SelectValue placeholder="Chromosome" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Chromosomes</SelectItem>
              {data.stats.chromosomes.map(chrom => (
                <SelectItem key={chrom} value={chrom}>{chrom}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          {data.stats.featureTypes.length > 0 && (
            <Select value={filterType} onValueChange={setFilterType}>
              <SelectTrigger className="w-[140px]">
                <SelectValue placeholder="Type" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Types</SelectItem>
                {data.stats.featureTypes.map(({ type }) => (
                  <SelectItem key={type} value={type}>{type}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          <Select value={filterStrand} onValueChange={setFilterStrand}>
            <SelectTrigger className="w-[120px]">
              <SelectValue placeholder="Strand" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Strands</SelectItem>
              <SelectItem value="+">+ Strand</SelectItem>
              <SelectItem value="-">- Strand</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {/* Feature Table */}
        <div className="rounded-lg border">
          <ScrollArea className="h-[400px]">
            <Table>
              <TableHeader className="sticky top-0 bg-background">
                <TableRow>
                  <TableHead className="w-[120px]">
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-8 p-0"
                      onClick={() => {
                        if (sortField === "start") setSortAsc(!sortAsc)
                        else { setSortField("start"); setSortAsc(true) }
                      }}
                    >
                      Location
                      <ArrowUpDown className="ml-1 h-3 w-3" />
                    </Button>
                  </TableHead>
                  <TableHead>Name</TableHead>
                  {(data.format === 'gff' || data.format === 'gtf') && (
                    <TableHead>Type</TableHead>
                  )}
                  <TableHead>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-8 p-0"
                      onClick={() => {
                        if (sortField === "length") setSortAsc(!sortAsc)
                        else { setSortField("length"); setSortAsc(false) }
                      }}
                    >
                      Length
                      <ArrowUpDown className="ml-1 h-3 w-3" />
                    </Button>
                  </TableHead>
                  <TableHead className="w-[60px]">Strand</TableHead>
                  {data.features[0]?.score !== undefined && (
                    <TableHead>Score</TableHead>
                  )}
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredFeatures.slice(0, 500).map((feature, idx) => (
                  <TableRow key={`${feature.chrom}-${feature.start}-${idx}`}>
                    <TableCell className="font-mono text-sm">
                      <div className="flex items-center gap-1">
                        <MapPin className="h-3 w-3 text-muted-foreground" />
                        <span>{feature.chrom}:</span>
                      </div>
                      <span className="text-xs text-muted-foreground">
                        {formatPosition(feature.start, feature.end)}
                      </span>
                    </TableCell>
                    <TableCell>
                      <div>
                        <p className="font-medium text-sm truncate max-w-[200px]">
                          {feature.name || feature.attributes?.gene_name || '-'}
                        </p>
                        {feature.attributes?.gene_id && feature.attributes.gene_id !== feature.name && (
                          <p className="text-xs text-muted-foreground truncate max-w-[200px]">
                            {feature.attributes.gene_id}
                          </p>
                        )}
                      </div>
                    </TableCell>
                    {(data.format === 'gff' || data.format === 'gtf') && (
                      <TableCell>
                        <Badge variant="secondary" className={getFeatureTypeColor(feature.featureType)}>
                          {feature.featureType || '-'}
                        </Badge>
                      </TableCell>
                    )}
                    <TableCell className="text-sm">
                      {formatLength(feature.start, feature.end)}
                    </TableCell>
                    <TableCell className={`text-center font-mono ${getStrandColor(feature.strand)}`}>
                      {feature.strand || '.'}
                    </TableCell>
                    {data.features[0]?.score !== undefined && (
                      <TableCell className="text-sm">
                        {feature.score?.toFixed(2) ?? '-'}
                      </TableCell>
                    )}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </ScrollArea>
        </div>

        {filteredFeatures.length > 500 && (
          <p className="text-xs text-muted-foreground text-center">
            Showing first 500 of {filteredFeatures.length.toLocaleString()} filtered features
          </p>
        )}
      </CardContent>
    </Card>
  )
}
