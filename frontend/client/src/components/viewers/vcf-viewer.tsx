/**
 * VCF Viewer Component
 * Displays variant call format (VCF) files with filtering and statistics
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
  CheckCircle,
  Dna,
  ArrowUpDown,
} from "lucide-react"
import type { OutputDataset } from "@shared/schema"

interface VCFViewerProps {
  output: OutputDataset
  className?: string
}

interface VCFVariant {
  chrom: string
  pos: number
  id: string
  ref: string
  alt: string
  qual: number | null
  filter: string
  info: Record<string, string>
  genotypes?: string[]
}

interface VCFData {
  header: {
    fileFormat: string
    samples: string[]
    contigs: string[]
    infoFields: { id: string; description: string }[]
  }
  variants: VCFVariant[]
  stats: {
    totalVariants: number
    snps: number
    indels: number
    multiallelic: number
    passedFilter: number
  }
}

export function VCFViewer({ output, className }: VCFViewerProps) {
  const [searchTerm, setSearchTerm] = useState("")
  const [filterChrom, setFilterChrom] = useState<string>("all")
  const [filterQuality, setFilterQuality] = useState<string>("all")
  const [sortField, setSortField] = useState<"pos" | "qual">("pos")
  const [sortAsc, setSortAsc] = useState(true)

  const { data, isLoading, error } = useQuery<VCFData>({
    queryKey: ['vcf', output.id],
    queryFn: async () => {
      const response = await fetch(`/api/outputs/${output.id}/parse?format=vcf&limit=1000`)
      if (!response.ok) throw new Error('Failed to parse VCF file')
      return response.json()
    },
  })

  // Get unique chromosomes for filtering
  const chromosomes = useMemo(() => {
    if (!data?.variants) return []
    return [...new Set(data.variants.map(v => v.chrom))].sort((a, b) => {
      // Natural sort for chromosomes
      const numA = parseInt(a.replace(/\D/g, ''))
      const numB = parseInt(b.replace(/\D/g, ''))
      if (!isNaN(numA) && !isNaN(numB)) return numA - numB
      return a.localeCompare(b)
    })
  }, [data?.variants])

  // Filter and sort variants
  const filteredVariants = useMemo(() => {
    if (!data?.variants) return []

    let result = [...data.variants]

    // Apply chromosome filter
    if (filterChrom !== "all") {
      result = result.filter(v => v.chrom === filterChrom)
    }

    // Apply quality filter
    if (filterQuality === "pass") {
      result = result.filter(v => v.filter === "PASS" || v.filter === ".")
    } else if (filterQuality === "high") {
      result = result.filter(v => v.qual !== null && v.qual >= 30)
    }

    // Apply search
    if (searchTerm) {
      const term = searchTerm.toLowerCase()
      result = result.filter(v =>
        v.chrom.toLowerCase().includes(term) ||
        v.id.toLowerCase().includes(term) ||
        v.ref.toLowerCase().includes(term) ||
        v.alt.toLowerCase().includes(term) ||
        v.pos.toString().includes(term)
      )
    }

    // Sort
    result.sort((a, b) => {
      if (sortField === "pos") {
        const chromCompare = a.chrom.localeCompare(b.chrom)
        if (chromCompare !== 0) return sortAsc ? chromCompare : -chromCompare
        return sortAsc ? a.pos - b.pos : b.pos - a.pos
      } else {
        const qualA = a.qual ?? -1
        const qualB = b.qual ?? -1
        return sortAsc ? qualA - qualB : qualB - qualA
      }
    })

    return result
  }, [data?.variants, filterChrom, filterQuality, searchTerm, sortField, sortAsc])

  const getVariantType = (ref: string, alt: string): string => {
    if (ref.length === 1 && alt.length === 1) return "SNP"
    if (ref.length > alt.length) return "DEL"
    if (ref.length < alt.length) return "INS"
    return "MNP"
  }

  const getVariantTypeColor = (type: string): string => {
    switch (type) {
      case "SNP": return "bg-blue-100 text-blue-800"
      case "DEL": return "bg-red-100 text-red-800"
      case "INS": return "bg-green-100 text-green-800"
      default: return "bg-gray-100 text-gray-800"
    }
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
            <span>Failed to load VCF file: {(error as Error).message}</span>
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
              <Dna className="h-5 w-5" />
              {output.name}
            </CardTitle>
            <CardDescription>
              {data.stats.totalVariants.toLocaleString()} variants •
              {data.header.samples.length > 0 && ` ${data.header.samples.length} samples •`}
              {data.header.fileFormat}
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
        <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
          <div className="p-3 rounded-lg bg-muted/50">
            <p className="text-xs text-muted-foreground">Total</p>
            <p className="text-lg font-semibold">{data.stats.totalVariants.toLocaleString()}</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-50">
            <p className="text-xs text-blue-600">SNPs</p>
            <p className="text-lg font-semibold text-blue-700">{data.stats.snps.toLocaleString()}</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-50">
            <p className="text-xs text-amber-600">Indels</p>
            <p className="text-lg font-semibold text-amber-700">{data.stats.indels.toLocaleString()}</p>
          </div>
          <div className="p-3 rounded-lg bg-purple-50">
            <p className="text-xs text-purple-600">Multi-allelic</p>
            <p className="text-lg font-semibold text-purple-700">{data.stats.multiallelic.toLocaleString()}</p>
          </div>
          <div className="p-3 rounded-lg bg-green-50">
            <p className="text-xs text-green-600">PASS Filter</p>
            <p className="text-lg font-semibold text-green-700">{data.stats.passedFilter.toLocaleString()}</p>
          </div>
        </div>

        {/* Filters */}
        <div className="flex flex-wrap gap-3">
          <div className="flex-1 min-w-[200px]">
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search variants..."
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
              {chromosomes.map(chrom => (
                <SelectItem key={chrom} value={chrom}>{chrom}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={filterQuality} onValueChange={setFilterQuality}>
            <SelectTrigger className="w-[140px]">
              <SelectValue placeholder="Quality" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Quality</SelectItem>
              <SelectItem value="pass">PASS only</SelectItem>
              <SelectItem value="high">High Quality (≥30)</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {/* Variant Table */}
        <div className="rounded-lg border">
          <ScrollArea className="h-[400px]">
            <Table>
              <TableHeader className="sticky top-0 bg-background">
                <TableRow>
                  <TableHead className="w-[100px]">
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-8 p-0"
                      onClick={() => {
                        if (sortField === "pos") setSortAsc(!sortAsc)
                        else { setSortField("pos"); setSortAsc(true) }
                      }}
                    >
                      Position
                      <ArrowUpDown className="ml-1 h-3 w-3" />
                    </Button>
                  </TableHead>
                  <TableHead>ID</TableHead>
                  <TableHead>Ref</TableHead>
                  <TableHead>Alt</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-8 p-0"
                      onClick={() => {
                        if (sortField === "qual") setSortAsc(!sortAsc)
                        else { setSortField("qual"); setSortAsc(false) }
                      }}
                    >
                      Quality
                      <ArrowUpDown className="ml-1 h-3 w-3" />
                    </Button>
                  </TableHead>
                  <TableHead>Filter</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredVariants.slice(0, 500).map((variant, idx) => {
                  const type = getVariantType(variant.ref, variant.alt)
                  return (
                    <TableRow key={`${variant.chrom}-${variant.pos}-${idx}`}>
                      <TableCell className="font-mono text-sm">
                        {variant.chrom}:{variant.pos.toLocaleString()}
                      </TableCell>
                      <TableCell className="text-sm">
                        {variant.id === "." ? "-" : variant.id}
                      </TableCell>
                      <TableCell className="font-mono text-sm">
                        {variant.ref.length > 10 ? `${variant.ref.slice(0, 10)}...` : variant.ref}
                      </TableCell>
                      <TableCell className="font-mono text-sm">
                        {variant.alt.length > 10 ? `${variant.alt.slice(0, 10)}...` : variant.alt}
                      </TableCell>
                      <TableCell>
                        <Badge variant="secondary" className={getVariantTypeColor(type)}>
                          {type}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-sm">
                        {variant.qual !== null ? variant.qual.toFixed(1) : "-"}
                      </TableCell>
                      <TableCell>
                        {variant.filter === "PASS" || variant.filter === "." ? (
                          <CheckCircle className="h-4 w-4 text-green-600" />
                        ) : (
                          <Badge variant="outline" className="text-xs">
                            {variant.filter}
                          </Badge>
                        )}
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </ScrollArea>
        </div>

        {filteredVariants.length > 500 && (
          <p className="text-xs text-muted-foreground text-center">
            Showing first 500 of {filteredVariants.length.toLocaleString()} filtered variants
          </p>
        )}
      </CardContent>
    </Card>
  )
}
