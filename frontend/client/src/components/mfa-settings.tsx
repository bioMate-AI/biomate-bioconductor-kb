import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Shield, ShieldCheck, ShieldOff, Copy, Download, Eye, EyeOff } from "lucide-react";
import { useToast } from "@/hooks/use-toast";

interface MfaStatus {
  enabled: boolean;
  verifiedAt: string | null;
  remainingRecoveryCodes: number;
}

export function MfaSettings() {
  const { toast } = useToast();
  const [status, setStatus] = useState<MfaStatus | null>(null);
  const [phase, setPhase] = useState<"idle" | "setup" | "verify" | "disable" | "codes">("idle");
  const [qrCode, setQrCode] = useState("");
  const [manualKey, setManualKey] = useState("");
  const [totpInput, setTotpInput] = useState("");
  const [password, setPassword] = useState("");
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([]);
  const [showManualKey, setShowManualKey] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => { fetchStatus(); }, []);

  async function fetchStatus() {
    try {
      const res = await fetch("/api/auth/mfa/status", { credentials: "include" });
      if (res.ok) setStatus(await res.json());
    } catch {}
  }

  async function startSetup() {
    setLoading(true); setError("");
    try {
      const res = await fetch("/api/auth/mfa/setup", { method: "POST", credentials: "include" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setQrCode(data.qrCode);
      setManualKey(data.manualKey);
      setPhase("setup");
    } catch (e: any) { setError(e.message); }
    finally { setLoading(false); }
  }

  async function verifySetup() {
    if (totpInput.length !== 6) return;
    setLoading(true); setError("");
    try {
      const res = await fetch("/api/auth/mfa/verify-setup", {
        method: "POST", credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token: totpInput }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setRecoveryCodes(data.recoveryCodes);
      setPhase("codes");
      await fetchStatus();
    } catch (e: any) { setError(e.message); setTotpInput(""); }
    finally { setLoading(false); }
  }

  async function disableMfa() {
    setLoading(true); setError("");
    try {
      const res = await fetch("/api/auth/mfa/disable", {
        method: "POST", credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password, token: totpInput }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      toast({ title: "MFA disabled" });
      setPhase("idle"); setPassword(""); setTotpInput("");
      await fetchStatus();
    } catch (e: any) { setError(e.message); }
    finally { setLoading(false); }
  }

  function copyRecoveryCodes() {
    navigator.clipboard.writeText(recoveryCodes.join("\n"));
    toast({ title: "Recovery codes copied" });
  }

  function downloadRecoveryCodes() {
    const blob = new Blob([recoveryCodes.join("\n")], { type: "text/plain" });
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob);
    a.download = "biomate-recovery-codes.txt"; a.click();
  }

  if (!status) return <div className="text-sm text-muted-foreground">Loading...</div>;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          {status.enabled
            ? <ShieldCheck className="h-5 w-5 text-green-500" />
            : <ShieldOff className="h-5 w-5 text-muted-foreground" />}
          <div>
            <p className="text-sm font-medium">Two-factor authentication</p>
            <p className="text-xs text-muted-foreground">
              {status.enabled
                ? `Enabled since ${new Date(status.verifiedAt!).toLocaleDateString()} · ${status.remainingRecoveryCodes} recovery codes remaining`
                : "Add an extra layer of security to your account"}
            </p>
          </div>
        </div>
        <Badge variant={status.enabled ? "default" : "secondary"}>
          {status.enabled ? "Enabled" : "Disabled"}
        </Badge>
      </div>

      {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

      {/* ── Idle state ── */}
      {phase === "idle" && !status.enabled && (
        <Button onClick={startSetup} disabled={loading} size="sm" className="gap-2">
          <Shield className="h-4 w-4" /> Enable two-factor authentication
        </Button>
      )}

      {phase === "idle" && status.enabled && (
        <Button variant="outline" onClick={() => setPhase("disable")} size="sm" className="gap-2 text-destructive border-destructive hover:bg-destructive/5">
          <ShieldOff className="h-4 w-4" /> Disable two-factor authentication
        </Button>
      )}

      {/* ── Setup: show QR code ── */}
      {phase === "setup" && (
        <div className="space-y-4 rounded-lg border p-4">
          <p className="text-sm font-medium">1. Scan this QR code with your authenticator app</p>
          <p className="text-xs text-muted-foreground">
            Use Google Authenticator, Authy, 1Password, or any TOTP-compatible app.
          </p>
          {qrCode && <img src={qrCode} alt="MFA QR code" className="w-40 h-40 rounded border" />}
          <div>
            <button
              className="text-xs text-muted-foreground underline"
              onClick={() => setShowManualKey(v => !v)}
            >
              {showManualKey ? "Hide" : "Show"} manual entry key
            </button>
            {showManualKey && (
              <code className="block mt-1 text-xs bg-muted px-2 py-1 rounded font-mono break-all">
                {manualKey}
              </code>
            )}
          </div>
          <div className="space-y-2">
            <p className="text-sm font-medium">2. Enter the 6-digit code to confirm</p>
            <div className="flex gap-2">
              <Input
                placeholder="000000"
                maxLength={6}
                value={totpInput}
                onChange={e => { setTotpInput(e.target.value.replace(/\D/g, "")); setError(""); }}
                onKeyDown={e => e.key === "Enter" && verifySetup()}
                className="w-32 text-center text-lg tracking-widest font-mono"
              />
              <Button onClick={verifySetup} disabled={loading || totpInput.length !== 6}>
                {loading ? "Verifying..." : "Verify"}
              </Button>
              <Button variant="ghost" onClick={() => { setPhase("idle"); setTotpInput(""); }}>
                Cancel
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* ── Recovery codes — shown once ── */}
      {phase === "codes" && (
        <div className="space-y-3 rounded-lg border border-green-200 bg-green-50 dark:bg-green-950/20 p-4">
          <div className="flex items-start gap-2">
            <ShieldCheck className="h-4 w-4 text-green-600 mt-0.5 shrink-0" />
            <p className="text-sm font-medium text-green-800 dark:text-green-200">
              MFA enabled! Save your recovery codes now — they won't be shown again.
            </p>
          </div>
          <p className="text-xs text-muted-foreground">
            If you lose access to your authenticator app, use one of these codes to log in.
            Each code can only be used once.
          </p>
          <div className="grid grid-cols-2 gap-1">
            {recoveryCodes.map(code => (
              <code key={code} className="text-xs font-mono bg-background border rounded px-2 py-1 text-center">
                {code}
              </code>
            ))}
          </div>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={copyRecoveryCodes} className="gap-1">
              <Copy className="h-3 w-3" /> Copy
            </Button>
            <Button variant="outline" size="sm" onClick={downloadRecoveryCodes} className="gap-1">
              <Download className="h-3 w-3" /> Download
            </Button>
            <Button size="sm" onClick={() => setPhase("idle")}>Done</Button>
          </div>
        </div>
      )}

      {/* ── Disable MFA ── */}
      {phase === "disable" && (
        <div className="space-y-3 rounded-lg border p-4">
          <p className="text-sm font-medium">Confirm identity to disable MFA</p>
          <div className="space-y-2">
            <Label className="text-xs">Password</Label>
            <Input
              type="password" placeholder="Your password"
              value={password}
              onChange={e => { setPassword(e.target.value); setError(""); }}
            />
          </div>
          <div className="space-y-2">
            <Label className="text-xs">Authenticator code</Label>
            <Input
              placeholder="000000" maxLength={6}
              value={totpInput}
              onChange={e => { setTotpInput(e.target.value.replace(/\D/g, "")); setError(""); }}
              className="w-32 text-center text-lg tracking-widest font-mono"
            />
          </div>
          <div className="flex gap-2">
            <Button
              variant="destructive" size="sm"
              onClick={disableMfa}
              disabled={loading || !password || totpInput.length !== 6}
            >
              {loading ? "Disabling..." : "Disable MFA"}
            </Button>
            <Button variant="ghost" size="sm" onClick={() => { setPhase("idle"); setPassword(""); setTotpInput(""); }}>
              Cancel
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
