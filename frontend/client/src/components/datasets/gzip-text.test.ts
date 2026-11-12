/**
 * In-browser gzip/bgzip prefix decoding for the dataset Preview (gzip-text.ts):
 * multi-member gzip, real BGZF blocks (BSIZE-split), range-cut tails, and the
 * decompressed-size cap. Inputs are built with Node zlib — real gzip bytes, no fakes.
 */
import { describe, it, expect, vi, afterEach } from "vitest"
import { gzipSync, deflateRawSync, inflateRawSync, crc32 } from "node:zlib"
import { gunzipPrefix } from "./gzip-text"

const enc = (s: string) => new TextEncoder().encode(s)
const concat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0))
  let o = 0
  for (const p of parts) { out.set(p, o); o += p.length }
  return out
}

/** One BGZF block (htslib layout: FEXTRA with the "BC" subfield carrying BSIZE-1). */
function bgzfBlock(text: string): Uint8Array {
  const data = enc(text)
  const cdata = deflateRawSync(data)
  const bsize = 18 + cdata.length + 8
  const header = new Uint8Array([0x1f, 0x8b, 8, 4, 0, 0, 0, 0, 0, 0xff, 6, 0, 66, 67, 2, 0, (bsize - 1) & 0xff, (bsize - 1) >> 8])
  const trailer = new Uint8Array(8)
  const dv = new DataView(trailer.buffer)
  dv.setUint32(0, crc32(data) >>> 0, true)
  dv.setUint32(4, data.length, true)
  return concat(header, cdata, trailer)
}
const BGZF_EOF = bgzfBlock("")

/**
 * A single-member gzip decoder that errors on trailing data — how some browsers'
 * DecompressionStream behave (Node's continues into the next member, which would
 * hide a splitting bug). Uses real zlib inflate; only the member semantics differ.
 */
class StrictSingleMemberGunzip extends TransformStream<Uint8Array, Uint8Array> {
  constructor(_format: string) {
    const parts: Uint8Array[] = []
    super({
      transform(chunk) { parts.push(chunk) },
      flush(controller) {
        const buf = Buffer.concat(parts)
        let p = 10
        if (buf[3] & 4) p += 2 + buf.readUInt16LE(10)
        const { buffer, engine } = inflateRawSync(buf.subarray(p), { info: true }) as unknown as
          { buffer: Buffer; engine: { bytesWritten: number } }
        if (p + engine.bytesWritten + 8 < buf.length) throw new TypeError("Junk found after end of compressed data.")
        controller.enqueue(new Uint8Array(buffer))
      },
    })
  }
}
afterEach(() => { vi.unstubAllGlobals() })

describe("gunzipPrefix", () => {
  it("decodes a single gzip member completely", async () => {
    const r = await gunzipPrefix(gzipSync(enc("hello\nworld\n")), 1024, true)
    expect(r).toEqual({ text: "hello\nworld\n", truncated: false })
  })

  it("decodes every member of a two-member gzip (cat a.gz b.gz)", async () => {
    const two = concat(gzipSync(enc("first member\n")), gzipSync(enc("second member\n")))
    const r = await gunzipPrefix(two, 1024, true)
    expect(r.text).toBe("first member\nsecond member\n")
    expect(r.truncated).toBe(false)
  })

  it("decodes a BGZF file block by block (BSIZE), including the empty EOF block", async () => {
    const lines = Array.from({ length: 3 }, (_, b) => Array.from({ length: 50 }, (_, i) => `chr1\t${b * 1000 + i}\t.\tA\tG\n`).join(""))
    const file = concat(...lines.map(bgzfBlock), BGZF_EOF)
    const r = await gunzipPrefix(file, 1 << 20, true)
    expect(r.text).toBe(lines.join(""))
    expect(r.truncated).toBe(false)
  })

  it("keeps what decoded when a Range request cut the last member", async () => {
    const a = bgzfBlock("complete block\n")
    const b = bgzfBlock("x".repeat(5000) + "\n")
    const cut = concat(a, b).subarray(0, a.length + Math.floor(b.length / 2))
    const r = await gunzipPrefix(cut, 1 << 20, false)
    expect(r.text.startsWith("complete block\n")).toBe(true)
    expect(r.truncated).toBe(true)
  })

  it("stops at the decompressed-size cap and reports truncation", async () => {
    const r = await gunzipPrefix(gzipSync(enc("a".repeat(100_000))), 1000, true)
    expect(r.text).toBe("a".repeat(1000))
    expect(r.truncated).toBe(true)
  })

  it("splits members itself — works with a decoder that stops at the first member", async () => {
    vi.stubGlobal("DecompressionStream", StrictSingleMemberGunzip)
    const two = concat(gzipSync(enc("first member\n")), gzipSync(enc("second member\n")))
    expect((await gunzipPrefix(two, 1024, true)).text).toBe("first member\nsecond member\n")
    const bgzf = concat(bgzfBlock("block one\n"), bgzfBlock("block two\n"), BGZF_EOF)
    expect(await gunzipPrefix(bgzf, 1024, true)).toEqual({ text: "block one\nblock two\n", truncated: false })
    const cut = concat(bgzfBlock("kept\n"), bgzfBlock("y".repeat(4000))).subarray(0, 60)
    expect(await gunzipPrefix(cut, 1024, false)).toEqual({ text: "kept\n", truncated: true })
  })

  it("rejects bytes that are not gzip", async () => {
    await expect(gunzipPrefix(enc("plain text"), 1024, true)).rejects.toThrow()
  })
})
