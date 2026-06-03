/**
 * ArtifactStore — pluggable persistence for finished job artifacts.
 *
 * Phase 0 of the async job-queue subsystem ships only the LocalArtifactStore
 * backend. S3ArtifactStore is intentionally deferred to Phase 1+ when the
 * first real call site (download-all-zip) needs it for cloud deploys.
 *
 * See docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md §9.
 */

import * as fs from "fs";
import * as path from "path";

export interface ArtifactReadResult {
  stream: NodeJS.ReadableStream;
  bytes: number;
  contentType: string;
}

export interface ArtifactRedirectResult {
  redirect: string;
}

export interface ArtifactWriteHandle {
  /** Stream the executor pipes the artifact into. */
  stream: NodeJS.WritableStream;
  /** Final URI (`file://…` or `s3://…`) once the writer closes successfully. */
  uri: string;
  /** Number of bytes written, valid only after the writer closes. */
  bytesWritten: () => number;
}

export interface ArtifactStore {
  open(jobId: string, contentType: string): ArtifactWriteHandle;
  read(jobId: string): ArtifactReadResult | ArtifactRedirectResult | null;
  delete(jobId: string): void;
}

function defaultDir(): string {
  return process.env.BIOMATE_ARTIFACT_DIR || "/tmp/biomate_artifacts";
}

/** Tiny .meta file sidecar so we can recover contentType without a DB hit. */
interface MetaFile {
  contentType: string;
}

export class LocalArtifactStore implements ArtifactStore {
  private readonly dir: string;
  private readonly contentTypes = new Map<string, string>();
  private readonly bytesWritten = new Map<string, number>();

  constructor(dir?: string) {
    this.dir = dir ?? defaultDir();
    fs.mkdirSync(this.dir, { recursive: true });
  }

  private artifactPath(jobId: string): string {
    return path.join(this.dir, jobId);
  }

  private metaPath(jobId: string): string {
    return path.join(this.dir, `${jobId}.meta.json`);
  }

  open(jobId: string, contentType: string): ArtifactWriteHandle {
    const filePath = this.artifactPath(jobId);
    const stream = fs.createWriteStream(filePath);
    let written = 0;
    stream.on("close", () => {
      this.bytesWritten.set(jobId, written);
      try {
        fs.writeFileSync(this.metaPath(jobId), JSON.stringify({ contentType } satisfies MetaFile));
      } catch {
        /* meta sidecar is best-effort */
      }
    });
    // Track byte count without consuming the stream.
    const origWrite = stream.write.bind(stream);
    (stream as any).write = (chunk: any, ...args: any[]) => {
      if (chunk) {
        written += Buffer.isBuffer(chunk) ? chunk.length : Buffer.byteLength(String(chunk));
      }
      return (origWrite as any)(chunk, ...args);
    };
    this.contentTypes.set(jobId, contentType);
    return {
      stream,
      uri: `file://${filePath}`,
      bytesWritten: () => this.bytesWritten.get(jobId) ?? written,
    };
  }

  read(jobId: string): ArtifactReadResult | null {
    const filePath = this.artifactPath(jobId);
    if (!fs.existsSync(filePath)) return null;
    const stat = fs.statSync(filePath);
    let contentType = this.contentTypes.get(jobId);
    if (!contentType) {
      try {
        const meta = JSON.parse(fs.readFileSync(this.metaPath(jobId), "utf8")) as MetaFile;
        contentType = meta.contentType;
      } catch {
        contentType = "application/octet-stream";
      }
    }
    return {
      stream: fs.createReadStream(filePath),
      bytes: stat.size,
      contentType,
    };
  }

  delete(jobId: string): void {
    for (const p of [this.artifactPath(jobId), this.metaPath(jobId)]) {
      try {
        fs.unlinkSync(p);
      } catch {
        /* ignore */
      }
    }
    this.contentTypes.delete(jobId);
    this.bytesWritten.delete(jobId);
  }
}

// Phase 0 default. Phase 1+ may swap this based on env (S3ArtifactStore).
let _defaultStore: ArtifactStore | null = null;
export function getArtifactStore(): ArtifactStore {
  if (!_defaultStore) _defaultStore = new LocalArtifactStore();
  return _defaultStore;
}
export function setArtifactStore(store: ArtifactStore): void {
  _defaultStore = store;
}
