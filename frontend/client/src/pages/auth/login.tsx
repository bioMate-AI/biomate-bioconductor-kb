import { useState } from "react"
import { useLocation } from "wouter"
import { useAuth } from "@/contexts/auth-context"
import { Loader2, Eye, EyeOff } from "lucide-react"
import { useToast } from "@/hooks/use-toast"

const V2 = {
  bg:         '#f6efde',
  bgCard:     '#faf6ee',
  navy:       '#14283a',
  accent:     '#2a5582',
  accentHov:  '#1f4368',
  warm:       '#b78048',
  muted:      '#4d6175',
  border:     '#d3c7a8',
  borderFoc:  '#2a5582',
  red:        '#c0392b',
  inputBg:    '#fff',
}

const inputStyle: React.CSSProperties = {
  width: '100%', padding: '10px 14px', fontSize: '0.95rem',
  border: `1px solid ${V2.border}`, borderRadius: 8,
  background: V2.inputBg, color: V2.navy, outline: 'none',
  fontFamily: 'inherit', transition: 'border-color .15s',
}

export default function LoginPage() {
  const [, setLocation] = useLocation()
  const { login, loginWithGoogle, loginWithGithub } = useAuth()
  const { toast } = useToast()
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [rememberMe, setRememberMe] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setIsLoading(true); setError(null)
    try {
      await login(email, password, rememberMe)
      // auth-context.login() already calls setLocation('/') on success
    } catch (err) {
      setError(err instanceof Error ? err.message : "Invalid credentials. Please try again.")
    } finally {
      setIsLoading(false)
    }
  }

  const handleGoogle = async () => {
    try { setIsLoading(true); await loginWithGoogle() }
    catch { toast({ variant: "destructive", title: "Google login not configured yet." }); setIsLoading(false) }
  }

  const handleGithub = async () => {
    try { setIsLoading(true); await loginWithGithub() }
    catch { toast({ variant: "destructive", title: "GitHub login not configured yet." }); setIsLoading(false) }
  }

  return (
    <div style={{ minHeight: '100vh', background: V2.bg, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '24px 16px' }}>
      <div style={{ width: '100%', maxWidth: 420 }}>

        {/* Logo */}
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <a href="https://biomate.ai" style={{ textDecoration: 'none', display: 'inline-block' }}>
            <img src="/biomate-logo.png" alt="BioMate" style={{ height: 40, width: 'auto' }} />
          </a>
          <p style={{ marginTop: 10, color: V2.muted, fontSize: '0.9rem' }}>Sign in to your account</p>
        </div>

        {/* Card */}
        <div style={{ background: V2.bgCard, border: `1px solid ${V2.border}`, borderRadius: 14, padding: '36px 32px', boxShadow: '0 4px 24px rgba(20,40,58,.08)' }}>
          <form onSubmit={handleSubmit}>

            <div style={{ marginBottom: 18 }}>
              <label style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, color: V2.navy, marginBottom: 6 }}>Email</label>
              <input
                type="email" required placeholder="name@institution.edu"
                value={email} onChange={e => setEmail(e.target.value)} disabled={isLoading}
                style={inputStyle}
                onFocus={e => e.target.style.borderColor = V2.borderFoc}
                onBlur={e => e.target.style.borderColor = V2.border}
              />
            </div>

            <div style={{ marginBottom: 10 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
                <label style={{ fontSize: '0.85rem', fontWeight: 600, color: V2.navy }}>Password</label>
                <a href="/forgot-password" style={{ fontSize: '0.8rem', color: V2.accent, textDecoration: 'none' }}
                  onMouseOver={e => (e.target as HTMLElement).style.color = V2.accentHov}
                  onMouseOut={e => (e.target as HTMLElement).style.color = V2.accent}>
                  Forgot password?
                </a>
              </div>
              <div style={{ position: 'relative' }}>
                <input
                  type={showPassword ? "text" : "password"}
                  required placeholder="••••••••"
                  value={password} onChange={e => setPassword(e.target.value)} disabled={isLoading}
                  style={{ ...inputStyle, paddingRight: 38 }}
                  onFocus={e => e.target.style.borderColor = V2.borderFoc}
                  onBlur={e => e.target.style.borderColor = V2.border}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(v => !v)}
                  aria-label={showPassword ? "Hide password" : "Show password"}
                  tabIndex={-1}
                  style={{
                    position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)',
                    background: 'transparent', border: 'none', cursor: 'pointer', padding: 4,
                    color: V2.muted, display: 'flex', alignItems: 'center'
                  }}
                >
                  {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                </button>
              </div>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 22 }}>
              <input type="checkbox" id="rem" checked={rememberMe} onChange={e => setRememberMe(e.target.checked)} disabled={isLoading}
                style={{ width: 16, height: 16, accentColor: V2.accent }} />
              <label htmlFor="rem" style={{ fontSize: '0.82rem', color: V2.muted, cursor: 'pointer' }}>Remember me for 30 days</label>
            </div>

            {error && (
              <div style={{ background: '#fdf2f2', border: `1px solid #f5c6c6`, borderRadius: 8, padding: '10px 14px', marginBottom: 16, fontSize: '0.85rem', color: V2.red }}>
                {error}
                {error.includes('credentials') && (
                  <> &nbsp;<button type="button" onClick={() => setLocation('/register')}
                    style={{ color: V2.accent, background: 'none', border: 'none', padding: 0, cursor: 'pointer', fontSize: '0.85rem', textDecoration: 'underline' }}>
                    Register instead
                  </button></>
                )}
              </div>
            )}

            <button type="submit" disabled={isLoading} style={{
              width: '100%', padding: '12px', borderRadius: 8, border: 'none', cursor: isLoading ? 'not-allowed' : 'pointer',
              background: V2.accent, color: '#fff', fontWeight: 700, fontSize: '0.95rem',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
              opacity: isLoading ? 0.7 : 1, transition: 'background .15s',
            }}
              onMouseOver={e => !isLoading && ((e.currentTarget as HTMLElement).style.background = V2.accentHov)}
              onMouseOut={e => (e.currentTarget as HTMLElement).style.background = V2.accent}>
              {isLoading && <Loader2 style={{ width: 16, height: 16, animation: 'spin 1s linear infinite' }} />}
              Sign in
            </button>
          </form>

          {/*
            OAuth (Google / GitHub) hidden on dev-public — OAuth providers
            aren't configured yet, so the buttons would just toast an error.
            Re-enable once provider keys are in env + the backend callback
            routes are wired. The handlers (handleGoogle/handleGithub) and
            the loginWithGoogle/loginWithGithub hooks are kept so re-enabling
            is a single un-comment.

            <div style={{ display: 'flex', alignItems: 'center', margin: '24px 0', gap: 12 }}>
              <div style={{ flex: 1, height: 1, background: V2.border }} />
              <span style={{ fontSize: '0.75rem', color: V2.muted, letterSpacing: '0.08em', textTransform: 'uppercase' }}>or</span>
              <div style={{ flex: 1, height: 1, background: V2.border }} />
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
              ... OAuth buttons map(Google, GitHub) ...
            </div>
          */}
        </div>

        <p style={{ textAlign: 'center', marginTop: 20, fontSize: '0.88rem', color: V2.muted }}>
          Don't have an account?{' '}
          <button type="button" onClick={() => setLocation('/register')} style={{
            color: V2.accent, background: 'none', border: 'none', padding: 0,
            cursor: 'pointer', fontWeight: 600, textDecoration: 'underline',
          }}>Sign up free</button>
        </p>
      </div>
      <style>{`@keyframes spin { from { transform: rotate(0deg) } to { transform: rotate(360deg) } }`}</style>
    </div>
  )
}
