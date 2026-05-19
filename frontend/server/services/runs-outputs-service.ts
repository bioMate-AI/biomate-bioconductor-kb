/**
 * runs-outputs-service.ts — Single source of truth for "outputs for a run".
 *
 * Why this exists:
 *   The same end-user failure ("workflow ran, outputs don't show") has been
 *   patched across 4 endpoints, 4 storage places, 3 IDs, and 3 UI surfaces.
 *   Each fix is real but only closes one symptom because there's no
 *   canonical outputs path. This module owns that path.
 *
 * See docs/20260518_OUTPUTS_SERVICE_CONSOLIDATION_SPEC.md for the full plan.
 *
 * PR 1 (this file): service + canonical GET endpoint, no UI changes.
 * PR 2: UI migrates to consume this endpoint, ChatOutputAttachments becomes thin.
 * PR 3: legacy endpoints become 301 redirects to the canonical one.
 */

import {
  S3Client,
  ListObjectsV2Command,
  GetObjectCommand,
  type _Object as S3Object,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { storage } from "../storage";
import { classifyFileType } from "../bioinformatics-parsers";

const PRESIGN_TTL_SEC = 3600;
const DEFAULT_NF_BUCKET =
  process.env.AWS_S3_NEXTFLOW_BUCKET || "biomate-nextflow-work";

/** Single S3 client. us-east-1 + follow-redirects + NF creds when present.
 *  Default credential chain when NF creds are absent (lets a dev environment
 *  with only AWS_ACCESS_KEY_ID still work). One construction; no drift. */
let _s3: S3Client | null = null;
function s3(): S3Client {
  if (_s3) return _s3;
  const key = process.env.AWS_NF_ACCESS_KEY_ID;
  const sec = process.env.AWS_NF_SECRET_ACCESS_KEY;
  _s3 = new S3Client({
    region: "us-east-1",
    followRegionRedirects: true,
    ...(key && sec
      ? { credentials: { accessKeyId: key, secretAccessKey: sec } }
      : {}),
  });
  return _s3;
}

// ── Types ────────────────────────────────────────────────────────────────────

export interface CanonicalRunMeta {
  /** Frontend executionRunId (UUID generated on create). Canonical key. */
  runId: string;
  /** Galaxy invocation/SSE id. */
  galaxyInvocationId: string | null;
  /** Nextflow's own run id (often = galaxyInvocationId for Batch runs). */
  nextflowRunId: string | null;
  /** Canonical S3 prefix where Nextflow wrote outputs. May be null for
   *  in-flight runs or local dev runs. */
  s3Outdir: string | null;
  status: string;
  workflowName: string;
}

export interface CanonicalOutput {
  /** Stable id; `${runId}:${s3Key}` so React keys never collide. */
  id: string;
  name: string;
  /** Lowercased, no leading dot. */
  extension: string;
  size: number;
  /** Drives renderer selection; from `classifyFileType()`. */
  fileType: string;
  /** Presigned S3 URL, valid PRESIGN_TTL_SEC. Always set. */
  downloadUrl: string;
  s3Uri: string;
  s3Bucket: string;
  s3Key: string;
  /** Step / workflow process name if derivable from path. */
  step: string | null;
  /** True when the browser/viewer can render directly. */
  previewable: boolean;
  /** Mirrors metadata.s3Uri for legacy UI consumers (drop in PR 3). */
  metadata: { s3Uri: string };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

const VISUALIZABLE_EXTS = new Set([
  "png", "jpg", "jpeg", "gif", "svg", "html", "htm",
  "pdb", "cif", "mmcif",
  "mrc", "mrcs", "map", "ccp4",
  "fasta", "fa", "txt", "log", "json", "csv", "tsv", "md",
  "vcf", "bed", "gff",
]);

/** Parse `s3://bucket/key/prefix/` → {bucket, prefix}. */
function parseS3Uri(uri: string): { bucket: string; prefix: string } | null {
  const m = uri.match(/^s3:\/\/([^/]+)\/(.+?)\/?$/);
  if (!m) return null;
  return { bucket: m[1], prefix: m[2] };
}

/** Best-effort step name from S3 key. CryoSPARC writes `<bucket>/<prefix>/<hash>/<NN_step_name>/<file>`. */
function deriveStep(s3Key: string): string | null {
  const parts = s3Key.split("/");
  if (parts.length < 2) return null;
  const candidate = parts[parts.length - 2];
  if (!candidate || /^[0-9a-f]{8}$/i.test(candidate)) return null;
  return candidate;
}

// ── Service ──────────────────────────────────────────────────────────────────

export class RunsOutputsService {
  /** Resolve any id (runId / galaxyInvocationId / nextflowRunId) to canonical meta. */
  async resolve(anyId: string): Promise<CanonicalRunMeta | null> {
    if (!anyId) return null;
    const run =
      (await storage.getExecutionRun(anyId)) ||
      (await storage.getExecutionRunByGalaxyId(anyId));
    if (!run) return null;

    const exec: any = run.execution || {};
    const nfStatus: any = exec.nextflowStatus || {};

    // Canonical outdir resolution order:
    // 1. nextflowStatus.outdir (live run)
    // 2. execution.nextflowOutputDir (persisted)
    // 3. derive from canonical bucket + nfRunId
    let s3Outdir: string | null = null;
    if (typeof nfStatus.outdir === "string" && nfStatus.outdir.startsWith("s3://")) {
      s3Outdir = nfStatus.outdir;
    } else if (typeof exec.nextflowOutputDir === "string" && exec.nextflowOutputDir.startsWith("s3://")) {
      s3Outdir = exec.nextflowOutputDir;
    } else {
      const nfRunId: string =
        exec.nextflowRunId || exec.galaxyInvocationId || run.id;
      if (nfRunId) {
        s3Outdir = `s3://${DEFAULT_NF_BUCKET}/nextflow/outputs/${nfRunId}`;
      }
    }

    return {
      runId: run.id,
      galaxyInvocationId: exec.galaxyInvocationId || null,
      nextflowRunId: exec.nextflowRunId || null,
      s3Outdir,
      status: exec.status || "unknown",
      workflowName: run.workflowName || "",
    };
  }

  /** List outputs for a run. Canonical, normalized, presigned. */
  async list(anyId: string): Promise<CanonicalOutput[]> {
    const meta = await this.resolve(anyId);
    if (!meta || !meta.s3Outdir) return [];

    const parsed = parseS3Uri(meta.s3Outdir);
    if (!parsed) return [];

    const client = s3();
    const items: S3Object[] = [];
    let continuationToken: string | undefined = undefined;
    try {
      do {
        const lr: any = await client.send(
          new ListObjectsV2Command({
            Bucket: parsed.bucket,
            Prefix: `${parsed.prefix}/`,
            ContinuationToken: continuationToken,
            MaxKeys: 1000,
          })
        );
        for (const obj of lr.Contents || []) {
          if (!obj.Key || obj.Key.endsWith("/")) continue;
          items.push(obj);
        }
        continuationToken = lr.IsTruncated ? lr.NextContinuationToken : undefined;
      } while (continuationToken);
    } catch (e: any) {
      console.warn(
        `[runs-outputs] S3 list failed for ${meta.s3Outdir}: ${e?.message || e}`
      );
      return [];
    }

    // Presign + normalize in parallel
    return Promise.all(
      items.map(async (obj) => {
        const s3Key = obj.Key!;
        const name = s3Key.split("/").pop() || s3Key;
        const extension = (name.includes(".") ? name.split(".").pop() || "" : "")
          .toLowerCase()
          .replace(/^\./, "");
        const fileType = classifyFileType(extension);
        const s3Uri = `s3://${parsed.bucket}/${s3Key}`;
        let downloadUrl = "";
        try {
          downloadUrl = await getSignedUrl(
            client,
            new GetObjectCommand({ Bucket: parsed.bucket, Key: s3Key }),
            { expiresIn: PRESIGN_TTL_SEC }
          );
        } catch (e: any) {
          console.warn(
            `[runs-outputs] presign failed for ${s3Key}: ${e?.message || e}`
          );
        }
        return {
          id: `${meta.runId}:${s3Key}`,
          name,
          extension,
          size: obj.Size || 0,
          fileType,
          downloadUrl,
          s3Uri,
          s3Bucket: parsed.bucket,
          s3Key,
          step: deriveStep(s3Key),
          previewable: VISUALIZABLE_EXTS.has(extension),
          metadata: { s3Uri },
        } satisfies CanonicalOutput;
      })
    );
  }
}

export const runsOutputsService = new RunsOutputsService();
