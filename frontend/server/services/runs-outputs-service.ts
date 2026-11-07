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
import {
  buildManifest,
  readManifest,
  entryToCanonical,
  isTerminalStatus,
  type OutputManifest,
} from "./runs-outputs-manifest";

const PRESIGN_TTL_SEC = 3600;
const DEFAULT_NF_BUCKET =
  process.env.AWS_S3_NEXTFLOW_BUCKET || "biomate-nextflow-work";

/** Single S3 client. us-east-1 + follow-redirects + NF creds when present.
 *  On-prem MinIO: uses S3_ENDPOINT_URL + forcePathStyle (no AWS region redirect).
 *  Default credential chain when NF creds are absent (lets a dev environment
 *  with only AWS_ACCESS_KEY_ID still work). One construction; no drift. */
let _s3: S3Client | null = null;
function s3(): S3Client {
  if (_s3) return _s3;
  const key = process.env.AWS_NF_ACCESS_KEY_ID;
  const sec = process.env.AWS_NF_SECRET_ACCESS_KEY;
  const endpointUrl = process.env.S3_ENDPOINT_URL;
  _s3 = new S3Client(endpointUrl ? {
    endpoint: endpointUrl,
    region: "us-east-1",
    forcePathStyle: true,
    credentials: {
      accessKeyId: key || process.env.AWS_ACCESS_KEY_ID || "",
      secretAccessKey: sec || process.env.AWS_SECRET_ACCESS_KEY || "",
    },
  } : {
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
  /** When the run started (Date or ISO string). Used by the
   *  status-reconcile-on-running gate to avoid false-upgrading runs that
   *  just submitted within the typical AWS Batch cold-start window. */
  startedAt: Date | string | null;
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
      startedAt: exec.startedAt || null,
      workflowName: run.workflowName || "",
    };
  }

  /** List outputs for a run. Canonical, normalized, presigned. */
  /**
   * Persist a manifest of a terminal run's outputs into its (DB-backed)
   * executionJson, so later reads never depend on re-deriving the S3 prefix or
   * on a wiped in-memory store. The single writer for the output manifest (L1a).
   */
  async registerOutputs(anyId: string, outputs: CanonicalOutput[]): Promise<void> {
    if (!outputs.length) return;
    const run =
      (await storage.getExecutionRun(anyId)) ||
      (await storage.getExecutionRunByGalaxyId(anyId));
    if (!run) return;
    const exec: any = (run as any).execution || {};
    const manifest = buildManifest(outputs, new Date().toISOString());
    try {
      await storage.updateExecutionRun(run.id, {
        execution: { ...exec, outputManifest: manifest },
      } as any);
    } catch (e: any) {
      console.warn(`[runs-outputs] registerOutputs persist failed for ${run.id}: ${e?.message || e}`);
    }
  }

  /** Re-presign the stable manifest entries into full CanonicalOutputs. */
  private async fromManifest(runId: string, manifest: OutputManifest): Promise<CanonicalOutput[]> {
    const client = s3();
    return Promise.all(
      manifest.entries.map(async (entry) => {
        let downloadUrl = "";
        try {
          downloadUrl = await getSignedUrl(
            client,
            new GetObjectCommand({ Bucket: entry.s3Bucket, Key: entry.s3Key }),
            { expiresIn: PRESIGN_TTL_SEC },
          );
        } catch (e: any) {
          console.warn(`[runs-outputs] manifest presign failed for ${entry.s3Key}: ${e?.message || e}`);
        }
        return entryToCanonical(entry, runId, downloadUrl);
      }),
    );
  }

  async list(anyId: string): Promise<CanonicalOutput[]> {
    const meta = await this.resolve(anyId);
    if (!meta) return [];

    // Manifest-first: a terminal run that was listed once has its stable output
    // set persisted in executionJson — rebuild from there (survives restarts and
    // never re-derives the S3 prefix). Falls through to a live listing when no
    // manifest exists yet (in-flight runs, or runs registered before this shipped).
    const runForManifest =
      (await storage.getExecutionRun(meta.runId)) ||
      (await storage.getExecutionRunByGalaxyId(meta.runId));
    const manifest = readManifest((runForManifest as any)?.execution);
    if (manifest) {
      return this.fromManifest(meta.runId, manifest);
    }

    const client = s3();
    const items: S3Object[] = [];
    // Prefix listing (only when a prefix is derivable). NEVER early-return on an
    // empty/absent prefix — the reliable-source recovery below must still run for
    // runs whose s3Outdir can't be derived (the exact 0-outputs case).
    const parsed = meta.s3Outdir ? parseS3Uri(meta.s3Outdir) : null;
    if (parsed) {
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
      }
    }

    // Task #16 fallback: when publishDir never ran (Nextflow JVM died mid-run
    // — container restart, worker recycle, OOM), output files are stranded in
    // s3://<bucket>/nextflow/work/<domain>/<nfRunId>/<hash>/<file>. Harvest
    // them so users see real outputs instead of an empty list. Derive the
    // work prefix by translating ".../outputs/<domain>/<hash>" →
    // ".../work/<domain>/<nfRunId>/". Skip Nextflow control files (.command.*,
    // .exitcode, etc.) — they're not user outputs.
    if (items.length === 0 && parsed) {
      const m = parsed.prefix.match(/^(.*)\/outputs\/([^/]+)\/([^/]+)$/);
      const nfRunId = meta.nextflowRunId || meta.galaxyInvocationId || meta.runId;
      if (m && nfRunId) {
        const workPrefix = `${m[1]}/work/${m[2]}/${nfRunId}/`;
        let workCt: string | undefined = undefined;
        try {
          do {
            const lr: any = await client.send(
              new ListObjectsV2Command({
                Bucket: parsed.bucket,
                Prefix: workPrefix,
                ContinuationToken: workCt,
                MaxKeys: 1000,
              })
            );
            for (const obj of lr.Contents || []) {
              if (!obj.Key || obj.Key.endsWith("/")) continue;
              const name = obj.Key.split("/").pop() || "";
              if (name.startsWith(".")) continue; // skip .command.*, .exitcode, etc.
              items.push(obj);
            }
            workCt = lr.IsTruncated ? lr.NextContinuationToken : undefined;
          } while (workCt);
          if (items.length > 0) {
            console.info(
              `[runs-outputs] publishDir gap recovery: harvested ${items.length} files from work/ for run ${meta.runId}`
            );
            // Status upgrade for this case is now handled by the unified
            // reconcile block below (after both outputs/ and work/ paths).
          }
        } catch (e: any) {
          console.warn(
            `[runs-outputs] work/ fallback list failed for ${workPrefix}: ${e?.message || e}`
          );
        }
      }
    }

    // Listing artifacts is deliberately read-only. A workflow can publish
    // intermediates before a later process fails; work/ recovery can likewise
    // expose partial task files. Only the executor's explicit terminal signal
    // (exit status, completed trace, or backend status) may change run state.
    // This service must therefore never promote running/failed runs because
    // objects happen to be present in S3.

    // Reliable-source fallback (R0 subsumes R3): the derived prefix can be wrong
    // for a run, but the executor's REPORTED file list
    // (execution.nextflowStatus.s3_output_files, persisted in executionJson) has
    // each output's real s3_uri — possibly in a different bucket than the derived
    // prefix. Seed outputs from it, then register the manifest so future reads are
    // prefix-independent. This is what lets a run whose R0 prefix is wrong (the
    // exact 0-outputs bug) still resolve.
    if (items.length === 0) {
      let reported: any[] =
        (runForManifest as any)?.execution?.nextflowStatus?.s3_output_files ||
        (runForManifest as any)?.execution?.nextflowStatus?.output_files ||
        [];
      if (!reported.length) {
        // Live recovery (R0 subsumes R3's Galaxy-status fallback): when nothing
        // was persisted (no poll landed before a restart), ask the executor for
        // the file list directly. This is the source R3 uses to recover 6
        // outputs where R0's prefix listing sees none.
        const nfRunId = meta.nextflowRunId || meta.galaxyInvocationId || meta.runId;
        if (nfRunId) {
          try {
            const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
            const gResp: any = await fetch(`${galaxyUrl}/api/nextflow/status/${nfRunId}`, {
              signal: AbortSignal.timeout(8000),
            });
            if (gResp.ok) {
              const gData: any = await gResp.json();
              if (Array.isArray(gData?.s3_output_files) && gData.s3_output_files.length) {
                reported = gData.s3_output_files;
              }
            }
          } catch (e: any) {
            console.warn(`[runs-outputs] galaxy status recovery failed: ${e?.message || e}`);
          }
        }
      }
      if (reported.length) {
        const seeded = (
          await Promise.all(
            reported.map(async (f: any): Promise<CanonicalOutput | null> => {
              const s3Uri: string = f?.s3_uri || f?.s3Uri || "";
              const mm = s3Uri.match(/^s3:\/\/([^/]+)\/(.+)$/);
              if (!mm) return null;
              const bucket = mm[1];
              const key = mm[2];
              const name = f?.name || key.split("/").pop() || key;
              const extension = (name.includes(".") ? name.split(".").pop() || "" : "")
                .toLowerCase()
                .replace(/^\./, "");
              let downloadUrl = "";
              try {
                downloadUrl = await getSignedUrl(
                  client,
                  new GetObjectCommand({ Bucket: bucket, Key: key }),
                  { expiresIn: PRESIGN_TTL_SEC },
                );
              } catch (e: any) {
                console.warn(`[runs-outputs] seed presign failed for ${key}: ${e?.message || e}`);
              }
              return {
                id: `${meta.runId}:${key}`,
                name,
                extension,
                size: f?.size || 0,
                fileType: classifyFileType(extension),
                downloadUrl,
                s3Uri,
                s3Bucket: bucket,
                s3Key: key,
                step: deriveStep(key),
                previewable: VISUALIZABLE_EXTS.has(extension),
                metadata: { s3Uri },
              };
            }),
          )
        ).filter((x): x is CanonicalOutput => x !== null);
        if (seeded.length) {
          if (isTerminalStatus(meta.status)) void this.registerOutputs(meta.runId, seeded);
          return seeded;
        }
      }

      // Local executor fallback (on-prem MinIO deployments): when S3 listing and
      // s3_output_files both returned nothing, ask Galaxy for the local filesystem
      // file listing. Galaxy's /api/nextflow/runs/{id}/output_files scans the run's
      // output dir and returns {name, rel_path, local_path, size, download_url}.
      // We proxy the download_url through /api/galaxy-proxy/... so the browser
      // never touches Galaxy directly. Triggers when: (a) S3_ENDPOINT_URL is set
      // (MinIO mode — the outdir is local, not s3://) OR (b) the stored outdir
      // is a local path.
      const _nfOutdir: string = (runForManifest as any)?.execution?.nextflowStatus?.outdir || "";
      const _isLocalExecutor = !!process.env.S3_ENDPOINT_URL || (!_nfOutdir.startsWith("s3://") && _nfOutdir.startsWith("/"));
      const nfRunId2 = meta.nextflowRunId || meta.galaxyInvocationId || meta.runId;
      if (_isLocalExecutor && nfRunId2) {
        try {
          const galaxyUrl2 = process.env.GALAXY_URL || "http://localhost:8081";
          const localResp: any = await fetch(
            `${galaxyUrl2}/api/nextflow/runs/${nfRunId2}/output_files`,
            { signal: AbortSignal.timeout(8000) },
          );
          if (localResp.ok) {
            const localData: any = await localResp.json();
            if (Array.isArray(localData.files) && localData.files.length > 0) {
              const localOutputs: CanonicalOutput[] = localData.files.map((f: any) => {
                const name: string = f.name || f.filename || "";
                const relPath: string = f.rel_path || name;
                const extension = (name.includes(".") ? name.split(".").pop() || "" : "")
                  .toLowerCase()
                  .replace(/^\./, "");
                // Route downloads through the galaxy-proxy so the browser hits Node,
                // not the Galaxy container host directly.
                const downloadUrl = `/api/galaxy-proxy/api/nextflow/outputs/local-download` +
                  `?run_id=${encodeURIComponent(nfRunId2)}&rel_path=${encodeURIComponent(relPath)}`;
                // Use a synthetic s3Uri so the manifest can store these without breaking
                // the manifest schema (bucket/key remain unused for local files).
                const syntheticUri = `local://${nfRunId2}/${relPath}`;
                return {
                  id: `${meta.runId}:${relPath}`,
                  name,
                  extension,
                  size: f.size || 0,
                  fileType: classifyFileType(extension),
                  downloadUrl,
                  s3Uri: syntheticUri,
                  s3Bucket: "",
                  s3Key: relPath,
                  step: deriveStep(relPath),
                  previewable: VISUALIZABLE_EXTS.has(extension),
                  metadata: { s3Uri: syntheticUri },
                } satisfies CanonicalOutput;
              });
              console.info(`[runs-outputs] local executor recovery: ${localOutputs.length} files for run ${meta.runId}`);
              return localOutputs;
            }
          }
        } catch (e: any) {
          console.warn(`[runs-outputs] local executor recovery failed: ${e?.message || e}`);
        }
      }
    }

    // Presign + normalize in parallel. (items is only populated from the prefix
    // listing, so parsed is non-null whenever items is non-empty.)
    if (!parsed) return [];
    const outputs = await Promise.all(
      items.map(async (obj) => {
        const s3Key = obj.Key!;
        const name = s3Key.split("/").pop() || s3Key;
        const extension = (name.includes(".") ? name.split(".").pop() || "" : "")
          .toLowerCase()
          .replace(/^\./, "");
        const fileType = classifyFileType(extension);
        const s3Uri = `s3://${parsed.bucket}/${s3Key}`;
        let downloadUrl = "";
        // On-prem MinIO: presigned URLs embed the internal minio:9000 hostname
        // which browsers cannot reach. Route through the Galaxy streaming proxy
        // (/api/nextflow/outputs/download) which is proxied by Node.js.
        if (process.env.S3_ENDPOINT_URL) {
          downloadUrl = `/api/nextflow/outputs/download?s3_uri=${encodeURIComponent(s3Uri)}&run_id=${encodeURIComponent(meta.runId)}`;
        } else {
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

    // Opportunistic manifest registration (L1a): once a TERMINAL run's outputs
    // are successfully listed from S3, persist them so every future read — any
    // surface, after any restart — rebuilds from the manifest instead of
    // re-deriving the prefix. Fire-and-forget: never blocks or fails the read.
    if (outputs.length && isTerminalStatus(meta.status)) {
      void this.registerOutputs(meta.runId, outputs);
    }

    return outputs;
  }
}

export const runsOutputsService = new RunsOutputsService();
