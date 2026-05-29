/**
 * useUiFlavor — feature flag gate for the in-progress v2 chrome.
 *
 * Read order:
 *   1. `?ui=v1` or `?ui=v2` URL parameter (also persisted to localStorage)
 *   2. localStorage `biomate_ui` value
 *   3. default `'v1'`
 *
 * v2 is loaded behind this flag while we incrementally merge the
 * frontend/research_agent_v2/ sandbox into the live app. See
 * docs/20260527_V2_INCREMENTAL_MERGE_PLAN.md.
 */
import { useEffect, useState } from "react";

export type UiFlavor = "v1" | "v2";

const STORAGE_KEY = "biomate_ui";

function readInitial(): UiFlavor {
  if (typeof window === "undefined") return "v1";
  try {
    const fromUrl = new URLSearchParams(window.location.search).get("ui");
    if (fromUrl === "v1" || fromUrl === "v2") return fromUrl;
    const fromStorage = window.localStorage.getItem(STORAGE_KEY);
    return fromStorage === "v2" ? "v2" : "v1";
  } catch {
    return "v1";
  }
}

export function useUiFlavor(): UiFlavor {
  const [flavor] = useState<UiFlavor>(readInitial);

  // Persist URL choice so subsequent navigations remember the flavor.
  useEffect(() => {
    if (typeof window === "undefined") return;
    try {
      const fromUrl = new URLSearchParams(window.location.search).get("ui");
      if (fromUrl === "v1" || fromUrl === "v2") {
        window.localStorage.setItem(STORAGE_KEY, fromUrl);
      }
    } catch {
      // ignore — privacy-mode browsers may block localStorage
    }
  }, []);

  return flavor;
}
