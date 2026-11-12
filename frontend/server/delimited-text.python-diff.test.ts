// @vitest-environment node
/**
 * Differential test: parseDelimited / applyCellEdits against Python's csv.reader — the parser the
 * rows reader uses (galaxy.ai.data_perception._iter_table: text mode with universal newlines,
 * csv.reader, blank / all-empty rows skipped). A seeded generator builds CSV texts from the
 * characters that matter (delimiter, quotes, \r, \n, \r\n, spaces, non-ASCII), Python parses them
 * in one subprocess, and every text must parse identically; every random cell edit must produce
 * a file Python reads as exactly the expected rows.
 *
 * Needs python3 on PATH. Without it the suite is SKIPPED with the reason in its title and a
 * console warning — never silently passed.
 */
import { describe, expect, it } from "vitest"
import { spawnSync } from "child_process"
import { applyCellEdits, parseDelimited } from "./delimited-text"

const PY = "python3"
const probe = spawnSync(PY, ["-c", "import csv, io, json, sys"], { encoding: "utf-8" })
const havePython = probe.status === 0
const reason = havePython ? "" : `SKIPPED: ${PY} not available (${probe.error?.message ?? probe.stderr?.trim() ?? "exit " + probe.status})`
if (!havePython) console.warn(`[delimited-text.python-diff] ${reason}`)

// Same reading as the rows reader: bytes → TextIOWrapper (universal newlines) → csv.reader;
// blank / all-empty rows skipped. DATA mode also consumes record 1 as the header first (even a
// blank one), exactly like _iter_table with a header row — the numbering edits use.
const READER = `
import csv, io, json, sys
mode = sys.argv[1]
out = []
for t in json.load(sys.stdin):
    f = io.TextIOWrapper(io.BytesIO(t.encode("utf-8")), encoding="utf-8")
    try:
        rows = []
        for i, r in enumerate(csv.reader(f)):
            if mode == "data" and i == 0:
                continue
            if r and not all(c == "" for c in r):
                rows.append(r)
        out.append(rows)
    except csv.Error as e:
        out.append({"error": str(e)})
json.dump(out, sys.stdout)
`

function pyParse(texts: string[], mode: "all" | "data" = "all"): Array<string[][] | { error: string }> {
  const r = spawnSync(PY, ["-c", READER, mode], { input: JSON.stringify(texts), encoding: "utf-8", maxBuffer: 64 * 1024 * 1024 })
  if (r.status !== 0) throw new Error(`python failed: ${r.stderr}`)
  return JSON.parse(r.stdout)
}

/** mulberry32 — deterministic corpus. */
function rng(seed: number) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
const PIECES = ["a", "b", "1", "", " ", ",", ",", '"', '""', "\n", "\r\n", "\r", "é", "数", "x y"]

function genText(r: () => number): string {
  let s = ""
  const n = 1 + Math.floor(r() * 40)
  for (let i = 0; i < n; i++) s += PIECES[Math.floor(r() * PIECES.length)]
  return s
}
/** A well-formed-ish CSV: fields quoted when they need it, plus some raw noise. */
function genTable(r: () => number): string {
  const rows = 1 + Math.floor(r() * 5), cols = 1 + Math.floor(r() * 4)
  const term = ["\n", "\r\n", "\r"][Math.floor(r() * 3)]
  const lines: string[] = []
  for (let i = 0; i < rows; i++) {
    const f: string[] = []
    for (let j = 0; j < cols; j++) {
      const v = genText(r).slice(0, 6)
      f.push(r() < 0.5 ? `"${v.replace(/"/g, '""')}"` : v.replace(/[",\r\n]/g, ""))
    }
    lines.push(f.join(","))
  }
  return lines.join(term) + (r() < 0.5 ? term : "")
}

describe.skipIf(!havePython)(`parseDelimited vs Python csv.reader${reason ? ` (${reason})` : ""}`, () => {
  it("parses a 3,000-text generated corpus exactly like Python", () => {
    const r = rng(20261112)
    const texts = Array.from({ length: 3000 }, (_, i) => (i % 2 ? genText(r) : genTable(r)))
    const py = pyParse(texts)
    const mismatches: string[] = []
    texts.forEach((t, i) => {
      const p = py[i]
      if (!Array.isArray(p)) return // Python refused the text; nothing to match
      const ours = parseDelimited(t, ",")
      if (JSON.stringify(ours) !== JSON.stringify(p)) mismatches.push(`${JSON.stringify(t)} → ours ${JSON.stringify(ours)} python ${JSON.stringify(p)}`)
    })
    expect(mismatches.slice(0, 5)).toEqual([])
  })

  it("every random cell edit yields a file Python reads as exactly the expected rows", () => {
    const r = rng(7)
    // Data rows as the rows reader numbers them (record 1 is the header), taken from Python itself.
    const pool: string[] = []
    for (let i = 0; i < 6000; i++) pool.push(i % 2 ? genText(r) : genTable(r))
    const before = pyParse(pool, "data")
    const cases: Array<{ text: string; row: number; col: number; value: string; expected: string[][] }> = []
    const sources: string[] = []
    pool.forEach((text, i) => {
      const data = before[i]
      if (!Array.isArray(data) || data.length === 0 || cases.length >= 1500) return
      const row = Math.floor(r() * data.length)
      const col = Math.floor(r() * (data[row].length + 1)) // sometimes one past the end (padding)
      const value = genText(r).slice(0, 5)
      const res = applyCellEdits(text, ",", [{ row, col, from: data[row][col] ?? "", value }])
      if (res.conflicts.length) throw new Error(`edit refused on ${JSON.stringify(text)}: ${JSON.stringify(res.conflicts)}`)
      const expected = data.map((x) => [...x])
      const target = expected[row]
      while (target.length <= col) target.push("")
      target[col] = value.replace(/\r\n?/g, "\n")
      cases.push({ text: res.text, row, col, value, expected: expected.filter((x) => !x.every((c) => c === "")) })
      sources.push(text)
    })
    expect(cases.length).toBeGreaterThan(1000)
    const py = pyParse(cases.map((c) => c.text), "data")
    const bad: string[] = []
    cases.forEach((c, i) => {
      if (JSON.stringify(py[i]) !== JSON.stringify(c.expected)) {
        bad.push(`${JSON.stringify(sources[i])} edit r${c.row} c${c.col}=${JSON.stringify(c.value)} → ${JSON.stringify(c.text)}: python ${JSON.stringify(py[i])} expected ${JSON.stringify(c.expected)}`)
      }
    })
    expect(bad.slice(0, 5)).toEqual([])
  })
})
