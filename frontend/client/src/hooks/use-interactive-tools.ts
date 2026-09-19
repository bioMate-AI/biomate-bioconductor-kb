import { useEffect, useState } from "react";

/**
 * Which interactive tools are actually launchable in this deployment. Backed by
 * GET /api/interactive/available, which probes the Galaxy toolbox. Used to hide
 * "Open in RStudio/Jupyter/CellxGene" buttons that would otherwise 400 because
 * the tool isn't provisioned — an honest "not available" beats a dead button.
 *
 * Availability is static per environment, so the result is cached module-wide;
 * the first hook mount does one fetch, the rest read the cache instantly.
 */
export type InteractiveToolKey = "jupyter" | "rstudio" | "cellxgene";
export interface InteractiveToolsAvailability {
  available: boolean;
  tools: Record<InteractiveToolKey, boolean>;
}

const FAIL_CLOSED: InteractiveToolsAvailability = {
  available: false,
  tools: { jupyter: false, rstudio: false, cellxgene: false },
};

let cached: InteractiveToolsAvailability | null = null;
let inflight: Promise<InteractiveToolsAvailability> | null = null;

function load(): Promise<InteractiveToolsAvailability> {
  if (inflight) return inflight;
  inflight = fetch("/api/interactive/available", { credentials: "include" })
    .then((r) => (r.ok ? r.json() : FAIL_CLOSED))
    .then((d: any): InteractiveToolsAvailability => ({
      available: !!d?.available,
      tools: {
        jupyter: !!d?.tools?.jupyter,
        rstudio: !!d?.tools?.rstudio,
        cellxgene: !!d?.tools?.cellxgene,
      },
    }))
    .catch(() => FAIL_CLOSED)
    .then((d) => {
      cached = d;
      return d;
    });
  return inflight;
}

/** Test-only: clear the module-level cache so each test starts fresh. */
export function __resetInteractiveToolsCache(): void {
  cached = null;
  inflight = null;
}

export function useInteractiveToolsAvailable(): {
  data: InteractiveToolsAvailability | null;
  loading: boolean;
} {
  const [data, setData] = useState<InteractiveToolsAvailability | null>(cached);
  const [loading, setLoading] = useState(!cached);

  useEffect(() => {
    if (cached) {
      setData(cached);
      setLoading(false);
      return;
    }
    let alive = true;
    load().then((d) => {
      if (!alive) return;
      setData(d);
      setLoading(false);
    });
    return () => {
      alive = false;
    };
  }, []);

  return { data, loading };
}
