/**
 * Tests for the chat-session ↔ LTM-session bridge.
 *
 * The 2026-06-13 audit found memory-integration's recordEpisode was
 * silently dropping writes because chat-stream passed its text
 * sessionId straight through, but project_episodes.session_id is uuid
 * (FK → sessions.id). Fix: MemoryService.ensureChatLtmSession finds-
 * or-creates an LTM session keyed by chat_session_id (UNIQUE), returns
 * its UUID, and chat-stream passes that as context.memorySessionId.
 *
 * Source-level guard so a future refactor can't accidentally pass the
 * text sessionId straight through again.
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const SRC = path.join(__dirname);

describe("LTM session bridge — schema + helper + wiring", () => {
  const MIG = fs.readFileSync(path.join(SRC, "..", "migrations", "0016_ltm_sessions_chat_link.sql"), "utf-8");
  const MEM = fs.readFileSync(path.join(SRC, "memory-repository.ts"), "utf-8");
  const SCHEMA = fs.readFileSync(path.join(SRC, "..", "shared", "ltm-schema.ts"), "utf-8");
  const ROUTES = fs.readFileSync(path.join(SRC, "routes.ts"), "utf-8");

  it("migration adds chat_session_id column + UNIQUE index", () => {
    expect(/ALTER TABLE sessions\s+ADD COLUMN IF NOT EXISTS chat_session_id text/i.test(MIG)).toBe(true);
    expect(/CREATE UNIQUE INDEX IF NOT EXISTS sessions_chat_session_id_idx[\s\S]*chat_session_id/i.test(MIG)).toBe(true);
  });

  it("drizzle schema declares chatSessionId on sessions table", () => {
    // Anchor to the sessions pgTable block so we don't accidentally match
    // something unrelated.
    const block = SCHEMA.split('pgTable("sessions"')[1]?.split('export const')[0] ?? "";
    expect(/chatSessionId\s*:\s*text\(\s*['"]chat_session_id['"]\s*\)/.test(block)).toBe(true);
    expect(/chatSessionIdIdx\s*:\s*index\(['"]sessions_chat_session_id_idx['"]\)/.test(block)).toBe(true);
  });

  it("MemoryService.ensureChatLtmSession is implemented and find-or-create", () => {
    // Multi-line tolerant signature match
    expect(/async\s+ensureChatLtmSession\s*\([\s\S]{0,200}\)\s*:\s*Promise<string\s*\|\s*null>/.test(MEM)).toBe(true);
    // Body anchors: scope to the method body and assert SELECT-by-chat_session_id + INSERT-with-chatSessionId.
    const body = MEM.split("async ensureChatLtmSession")[1]?.split("\n  /**")[0] ?? "";
    expect(body.includes("findFirst")).toBe(true);
    expect(body.includes("chatSessionId")).toBe(true);
    expect(body.includes("db.insert(ltmSchema.sessions)")).toBe(true);
  });

  it("ensureChatLtmSession degrades to null on DB error (chat must not break)", () => {
    const body = MEM.split("async ensureChatLtmSession")[1]?.split("\n  /**")[0] ?? "";
    expect(body.includes("} catch")).toBe(true);
    expect(body.includes("return null")).toBe(true);
  });

  it("chat-stream calls ensureChatLtmSession after ensureLtmUser + resolveProjectForChat", () => {
    expect(/ensureLtmUser[\s\S]{0,300}resolveProjectForChat[\s\S]{0,300}ensureChatLtmSession/.test(ROUTES)).toBe(true);
  });

  it("chat-stream passes the LTM UUID (not the text sessionId) as memorySessionId", () => {
    expect(/memorySessionId\s*:\s*_ltmSessionUuid\s*\?\?\s*undefined/.test(ROUTES)).toBe(true);
  });

  it("chat-stream does NOT pass the text sessionId straight through as memorySessionId", () => {
    // Smoking-gun negative: the old broken pattern must not reappear.
    expect(/memorySessionId\s*:\s*_resolvedSessionId/.test(ROUTES)).toBe(false);
  });
});
