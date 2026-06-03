/**
 * MfaEnrollScreen — set up real RFC 6238 TOTP for 21 CFR Part 11 e-sign.
 *
 * Closes S2 from docs/20260603_IND_MODULE_HONEST_AUDIT.md. Before this,
 * the sign overlay asked for an "authenticator code" but the dev backend
 * accepted any 6 digits. After this, the user can scan a QR (Google
 * Authenticator / 1Password / Authy), confirm the code once, and from
 * then on the sign endpoint uses pyotp.TOTP(secret).verify().
 */
import { useEffect, useState } from "react";
import { X } from "lucide-react";
import { enrollMfa, confirmMfa, resetMfa, getMfaStatus } from "@/lib/ind-report-api";

export function MfaEnrollScreen({
  onClose, onEnrolled,
}: {
  onClose: () => void;
  onEnrolled?: () => void;
}) {
  const [step, setStep] = useState<"loading" | "qr" | "done">("loading");
  const [secret, setSecret] = useState<string>("");
  const [qrB64, setQrB64] = useState<string>("");
  const [code, setCode] = useState<string>("");
  const [err, setErr] = useState<string>("");
  const [busy, setBusy] = useState(false);
  const [alreadyEnrolled, setAlreadyEnrolled] = useState(false);

  // On mount: check whether the user is already enrolled. If yes, jump to
  // the "done" view with a Reset option.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const s = await getMfaStatus();
        if (cancelled) return;
        if (s.enrolled) {
          setAlreadyEnrolled(true);
          setStep("done");
          return;
        }
        // Not enrolled yet → request a fresh secret.
        const e = await enrollMfa();
        if (cancelled) return;
        setSecret(e.secret);
        setQrB64(e.qr_png_base64);
        setStep("qr");
      } catch (ex: any) {
        if (!cancelled) {
          setErr(String(ex?.message ?? ex));
          setStep("qr"); // show error UI
        }
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const submit = async () => {
    setBusy(true);
    setErr("");
    try {
      await confirmMfa(code);
      setStep("done");
      onEnrolled?.();
    } catch (ex: any) {
      setErr(String(ex?.message ?? ex));
    } finally {
      setBusy(false);
    }
  };

  const reset = async () => {
    setBusy(true);
    try {
      await resetMfa();
      const e = await enrollMfa();
      setSecret(e.secret);
      setQrB64(e.qr_png_base64);
      setStep("qr");
      setCode("");
      setAlreadyEnrolled(false);
      setErr("");
    } catch (ex: any) {
      setErr(String(ex?.message ?? ex));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      className="modal-backdrop"
      onClick={busy ? undefined : onClose}
      style={{
        position: "fixed", inset: 0, zIndex: 70,
        background: "rgba(0,0,0,0.45)",
        display: "flex", alignItems: "center", justifyContent: "center",
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          background: "var(--ind-bg, white)",
          border: "1px solid var(--ind-border, #e5e7eb)",
          borderRadius: 8,
          width: "min(440px, 92vw)",
          padding: 22, position: "relative",
          boxShadow: "0 10px 40px rgba(0,0,0,0.18)",
        }}
      >
        <button
          onClick={onClose}
          disabled={busy}
          style={{
            position: "absolute", top: 12, right: 12,
            background: "none", border: "none", cursor: "pointer",
            color: "var(--ind-text-dim)",
          }}
        >
          <X size={18} />
        </button>

        {step === "loading" && <div style={{ padding: 20 }}>Loading…</div>}

        {step === "qr" && (
          <>
            <h3 style={{ marginTop: 0 }}>Set up your authenticator app</h3>
            <p style={{ fontSize: 13, color: "var(--ind-text-muted)" }}>
              Scan the QR with Google Authenticator, 1Password, Authy, or any
              other RFC 6238 TOTP app. After enrollment, every IND signature
              requires a fresh 6-digit code from your app.
            </p>
            {qrB64 ? (
              <img
                src={`data:image/png;base64,${qrB64}`}
                alt="MFA QR code"
                style={{
                  display: "block", margin: "12px auto",
                  width: 200, height: 200,
                  border: "1px solid var(--ind-border, #e5e7eb)",
                  background: "white",
                }}
              />
            ) : (
              <div style={{ padding: 20 }}>Generating QR…</div>
            )}
            <div style={{ fontSize: 12, color: "var(--ind-text-muted)" }}>
              Or enter manually:
            </div>
            <div
              className="mono"
              style={{
                marginTop: 4, padding: 6,
                background: "var(--ind-surface, #f9fafb)",
                borderRadius: 4, fontSize: 13, wordBreak: "break-all",
              }}
            >
              {secret || "(not yet generated)"}
            </div>
            <label style={{ display: "block", marginTop: 14, fontSize: 12 }}>
              6-digit code from your app:
              <input
                type="text"
                inputMode="numeric"
                pattern="[0-9]{6}"
                maxLength={6}
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
                style={{
                  width: "100%", marginTop: 4, padding: "8px 10px",
                  fontSize: 18, letterSpacing: 4, textAlign: "center",
                  border: "1px solid var(--ind-border, #d1d5db)", borderRadius: 4,
                }}
                autoFocus
              />
            </label>
            {err && (
              <div style={{ color: "var(--ind-err)", fontSize: 13, marginTop: 8 }}>
                {err}
              </div>
            )}
            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 14 }}>
              <button className="ind-btn" onClick={onClose} disabled={busy}>
                Cancel
              </button>
              <button
                className="ind-btn primary"
                onClick={submit}
                disabled={busy || code.length !== 6}
              >
                {busy ? "Verifying…" : "Verify & enable"}
              </button>
            </div>
          </>
        )}

        {step === "done" && (
          <>
            <h3 style={{ marginTop: 0 }}>
              {alreadyEnrolled ? "MFA already enabled" : "MFA enabled ✓"}
            </h3>
            <p style={{ fontSize: 13, color: "var(--ind-text-muted)" }}>
              {alreadyEnrolled
                ? "You're already enrolled. Use Reset to enroll a new authenticator (the old one stops working immediately)."
                : "You're all set. Future signatures will require a fresh 6-digit code from your authenticator app."}
            </p>
            {err && (
              <div style={{ color: "var(--ind-err)", fontSize: 13, marginTop: 8 }}>
                {err}
              </div>
            )}
            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 14 }}>
              {alreadyEnrolled && (
                <button className="ind-btn" onClick={reset} disabled={busy}>
                  Reset
                </button>
              )}
              <button className="ind-btn primary" onClick={onClose} disabled={busy}>
                Close
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
