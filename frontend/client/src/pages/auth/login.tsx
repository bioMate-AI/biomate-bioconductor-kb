import { useState } from "react"
import { useLocation } from "wouter"
import { useAuth } from "@/contexts/auth-context"
import { Loader2 } from "lucide-react"
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
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setIsLoading(true); setError(null)
    try {
      await login(email, password, rememberMe)
      setLocation('/')
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
          <a href="https://biomate.ai" style={{ textDecoration: 'none' }}>
            <span style={{ fontSize: '1.6rem', fontWeight: 800, color: V2.navy, letterSpacing: '-0.02em' }}>BioMate</span>
            <span style={{ fontSize: '1.6rem', fontWeight: 800, color: V2.accent, marginLeft: 2 }}>AI</span>
          </a>
          <p style={{ marginTop: 6, color: V2.muted, fontSize: '0.9rem' }}>Sign in to your account</p>
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
              <input
                type="password" required placeholder="••••••••"
                value={password} onChange={e => setPassword(e.target.value)} disabled={isLoading}
                style={inputStyle}
                onFocus={e => e.target.style.borderColor = V2.borderFoc}
                onBlur={e => e.target.style.borderColor = V2.border}
              />
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

          {/* Divider */}
          <div style={{ display: 'flex', alignItems: 'center', margin: '24px 0', gap: 12 }}>
            <div style={{ flex: 1, height: 1, background: V2.border }} />
            <span style={{ fontSize: '0.75rem', color: V2.muted, letterSpacing: '0.08em', textTransform: 'uppercase' }}>or</span>
            <div style={{ flex: 1, height: 1, background: V2.border }} />
          </div>

          {/* OAuth */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            {[
              { label: 'Google', onClick: handleGoogle, icon: <svg width="18" height="18" viewBox="0 0 24 24"><path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/><path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/><path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/><path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/></svg> },
              { label: 'GitHub', onClick: handleGithub, icon: <svg width="18" height="18" viewBox="0 0 24 24"><path fill={V2.navy} d="M12 2A10 10 0 0 0 2 12c0 4.42 2.87 8.17 6.84 9.5.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34-.46-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.87 1.52 2.34 1.07 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.92 0-1.11.38-2 1.03-2.71-.1-.25-.45-1.29.1-2.64 0 0 .84-.27 2.75 1.02.79-.22 1.65-.33 2.5-.33.85 0 1.71.11 2.5.33 1.91-1.29 2.75-1.02 2.75-1.02.55 1.35.2 2.39.1 2.64.65.71 1.03 1.6 1.03 2.71 0 3.82-2.34 4.66-4.57 4.91.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0 0 12 2z"/></svg> },
            ].map(({ label, onClick, icon }) => (
              <button key={label} type="button" onClick={onClick} disabled={isLoading} style={{
                display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
                padding: '10px', borderRadius: 8, border: `1px solid ${V2.border}`,
                background: V2.bgCard, color: V2.navy, fontWeight: 600, fontSize: '0.88rem',
                cursor: isLoading ? 'not-allowed' : 'pointer', transition: 'border-color .15s',
              }}
                onMouseOver={e => (e.currentTarget as HTMLElement).style.borderColor = V2.accent}
                onMouseOut={e => (e.currentTarget as HTMLElement).style.borderColor = V2.border}>
                {icon} {label}
              </button>
            ))}
          </div>
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
