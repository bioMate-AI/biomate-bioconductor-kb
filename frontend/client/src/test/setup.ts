/**
 * Vitest Test Setup
 *
 * This file runs before all tests and sets up:
 * - DOM environment (jsdom)
 * - Mock implementations for browser APIs
 * - Custom matchers from @testing-library
 */

import '@testing-library/jest-dom/vitest';

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
