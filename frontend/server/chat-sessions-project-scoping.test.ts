/**
 * Tests for chat_sessions.project_id persistence + cross-session
 * isolation policy.
 *
 * Background: docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md
 * states the project is the only valid boundary for cross-session
 * context reuse. The chat-stream UPSERT must therefore:
 *   - write project_id alongside session_id on the very first persist
 *     so the linkage is durable for cold-refresh recovery
 *   - never overwrite an already-set project_id (preserves any future
 *     UI selector's choice over the server's auto-default)
 *   - prefer the server-resolved projectId over a client-sent value
 *
 * The hoisting of _resolvedProjectId from the inner Q4 block to the
 * handler scope is the load-bearing fix that lets the persist closure
 * see the resolved value. Lock the hoist + read order in source-level
 * assertions.
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const SERVER = path.join(__dirname);

describe("chat_sessions.project_id wiring (Q4 follow-on)", () => {
  const ROUTES = fs.readFileSync(path.join(SERVER, "routes.ts"), "utf-8");

  it("_resolvedProjectId is HOISTED to handler scope, declared before persistAssistantMessage", () => {
    const declMatch = ROUTES.match(/let _resolvedProjectId\s*:\s*string\s*\|\s*undefined\s*;/);
    expect(declMatch).not.toBeNull();
    const declIdx = ROUTES.indexOf("let _resolvedProjectId:");
    const persistFnIdx = ROUTES.indexOf("const persistAssistantMessage = async");
    // Closure-over-mutable-var pattern: the declaration must precede the closure.
    expect(declIdx).toBeLessThan(persistFnIdx);
    expect(declIdx).toBeGreaterThan(0);
  });

  it("INSERT writes project_id alongside session_id, user_id, messages", () => {
    expect(/INSERT INTO chat_sessions\s*\(\s*session_id\s*,\s*user_id\s*,\s*title\s*,\s*messages\s*,\s*project_id\s*\)/.test(ROUTES)).toBe(true);
  });

  it("ON CONFLICT update keeps the existing project_id when already set (COALESCE-first)", () => {
    // The COALESCE(chat_sessions.project_id, EXCLUDED.project_id) form prevents
    // a later server-default from clobbering a previously-set value.
    expect(/project_id\s*=\s*COALESCE\s*\(\s*chat_sessions\.project_id\s*,\s*EXCLUDED\.project_id\s*\)/.test(ROUTES)).toBe(true);
  });

  it("server-resolved projectId takes priority over client-sent one in the persist closure", () => {
    expect(/_resolvedProjectId\s*\|\|\s*ctx\.projectId\s*\|\|\s*null/.test(ROUTES)).toBe(true);
  });

  it("the migration creates the column + scoping indexes", () => {
    const MIG = fs.readFileSync(
      path.join(SERVER, "..", "migrations", "0015_chat_sessions_project_id.sql"),
      "utf-8"
    );
    expect(/ALTER TABLE chat_sessions\s+ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES projects\(id\) ON DELETE SET NULL/i.test(MIG)).toBe(true);
    // Two indexes: bare project_id (for FK lookups) and compound (for the
    // cold-refresh recovery query path).
    expect(/CREATE INDEX IF NOT EXISTS chat_sessions_project_id_idx/i.test(MIG)).toBe(true);
    expect(/CREATE INDEX IF NOT EXISTS chat_sessions_project_last_activity_idx[\s\S]*project_id,\s*last_activity DESC/i.test(MIG)).toBe(true);
  });
});
