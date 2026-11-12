import { describe, expect, it } from "vitest"
import { deriveParamOrigin } from "./parameter-group"

describe("parameter origin (founder 2026-11-12: example SMILES labelled 推荐 / default)", () => {
  const base = { id: "smiles_list", name: "smiles_list", type: "text" } as any
  it("a workflow example value is 'example' — even if a stale hint marked it auto-filled", () => {
    expect(deriveParamOrigin({ ...base, example: true })).toBe("example")
    expect(deriveParamOrigin({ ...base, example: true, autoFilled: true })).toBe("example")
  })
  it("the user's edit still wins; real recommendations stay recommended", () => {
    expect(deriveParamOrigin({ ...base, example: true, overridden: true })).toBe("edited")
    expect(deriveParamOrigin({ ...base, autoFilled: true })).toBe("recommended")
    expect(deriveParamOrigin({ ...base })).toBe("default")
  })
})
