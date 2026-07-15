import { useEffect, useState } from "react"
import { useParams, useLocation } from "wouter"
import { useAuth } from "@/contexts/auth-context"
import { Loader2, Users, LogIn } from "lucide-react"
import { Button } from "@/components/ui/button"

interface ShareInfo {
  projectId: string
  projectName: string
  description?: string
  role: string
}

export default function JoinProjectPage() {
  const { token } = useParams<{ token: string }>()
  const [, navigate] = useLocation()
  const { user, isLoading: authLoading } = useAuth()

  const [info, setInfo] = useState<ShareInfo | null>(null)
  const [fetchError, setFetchError] = useState<string | null>(null)
  const [joining, setJoining] = useState(false)
  const [joinError, setJoinError] = useState<string | null>(null)

  // Fetch project preview (public endpoint — no auth needed)
  useEffect(() => {
    if (!token) return
    fetch(`/api/join/${encodeURIComponent(token)}`)
      .then(r => r.json())
      .then(data => {
        if (data.error) setFetchError(data.error)
        else setInfo(data)
      })
      .catch(() => setFetchError("Failed to load share link"))
  }, [token])

  // Once we know user is logged in and share info is loaded, auto-join
  useEffect(() => {
    if (authLoading || !user || !info || joining) return
    handleJoin()
  }, [authLoading, user, info])

  async function handleJoin() {
    if (!token) return
    setJoining(true)
    setJoinError(null)
    try {
      const r = await fetch(`/api/join/${encodeURIComponent(token)}/accept`, {
        method: "POST",
        credentials: "include",
      })
      const data = await r.json()
      if (!r.ok) {
        setJoinError(data.error ?? "Failed to join project")
        setJoining(false)
        return
      }
      // Redirect to the project page
      navigate(`/project/${data.projectId}`)
    } catch {
      setJoinError("Network error — please try again")
      setJoining(false)
    }
  }

  // ── Loading states ───────────────────────────────────────────────────────────
  if (!token || fetchError) {
    return (
      <div style={styles.page}>
        <div style={styles.card}>
          <div style={styles.iconWrap}>
            <Users size={28} style={{ color: "#2a5582" }} />
          </div>
          <h1 style={styles.title}>Invalid share link</h1>
          <p style={styles.sub}>
            {fetchError ?? "This link is invalid or has been revoked."}
          </p>
          <Button variant="outline" onClick={() => navigate("/")} style={{ marginTop: 20 }}>
            Go to BioMate
          </Button>
        </div>
      </div>
    )
  }

  if (!info) {
    return (
      <div style={styles.page}>
        <div style={styles.card}>
          <Loader2 size={24} style={{ animation: "spin 1s linear infinite", color: "#2a5582" }} />
          <p style={{ ...styles.sub, marginTop: 12 }}>Loading…</p>
        </div>
      </div>
    )
  }

  // ── Logged-in: show joining spinner ─────────────────────────────────────────
  if (!authLoading && user) {
    return (
      <div style={styles.page}>
        <div style={styles.card}>
          <div style={styles.iconWrap}>
            <Users size={28} style={{ color: "#2a5582" }} />
          </div>
          <h1 style={styles.title}>{info.projectName}</h1>
          {info.description && <p style={styles.sub}>{info.description}</p>}
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 20, color: "#4d6175" }}>
            <Loader2 size={16} style={{ animation: "spin 1s linear infinite" }} />
            <span style={{ fontSize: 14 }}>
              {joining ? "Joining project…" : joinError ? "" : "Preparing…"}
            </span>
          </div>
          {joinError && (
            <div style={{ marginTop: 16 }}>
              <p style={{ color: "#c0392b", fontSize: 13, marginBottom: 12 }}>{joinError}</p>
              <Button onClick={handleJoin} disabled={joining}>
                Try again
              </Button>
            </div>
          )}
        </div>
      </div>
    )
  }

  // ── Not logged in: show project info + auth options ──────────────────────────
  const nextPath = `/join/${token}`
  return (
    <div style={styles.page}>
      <div style={styles.card}>
        <div style={styles.iconWrap}>
          <Users size={28} style={{ color: "#2a5582" }} />
        </div>
        <p style={styles.eyebrow}>You've been invited to a project</p>
        <h1 style={styles.title}>{info.projectName}</h1>
        {info.description && <p style={styles.sub}>{info.description}</p>}
        <p style={styles.roleNote}>
          You'll join as <strong>{info.role}</strong>
        </p>

        <div style={styles.actions}>
          <Button
            style={styles.primaryBtn}
            onClick={() => navigate(`/login?next=${encodeURIComponent(nextPath)}`)}
          >
            <LogIn size={15} style={{ marginRight: 6 }} />
            Sign in to join
          </Button>
          <Button
            variant="outline"
            style={styles.secondaryBtn}
            onClick={() => navigate(`/register?next=${encodeURIComponent(nextPath)}`)}
          >
            Create account &amp; join
          </Button>
        </div>

        <p style={styles.hint}>
          Already a member? Sign in and you'll be redirected automatically.
        </p>
      </div>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  page: {
    minHeight: "100vh",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    background: "#f6efde",
    padding: "24px 16px",
  },
  card: {
    background: "#faf6ee",
    border: "1px solid #d3c7a8",
    borderRadius: 16,
    padding: "40px 36px",
    maxWidth: 440,
    width: "100%",
    textAlign: "center",
    boxShadow: "0 2px 12px rgba(20,40,58,0.08)",
  },
  iconWrap: {
    width: 56,
    height: 56,
    borderRadius: "50%",
    background: "#e8f0f7",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    margin: "0 auto 18px",
  },
  eyebrow: {
    fontSize: 12,
    fontWeight: 600,
    letterSpacing: "0.06em",
    textTransform: "uppercase" as const,
    color: "#4d6175",
    marginBottom: 6,
  },
  title: {
    fontSize: 22,
    fontWeight: 700,
    color: "#14283a",
    margin: "0 0 10px",
  },
  sub: {
    fontSize: 14,
    color: "#4d6175",
    lineHeight: 1.5,
    margin: "0 0 6px",
  },
  roleNote: {
    fontSize: 13,
    color: "#4d6175",
    margin: "12px 0 0",
  },
  actions: {
    display: "flex",
    flexDirection: "column" as const,
    gap: 10,
    marginTop: 24,
  },
  primaryBtn: {
    background: "#2a5582",
    color: "#fff",
    height: 42,
    fontSize: 14,
    fontWeight: 600,
    borderRadius: 8,
  },
  secondaryBtn: {
    height: 42,
    fontSize: 14,
    borderRadius: 8,
  },
  hint: {
    fontSize: 12,
    color: "#8a9aaa",
    marginTop: 18,
    lineHeight: 1.4,
  },
}
