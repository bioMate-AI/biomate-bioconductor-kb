import { useEffect, useState } from "react";

export type UiFlavor = "v1" | "v2";

/**
 * Independent flag for previewing only the new v2 after-run 7-tab report
 * while keeping the v1 chrome (chat-with-artifacts + nextflow-workflow-viewer).
 *
 * Lets users see the redesigned report on real runs without switching the
 * whole platform to the v2 shell. Toggle:
 *   - URL param: ?afterrun=v2 / ?afterrun=v1
 *   - persistent: localStorage.biomate_afterrun = 'v2'
 */
const AFTERRUN_KEY = "biomate_afterrun";

export function useAfterRunFlavor(): UiFlavor {
  const [flavor] = useState<UiFlavor>(() => {
    if (typeof window === "undefined") return "v1";
    try {
      const fromUrl = new URLSearchParams(window.location.search).get("afterrun");
      if (fromUrl === "v1" || fromUrl === "v2") return fromUrl;
      const fromStorage = window.localStorage.getItem(AFTERRUN_KEY);
      return fromStorage === "v2" ? "v2" : "v1";
    } catch {
      return "v1";
    }
  });

  useEffect(() => {
    if (typeof window === "undefined") return;
    try {
      const fromUrl = new URLSearchParams(window.location.search).get("afterrun");
      if (fromUrl === "v1" || fromUrl === "v2") {
        window.localStorage.setItem(AFTERRUN_KEY, fromUrl);
      }
    } catch {
      // ignore
    }
  }, []);

  return flavor;
}
