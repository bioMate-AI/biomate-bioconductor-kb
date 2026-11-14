/**
 * Regression gate: e2e specs must not ignore shell BASE_URL via BIOMATE_URL-only.
 * See docs/20261113_E2E_BASE_URL_PRECEDENCE_AUDIT.md.
 */
import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const e2eDir = path.join(__dirname, "..", "e2e");

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (
        ent.name === "node_modules" ||
        ent.name === "test-results" ||
        ent.name === "reports" ||
        ent.name === "execshots"
      ) {
        continue;
      }
      out.push(...walk(p));
    } else if (
      /\.(ts|tsx|mjs|js)$/.test(ent.name) &&
      !ent.name.startsWith("_e2e-base-url") &&
      !ent.name.includes(".archived")
    ) {
      out.push(p);
    }
  }
  return out;
}

describe("e2e BASE_URL class", () => {
  it("no spec assigns target URL from BIOMATE_URL alone", () => {
    const offenders: string[] = [];
    for (const file of walk(e2eDir)) {
      const text = fs.readFileSync(file, "utf8");
      for (const [i, line] of text.split("\n").entries()) {
        const t = line.trim();
        if (t.startsWith("//") || t.startsWith("*") || t.startsWith("/*")) continue;
        if (/process\.env\.BIOMATE_URL\s*\|\|/.test(line)) {
          offenders.push(`${path.relative(e2eDir, file)}:${i + 1}: ${t.slice(0, 120)}`);
        }
      }
    }
    expect(offenders, offenders.join("\n")).toEqual([]);
  });
});
