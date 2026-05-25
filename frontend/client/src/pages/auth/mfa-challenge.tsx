import { useState } from "react";
import { useLocation } from "wouter";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Shield } from "lucide-react";
import { useAuth } from "@/contexts/auth-context";

export default function MfaChallengePage() {
  const [, setLocation] = useLocation();
  const { checkAuth } = useAuth() as any;

  const [challengeToken] = useState<string>(() => {
    try { return (history.state as any)?.challengeToken ?? ""; } catch { return ""; }
  });

  const [token, setToken] = useState("");
  const [useRecovery, setUseRecovery] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [remaining, setRemaining] = useState<number | null>(null);

  async function submit() {
    if (!challengeToken) { setError("Session expired. Please log in again."); return; }
    const code = useRecovery ? token.trim() : token.replace(/\D/g, "");
    if (!useRecovery && code.length !== 6) return;

    setLoading(true); setError("");
    try {
      const res = await fetch("/api/auth/mfa/challenge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ challengeToken, token: code }),
      });
      const data = await res.json();

      if (res.status === 429) { setError(data.error); return; }
      if (!res.ok) {
        if (data.remainingAttempts !== undefined) setRemaining(data.remainingAttempts);
        setError(data.error || "Invalid code");
        setToken("");
        return;
      }

      if (data.token) {
        document.cookie = `biomate_token=${data.token}; path=/; SameSite=Strict`;
      }
      if (checkAuth) await checkAuth();
      setLocation("/");
    } catch {
      setError("Network error. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="text-center space-y-2">
          <div className="flex justify-center mb-1">
            <img src="/biomate-logo.png" alt="BioMate" className="h-10 w-auto" />
          </div>
          <div className="flex justify-center">
            <Shield className="h-8 w-8 text-primary" />
          </div>
          <h1 className="text-2xl font-semibold">Two-factor authentication</h1>
          <p className="text-sm text-muted-foreground">
            {useRecovery
              ? "Enter one of your recovery codes."
              : "Enter the 6-digit code from your authenticator app."}
          </p>
        </div>

        {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}
        {remaining !== null && remaining > 0 && (
          <Alert>
            <AlertDescription>
              {remaining} attempt{remaining !== 1 ? "s" : ""} remaining before lockout.
            </AlertDescription>
          </Alert>
        )}

        <div className="space-y-4">
          {useRecovery ? (
            <Input
              placeholder="XXXXX-XXXXX"
              value={token}
              onChange={e => { setToken(e.target.value.toUpperCase()); setError(""); }}
              onKeyDown={e => e.key === "Enter" && submit()}
              className="text-center font-mono tracking-widest"
              data-testid="recovery-code-input"
              autoFocus
            />
          ) : (
            <Input
              placeholder="000000"
              maxLength={6}
              value={token}
              onChange={e => {
                const v = e.target.value.replace(/\D/g, "");
                setToken(v); setError("");
                if (v.length === 6) setTimeout(submit, 80);
              }}
              className="text-center text-2xl tracking-[0.5em] font-mono"
              data-testid="totp-input"
              autoFocus
            />
          )}

          <Button
            onClick={submit}
            disabled={loading || (!useRecovery && token.length !== 6) || (useRecovery && !token.trim())}
            className="w-full"
            data-testid="mfa-submit"
          >
            {loading ? "Verifying..." : "Continue"}
          </Button>

          <div className="text-center space-y-2">
            <button
              className="block w-full text-xs text-muted-foreground underline"
              onClick={() => { setUseRecovery(v => !v); setToken(""); setError(""); }}
              data-testid="toggle-recovery"
            >
              {useRecovery ? "Use authenticator app instead" : "Use a recovery code instead"}
            </button>
            <button
              className="block w-full text-xs text-muted-foreground underline"
              onClick={() => setLocation("/login")}
            >
              Back to login
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
