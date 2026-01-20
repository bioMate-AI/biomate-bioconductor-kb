/**
 * Sequence Viewer Component
 * Displays FASTA and FASTQ sequence files with statistics and quality visualization
 */

import { useState, useMemo } from "react"
import { useQuery } from "@tanstack/react-query"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Skeleton } from "@/components/ui/skeleton"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  Download,
  Search,
  AlertCircle,
  Dna,
  BarChart3,
  List,
  Copy,
  Check,
} from "lucide-react"
import type { OutputDataset } from "@shared/schema"

interface SequenceViewerProps {
  output: OutputDataset
  className?: string
}

interface SequenceRecord {
  id: string
  description: string
  sequence: string
  length: number
  gcContent: number
  quality?: number[] // For FASTQ
  avgQuality?: number
}

interface SequenceData {
  format: 'fasta' | 'fastq'
  sequences: SequenceRecord[]
  stats: {
    totalSequences: number
    totalBases: number
    avgLength: number
    minLength: number
    maxLength: number
    avgGcContent: number
    n50?: number
    avgQuality?: number // For FASTQ
    q30Percent?: number // Percent of bases >= Q30
  }
  baseComposition: {
    A: number
    T: number
    G: number
    C: number
    N: number
  }
}

export function SequenceViewer({ output, className }: SequenceViewerProps) {
  const [searchTerm, setSearchTerm] = useState("")
  const [selectedSeq, setSelectedSeq] = useState<SequenceRecord | null>(null)
  const [copiedId, setCopiedId] = useState<string | null>(null)
  const [lengthFilter, setLengthFilter] = useState<string>("all")

  const isFastq = output.extension.toLowerCase() === 'fastq' || output.extension.toLowerCase() === 'fq'

  const { data, isLoading, error } = useQuery<SequenceData>({
    queryKey: ['sequence', output.id],
    queryFn: async () => {
      const response = await fetch(`/api/outputs/${output.id}/parse?format=${isFastq ? 'fastq' : 'fasta'}&limit=500`)
      if (!response.ok) throw new Error('Failed to parse sequence file')
      return response.json()
    },
  })

  // Filter sequences
  const filteredSequences = useMemo(() => {
    if (!data?.sequences) return []

    let result = [...data.sequences]

    // Apply search
    if (searchTerm) {
      const term = searchTerm.toLowerCase()
      result = result.filter(s =>
        s.id.toLowerCase().includes(term) ||
        s.description.toLowerCase().includes(term)
      )
    }

    // Apply length filter
    if (lengthFilter === "short") {
      result = result.filter(s => s.length < 1000)
    } else if (lengthFilter === "medium") {
      result = result.filter(s => s.length >= 1000 && s.length < 10000)
    } else if (lengthFilter === "long") {
      result = result.filter(s => s.length >= 10000)
    }

    return result
  }, [data?.sequences, searchTerm, lengthFilter])

  const copySequence = async (seq: SequenceRecord) => {
    await navigator.clipboard.writeText(seq.sequence)
    setCopiedId(seq.id)
    setTimeout(() => setCopiedId(null), 2000)
  }

  const formatSequence = (sequence: string, lineLength = 60): string => {
    const lines: string[] = []
    for (let i = 0; i < sequence.length; i += lineLength) {
      lines.push(sequence.slice(i, i + lineLength))
    }
    return lines.join('\n')
  }

  const getBaseColor = (base: string): string => {
    switch (base.toUpperCase()) {
      case 'A': return 'text-green-600'
      case 'T': return 'text-red-600'
      case 'G': return 'text-yellow-600'
      case 'C': return 'text-blue-600'
      default: return 'text-gray-400'
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
            <span>Failed to load sequence file: {(error as Error).message}</span>
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
              {data.format.toUpperCase()} •
              {data.stats.totalSequences.toLocaleString()} sequences •
              {(data.stats.totalBases / 1e6).toFixed(2)} Mb
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
        <Tabs defaultValue="stats">
          <TabsList>
            <TabsTrigger value="stats" className="gap-1">
              <BarChart3 className="h-4 w-4" />
              Statistics
            </TabsTrigger>
            <TabsTrigger value="sequences" className="gap-1">
              <List className="h-4 w-4" />
              Sequences
            </TabsTrigger>
          </TabsList>

          <TabsContent value="stats" className="space-y-4">
            {/* General Statistics */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <div className="p-3 rounded-lg bg-muted/50">
                <p className="text-xs text-muted-foreground">Sequences</p>
                <p className="text-lg font-semibold">{data.stats.totalSequences.toLocaleString()}</p>
              </div>
              <div className="p-3 rounded-lg bg-muted/50">
                <p className="text-xs text-muted-foreground">Total Bases</p>
                <p className="text-lg font-semibold">{(data.stats.totalBases / 1e6).toFixed(2)} Mb</p>
              </div>
              <div className="p-3 rounded-lg bg-muted/50">
                <p className="text-xs text-muted-foreground">Avg Length</p>
                <p className="text-lg font-semibold">{data.stats.avgLength.toLocaleString()} bp</p>
              </div>
              <div className="p-3 rounded-lg bg-muted/50">
                <p className="text-xs text-muted-foreground">GC Content</p>
                <p className="text-lg font-semibold">{(data.stats.avgGcContent * 100).toFixed(1)}%</p>
              </div>
            </div>

            {/* Length Stats */}
            <div className="grid grid-cols-3 gap-3">
              <div className="p-3 rounded-lg border">
                <p className="text-xs text-muted-foreground">Min Length</p>
                <p className="text-lg font-semibold">{data.stats.minLength.toLocaleString()} bp</p>
              </div>
              <div className="p-3 rounded-lg border">
                <p className="text-xs text-muted-foreground">Max Length</p>
                <p className="text-lg font-semibold">{data.stats.maxLength.toLocaleString()} bp</p>
              </div>
              {data.stats.n50 && (
                <div className="p-3 rounded-lg border">
                  <p className="text-xs text-muted-foreground">N50</p>
                  <p className="text-lg font-semibold">{data.stats.n50.toLocaleString()} bp</p>
                </div>
              )}
            </div>

            {/* Quality Stats (FASTQ only) */}
            {isFastq && data.stats.avgQuality !== undefined && (
              <div className="grid grid-cols-2 gap-3">
                <div className="p-3 rounded-lg bg-green-50">
                  <p className="text-xs text-green-600">Avg Quality</p>
                  <p className="text-lg font-semibold text-green-700">Q{data.stats.avgQuality.toFixed(1)}</p>
                </div>
                {data.stats.q30Percent !== undefined && (
                  <div className="p-3 rounded-lg bg-blue-50">
                    <p className="text-xs text-blue-600">Q30+ Bases</p>
                    <p className="text-lg font-semibold text-blue-700">{data.stats.q30Percent.toFixed(1)}%</p>
                  </div>
                )}
              </div>
            )}

            {/* Base Composition */}
            <div className="space-y-2">
              <h4 className="text-sm font-medium">Base Composition</h4>
              <div className="flex h-8 rounded-lg overflow-hidden">
                {Object.entries(data.baseComposition).map(([base, count]) => {
                  const percent = (count / data.stats.totalBases) * 100
                  if (percent < 0.1) return null
                  const colors: Record<string, string> = {
                    A: 'bg-green-500',
                    T: 'bg-red-500',
                    G: 'bg-yellow-500',
                    C: 'bg-blue-500',
                    N: 'bg-gray-300',
                  }
                  return (
                    <div
                      key={base}
                      className={`${colors[base]} flex items-center justify-center text-xs text-white font-medium`}
                      style={{ width: `${percent}%` }}
                      title={`${base}: ${percent.toFixed(1)}%`}
                    >
                      {percent >= 5 && `${base} ${percent.toFixed(0)}%`}
                    </div>
                  )
                })}
              </div>
              <div className="flex gap-4 text-xs text-muted-foreground">
                <span className="flex items-center gap-1">
                  <div className="w-3 h-3 rounded bg-green-500" /> A: {((data.baseComposition.A / data.stats.totalBases) * 100).toFixed(1)}%
                </span>
                <span className="flex items-center gap-1">
                  <div className="w-3 h-3 rounded bg-red-500" /> T: {((data.baseComposition.T / data.stats.totalBases) * 100).toFixed(1)}%
                </span>
                <span className="flex items-center gap-1">
                  <div className="w-3 h-3 rounded bg-yellow-500" /> G: {((data.baseComposition.G / data.stats.totalBases) * 100).toFixed(1)}%
                </span>
                <span className="flex items-center gap-1">
                  <div className="w-3 h-3 rounded bg-blue-500" /> C: {((data.baseComposition.C / data.stats.totalBases) * 100).toFixed(1)}%
                </span>
              </div>
            </div>
          </TabsContent>

          <TabsContent value="sequences" className="space-y-4">
            {/* Filters */}
            <div className="flex gap-3">
              <div className="flex-1">
                <div className="relative">
                  <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
                  <Input
                    placeholder="Search sequences by ID or description..."
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    className="pl-9"
                  />
                </div>
              </div>
              <Select value={lengthFilter} onValueChange={setLengthFilter}>
                <SelectTrigger className="w-[150px]">
                  <SelectValue placeholder="Length" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Lengths</SelectItem>
                  <SelectItem value="short">&lt; 1kb</SelectItem>
                  <SelectItem value="medium">1kb - 10kb</SelectItem>
                  <SelectItem value="long">&gt; 10kb</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Sequence List */}
            <ScrollArea className="h-[400px] rounded-lg border">
              <div className="divide-y">
                {filteredSequences.map((seq) => (
                  <div
                    key={seq.id}
                    className={`p-3 cursor-pointer hover:bg-muted/50 transition-colors ${
                      selectedSeq?.id === seq.id ? 'bg-muted' : ''
                    }`}
                    onClick={() => setSelectedSeq(selectedSeq?.id === seq.id ? null : seq)}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex-1 min-w-0">
                        <p className="font-mono text-sm font-medium truncate">{seq.id}</p>
                        {seq.description && (
                          <p className="text-xs text-muted-foreground truncate">{seq.description}</p>
                        )}
                      </div>
                      <div className="flex items-center gap-2 ml-2">
                        <Badge variant="secondary" className="text-xs">
                          {seq.length.toLocaleString()} bp
                        </Badge>
                        <Badge variant="outline" className="text-xs">
                          GC: {(seq.gcContent * 100).toFixed(1)}%
                        </Badge>
                        {seq.avgQuality !== undefined && (
                          <Badge variant="outline" className="text-xs">
                            Q{seq.avgQuality.toFixed(0)}
                          </Badge>
                        )}
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 w-7 p-0"
                          onClick={(e) => {
                            e.stopPropagation()
                            copySequence(seq)
                          }}
                        >
                          {copiedId === seq.id ? (
                            <Check className="h-3 w-3 text-green-600" />
                          ) : (
                            <Copy className="h-3 w-3" />
                          )}
                        </Button>
                      </div>
                    </div>

                    {/* Expanded sequence view */}
                    {selectedSeq?.id === seq.id && (
                      <div className="mt-3 p-3 rounded bg-muted/50">
                        <pre className="font-mono text-xs whitespace-pre-wrap break-all leading-relaxed">
                          {formatSequence(seq.sequence.slice(0, 1000))}
                          {seq.sequence.length > 1000 && (
                            <span className="text-muted-foreground">
                              {'\n'}... and {(seq.sequence.length - 1000).toLocaleString()} more bases
                            </span>
                          )}
                        </pre>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </ScrollArea>

            <p className="text-xs text-muted-foreground text-center">
              Showing {filteredSequences.length.toLocaleString()} of {data.stats.totalSequences.toLocaleString()} sequences
            </p>
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  )
}
