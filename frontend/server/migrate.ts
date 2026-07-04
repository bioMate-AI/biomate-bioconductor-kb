/**
 * Boot-time SQL migration runner.
 *
 * Applies any `frontend/migrations/*.sql` files that haven't been recorded in
 * the `_migrations` tracking table, in lexicographic filename order. Runs
 * before `registerRoutes` in `index.ts` so handlers never see a missing table.
 *
 * Idempotent: safe to call on every boot. Aborts the process on first failure
 * — a half-applied schema is worse than a refused start.
 *
 * Filed as Gap A in docs/20260603_PHASE1_GAPS_NEXTFLOW_DOWNLOAD_AND_MIGRATION_RUNNER.md
 * (Phase 1 of the async-job-queue subsystem shipped `0012_download_jobs.sql`
 * but `sync_to_dev.sh` didn't apply it; the missing table crashed the worker).
 */
import { createHash } from "crypto";
import { readFileSync, readdirSync } from "fs";
import { join } from "path";
import { pool } from "./db";

const MIGRATIONS_DIR = join(process.cwd(), "migrations");

interface AppliedRow {
  filename: string;
  sha256: string;
}

export async function applyPendingMigrations(): Promise<{ applied: string[]; skipped: string[] }> {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS _migrations (
        filename   text PRIMARY KEY,
        sha256     text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now()
      )
    `);

    const { rows: appliedRows } = await client.query<AppliedRow>(
      "SELECT filename, sha256 FROM _migrations",
    );
    const applied = new Map(appliedRows.map((r) => [r.filename, r.sha256]));

    let files: string[];
    try {
      files = readdirSync(MIGRATIONS_DIR)
        .filter((f) => f.endsWith(".sql") && !f.startsWith("._"))
        .sort();
    } catch (err: any) {
      if (err?.code === "ENOENT") {
        console.warn(`[migrate] ${MIGRATIONS_DIR} not found — skipping`);
        return { applied: [], skipped: [] };
      }
      throw err;
    }

    const newlyApplied: string[] = [];
    const skipped: string[] = [];

    for (const filename of files) {
      const sql = readFileSync(join(MIGRATIONS_DIR, filename), "utf8");
      const sha = createHash("sha256").update(sql).digest("hex");

      const prior = applied.get(filename);
      if (prior) {
        if (prior !== sha) {
          // Hash drift = someone edited a file post-apply. Loud warn but
          // don't abort — re-applying could be destructive. Human must
          // resolve: either revert the file or write a new migration.
          console.warn(
            `[migrate] WARNING: ${filename} hash changed since it was applied ` +
              `(was ${prior.slice(0, 8)}, now ${sha.slice(0, 8)}). Not re-applying. ` +
              `Write a new migration if the change is intentional.`,
          );
        }
        skipped.push(filename);
        continue;
      }

      console.log(`[migrate] applying ${filename}…`);
      try {
        await client.query("BEGIN");
        await client.query(sql);
        await client.query("INSERT INTO _migrations (filename, sha256) VALUES ($1, $2)", [
          filename,
          sha,
        ]);
        await client.query("COMMIT");
        newlyApplied.push(filename);
      } catch (err: any) {
        await client.query("ROLLBACK").catch(() => {});
        // "Already-applied but untracked" recovery: when a migration fails
        // with PG codes 42P07 (relation already exists), 42710 (duplicate
        // object), or 42P06 (duplicate schema), the underlying schema
        // change is already present — most commonly because the migration
        // was applied via a side-channel (sync_to_dev's psql loop) before
        // the _migrations tracking table existed. Record it as applied so
        // subsequent boots don't keep re-running and failing on it.
        const code = err?.code;
        const ALREADY_APPLIED_CODES = new Set(["42P07", "42710", "42P06"]);
        if (ALREADY_APPLIED_CODES.has(code)) {
          console.warn(
            `[migrate] ${filename} already applied out-of-band (PG ${code}: ${err?.message?.slice(0, 100)}). Recording as applied.`
          );
          try {
            await client.query(
              "INSERT INTO _migrations (filename, sha256) VALUES ($1, $2) ON CONFLICT (filename) DO NOTHING",
              [filename, sha],
            );
            skipped.push(filename);
            continue;
          } catch (recordErr) {
            console.error(`[migrate] failed to record ${filename} as already-applied:`, recordErr);
            // Fall through to fatal abort if even the tracking insert fails.
          }
        }
        console.error(`[migrate] FATAL: ${filename} failed:`, err);
        throw err;
      }
    }

    if (newlyApplied.length > 0) {
      console.log(`[migrate] applied ${newlyApplied.length} migration(s): ${newlyApplied.join(", ")}`);
    } else {
      console.log(`[migrate] no pending migrations (${skipped.length} already applied)`);
    }
    return { applied: newlyApplied, skipped };
  } finally {
    client.release();
  }
}
