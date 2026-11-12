/**
 * Decode the beginning of a gzip / bgzip file in the browser for the dataset Preview.
 *
 * Uses the platform DecompressionStream("gzip") — no JS inflate dependency. Two facts
 * shape the implementation:
 *
 * 1. bgzip (BGZF: .vcf.gz, .bed.gz, .gtf.gz from htslib, .bgz) is a CONCATENATION of
 *    small gzip members. Not every browser's DecompressionStream continues past the
 *    first member (some error on "trailing data", some stop), so we never rely on it:
 *    the input is split into members first — exactly via the BGZF block size (BSIZE in
 *    the "BC" extra subfield) when present, otherwise at the next gzip header — and
 *    each member is decoded by its own stream. A false header candidate inside deflate
 *    data simply fails to decode cleanly and is merged with the following segment.
 * 2. The bytes come from a Range request, so the LAST member is usually cut. A cut
 *    stream errors at its end; everything decoded before the error is kept.
 *
 * A stream that errors discards output it has queued but not yet handed to a reader,
 * so input is written in small chunks and each chunk's output is drained before the
 * next one (and before close) — see decodeMember.
 */

export class DecompressionUnavailableError extends Error {}

export function decompressionAvailable(): boolean {
  return typeof (globalThis as { DecompressionStream?: unknown }).DecompressionStream === "function"
}

export interface GunzipResult {
  /** Decoded text (UTF-8, at most `limit` bytes of decompressed output). */
  text: string
  /** True when the output stops before the end of the file's content. */
  truncated: boolean
}

const WRITE_CHUNK = 16 * 1024

/** True when a gzip member header plausibly starts at `i` (magic, CM=deflate, no reserved flags). */
function isMemberStart(b: Uint8Array, i: number): boolean {
  return i + 10 <= b.length && b[i] === 0x1f && b[i + 1] === 0x8b && b[i + 2] === 0x08 && (b[i + 3] & 0xe0) === 0
}

/** BGZF block length from the "BC" extra subfield of the member at `i`, or null. */
function bgzfBlockSize(b: Uint8Array, i: number): number | null {
  if (!isMemberStart(b, i) || (b[i + 3] & 0x04) === 0 || i + 12 > b.length) return null
  const xlen = b[i + 10] | (b[i + 11] << 8)
  let p = i + 12
  const end = p + xlen
  if (end > b.length) return null
  while (p + 4 <= end) {
    const slen = b[p + 2] | (b[p + 3] << 8)
    if (b[p] === 66 /* B */ && b[p + 1] === 67 /* C */ && slen === 2 && p + 6 <= end) {
      return (b[p + 4] | (b[p + 5] << 8)) + 1
    }
    p += 4 + slen
  }
  return null
}

/** Offset of the next candidate member start after the member starting at `start`. */
function nextCandidate(b: Uint8Array, start: number, from: number): number {
  if (from === start) {
    const bsize = bgzfBlockSize(b, start)
    if (bsize != null && start + bsize <= b.length) return start + bsize
  }
  // The smallest possible member is 18 bytes (10 header + 2 deflate + 8 trailer).
  for (let i = Math.max(from + 1, start + 18); i < b.length; i++) {
    if (isMemberStart(b, i)) return i
  }
  return b.length
}

interface MemberOutput { chunks: Uint8Array[]; bytes: number; ok: boolean; hitLimit: boolean }

/** Decode one gzip member (input = exactly that member, or a cut tail). */
async function decodeMember(input: Uint8Array, limit: number): Promise<MemberOutput> {
  const ds = new (globalThis as unknown as { DecompressionStream: new (f: string) => TransformStream<Uint8Array, Uint8Array> })
    .DecompressionStream("gzip")
  const writer = ds.writable.getWriter()
  const reader = ds.readable.getReader()
  const out: MemberOutput = { chunks: [], bytes: 0, ok: false, hitLimit: false }
  let stop = false
  const reading = (async () => {
    try {
      while (true) {
        const { done, value } = await reader.read()
        if (done) return true
        if (!value?.length) continue
        const room = limit - out.bytes
        out.chunks.push(value.length > room ? value.subarray(0, room) : value)
        out.bytes += Math.min(value.length, room)
        if (out.bytes >= limit) { out.hitLimit = true; stop = true; await reader.cancel().catch(() => {}); return false }
      }
    } catch { return false }
  })()
  const writing = (async () => {
    try {
      for (let p = 0; p < input.length && !stop; p += WRITE_CHUNK) {
        await writer.write(input.subarray(p, p + WRITE_CHUNK))
      }
      // An empty write resolves only after the previous chunk's output was drained
      // (TransformStream backpressure), so a flush error at close() loses nothing.
      if (!stop) await writer.write(new Uint8Array(0))
      if (!stop) await writer.close()
    } catch { /* surfaced through the reader */ }
  })()
  const [readOk] = await Promise.all([reading, writing])
  out.ok = readOk && !out.hitLimit
  return out
}

/**
 * Decompress the start of a gzip/bgzip byte prefix. `inputComplete` says whether
 * `bytes` is the whole file (false for a range-cut prefix). Output is capped at
 * `limit` decompressed bytes.
 */
export async function gunzipPrefix(bytes: Uint8Array, limit: number, inputComplete: boolean): Promise<GunzipResult> {
  if (!decompressionAvailable()) throw new DecompressionUnavailableError("DecompressionStream unavailable")
  const committed: Uint8Array[] = []
  let total = 0
  let truncated = !inputComplete
  let start = 0
  let cut = false
  while (start < bytes.length && total < limit) {
    if (!isMemberStart(bytes, start)) {
      // Not gzip at all (first member) or trailing bytes after the last member.
      if (start === 0) throw new Error("not gzip")
      break
    }
    let end = nextCandidate(bytes, start, start)
    let member = await decodeMember(bytes.subarray(start, end), limit - total)
    // A failed segment that is not the tail: the boundary was a false header inside
    // deflate data (or a BGZF size we could not trust) — extend to the next candidate.
    while (!member.ok && !member.hitLimit && end < bytes.length) {
      end = nextCandidate(bytes, start, end)
      member = await decodeMember(bytes.subarray(start, end), limit - total)
    }
    committed.push(...member.chunks)
    total += member.bytes
    if (member.hitLimit) { truncated = true; break }
    if (!member.ok) { cut = true; break }
    start = end
  }
  if (cut) truncated = true
  if (total >= limit) truncated = true
  const buf = new Uint8Array(total)
  let o = 0
  for (const c of committed) { buf.set(c, o); o += c.length }
  // stream:true drops an incomplete trailing UTF-8 sequence instead of emitting U+FFFD.
  const text = new TextDecoder().decode(buf, { stream: truncated })
  return { text, truncated }
}
