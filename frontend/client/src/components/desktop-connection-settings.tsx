/**
 * DesktopConnectionSettings — shown inside SettingsDialog on desktop builds.
 * Lets users switch between client mode (cloud) and host mode (local).
 * Renders nothing in the browser.
 */
import { useState, useEffect } from "react";
import { Globe, Server, CheckCircle2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  isDesktop,
  desktopGetServerUrl,
  desktopSetServerUrl,
  desktopGetAppInfo,
  AppInfo,
} from "@/lib/desktop";

const CLOUD_URL = "https://dev-public.biomate.ai";
const LOCAL_URL = "http://localhost:5000";

export function DesktopConnectionSettings() {
  const [serverUrl, setServerUrl] = useState(CLOUD_URL);
  const [customUrl, setCustomUrl] = useState("");
  const [appInfo, setAppInfo] = useState<AppInfo | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (!isDesktop()) return;
    desktopGetServerUrl().then(url => {
      setServerUrl(url || CLOUD_URL);
      if (url && url !== CLOUD_URL && url !== LOCAL_URL) setCustomUrl(url);
    });
    desktopGetAppInfo().then(setAppInfo);
  }, []);

  if (!isDesktop()) return null;

  const mode =
    serverUrl === CLOUD_URL ? "cloud" :
    serverUrl === LOCAL_URL ? "local" : "custom";

  async function applyUrl(url: string) {
    await desktopSetServerUrl(url);
    setServerUrl(url);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
    // Reload so the WebView points to the new server
    window.location.href = url;
  }

  return (
    <div className="space-y-5">
      <div>
        <h3 className="text-sm font-semibold mb-1">Connection Mode</h3>
        <p className="text-xs text-muted-foreground mb-3">
          Desktop v{appInfo?.version} · {appInfo?.platform}
        </p>
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={() => applyUrl(CLOUD_URL)}
            className={`flex flex-col items-start gap-1 rounded-lg border p-4 text-left transition-colors
              ${mode === "cloud"
                ? "border-primary bg-primary/5"
                : "border-border hover:border-primary/40"}`}
          >
            <Globe className="h-5 w-5 text-primary mb-1" />
            <span className="text-sm font-medium">Cloud</span>
            <span className="text-xs text-muted-foreground">dev-public.biomate.ai</span>
          </button>
          <button
            onClick={() => applyUrl(LOCAL_URL)}
            className={`flex flex-col items-start gap-1 rounded-lg border p-4 text-left transition-colors
              ${mode === "local"
                ? "border-primary bg-primary/5"
                : "border-border hover:border-primary/40"}`}
          >
            <Server className="h-5 w-5 text-amber-500 mb-1" />
            <span className="text-sm font-medium">Local</span>
            <span className="text-xs text-muted-foreground">localhost:5000</span>
          </button>
        </div>
      </div>

      <div className="space-y-2">
        <Label className="text-xs">Custom server URL</Label>
        <div className="flex gap-2">
          <Input
            value={customUrl}
            onChange={e => setCustomUrl(e.target.value)}
            placeholder="https://your-biomate-instance.example.com"
            className="text-xs h-8"
          />
          <Button
            size="sm"
            variant="outline"
            className="h-8 px-3 shrink-0"
            disabled={!customUrl}
            onClick={() => customUrl && applyUrl(customUrl)}
          >
            Connect
          </Button>
        </div>
      </div>

      {saved && (
        <div className="flex items-center gap-1.5 text-xs text-green-600">
          <CheckCircle2 className="h-3.5 w-3.5" />
          Saved — reconnecting…
        </div>
      )}
    </div>
  );
}
