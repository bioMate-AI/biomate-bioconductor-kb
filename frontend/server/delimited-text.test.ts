/**
 * In-place cell edits must change only the edited cells (2026-11-11: line.split(",") editing broke
 * quoted fields and turned CRLF into LF). Row numbering must match the Python rows reader.
 */
import { describe, it, expect } from "vitest"
import { applyCellEdits, parseRecord, splitRecords, quoteField, readCell, parseDelimited, pickDelimiter } from "./delimited-text"

describe("parseRecord / splitRecords (Python csv rules)", () => {
  it("quoted fields hold delimiters, escaped quotes and newlines", () => {
    expect(parseRecord('1,"x, y","say ""hi""",', ",").map((f) => f.value)).toEqual(["1", "x, y", 'say "hi"', ""])
    const recs = splitRecords('a,b\r\n1,"line1\nline2"\r\n2,z', ",")
    expect(recs.map((r) => r.term)).toEqual(["\r\n", "\r\n", ""])
    expect(recs).toHaveLength(3)
  })
  it("a quote in the middle of an unquoted field is literal", () => {
    expect(parseRecord('5" disk,ok', ",").map((f) => f.value)).toEqual(['5" disk', "ok"])
  })
  it("minimal quoting", () => {
    expect(quoteField("plain", ",")).toBe("plain")
    expect(quoteField("a,b", ",")).toBe('"a,b"')
    expect(quoteField('5"', ",")).toBe('"5"""')
    expect(quoteField("a,b", "\t")).toBe("a,b")
  })
})

describe("applyCellEdits", () => {
  const csv = 'id,label,note\r\n1,"x, y",keep "as is"\r\n\r\n2,b,"multi\nline"\r\n'

  it("edits only the target field; quoting, CRLF and other bytes are kept", () => {
    const r = applyCellEdits(csv, ",", [{ row: 0, col: 2, from: 'keep "as is"', value: "new" }])
    expect(r.conflicts).toEqual([])
    expect(r.applied).toBe(1)
    expect(r.text).toBe('id,label,note\r\n1,"x, y",new\r\n\r\n2,b,"multi\nline"\r\n')
  })

  it("re-quotes an edited value that needs it", () => {
    const r = applyCellEdits(csv, ",", [{ row: 0, col: 1, from: "x, y", value: 'a "b", c' }])
    expect(r.text.split("\r\n")[1]).toBe('1,"a ""b"", c",keep "as is"')
  })

  it("numbers data rows like the reader: blank records skipped, multi-line record is one row", () => {
    expect(readCell(csv, ",", 1, 0)).toBe("2")
    expect(readCell(csv, ",", 1, 2)).toBe("multi\nline")
    const r = applyCellEdits(csv, ",", [{ row: 1, col: 2, from: "multi\nline", value: "one" }])
    expect(r.text.endsWith("2,b,one\r\n")).toBe(true)
  })

  it("rejects ALL edits when one 'from' does not match (stale version / wrong row)", () => {
    const r = applyCellEdits(csv, ",", [
      { row: 0, col: 0, from: "1", value: "10" },
      { row: 1, col: 1, from: "WRONG", value: "x" },
    ])
    expect(r.applied).toBe(0)
    expect(r.text).toBe(csv)
    expect(r.conflicts).toEqual([{ row: 1, col: 1, expected: "WRONG", actual: "b" }])
  })

  it("rejects rows / columns that do not exist", () => {
    const r = applyCellEdits(csv, ",", [{ row: 9, col: 0, from: "", value: "x" }])
    expect(r.applied).toBe(0)
    expect(r.conflicts[0].actual).toBeNull()
  })

  it("TSV, header-less files, BOM and missing trailing newline", () => {
    const tsv = "﻿chr1\t100\t200\nchr2\t300\t400"
    const r = applyCellEdits(tsv, "\t", [{ row: 1, col: 1, from: "300", value: "350" }], { headerRows: 0 })
    expect(r.text).toBe("﻿chr1\t100\t200\nchr2\t350\t400")
  })

  it("headerRows 0 (a header-less table): row 0 is line 1; with headerRows 1 the same index is line 2", () => {
    const csv = "1,2.5,x\n3,4.1,y\n"
    expect(applyCellEdits(csv, ",", [{ row: 0, col: 2, from: "x", value: "X" }], { headerRows: 0 }).text).toBe("1,2.5,X\n3,4.1,y\n")
    // The wrong numbering cannot land on the wrong cell: the `from` check refuses it.
    const wrong = applyCellEdits(csv, ",", [{ row: 0, col: 2, from: "x", value: "X" }], { headerRows: 1 })
    expect(wrong.applied).toBe(0)
    expect(wrong.conflicts[0]).toEqual({ row: 0, col: 2, expected: "x", actual: "y" })
  })

  it("values match Python's universal-newline reading (\\r inside a quoted field reads as \\n)", () => {
    expect(readCell('a,b\r1,2\r3,"4\r5"\r', ",", 1, 1)).toBe("4\n5")
  })

  it("an edit past the last field pads the record", () => {
    const r = applyCellEdits("a,b,c\n1,2\n", ",", [{ row: 0, col: 2, from: "", value: "3" }])
    expect(r.text).toBe("a,b,c\n1,2,3\n")
  })
})

describe("parseDelimited / pickDelimiter (version Compare)", () => {
  it("quoted fields and multi-line records do not shift later rows", () => {
    const rows = parseDelimited('id,note\n1,"a, b"\n2,"x\ny"\n\n3,z\n', ",")
    expect(rows).toEqual([["id", "note"], ["1", "a, b"], ["2", "x\ny"], ["3", "z"]])
  })
  it("delimiter by extension, else by first-line counts", () => {
    expect(pickDelimiter("a,b", "tsv")).toBe("\t")
    expect(pickDelimiter("a\tb\tc,d\n", "txt")).toBe("\t")
    expect(pickDelimiter("a,b\n", "")).toBe(",")
  })
})

describe("audit 2026-11-12 — EOF quote, mid-field quote, rowFrom", () => {
  it("splitRecords: a quote in the middle of an unquoted field does not open quoting (the newline still ends the record)", () => {
    const recs = splitRecords('a,b\n5" disk,ok\n2,x\n', ",")
    expect(recs).toHaveLength(3)
    expect(parseDelimited('a,b\n5" disk,ok\n2,x\n', ",")).toEqual([["a", "b"], ['5" disk', "ok"], ["2", "x"]])
    // after a delimiter the field starts again: a quote there DOES open quoting
    expect(splitRecords('a,"b\nc",d\n', ",")).toHaveLength(1)
  })

  it("padding after a field the file ends inside closes the quote (1,\"x at EOF + edit col 2 → 1,\"x\",3)", () => {
    const text = 'a,b,c\n1,"x'
    const r = applyCellEdits(text, ",", [{ row: 0, col: 2, from: "", value: "3" }])
    expect(r.conflicts).toEqual([])
    expect(r.text).toBe('a,b,c\n1,"x",3')
    expect(parseDelimited(r.text, ",")).toEqual([["a", "b", "c"], ["1", "x", "3"]])
    // an earlier field edited, the open field last and untouched: its bytes are kept as-is
    expect(applyCellEdits(text, ",", [{ row: 0, col: 0, from: "1", value: "9" }]).text).toBe('a,b,c\n9,"x')
  })

  it("rowFrom: the whole row must match, so a mis-numbered edit cannot land on a twin cell value", () => {
    const bed = "chr1\t100\t200\t0\nchr2\t300\t400\t0\n"
    const wrong = applyCellEdits(bed, "\t", [{ row: 0, col: 3, from: "0", value: "9", rowFrom: ["chr1", "100", "200", "0"] }], { headerRows: 1 })
    expect(wrong.applied).toBe(0)
    expect(wrong.conflicts[0]).toMatchObject({ row: 0, col: 3, rowMismatch: true })
    const right = applyCellEdits(bed, "\t", [{ row: 0, col: 3, from: "0", value: "9", rowFrom: ["chr1", "100", "200", "0"] }], { headerRows: 0 })
    expect(right.text).toBe("chr1\t100\t200\t9\nchr2\t300\t400\t0\n")
    // trailing empty fields are not significant (the reader pads short rows)
    expect(applyCellEdits("a,b,c\n1,2\n", ",", [{ row: 0, col: 0, from: "1", value: "7", rowFrom: ["1", "2", ""] }]).applied).toBe(1)
  })
})

describe("skipLines (rows reader's leading comment/blank lines)", () => {
  it("featureCounts-style file: row 0 is the first data line after the comment and header", () => {
    const fc = "# Program:featureCounts v2.0.1; Command:...\nGeneid\tChr\tS1\nG1\tchr1\t5\nG2\tchr1\t7\n"
    expect(readCell(fc, "\t", 0, 0, { headerRows: 1, skipLines: 1 })).toBe("G1")
    const r = applyCellEdits(fc, "\t", [{ row: 1, col: 2, from: "7", value: "8" }], { headerRows: 1, skipLines: 1 })
    expect(r.conflicts).toEqual([])
    expect(r.text).toBe("# Program:featureCounts v2.0.1; Command:...\nGeneid\tChr\tS1\nG1\tchr1\t5\nG2\tchr1\t8\n")
    // without skipLines the comment would be taken as the header and rows shift
    expect(readCell(fc, "\t", 0, 0, { headerRows: 1 })).toBe("Geneid")
  })
  it("counts CRLF and blank lines as physical lines", () => {
    const t = "#c\r\n\r\nh\r\nv\r\n"
    expect(readCell(t, ",", 0, 0, { headerRows: 1, skipLines: 2 })).toBe("v")
  })
})
