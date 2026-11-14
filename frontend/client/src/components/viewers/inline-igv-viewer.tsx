/**
 * In-product IGV.js track viewer for BAM (+BAI) and indexed VCF.gz (+TBI/CSI).
 * Lazy-loads `igv` — same pattern as density / 3dmol. Does NOT use Interactive Tools.
 */
import { useEffect, useRef, useState } from "react";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  genomicsTrackKind,
  siblingIndexPathCandidates,
  stepFileUrl,
  type GenomicsTrackKind,
} from "./genomics-index";

export type InlineIgvViewerProps = {
  /** Primary track URL (authenticated step-file or signed S3 URL). Must support Range. */
  url: string;
  /** File name or path used to pick track type + default index candidates. */
  name: string;
  /**
   * For run step-file previews: resolve sibling .bai/.tbi via the same run.
   * Omit for signed URLs — pass indexUrl instead when known.
   */
  runId?: string;
  /** Absolute path of the primary file within the run (for sibling index lookup). */
  filePath?: string;
  /** Explicit index URL when already known (Data Hub signed URL for .bai). */
  indexUrl?: string;
  /** Optional download fallback href. */
  downloadUrl?: string;
  className?: string;
};

async function probeOk(url: string, signal: AbortSignal): Promise<boolean> {
  try {
    const head = await fetch(url, { method: "HEAD", credentials: "include", signal });
    if (head.ok || head.status === 206) return true;
    // Some proxies reject HEAD — try a tiny Range GET.
    const get = await fetch(url, {
      credentials: "include",
      signal,
      headers: { Range: "bytes=0-0" },
    });
    return get.ok || get.status === 206;
  } catch {
    return false;
  }
}

async function resolveIndexUrl(
  props: InlineIgvViewerProps,
  kind: GenomicsTrackKind,
  signal: AbortSignal,
): Promise<string | null> {
  if (props.indexUrl) {
    return (await probeOk(props.indexUrl, signal)) ? props.indexUrl : null;
  }
  if (props.runId && props.filePath) {
    for (const cand of siblingIndexPathCandidates(props.filePath, kind)) {
      const u = stepFileUrl(props.runId, cand);
      if (await probeOk(u, signal)) return u;
    }
  }
  // Signed URL conventions: append .bai / .tbi to the object URL path when possible.
  try {
    const u = new URL(props.url, window.location.origin);
    const path = u.pathname;
    const tries =
      kind === "bam"
        ? [`${path}.bai`, path.replace(/\.bam$/i, ".bai")]
        : [`${path}.tbi`, `${path}.csi`];
    for (const p of tries) {
      const next = new URL(props.url, window.location.origin);
      next.pathname = p;
      if (await probeOk(next.toString(), signal)) return next.toString();
    }
  } catch {
    /* relative URL without origin — skip */
  }
  return null;
}

export function InlineIgvViewer(props: InlineIgvViewerProps) {
  const hostRef = useRef<HTMLDivElement>(null);
  const browserRef = useRef<{ remove?: () => void } | null>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "no-index" | "error">("loading");
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    const abort = new AbortController();
    let cancelled = false;

    (async () => {
      setStatus("loading");
      setMessage(null);
      const kind = genomicsTrackKind(props.name) || genomicsTrackKind(props.filePath || "");
      if (!kind) {
        setStatus("error");
        setMessage("Unsupported genomics format for IGV (need .bam or .vcf.gz).");
        return;
      }
      const indexURL = await resolveIndexUrl(props, kind, abort.signal);
      if (cancelled || abort.signal.aborted) return;
      if (!indexURL) {
        setStatus("no-index");
        setMessage(
          kind === "bam"
            ? "BAM index (.bai) not found next to this file. Download the BAM and index, or re-run with indexing."
            : "VCF index (.tbi / .csi) not found next to this file.",
        );
        return;
      }

      try {
        const igvMod: any = await import("igv");
        const createBrowser =
          igvMod?.default?.createBrowser ?? igvMod?.createBrowser;
        if (typeof createBrowser !== "function") {
          throw new Error("igv.createBrowser not available");
        }
        if (cancelled || !hostRef.current) return;
        // Tear down any prior browser in this slot.
        try {
          browserRef.current?.remove?.();
        } catch {
          /* ignore */
        }
        browserRef.current = null;
        hostRef.current.innerHTML = "";

        const track =
          kind === "bam"
            ? {
                type: "alignment",
                format: "bam",
                name: props.name,
                url: props.url,
                indexURL,
              }
            : {
                type: "variant",
                format: "vcf",
                name: props.name,
                url: props.url,
                indexURL,
              };

        // Hosted hg38 reference — contig names that match GRCh38 load; others still
        // show the track list with an honest locus warning inside IGV.
        const browser = await createBrowser(hostRef.current, {
          genome: "hg38",
          locus: "chr1:1-1000",
          showChromosomeWidget: true,
          showTrackLabels: true,
          tracks: [track],
        });
        if (cancelled) {
          try {
            browser?.remove?.();
          } catch {
            /* ignore */
          }
          return;
        }
        browserRef.current = browser;
        setStatus("ready");
      } catch (e: any) {
        if (cancelled) return;
        setStatus("error");
        setMessage(e?.message || "Failed to load IGV viewer");
      }
    })();

    return () => {
      cancelled = true;
      abort.abort();
      try {
        browserRef.current?.remove?.();
      } catch {
        /* ignore */
      }
      browserRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- remount when track identity changes
  }, [props.url, props.name, props.runId, props.filePath, props.indexUrl]);

  const dl = props.downloadUrl || props.url;

  return (
    <div className={props.className} data-testid="inline-igv-viewer">
      {status === "loading" && (
        <div className="flex items-center gap-2 text-xs text-muted-foreground p-3" data-testid="inline-igv-loading">
          <Loader2 className="h-3.5 w-3.5 animate-spin" />
          Loading genome browser…
        </div>
      )}
      {(status === "no-index" || status === "error") && (
        <div className="rounded border p-3 text-xs space-y-2" data-testid="inline-igv-fallback" role="status">
          <p className="text-muted-foreground">{message}</p>
          <Button asChild variant="outline" size="sm" className="h-7 text-xs">
            <a href={dl} download={props.name} rel="noopener">
              Download file
            </a>
          </Button>
        </div>
      )}
      <div
        ref={hostRef}
        className="w-full min-h-[280px] max-h-[480px] overflow-auto rounded border bg-background"
        data-testid="inline-igv-host"
        style={{ display: status === "ready" || status === "loading" ? "block" : "none" }}
      />
    </div>
  );
}
