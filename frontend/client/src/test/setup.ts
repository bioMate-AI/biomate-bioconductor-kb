/**
 * Vitest Test Setup
 *
 * This file runs before all tests and sets up:
 * - DOM environment (jsdom)
 * - Mock implementations for browser APIs
 * - Custom matchers from @testing-library
 */

import '@testing-library/jest-dom/vitest';

// Server-side tests transitively import server/db.ts, which throws at
// module-load time if DATABASE_URL is missing. The pg Pool is lazy (no
// connection until a query runs), so a stub URL satisfies the guard
// without enabling real DB hits — server tests that touch the db mock
// the drizzle layer above it. Without this, server/galaxy-assistant-
// history-block.test.ts + server/galaxy-assistant-history-edge-cases
// .test.ts crash before collection with "DATABASE_URL environment
// variable is required" and mask real regressions in the rest of the
// server suite.
if (!process.env.DATABASE_URL) {
  process.env.DATABASE_URL =
    "postgres://stub:stub@127.0.0.1:5432/vitest-stub";
}

// Mock window.matchMedia
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: (query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }),
});

// Mock ResizeObserver
class MockResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
}

Object.defineProperty(window, 'ResizeObserver', {
  writable: true,
  value: MockResizeObserver,
});

// Mock IntersectionObserver
class MockIntersectionObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
}

Object.defineProperty(window, 'IntersectionObserver', {
  writable: true,
  value: MockIntersectionObserver,
});

// Mock scrollTo
Object.defineProperty(window, 'scrollTo', {
  writable: true,
  value: () => {},
});

// Mock fetch if needed
if (typeof global.fetch === 'undefined') {
  global.fetch = async () => ({
    ok: true,
    json: async () => ({}),
    text: async () => '',
    headers: new Headers(),
    status: 200,
    statusText: 'OK',
  }) as Response;
}
