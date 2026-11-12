import { describe, expect, it } from "vitest"
import { isTiff, parseTiffPreviewInfo, tiffCaption } from "./tiff-preview-info"

describe("tiffCaption — what the server drew", () => {
  it("pages, series, channels, bit depth, stretch, size and pyramid level", () => {
    expect(tiffCaption({ planeCount: 3, plane: 0, dtype: "uint16", stretch: { low: [1], high: [2] }, axes: "ZYX", shape: [3, 512, 640] }))
      .toBe("first of 3 pages · 16-bit, contrast stretched · 640 × 512 px")
    expect(tiffCaption({ planeCount: 25, plane: 6, seriesCount: 6, series: 0, channels: 4, channelsShown: 1, dtype: "uint8", axes: "CYX", shape: [4, 5, 5] }))
      .toBe("page 7 of 25 · series 1 of 6 · channel 1 of 4 · 8-bit · 5 × 5 px")
    expect(tiffCaption({ dtype: "float32", stretch: {}, level: 2, levelCount: 3, axes: "YX", shape: [4096, 3000] }))
      .toBe("32-bit float, contrast stretched · 3000 × 4096 px · drawn from pyramid level 3 of 3")
    expect(tiffCaption({ dtype: "bool", constant: true, axes: "YX", shape: [10, 10] })).toBe("1-bit, uniform image · 10 × 10 px")
    expect(tiffCaption({ dtype: "int16", stretch: {}, channels: 3, channelsShown: 3, axes: "YXS", shape: [8, 9, 3] })).toBe("16-bit signed, contrast stretched · 9 × 8 px")
    expect(tiffCaption({ dtype: "complex64", stretch: {} })).toBe("32-bit float, contrast stretched")
    expect(tiffCaption(null)).toBe("")
  })
  it("parses only a JSON object header", () => {
    expect(parseTiffPreviewInfo('{"planeCount":2}')).toEqual({ planeCount: 2 })
    for (const h of [null, "", "not json", "[1]", "3"]) expect(parseTiffPreviewInfo(h)).toBeNull()
  })
  it("TIFF by the profiler's format, by name only without one", () => {
    expect(isTiff("x.bin", "ome.tiff")).toBe(true)
    expect(isTiff("x.tif", "png")).toBe(false)
    expect(isTiff("a/b.OME.TIF")).toBe(true)
    expect(isTiff("x.btf")).toBe(true)
    expect(isTiff("x.png")).toBe(false)
  })
})
