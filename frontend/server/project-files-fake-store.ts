/**
 * TEST HARNESS (not imported by the app): an in-memory stand-in for the Postgres tables and the
 * S3 bucket behind the project file routes, for route BEHAVIOUR tests over loopback HTTP
 * (project-files-integrity.test.ts, project-file-rows-upload.test.ts).
 *
 * It interprets exactly the statements project-routes.ts issues against project_files,
 * project_file_versions and project_object_key_reservations, with the semantics that matter
 * for integrity:
 *   - pg_advisory_xact_lock(key) is a real per-key mutex held until COMMIT/ROLLBACK, so
 *     concurrent requests interleave as they would on Postgres;
 *   - ROLLBACK undoes the transaction's writes;
 *   - an UPDATE's `version_no = $n` precondition is honoured (rowCount 0 when it fails).
 * An unrecognised statement touching these tables THROWS, so a query change in the routes
 * cannot silently turn into "0 rows" here.
 */
import { createHash, randomUUID } from "crypto";

export type Row = Record<string, any>;
type Undo = () => void;

export class FakeStore {
  files: Row[] = [];
  versions: Row[] = [];
  reservations = new Map<string, Row>();
  users: Row[] = [];
  members: Row[] = [];
  activity: Row[] = [];
  objects = new Map<string, Buffer>();
  puts: string[] = [];
  deletes: string[] = [];
  presigned: Array<{ key: string; name?: string }> = [];
  /** Delay (ms) inside putObject — lets concurrent requests interleave at the S3 write. */
  putDelayMs = 0;
  private clock = Date.parse("2026-11-01T00:00:00Z");
  private locks = new Map<string, Promise<void>>();

  reset(): void {
    this.files = []; this.versions = []; this.reservations.clear(); this.users = []; this.members = [];
    this.activity = []; this.objects.clear(); this.puts = []; this.deletes = []; this.presigned = [];
    this.putDelayMs = 0;
  }

  /** Strictly increasing timestamps (so "which time belongs to which version" is testable). */
  now(): Date { this.clock += 60_000; return new Date(this.clock); }

  static sha(buf: Buffer | string): string {
    return createHash("sha256").update(buf).digest("hex");
  }

  /** Seed a file row (+ its bytes) the way an upload would have stored it. */
  addFile(f: Partial<Row> & { project_id: string; name: string; s3_key: string }, bytes?: Buffer | string): Row {
    const buf = bytes === undefined ? undefined : Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes, "utf-8");
    if (buf) this.objects.set(f.s3_key, buf);
    const at = this.now();
    const row: Row = {
      id: randomUUID(), user_id: "owner-1", size: buf?.length ?? 0, content_type: "text/csv", source: "upload",
      run_id: null, workflow_name: null, step_name: null, input_context: null,
      content_hash: buf ? FakeStore.sha(buf) : null, version_no: 1, created_at: at,
      version_created_at: at, version_author: f.user_id ?? "owner-1", ...f,
    };
    this.files.push(row);
    return row;
  }

  // ─── S3 ───────────────────────────────────────────────────────────────
  s3 = {
    putObject: async (key: string, body: Buffer) => {
      this.puts.push(key);
      if (this.putDelayMs) await new Promise((r) => setTimeout(r, this.putDelayMs));
      this.objects.set(key, Buffer.from(body));
    },
    getFileSize: async (key: string) => {
      const b = this.objects.get(key);
      if (!b) throw new Error(`NoSuchKey ${key}`);
      return b.length;
    },
    readBuffer: async (key: string, maxBytes: number) => {
      const b = this.objects.get(key);
      if (!b) throw new Error(`NoSuchKey ${key}`);
      return b.subarray(0, maxBytes);
    },
    readTextPrefix: async (key: string, maxBytes = 256 * 1024) => {
      const b = this.objects.get(key);
      if (!b) throw new Error(`NoSuchKey ${key}`);
      return b.subarray(0, maxBytes).toString("utf-8");
    },
    deleteFile: async (key: string) => { this.deletes.push(key); this.objects.delete(key); return true; },
    generatePresignedDownloadUrl: async (key: string, _exp?: number, name?: string) => {
      this.presigned.push({ key, name });
      return `https://s3.test/${key}${name ? `?response-content-disposition=${encodeURIComponent(name)}` : ""}`;
    },
    getBucketName: () => "test-bucket",
  };

  // ─── Postgres ─────────────────────────────────────────────────────────
  pool = {
    query: (text: string, params: any[] = []) => this.exec(text, params, null),
    connect: async () => {
      const tx = { undo: [] as Undo[], held: [] as Array<() => void>, open: false };
      return {
        query: (text: string, params: any[] = []) => this.exec(text, params, tx),
        release: () => { for (const r of tx.held.splice(0)) r(); },
      };
    },
  };

  private async acquire(key: string): Promise<() => void> {
    const prev = this.locks.get(key) ?? Promise.resolve();
    let release!: () => void;
    const mine = new Promise<void>((r) => { release = r; });
    const chained = prev.then(() => mine);
    this.locks.set(key, chained);
    await prev;
    return () => { release(); if (this.locks.get(key) === chained) this.locks.delete(key); };
  }

  private async exec(text: string, p: any[], tx: { undo: Undo[]; held: Array<() => void>; open: boolean } | null): Promise<any> {
    const t = text.replace(/\s+/g, " ").trim();
    const undo = (u: Undo) => { if (tx?.open) tx.undo.push(u); };
    const ok = (rows: Row[] = [], rowCount = rows.length) => ({ rows, rowCount });

    if (/^(CREATE|ALTER)\b/.test(t)) return ok();
    if (t === "BEGIN") { if (tx) { tx.open = true; tx.undo = []; } return ok(); }
    if (t === "COMMIT" || t === "ROLLBACK") {
      if (tx) {
        if (t === "ROLLBACK") for (const u of tx.undo.reverse()) u();
        tx.undo = []; tx.open = false;
        for (const r of tx.held.splice(0)) r();
      }
      return ok();
    }
    if (/pg_advisory_xact_lock/.test(t)) {
      if (!tx) throw new Error("fake: advisory xact lock outside a transaction");
      tx.held.push(await this.acquire(String(p[0])));
      return ok([{}]);
    }
    if (/FROM project_members WHERE project_id/.test(t)) {
      return ok(this.members.filter((m) => m.project_id === p[0] && String(m.user_id) === String(p[1])));
    }
    if (t.startsWith("INSERT INTO project_activity")) {
      this.activity.push({ project_id: p[0], actor: p[1], event_type: p[2], payload: JSON.parse(p[3]) });
      return ok();
    }
    if (/FROM users WHERE id::text = ANY/.test(t)) {
      return ok(this.users.filter((u) => (p[0] as string[]).includes(String(u.id))));
    }

    // project_files reads
    if (/FROM project_files WHERE project_id::text = \$1 AND \(content_hash = \$2 OR name = \$3/.test(t)) {
      const [pid, hash, name, like, anc] = p;
      const prefix = String(like).slice(0, -1).replace(/\\([\\%_])/g, "$1");
      return ok(this.files.filter((f) => f.project_id === pid && (
        (f.content_hash && f.content_hash === hash) || f.name === name || f.name.startsWith(prefix) || (anc as string[]).includes(f.name)
      )).map((f) => ({ ...f })));
    }
    if (/^SELECT .* FROM project_files WHERE id::text = \$1 AND project_id::text = \$2( FOR UPDATE)?$/.test(t)) {
      return ok(this.files.filter((f) => f.id === p[0] && f.project_id === p[1]).map((f) => ({ ...f })));
    }
    if (/^SELECT id::text AS id, name, source FROM project_files WHERE project_id::text = \$1$/.test(t)) {
      return ok(this.files.filter((f) => f.project_id === p[0]).map((f) => ({ id: f.id, name: f.name, source: f.source })));
    }
    if (/^SELECT .* FROM project_files WHERE project_id = \$1 ORDER BY created_at DESC$/.test(t)) {
      return ok(this.files.filter((f) => f.project_id === p[0]).map((f) => ({ ...f })));
    }
    if (/^SELECT name, (s3_key, )?source FROM project_files WHERE project_id::text = \$1/.test(t)) {
      // project-folders.ts folder listings (folder context of the rows reader / folder profile)
      let rows = this.files.filter((f) => f.project_id === p[0]);
      if (/name LIKE \$2/.test(t)) {
        const prefix = String(p[1]).slice(0, -1).replace(/\\([\\%_])/g, "$1");
        rows = rows.filter((f) => f.name.startsWith(prefix));
      }
      if (/position\('\/' in name\) = 0/.test(t)) rows = rows.filter((f) => !f.name.includes("/"));
      return ok(rows.map((f) => ({ name: f.name, s3_key: f.s3_key, source: f.source })));
    }
    if (/^SELECT s3_key FROM project_files WHERE project_id::text = \$1 AND s3_key = ANY/.test(t)) {
      const [pid, cands] = p as [string, string[]];
      const taken = new Set<string>();
      for (const f of this.files) if (f.project_id === pid && cands.includes(f.s3_key)) taken.add(f.s3_key);
      for (const v of this.versions) if (v.project_id === pid && cands.includes(v.s3_key)) taken.add(v.s3_key);
      for (const [k, r] of this.reservations) if (r.project_id === pid && cands.includes(k)) taken.add(k);
      return ok([...taken].map((s3_key) => ({ s3_key })));
    }
    if (/^SELECT s3_key FROM project_files WHERE s3_key = ANY\(\$1::text\[\]\) UNION SELECT s3_key FROM project_file_versions/.test(t)) {
      const keys = p[0] as string[];
      const still = new Set<string>();
      for (const f of this.files) if (keys.includes(f.s3_key)) still.add(f.s3_key);
      for (const v of this.versions) if (keys.includes(v.s3_key)) still.add(v.s3_key);
      return ok([...still].map((s3_key) => ({ s3_key })));
    }

    // project_files writes
    if (t.startsWith("INSERT INTO project_files (project_id, user_id, name, s3_key, size, content_type, source, content_hash, version_created_at, version_author)")) {
      const at = this.now();
      const row: Row = {
        id: randomUUID(), project_id: p[0], user_id: p[1], name: p[2], s3_key: p[3], size: p[4], content_type: p[5],
        source: p[6], content_hash: p[7], run_id: null, workflow_name: null, step_name: null, input_context: null,
        version_no: 1, created_at: at, version_created_at: at, version_author: p[1],
      };
      this.files.push(row);
      undo(() => { this.files = this.files.filter((f) => f !== row); });
      return ok([{ ...row }]);
    }
    const upd = /^UPDATE project_files SET s3_key = \$1, size = \$2, (content_type = \$3, content_hash = \$4|content_hash = \$3), version_no = version_no \+ 1, version_created_at = now\(\), version_author = \$(\d) WHERE id::text = \$(\d) AND version_no = \$(\d) RETURNING/.exec(t);
    if (upd) {
      const withType = upd[1].startsWith("content_type");
      const author = p[Number(upd[2]) - 1], id = p[Number(upd[3]) - 1], base = Number(p[Number(upd[4]) - 1]);
      const f = this.files.find((x) => x.id === id && Number(x.version_no) === base);
      if (!f) return ok([], 0);
      const before = { ...f };
      Object.assign(f, {
        s3_key: p[0], size: p[1], ...(withType ? { content_type: p[2], content_hash: p[3] } : { content_hash: p[2] }),
        version_no: Number(f.version_no) + 1, version_created_at: this.now(), version_author: author,
      });
      undo(() => { Object.assign(f, before); });
      return ok([{ ...f }]);
    }
    if (/^UPDATE project_files f SET name = v.new_name FROM unnest/.test(t)) {
      const [ids, names, pid] = p as [string[], string[], string];
      let n = 0;
      ids.forEach((id, i) => {
        const f = this.files.find((x) => x.id === id && x.project_id === pid);
        if (f) { const old = f.name; f.name = names[i]; n++; undo(() => { f.name = old; }); }
      });
      return ok([], n);
    }
    if (/^DELETE FROM project_files WHERE id::text = \$1 AND project_id::text = \$2$/.test(t)) {
      const gone = this.files.filter((f) => f.id === p[0] && f.project_id === p[1]);
      this.files = this.files.filter((f) => !gone.includes(f));
      undo(() => { this.files.push(...gone); });
      return ok([], gone.length);
    }

    // project_file_versions
    if (t.startsWith("INSERT INTO project_file_versions")) {
      const row: Row = {
        id: randomUUID(), file_id: p[0], project_id: p[1], version_no: p[2], s3_key: p[3], size: p[4], content_type: p[5],
        content_hash: p[6], note: p[7], author: p[8], version_created_at: p[9], version_author: p[10], created_at: this.now(),
      };
      this.versions.push(row);
      undo(() => { this.versions = this.versions.filter((v) => v !== row); });
      return ok();
    }
    if (/^SELECT created_at, author FROM project_file_versions WHERE file_id::text = \$1 AND version_no = \$2/.test(t)) {
      return ok(this.versionRows(p[0], Number(p[1])));
    }
    if (/^SELECT [\w, ]+ FROM project_file_versions WHERE file_id::text = \$1 AND version_no = \$2 ORDER BY created_at ASC LIMIT 1$/.test(t)) {
      return ok(this.versionRows(p[0], Number(p[1])).slice(0, 1));
    }
    if (/^SELECT version_no, size, note, author, created_at, version_created_at, version_author FROM project_file_versions WHERE file_id::text = \$1 ORDER BY version_no DESC, created_at ASC$/.test(t)) {
      return ok(this.versions.filter((v) => v.file_id === p[0])
        .sort((a, b) => b.version_no - a.version_no || +a.created_at - +b.created_at).map((v) => ({ ...v })));
    }
    if (/^DELETE FROM project_file_versions WHERE file_id::text = \$1 AND project_id::text = \$2 RETURNING s3_key$/.test(t)) {
      const gone = this.versions.filter((v) => v.file_id === p[0] && v.project_id === p[1]);
      this.versions = this.versions.filter((v) => !gone.includes(v));
      undo(() => { this.versions.push(...gone); });
      return ok(gone.map((v) => ({ s3_key: v.s3_key })));
    }

    // key reservations
    if (t.startsWith("INSERT INTO project_object_key_reservations")) {
      const prev = this.reservations.get(p[0]);
      this.reservations.set(p[0], { project_id: p[1], created_at: this.now() });
      undo(() => { if (prev) this.reservations.set(p[0], prev); else this.reservations.delete(p[0]); });
      return ok();
    }
    if (/^DELETE FROM project_object_key_reservations WHERE s3_key = \$1$/.test(t)) {
      const prev = this.reservations.get(p[0]);
      this.reservations.delete(p[0]);
      undo(() => { if (prev) this.reservations.set(p[0], prev); });
      return ok([], prev ? 1 : 0);
    }

    if (/project_files|project_file_versions|project_object_key_reservations/.test(t)) {
      throw new Error(`fake store: unhandled statement: ${t}`);
    }
    return ok();
  }

  private versionRows(fileId: string, k: number): Row[] {
    return this.versions.filter((v) => v.file_id === fileId && Number(v.version_no) === k)
      .sort((a, b) => +a.created_at - +b.created_at).map((v) => ({ ...v }));
  }

  /** Every file row and archived version points at bytes whose hash and size match the row. */
  integrityProblems(): string[] {
    const out: string[] = [];
    for (const r of [...this.files, ...this.versions]) {
      const b = this.objects.get(r.s3_key);
      const what = `${r.file_id ? "version" : "file"} ${r.name ?? r.file_id} v${r.version_no} @ ${r.s3_key}`;
      if (!b) { out.push(`${what}: object missing`); continue; }
      if (r.content_hash && FakeStore.sha(b) !== r.content_hash) out.push(`${what}: hash mismatch`);
      if (Number(r.size) !== b.length) out.push(`${what}: size ${r.size} != ${b.length}`);
    }
    return out;
  }
}

/** One shared instance: vi.mock factories import it lazily (they run before module imports). */
export const fakeStore = new FakeStore();
