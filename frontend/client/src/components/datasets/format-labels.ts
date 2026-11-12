/**
 * Format names in the UI language. The profiler sends `format: {ext, label}` with an ENGLISH
 * label (data_perception.py _BIOMATE_LABELS / _BINARY_NAME_FORMATS, galaxy_formats.py _LABELS /
 * humanize_ext). The client owns the translation:
 *
 *  1. `FORMAT_LABELS[ext]` — the label the profiler gives that extension, with its zh text. Used
 *     only when the backend label IS that label: one extension can carry more than one label
 *     (`txt` is "Text" for a document and "Text (one value per line)" for a one-column table;
 *     `csv` is also "CSV (semicolon-separated)"), and the backend's word is the truth.
 *  2. A label that is a known name (any table entry, or a NAMES base like "Tar archive").
 *  3. "Base (qualifier, qualifier)": the base and each qualifier word translated separately.
 *  4. Otherwise the backend label, unchanged (format names like BAM / VCF are not translated).
 */
import { locale } from "@/lib/i18n"

interface Label { en: string; zh: string }

/** ext → the profiler's label for it, and its Chinese text. */
const FORMAT_LABELS: Record<string, Label> = {
  unknown: { en: "Unknown", zh: "未知格式" },
  data: { en: "Unknown", zh: "未知格式" },
  txt: { en: "Text", zh: "文本" },
  readme: { en: "Text", zh: "文本" },
  tabular: { en: "Tabular", zh: "制表符分隔表格" },
  jsonl: { en: "JSON Lines", zh: "JSON Lines（逐行 JSON）" },
  xlsx: { en: "Excel (xlsx)", zh: "Excel 表格（xlsx）" },
  xls: { en: "Excel (xls)", zh: "Excel 表格（xls）" },
  "excel.xls": { en: "Excel (xls)", zh: "Excel 表格（xls）" },
  mtx: { en: "Matrix Market", zh: "Matrix Market 稀疏矩阵" },
  h5: { en: "HDF5", zh: "HDF5 文件" },
  hdf5: { en: "HDF5", zh: "HDF5 文件" },
  loom: { en: "Loom", zh: "Loom 单细胞文件" },
  binary: { en: "Binary", zh: "二进制文件" },
  bin: { en: "Binary", zh: "二进制文件" },
  tar: { en: "Tar archive", zh: "Tar 归档" },
  tgz: { en: "Tar archive (gzip)", zh: "Tar 归档（gzip 压缩）" },
  "tar.gz": { en: "Tar archive (gzip)", zh: "Tar 归档（gzip 压缩）" },
  zip: { en: "ZIP archive", zh: "ZIP 压缩包" },
  "7z": { en: "7-Zip archive", zh: "7-Zip 压缩包" },
  docx: { en: "Word document", zh: "Word 文档" },
  pptx: { en: "PowerPoint", zh: "PowerPoint 演示文稿" },
  sqlite: { en: "SQLite database", zh: "SQLite 数据库" },
  db: { en: "SQLite database", zh: "SQLite 数据库" },
  rds: { en: "R data (RDS)", zh: "R 数据（RDS）" },
  npy: { en: "NumPy array", zh: "NumPy 数组" },
  mrcs: { en: "MRC stack", zh: "MRC 图像栈" },
  log: { en: "Log (text)", zh: "日志（文本）" },
  py: { en: "Python script", zh: "Python 脚本" },
  r: { en: "R script", zh: "R 脚本" },
  sh: { en: "Shell script", zh: "Shell 脚本" },
  nf: { en: "Nextflow script", zh: "Nextflow 脚本" },
  config: { en: "Configuration", zh: "配置文件" },
  ini: { en: "Configuration", zh: "配置文件" },
  interval: { en: "Interval", zh: "区间" },
  encodepeak: { en: "ENCODE peak (narrowPeak)", zh: "ENCODE 峰（narrowPeak）" },
  gz: { en: "gzip-compressed file", zh: "gzip 压缩文件" },
  bgz: { en: "bgzip-compressed file", zh: "bgzip 压缩文件" },
  bz2: { en: "bzip2-compressed file", zh: "bzip2 压缩文件" },
  xz: { en: "xz-compressed file", zh: "xz 压缩文件" },
  zst: { en: "zstd-compressed file", zh: "zstd 压缩文件" },
}

/** Base names that only appear inside a qualified label ("FAST5 archive (tar.gz)"). */
const NAMES: Label[] = [
  { en: "FAST5 archive", zh: "FAST5 归档" },
  { en: "ENCODE peak", zh: "ENCODE 峰" },
  { en: "R data", zh: "R 数据" },
  { en: "Log", zh: "日志" },
  { en: "Excel", zh: "Excel 表格" },
  // Recognised tool-output tables (data_perception.py KNOWN_TABLE_LAYOUTS → format.layout + label).
  { en: "featureCounts counts", zh: "featureCounts 计数表" },
  { en: "MAGeCK counts", zh: "MAGeCK sgRNA 计数表" },
  { en: "Salmon quantification", zh: "Salmon 定量结果" },
  { en: "RSEM quantification", zh: "RSEM 定量结果" },
]

/** Qualifier words in brackets ("FASTQ (gzip)", "CSV (semicolon-separated)"). */
const WORDS: Record<string, string> = {
  gzip: "gzip 压缩",
  bgzip: "bgzip 压缩",
  bzip2: "bzip2 压缩",
  xz: "xz 压缩",
  zstd: "zstd 压缩",
  uncompressed: "未压缩",
  "name-sorted": "按读段名排序",
  unsorted: "未排序",
  "color space": "色空间",
  solexa: "Solexa 编码",
  "one value per line": "每行一个值",
  "semicolon-separated": "分号分隔",
  text: "文本",
  narrowpeak: "narrowPeak",
}

const BY_NAME = new Map<string, string>()
for (const l of [...Object.values(FORMAT_LABELS), ...NAMES]) if (!BY_NAME.has(l.en)) BY_NAME.set(l.en, l.zh)

/** A format label in `lang` (defaults to the page locale); the backend label when nothing matches. */
export function formatLabelText(format: { ext?: string | null; label: string }, lang: string = locale): string {
  const label = format.label
  if (lang !== "zh") return label
  const byExt = format.ext ? FORMAT_LABELS[format.ext.toLowerCase()] : undefined
  if (byExt && byExt.en === label) return byExt.zh
  const named = BY_NAME.get(label)
  if (named) return named
  const m = /^(.*?)\s*\(([^)]*)\)\s*$/.exec(label)
  if (!m) return label
  const base = BY_NAME.get(m[1]) ?? m[1]
  const inner = m[2].split(/\s*,\s*/).map((w) => WORDS[w.toLowerCase()] ?? w).join("，")
  return `${base}（${inner}）`
}
