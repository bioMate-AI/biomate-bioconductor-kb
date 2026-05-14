/**
 * Bioinformatics File Parsers
 * Provides parsing utilities for common bioinformatics file formats
 */

// VCF Parser Types and Functions
export interface VCFVariant {
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

export interface VCFData {
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

export function parseVCF(content: string, limit = 1000): VCFData {
  const lines = content.split('\n')
  const header: VCFData['header'] = {
    fileFormat: '',
    samples: [],
    contigs: [],
    infoFields: [],
  }
  const variants: VCFVariant[] = []
  let stats = { totalVariants: 0, snps: 0, indels: 0, multiallelic: 0, passedFilter: 0 }

  let headerLine: string[] = []

  for (const line of lines) {
    if (line.startsWith('##fileformat=')) {
      header.fileFormat = line.split('=')[1]
    } else if (line.startsWith('##contig=')) {
      const match = line.match(/ID=([^,>]+)/)
      if (match) header.contigs.push(match[1])
    } else if (line.startsWith('##INFO=')) {
      const idMatch = line.match(/ID=([^,>]+)/)
      const descMatch = line.match(/Description="([^"]+)"/)
      if (idMatch) {
        header.infoFields.push({
          id: idMatch[1],
          description: descMatch?.[1] || '',
        })
      }
    } else if (line.startsWith('#CHROM')) {
      headerLine = line.split('\t')
      if (headerLine.length > 9) {
        header.samples = headerLine.slice(9)
      }
    } else if (!line.startsWith('#') && line.trim()) {
      stats.totalVariants++

      // Only parse up to limit variants for display
      if (variants.length < limit) {
        const fields = line.split('\t')
        const ref = fields[3]
        const alt = fields[4]

        const variant: VCFVariant = {
          chrom: fields[0],
          pos: parseInt(fields[1], 10),
          id: fields[2],
          ref,
          alt,
          qual: fields[5] === '.' ? null : parseFloat(fields[5]),
          filter: fields[6],
          info: parseVCFInfo(fields[7]),
        }

        if (fields.length > 9) {
          variant.genotypes = fields.slice(9)
        }

        variants.push(variant)

        // Update stats
        if (ref.length === 1 && alt.length === 1 && !alt.includes(',')) {
          stats.snps++
        } else if (ref.length !== alt.length || alt.includes(',')) {
          stats.indels++
        }
        if (alt.includes(',')) {
          stats.multiallelic++
        }
        if (variant.filter === 'PASS' || variant.filter === '.') {
          stats.passedFilter++
        }
      } else {
        // Still count for stats even if not in display list
        const fields = line.split('\t')
        const ref = fields[3]
        const alt = fields[4]
        if (ref.length === 1 && alt.length === 1 && !alt.includes(',')) {
          stats.snps++
        } else {
          stats.indels++
        }
        if (alt.includes(',')) {
          stats.multiallelic++
        }
        if (fields[6] === 'PASS' || fields[6] === '.') {
          stats.passedFilter++
        }
      }
    }
  }

  return { header, variants, stats }
}

function parseVCFInfo(infoStr: string): Record<string, string> {
  const info: Record<string, string> = {}
  if (infoStr === '.') return info

  for (const item of infoStr.split(';')) {
    const [key, value] = item.split('=')
    info[key] = value || 'true'
  }
  return info
}

// FASTA/FASTQ Parser Types and Functions
export interface SequenceRecord {
  id: string
  description: string
  sequence: string
  length: number
  gcContent: number
  quality?: number[]
  avgQuality?: number
}

export interface SequenceData {
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
    avgQuality?: number
    q30Percent?: number
  }
  baseComposition: {
    A: number
    T: number
    G: number
    C: number
    N: number
  }
}

export function parseFASTA(content: string, limit = 500): SequenceData {
  const sequences: SequenceRecord[] = []
  const baseComp = { A: 0, T: 0, G: 0, C: 0, N: 0 }
  let totalBases = 0
  let totalGC = 0
  const lengths: number[] = []

  const lines = content.split('\n')
  let currentRecord: Partial<SequenceRecord> | null = null
  let currentSeq = ''

  for (const line of lines) {
    if (line.startsWith('>')) {
      // Save previous record
      if (currentRecord && currentSeq) {
        const gcCount = (currentSeq.match(/[GC]/gi) || []).length
        const record: SequenceRecord = {
          id: currentRecord.id!,
          description: currentRecord.description || '',
          sequence: currentSeq,
          length: currentSeq.length,
          gcContent: currentSeq.length > 0 ? gcCount / currentSeq.length : 0,
        }

        if (sequences.length < limit) {
          sequences.push(record)
        }

        // Update stats
        lengths.push(currentSeq.length)
        totalBases += currentSeq.length
        totalGC += gcCount

        // Count bases
        for (const base of currentSeq.toUpperCase()) {
          if (base in baseComp) {
            baseComp[base as keyof typeof baseComp]++
          } else {
            baseComp.N++
          }
        }
      }

      // Start new record
      const headerParts = line.slice(1).split(/\s+/)
      currentRecord = {
        id: headerParts[0],
        description: headerParts.slice(1).join(' '),
      }
      currentSeq = ''
    } else if (!line.startsWith(';') && line.trim()) {
      currentSeq += line.trim()
    }
  }

  // Don't forget the last record
  if (currentRecord && currentSeq) {
    const gcCount = (currentSeq.match(/[GC]/gi) || []).length
    const record: SequenceRecord = {
      id: currentRecord.id!,
      description: currentRecord.description || '',
      sequence: currentSeq,
      length: currentSeq.length,
      gcContent: currentSeq.length > 0 ? gcCount / currentSeq.length : 0,
    }

    if (sequences.length < limit) {
      sequences.push(record)
    }

    lengths.push(currentSeq.length)
    totalBases += currentSeq.length
    totalGC += gcCount

    for (const base of currentSeq.toUpperCase()) {
      if (base in baseComp) {
        baseComp[base as keyof typeof baseComp]++
      } else {
        baseComp.N++
      }
    }
  }

  // Calculate N50
  lengths.sort((a, b) => b - a)
  let cumSum = 0
  let n50 = 0
  const halfTotal = totalBases / 2
  for (const len of lengths) {
    cumSum += len
    if (cumSum >= halfTotal) {
      n50 = len
      break
    }
  }

  return {
    format: 'fasta',
    sequences,
    stats: {
      totalSequences: lengths.length,
      totalBases,
      avgLength: lengths.length > 0 ? Math.round(totalBases / lengths.length) : 0,
      minLength: lengths.length > 0 ? Math.min(...lengths) : 0,
      maxLength: lengths.length > 0 ? Math.max(...lengths) : 0,
      avgGcContent: totalBases > 0 ? totalGC / totalBases : 0,
      n50,
    },
    baseComposition: baseComp,
  }
}

export function parseFASTQ(content: string, limit = 500): SequenceData {
  const sequences: SequenceRecord[] = []
  const baseComp = { A: 0, T: 0, G: 0, C: 0, N: 0 }
  let totalBases = 0
  let totalGC = 0
  let totalQuality = 0
  let q30Bases = 0
  const lengths: number[] = []

  const lines = content.split('\n')
  let i = 0

  while (i < lines.length) {
    const headerLine = lines[i]
    if (!headerLine?.startsWith('@')) {
      i++
      continue
    }

    const seqLine = lines[i + 1]
    const plusLine = lines[i + 2]
    const qualLine = lines[i + 3]

    if (!seqLine || !plusLine?.startsWith('+') || !qualLine) {
      i++
      continue
    }

    const headerParts = headerLine.slice(1).split(/\s+/)
    const gcCount = (seqLine.match(/[GC]/gi) || []).length

    // Parse quality scores (Phred+33)
    const quality = Array.from(qualLine).map(c => c.charCodeAt(0) - 33)
    const avgQuality = quality.reduce((a, b) => a + b, 0) / quality.length

    const record: SequenceRecord = {
      id: headerParts[0],
      description: headerParts.slice(1).join(' '),
      sequence: seqLine,
      length: seqLine.length,
      gcContent: seqLine.length > 0 ? gcCount / seqLine.length : 0,
      quality,
      avgQuality,
    }

    if (sequences.length < limit) {
      sequences.push(record)
    }

    // Update stats
    lengths.push(seqLine.length)
    totalBases += seqLine.length
    totalGC += gcCount
    totalQuality += quality.reduce((a, b) => a + b, 0)
    q30Bases += quality.filter(q => q >= 30).length

    // Count bases
    for (const base of seqLine.toUpperCase()) {
      if (base in baseComp) {
        baseComp[base as keyof typeof baseComp]++
      } else {
        baseComp.N++
      }
    }

    i += 4
  }

  return {
    format: 'fastq',
    sequences,
    stats: {
      totalSequences: lengths.length,
      totalBases,
      avgLength: lengths.length > 0 ? Math.round(totalBases / lengths.length) : 0,
      minLength: lengths.length > 0 ? Math.min(...lengths) : 0,
      maxLength: lengths.length > 0 ? Math.max(...lengths) : 0,
      avgGcContent: totalBases > 0 ? totalGC / totalBases : 0,
      avgQuality: totalBases > 0 ? totalQuality / totalBases : 0,
      q30Percent: totalBases > 0 ? (q30Bases / totalBases) * 100 : 0,
    },
    baseComposition: baseComp,
  }
}

// BED/GFF/GTF Parser Types and Functions
export interface AnnotationFeature {
  chrom: string
  start: number
  end: number
  name: string
  score?: number
  strand?: '+' | '-' | '.'
  featureType?: string
  source?: string
  attributes?: Record<string, string>
}

export interface AnnotationData {
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

export function parseBED(content: string, limit = 1000): AnnotationData {
  const features: AnnotationFeature[] = []
  const chromSet = new Set<string>()
  let totalBases = 0
  let plusStrand = 0
  let minusStrand = 0

  const lines = content.split('\n')

  for (const line of lines) {
    if (line.startsWith('#') || line.startsWith('track') || line.startsWith('browser') || !line.trim()) {
      continue
    }

    const fields = line.split('\t')
    if (fields.length < 3) continue

    const chrom = fields[0]
    const start = parseInt(fields[1], 10)
    const end = parseInt(fields[2], 10)

    chromSet.add(chrom)
    totalBases += end - start

    if (features.length < limit) {
      const feature: AnnotationFeature = {
        chrom,
        start,
        end,
        name: fields[3] || '',
        score: fields[4] ? parseFloat(fields[4]) : undefined,
        strand: (fields[5] as '+' | '-' | '.') || undefined,
      }
      features.push(feature)
    }

    if (fields[5] === '+') plusStrand++
    else if (fields[5] === '-') minusStrand++
  }

  return {
    format: 'bed',
    features,
    stats: {
      totalFeatures: features.length,
      chromosomes: Array.from(chromSet).sort(),
      featureTypes: [],
      avgLength: features.length > 0 ? Math.round(totalBases / features.length) : 0,
      totalBases,
      plusStrand,
      minusStrand,
    },
  }
}

export function parseGFF(content: string, limit = 1000): AnnotationData {
  const features: AnnotationFeature[] = []
  const chromSet = new Set<string>()
  const typeCount = new Map<string, number>()
  let totalBases = 0
  let plusStrand = 0
  let minusStrand = 0
  let totalFeatures = 0

  const lines = content.split('\n')

  for (const line of lines) {
    if (line.startsWith('#') || !line.trim()) continue

    const fields = line.split('\t')
    if (fields.length < 8) continue

    totalFeatures++
    const chrom = fields[0]
    const featureType = fields[2]
    const start = parseInt(fields[3], 10)
    const end = parseInt(fields[4], 10)

    chromSet.add(chrom)
    totalBases += end - start
    typeCount.set(featureType, (typeCount.get(featureType) || 0) + 1)

    if (features.length < limit) {
      const feature: AnnotationFeature = {
        chrom,
        start,
        end,
        name: '',
        source: fields[1],
        featureType,
        score: fields[5] !== '.' ? parseFloat(fields[5]) : undefined,
        strand: fields[6] as '+' | '-' | '.' || undefined,
        attributes: parseGFFAttributes(fields[8]),
      }

      // Extract name from attributes
      feature.name = feature.attributes?.Name ||
        feature.attributes?.gene_name ||
        feature.attributes?.ID ||
        ''

      features.push(feature)
    }

    if (fields[6] === '+') plusStrand++
    else if (fields[6] === '-') minusStrand++
  }

  const featureTypes = Array.from(typeCount.entries())
    .map(([type, count]) => ({ type, count }))
    .sort((a, b) => b.count - a.count)

  return {
    format: 'gff',
    features,
    stats: {
      totalFeatures,
      chromosomes: Array.from(chromSet).sort(),
      featureTypes,
      avgLength: totalFeatures > 0 ? Math.round(totalBases / totalFeatures) : 0,
      totalBases,
      plusStrand,
      minusStrand,
    },
  }
}

function parseGFFAttributes(attrStr: string): Record<string, string> {
  const attrs: Record<string, string> = {}
  if (!attrStr || attrStr === '.') return attrs

  // GFF3 uses key=value; GTF uses key "value";
  const isGTF = attrStr.includes('"')

  if (isGTF) {
    const regex = /(\w+)\s+"([^"]+)"/g
    let match
    while ((match = regex.exec(attrStr)) !== null) {
      attrs[match[1]] = match[2]
    }
  } else {
    for (const item of attrStr.split(';')) {
      const [key, value] = item.split('=')
      if (key && value) {
        attrs[key.trim()] = decodeURIComponent(value.trim())
      }
    }
  }

  return attrs
}

export function parseGTF(content: string, limit = 1000): AnnotationData {
  // GTF is essentially GFF2 format
  return parseGFF(content, limit)
}

// File type classification with bioinformatics support
export function classifyFileType(
  extension: string
): 'image' | 'table' | 'text' | 'binary' | 'interactive' | 'sequence' | 'alignment' | 'variants' | 'annotation' | 'singlecell' | 'density_map' | 'structure' {
  const ext = extension.toLowerCase().replace('.', '')

  // Bioinformatics-specific formats
  const sequenceExts = ['fasta', 'fa', 'fna', 'ffn', 'faa', 'frn', 'fastq', 'fq']
  const alignmentExts = ['bam', 'sam', 'cram']
  const variantExts = ['vcf']
  const annotationExts = ['bed', 'gff', 'gff3', 'gtf']
  const singleCellExts = ['h5ad', 'loom', 'h5']
  // Cryo-EM volumetric data — opened by DensityMapViewer (orthogonal 2D slices)
  const densityMapExts = ['mrc', 'mrcs', 'map', 'ccp4']
  // 3D macromolecular structures — opened by StructureViewer (3Dmol.js)
  const structureExts = ['pdb', 'cif', 'mmcif', 'ent']

  // Standard formats
  const imageExts = ['png', 'jpg', 'jpeg', 'svg', 'gif', 'pdf', 'tiff', 'bmp']
  const tableExts = ['tsv', 'csv', 'tabular', 'txt']
  const interactiveExts = ['html', 'htm']
  const textExts = ['log', 'md', 'json', 'xml', 'yaml', 'yml']

  if (sequenceExts.includes(ext)) return 'sequence'
  if (alignmentExts.includes(ext)) return 'alignment'
  if (variantExts.includes(ext)) return 'variants'
  if (annotationExts.includes(ext)) return 'annotation'
  if (singleCellExts.includes(ext)) return 'singlecell'
  if (densityMapExts.includes(ext)) return 'density_map'
  if (structureExts.includes(ext)) return 'structure'
  if (imageExts.includes(ext)) return 'image'
  if (interactiveExts.includes(ext)) return 'interactive'
  if (tableExts.includes(ext)) return 'table'
  if (textExts.includes(ext)) return 'text'

  return 'binary'
}
