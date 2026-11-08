import { describe, it, expect } from "vitest";
import { isNextflowRunNotFound } from "./nextflow-run-lost";

describe("isNextflowRunNotFound", () => {
  it("matches the GalaxyAPIError shape galaxyAPIProxy actually throws", () => {
    // What the interceptor in galaxy-api-proxy.ts throws for Galaxy's 404.
    expect(isNextflowRunNotFound({
      error: "ERR_BAD_REQUEST", message: "Request failed with status code 404", status_code: 404,
      detail: { detail: "Run not found: d59e2967-21ad-4a70-ae83-ac2a61daedf2" },
    })).toBe(true);
  });
  it("matches a plain axios error too", () => {
    expect(isNextflowRunNotFound({ response: { status: 404, data: { detail: "Run not found: x" } } })).toBe(true);
  });
  it("does not match other errors", () => {
    expect(isNextflowRunNotFound({ status_code: 404, detail: { detail: "Not Found" } })).toBe(false);
    expect(isNextflowRunNotFound({ status_code: 502, detail: "Run not found" })).toBe(false);
    expect(isNextflowRunNotFound({ message: "ECONNREFUSED" })).toBe(false);
    expect(isNextflowRunNotFound(undefined)).toBe(false);
  });
});
