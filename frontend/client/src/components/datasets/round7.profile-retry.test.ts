/**
 * A profile request is retried only when it never reached the profiler (no response, a dropped
 * connection, the backend down). A backend that TIMED OUT did receive the request and spent up
 * to the proxy's 120 s on it: retrying would repeat that load for nothing, so it is not retried.
 */
import { describe, it, expect } from "vitest"
import { ProfileRequestError, retryTransientProfile, profileFailure } from "./datasets-api"

describe("retryTransientProfile", () => {
  it("retries a request that never reached the profiler", () => {
    expect(retryTransientProfile(0, new TypeError("Failed to fetch"))).toBe(true)
    expect(retryTransientProfile(0, new ProfileRequestError(502, "x", "ECONNRESET"))).toBe(true)
    expect(retryTransientProfile(0, new ProfileRequestError(502, "x", "UND_ERR_SOCKET"))).toBe(true)
    expect(retryTransientProfile(0, new ProfileRequestError(503, "x"))).toBe(true)
  })
  it("does not retry a backend timeout (the request did reach it)", () => {
    expect(retryTransientProfile(0, new ProfileRequestError(502, "x", "TIMEOUT"))).toBe(false)
    expect(retryTransientProfile(0, new ProfileRequestError(504, "x"))).toBe(false)
    // …but it is still reported as a failed request, not an unreadable file.
    expect(profileFailure(new ProfileRequestError(502, "x", "TIMEOUT"))).toBe("unreachable")
  })
  it("never retries an answer (4xx) and stops after two retries", () => {
    expect(retryTransientProfile(0, new ProfileRequestError(403, "x"))).toBe(false)
    expect(retryTransientProfile(2, new TypeError("Failed to fetch"))).toBe(false)
  })
})
