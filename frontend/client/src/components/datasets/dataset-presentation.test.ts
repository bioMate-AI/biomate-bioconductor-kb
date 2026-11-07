import { describe, expect, it } from "vitest"
import { datasetContentType, datasetShape, openInErrorMessage } from "./dataset-presentation"

describe("dataset metadata and launch failures", () => {
  it("resolves generic storage MIME for JSON/YAML without overriding a specific MIME", () => {
    expect(datasetContentType("toxicity_report.json", "application/octet-stream")).toBe("application/json")
    expect(datasetContentType("protocol.YML", "application/octet-stream")).toBe("application/yaml")
    expect(datasetContentType("data.json", "text/plain")).toBe("text/plain")
  })
  it("does not report unavailable shape as an empty dataset", () => {
    expect(datasetShape({ shape: { rows: 0, cols: 0 }, quality: "watch", notes: [] })).toEqual({ rows: undefined, cols: undefined })
    expect(datasetShape({ shape: { rows: 0, cols: 2 }, columns: ["sample", "value"], quality: "watch", notes: [] })).toEqual({ rows: 0, cols: 2 })
  })
  it("uses useful server explanations instead of Axios boilerplate", () => {
    expect(openInErrorMessage({ error: "InteractiveLaunchError", message: "The dataset could not be staged." }, "Jupyter", 400)).toBe("Jupyter: The dataset could not be staged.")
    expect(openInErrorMessage({ error: "Request failed with status code 400" }, "Jupyter", 400)).toContain("The file was not opened")
  })
})
