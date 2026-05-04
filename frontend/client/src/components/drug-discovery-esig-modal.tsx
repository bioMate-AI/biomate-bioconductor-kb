/**
 * Surface 5 — Electronic Signature Modal (21 CFR Part 11 §11.200)
 *
 * Two modes:
 *   "sign"    — sign a specific regulatory action with 6-digit TOTP
 *               POST /api/drug-discovery/{campaignId}/esig/sign
 *   "enroll"  — one-time TOTP enrollment with QR code scan
 *               POST /api/drug-discovery/esig/enroll  → { qr_uri }
 *               POST /api/drug-discovery/esig/enroll/verify
 *
 * Usage:
 *   <DrugDiscoveryEsigModal
 *     mode="sign"
 *     campaignId="cmp-abc123"
 *     userId="alice@biotech.com"
 *     action="EXPORT_CRO_ORDER"
 *     meaning="I approve the synthesis order…"
 *     onSigned={(sigId) => ...}
 *     onClose={() => ...}
 *   />
 */
import { useState, useRef, useEffect, useCallback } from "react"
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { CheckCircle2, Shield, Loader2, AlertTriangle } from "lucide-react"
import { cn } from "@/lib/utils"

// ─────────────────────────────────────────────────────────────────────────────
// 6-digit OTP input
// ─────────────────────────────────────────────────────────────────────────────

type OtpState = "idle" | "checking" | "error" | "success"

interface OtpInputProps {
  state: OtpState
  onComplete: (code: string) => void
}

function OtpInput({ state, onComplete }: OtpInputProps) {
  const [vals, setVals] = useState(["", "", "", "", "", ""])
  const refs = useRef<(HTMLInputElement | null)[]>([])

  // Reset values when state returns to idle (after error retry)
  useEffect(() => {
    if (state === "idle") {
      setVals(["", "", "", "", "", ""])
      refs.current[0]?.focus()
    }
  }, [state])

  const onChange = (i: number, v: string) => {
    if (!/^\d?$/.test(v)) return
    const next = [...vals]
    next[i] = v
    setVals(next)
    if (v && i < 5) refs.current[i + 1]?.focus()
    if (next.every((x) => x !== "")) onComplete(next.join(""))
  }

  const onKey = (i: number, e: React.KeyboardEvent) => {
    if (e.key === "Backspace" && !vals[i] && i > 0) refs.current[i - 1]?.focus()
  }

  useEffect(() => {
    refs.current[0]?.focus()
  }, [])

  return (
    <div className="flex justify-center gap-1.5 my-3">
      {vals.map((v, i) => (
        <input
          key={i}
          ref={(el) => { refs.current[i] = el }}
          value={v}
          onChange={(e) => onChange(i, e.target.value)}
          onKeyDown={(e) => onKey(i, e)}
          disabled={state === "checking" || state === "success"}
          maxLength={1}
          className={cn(
            "w-9 h-11 text-center text-base font-mono border-2 rounded-md bg-background transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500",
            state === "error"   && "border-red-400 bg-red-50 dark:bg-red-950/30",
            state === "success" && "border-green-400 bg-green-50 dark:bg-green-950/30",
            state === "idle"    && "border-muted-foreground/30",
            state === "checking" && "border-muted-foreground/20 opacity-60"
          )}
          inputMode="numeric"
          autoComplete="one-time-code"
          data-testid={`otp-digit-${i}`}
        />
      ))}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface EsigSignProps {
  mode: "sign"
  campaignId: string
  userId: string
  action: string
  actionLabel?: string    // human-readable description of what is being signed
  meaning: string
  // Reviewer credentials — required for IND actions (GENERATE_IND / ASSEMBLE_IND)
  // per 21 CFR Part 11 §11.50 and FDA/EMA AI Guidance Jan 2026
  reviewerTitle?: string
  reviewerCredentials?: string
  reviewScope?: string
  onSigned: (sigId: string) => void
  onClose: () => void
  open: boolean
}

interface EsigEnrollProps {
  mode: "enroll"
  userId: string
  onEnrolled: () => void
  onClose: () => void
  open: boolean
}

export type DrugDiscoveryEsigModalProps = EsigSignProps | EsigEnrollProps

// ─────────────────────────────────────────────────────────────────────────────
// Sign modal
// ─────────────────────────────────────────────────────────────────────────────

const IND_ACTIONS = new Set(["GENERATE_IND", "ASSEMBLE_IND"])

function EsigSignModal({
  campaignId, userId, action, actionLabel, meaning,
  reviewerTitle: initialReviewerTitle,
  reviewerCredentials: initialReviewerCredentials,
  reviewScope: initialReviewScope,
  onSigned, onClose, open
}: Omit<EsigSignProps, "mode">) {
  const [otpState, setOtpState] = useState<OtpState>("idle")
  const [countdown, setCountdown] = useState(30)
  const [errorMsg, setErrorMsg] = useState("")
  const isIndAction = IND_ACTIONS.has(action)
  const [reviewerTitle, setReviewerTitle] = useState(initialReviewerTitle ?? "")
  const [reviewerCredentials, setReviewerCredentials] = useState(initialReviewerCredentials ?? "")
  const [reviewScope, setReviewScope] = useState(
    initialReviewScope ?? (isIndAction ? "§2.6.1–§2.6.5 nonclinical pharmacology and toxicology" : "")
  )

  useEffect(() => {
    if (otpState === "success") return
    const t = setInterval(() => setCountdown((c) => (c <= 1 ? 30 : c - 1)), 1000)
    return () => clearInterval(t)
  }, [otpState])

  const onComplete = useCallback(async (code: string) => {
    setOtpState("checking")
    setErrorMsg("")
    try {
      const body: Record<string, string> = { user_id: userId, action, meaning, totp_token: code }
      if (isIndAction) {
        if (reviewerTitle) body.reviewer_title = reviewerTitle
        if (reviewerCredentials) body.reviewer_credentials = reviewerCredentials
        if (reviewScope) body.review_scope = reviewScope
      }
      const res = await fetch(`/api/drug-discovery/${campaignId}/esig/sign`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail || `HTTP ${res.status}`)
      }
      const data = await res.json()
      setOtpState("success")
      setTimeout(() => onSigned(data.sig_id), 600)
    } catch (e: any) {
      setErrorMsg(e.message || "Invalid code")
      setOtpState("error")
      setTimeout(() => setOtpState("idle"), 1500)
    }
  }, [campaignId, userId, action, meaning, onSigned, isIndAction, reviewerTitle, reviewerCredentials, reviewScope])

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="text-sm">Electronic Signature Required</DialogTitle>
          <DialogDescription className="text-xs font-mono">21 CFR Part 11 §11.200(a)(1)</DialogDescription>
        </DialogHeader>

        {/* Action context */}
        <div className="rounded-md border px-3 py-2.5 text-xs space-y-1.5 bg-muted/30">
          <div>
            <span className="text-muted-foreground">Action:</span>{" "}
            <span className="font-mono">{action}</span>
          </div>
          <div>
            <span className="text-muted-foreground">Campaign:</span>{" "}
            <span className="font-mono">{campaignId}</span>
          </div>
          {actionLabel && (
            <div>
              <span className="text-muted-foreground">Details:</span>{" "}
              {actionLabel}
            </div>
          )}
        </div>

        {/* Meaning */}
        <div>
          <div className="text-xs font-medium text-muted-foreground mb-1">Meaning of signature</div>
          <div className="rounded-md border px-3 py-2.5 text-xs bg-indigo-50 dark:bg-indigo-950/30 text-indigo-800 dark:text-indigo-300 border-indigo-200 leading-relaxed">
            {meaning}
          </div>
          <div className="text-xs text-muted-foreground/70 italic mt-1">
            This meaning is permanently recorded in the audit trail.
          </div>
        </div>

        {/* Reviewer credentials (IND actions only) — 21 CFR Part 11 §11.50 */}
        {isIndAction && (
          <div className="space-y-2 border rounded-md px-3 py-2.5 bg-amber-50/40 dark:bg-amber-950/20 border-amber-200">
            <div className="text-xs font-medium text-amber-800 dark:text-amber-300">
              Reviewer Credentials — FDA/EMA AI Guidance (Jan 2026)
            </div>
            <div className="space-y-1.5">
              <label className="block text-xs text-muted-foreground">Title / Role</label>
              <input
                type="text"
                value={reviewerTitle}
                onChange={(e) => setReviewerTitle(e.target.value)}
                placeholder="e.g. Director, Computational Pharmacology"
                disabled={otpState === "checking" || otpState === "success"}
                className="w-full text-xs border rounded px-2 py-1.5 bg-background focus:outline-none focus:ring-1 focus:ring-blue-500"
                data-testid="esig-reviewer-title"
              />
            </div>
            <div className="space-y-1.5">
              <label className="block text-xs text-muted-foreground">Credentials</label>
              <input
                type="text"
                value={reviewerCredentials}
                onChange={(e) => setReviewerCredentials(e.target.value)}
                placeholder="e.g. PhD Pharmacology, 10 years IND experience"
                disabled={otpState === "checking" || otpState === "success"}
                className="w-full text-xs border rounded px-2 py-1.5 bg-background focus:outline-none focus:ring-1 focus:ring-blue-500"
                data-testid="esig-reviewer-credentials"
              />
            </div>
            <div className="space-y-1.5">
              <label className="block text-xs text-muted-foreground">Review Scope</label>
              <input
                type="text"
                value={reviewScope}
                onChange={(e) => setReviewScope(e.target.value)}
                placeholder="e.g. §2.6.1–§2.6.5 nonclinical pharmacology"
                disabled={otpState === "checking" || otpState === "success"}
                className="w-full text-xs border rounded px-2 py-1.5 bg-background focus:outline-none focus:ring-1 focus:ring-blue-500"
                data-testid="esig-review-scope"
              />
            </div>
            <div className="text-xs text-amber-700/70 dark:text-amber-400/70 italic">
              Optional but recommended for pre-IND submissions. Recorded in the frozen document.
            </div>
          </div>
        )}

        {/* OTP */}
        <div>
          <div className="text-xs text-muted-foreground text-center">
            Enter your 6-digit authenticator code
          </div>
          <OtpInput state={otpState} onComplete={onComplete} />
          <div className={cn(
            "text-xs text-center",
            otpState === "error" ? "text-red-600 dark:text-red-400" : "text-muted-foreground"
          )}>
            {otpState === "error"
              ? (errorMsg || "Invalid code. Try again.")
              : `Code refreshes in ${countdown}s`}
          </div>
        </div>

        {/* Shield note */}
        <div className="text-xs text-muted-foreground/70 flex items-start gap-1.5 leading-relaxed">
          <Shield className="h-3.5 w-3.5 mt-0.5 shrink-0" />
          This signature is uniquely linked to your identity and cannot be reused.
          The audit record will include your user ID, the meaning above, and a SHA-256 hash of this action's payload.
        </div>

        <DialogFooter className="gap-2">
          <Button size="sm" variant="ghost" className="h-7 text-xs" onClick={onClose}>
            Cancel
          </Button>
          <Button
            size="sm"
            className="h-7 text-xs gap-1"
            disabled={otpState === "checking" || otpState === "success"}
            data-testid="esig-sign-button"
          >
            {otpState === "checking" ? (
              <><Loader2 className="h-3 w-3 animate-spin" /> Verifying…</>
            ) : otpState === "success" ? (
              <><CheckCircle2 className="h-3 w-3" /> Signed</>
            ) : (
              <>Sign and Continue</>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Enroll modal
// ─────────────────────────────────────────────────────────────────────────────

function EsigEnrollModal({ userId, onEnrolled, onClose, open }: Omit<EsigEnrollProps, "mode">) {
  const [otpState, setOtpState] = useState<OtpState>("idle")
  const [qrUri, setQrUri] = useState<string | null>(null)
  const [loadingQr, setLoadingQr] = useState(false)
  const [errorMsg, setErrorMsg] = useState("")

  // Fetch QR on open
  useEffect(() => {
    if (!open) return
    setLoadingQr(true)
    fetch("/api/drug-discovery/esig/enroll", {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user_id: userId }),
    })
      .then((r) => r.json())
      .then((data) => setQrUri(data.qr_uri))
      .catch(() => setQrUri(null))
      .finally(() => setLoadingQr(false))
  }, [open, userId])

  const onComplete = useCallback(async (code: string) => {
    setOtpState("checking")
    setErrorMsg("")
    try {
      const res = await fetch("/api/drug-discovery/esig/enroll/verify", {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: userId, totp_token: code }),
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail || `HTTP ${res.status}`)
      }
      setOtpState("success")
      setTimeout(() => onEnrolled(), 600)
    } catch (e: any) {
      setErrorMsg(e.message || "Invalid code")
      setOtpState("error")
      setTimeout(() => setOtpState("idle"), 1500)
    }
  }, [userId, onEnrolled])

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="text-sm">Set Up Electronic Signature</DialogTitle>
          <DialogDescription className="text-xs font-mono">
            21 CFR Part 11 §11.200 — one-time enrollment
          </DialogDescription>
        </DialogHeader>

        <p className="text-xs text-muted-foreground leading-relaxed">
          BioMate uses time-based one-time passwords (TOTP) for electronic signatures. These are
          cryptographically linked to your identity and cannot be reused, as required by
          21 CFR Part 11 §11.200(a)(1).
        </p>

        {/* QR code area */}
        <div className="flex flex-col items-center gap-2">
          {loadingQr ? (
            <div className="w-40 h-40 flex items-center justify-center border rounded-md bg-muted/30">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : qrUri ? (
            <QrDisplay uri={qrUri} />
          ) : (
            <div className="w-40 h-40 flex items-center justify-center border rounded-md bg-muted/30">
              <AlertTriangle className="h-5 w-5 text-muted-foreground" />
            </div>
          )}
          {qrUri && (
            <div className="text-xs text-muted-foreground/70 font-mono text-center break-all max-w-xs">
              {qrUri.slice(0, 60)}…
            </div>
          )}
        </div>

        <ol className="text-xs text-muted-foreground space-y-1 pl-4 list-decimal">
          <li>Install an authenticator app (Google Authenticator, Authy, 1Password).</li>
          <li>Scan the QR code above.</li>
          <li>Enter the 6-digit code from your app:</li>
        </ol>

        <OtpInput state={otpState} onComplete={onComplete} />

        {otpState === "error" && (
          <div className="text-xs text-red-600 dark:text-red-400 text-center">
            {errorMsg || "Invalid code. Try again."}
          </div>
        )}

        <div className="text-xs text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 rounded-md px-3 py-2 leading-relaxed">
          ⚠ If you lose access to your authenticator, contact your system administrator to reset enrollment.
        </div>

        <DialogFooter className="gap-2">
          <Button size="sm" variant="ghost" className="h-7 text-xs" onClick={onClose}>
            Cancel
          </Button>
          <Button
            size="sm"
            className="h-7 text-xs gap-1"
            disabled={otpState !== "idle"}
            data-testid="esig-enroll-button"
          >
            {otpState === "checking" ? (
              <><Loader2 className="h-3 w-3 animate-spin" /> Verifying…</>
            ) : otpState === "success" ? (
              <><CheckCircle2 className="h-3 w-3" /> Enrolled</>
            ) : (
              <>Verify and Enable</>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// QR display — renders via Google Charts API (no npm dep required)
// Falls back to copyable text URI if the image fails to load.
// ─────────────────────────────────────────────────────────────────────────────

function QrDisplay({ uri }: { uri: string }) {
  const [copied, setCopied] = useState(false)
  const [imgError, setImgError] = useState(false)

  const copyUri = () => {
    navigator.clipboard.writeText(uri).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  // Use a QR generation service embedded as an img src.
  // NOTE: This sends the otpauth URI to an external service. In production,
  // replace with a self-hosted QR generator or the `qrcode` npm package.
  const qrSrc = `https://api.qrserver.com/v1/create-qr-code/?size=160x160&data=${encodeURIComponent(uri)}`

  if (imgError) {
    return (
      <div className="w-40 rounded-md border bg-muted/30 px-3 py-4 text-center space-y-2">
        <p className="text-xs text-muted-foreground">QR unavailable — copy URI manually:</p>
        <button
          className="text-xs font-mono text-blue-600 dark:text-blue-400 break-all underline"
          onClick={copyUri}
        >
          {copied ? "Copied!" : uri.slice(0, 40) + "…"}
        </button>
      </div>
    )
  }

  return (
    <div className="border rounded-md overflow-hidden bg-white p-1">
      <img
        src={qrSrc}
        width={160}
        height={160}
        alt="TOTP QR code"
        onError={() => setImgError(true)}
      />
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Public export — dispatches to sign or enroll
// ─────────────────────────────────────────────────────────────────────────────

export function DrugDiscoveryEsigModal(props: DrugDiscoveryEsigModalProps) {
  if (props.mode === "sign") {
    const { mode: _, ...rest } = props
    return <EsigSignModal {...rest} />
  }
  const { mode: _, ...rest } = props
  return <EsigEnrollModal {...rest} />
}
