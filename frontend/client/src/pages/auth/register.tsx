import { useEffect, useState } from "react"
import { useLocation, useSearch } from "wouter"
import { useAuth } from "@/contexts/auth-context"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, Check, CreditCard, Lock, Shield, Zap, Eye, EyeOff } from "lucide-react"
import { Separator } from "@/components/ui/separator"
import { Checkbox } from "@/components/ui/checkbox"
import { useToast } from "@/hooks/use-toast"
import { DomainProfileSelector, type DomainProfile } from "@/components/domain-profile-selector"

export default function RegisterPage() {
  const [, setLocation] = useLocation()
  const search = useSearch()
  const { loginWithGoogle, loginWithGithub } = useAuth()
  const { toast } = useToast()

  // Pre-fill invite code from ?invite=CODE query param
  const prefilledCode = new URLSearchParams(search).get('invite') || ''
  // ?next=URL redirects to that URL after successful registration (e.g. checkout page)
  const nextUrl = new URLSearchParams(search).get('next') || ''
  // ?q= pending use-case query from marketing page — passed through to the platform after auth
  const pendingQuery = new URLSearchParams(search).get('q') || ''

  // Three-step: "account" → "domain" → platform (trial step auto-proceeds)
  const [step, setStep] = useState<"account" | "domain" | "trial">("account")
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirmPassword, setShowConfirmPassword] = useState(false)

  const [formData, setFormData] = useState({
    name: "",
    email: "",
    organization: "",
    role: "",
    password: "",
    confirmPassword: "",
    inviteCode: prefilledCode,
    agreeToTerms: false
  })
  const [isLoading, setIsLoading] = useState(false)
  const [authToken, setAuthToken] = useState<string | null>(null)
  const [inviteRequired, setInviteRequired] = useState<boolean | null>(null)

  useEffect(() => {
    fetch('/api/auth/config', { credentials: 'include' })
      .then(r => r.ok ? r.json() : null)
      .then(c => { if (c) setInviteRequired(!!c.requireInviteCode) })
      .catch(() => {})
  }, [])

  const passwordRequirements = [
    { label: "At least 8 characters", met: formData.password.length >= 8 },
    { label: "Contains a number", met: /\d/.test(formData.password) },
    { label: "Contains a special character", met: /[!@#$%^&*]/.test(formData.password) }
  ]

  // ── Step 1: create account ─────────────────────────────────────────────────

  const handleAccountSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (formData.password !== formData.confirmPassword) {
      toast({ variant: "destructive", title: "Passwords do not match", description: "Please make sure both passwords are the same." })
      return
    }
    if (!formData.agreeToTerms) {
      toast({ variant: "destructive", title: "Terms required", description: "Please agree to the terms and privacy policy." })
      return
    }
    if (!passwordRequirements.every(r => r.met)) {
      toast({ variant: "destructive", title: "Password requirements not met", description: "Please ensure your password meets all requirements." })
      return
    }
    if (!formData.organization.trim()) {
      toast({ variant: "destructive", title: "Institution required", description: "Please enter your institution or organization." })
      return
    }
    if (!formData.role) {
      toast({ variant: "destructive", title: "Role required", description: "Please select your role." })
      return
    }

    setIsLoading(true)
    try {
      const res = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          fullName: formData.name,
          email: formData.email,
          organization: formData.organization || undefined,
          role: formData.role || undefined,
          password: formData.password,
          termsAccepted: true,
          ...(formData.inviteCode ? { inviteCode: formData.inviteCode } : {}),
        }),
      })
      const data = await res.json()
      if (!res.ok) {
        const msg = data.error || 'Registration failed'
        const friendlyMsg: Record<string, string> = {
          INVITE_CODE_REQUIRED: 'An invite code is required to register during our closed beta.',
          INVALID_INVITE_CODE: 'That invite code is not valid. Please check it and try again.',
          INVITE_CODE_EXPIRED: 'That invite code has expired. Please request a new one.',
          INVITE_CODE_EXHAUSTED: 'That invite code has already been used the maximum number of times.',
          REGISTRATION_LIMIT_EXCEEDED: 'Too many registration attempts from this device. Please wait 1 hour and try again.',
        }
        throw new Error(friendlyMsg[msg] ?? data.message ?? msg)
      }

      // Store token so start-trial call can authenticate
      localStorage.setItem('auth_token', data.token)
      localStorage.setItem('user', JSON.stringify(data.user))
      setAuthToken(data.token)
      // Go directly to domain profile (skip email-sent intermediate screen)
      setStep("domain")
    } catch (error) {
      toast({
        variant: "destructive",
        title: "Registration failed",
        description: error instanceof Error ? error.message : "Please try again.",
      })
    } finally {
      setIsLoading(false)
    }
  }

  // ── Step 2: domain profile ────────────────────────────────────────────────

  const handleSaveDomainProfile = async (profile: DomainProfile) => {
    // Best-effort: save profile then proceed regardless of outcome
    try {
      await fetch('/api/user/domain-profile', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(authToken ? { 'Authorization': `Bearer ${authToken}` } : {}),
        },
        credentials: 'include',
        body: JSON.stringify(profile),
      })
    } catch {
      // Non-fatal — user can update profile later from settings
    }
    localStorage.setItem('biomate_onboarding_done', '1')
    void handleStartTrial()
  }

  const handleSkipDomainProfile = () => {
    localStorage.setItem('biomate_onboarding_done', '1')
    void handleStartTrial()
  }

  // ── Step 3: start Stripe trial ─────────────────────────────────────────────

  // Build the final redirect URL, preserving pending query for auto-submit in chat
  const finalRedirectUrl = () => {
    const base = nextUrl || '/'
    return pendingQuery ? `${base}${base.includes('?') ? '&' : '?'}q=${encodeURIComponent(pendingQuery)}` : base
  }

  const handleStartTrial = async () => {
    setIsLoading(true)
    try {
      const res = await fetch('/api/payments/start-trial', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`,
        },
        credentials: 'include',
        body: JSON.stringify({ tier: 'professional', interval: 'monthly', returnUrl: `${window.location.origin}/` }),
      })

      // If endpoint doesn't exist or Stripe not configured, go straight to app
      if (!res.ok) { window.location.href = finalRedirectUrl(); return }

      const data = await res.json()
      if (data.devMode || !data.url) {
        window.location.href = finalRedirectUrl(); return
      }
      // Stripe configured — redirect to Checkout (query will be lost; user can re-type)
      window.location.href = data.url
    } catch {
      window.location.href = finalRedirectUrl()
    }
  }

  const handleSkipForNow = () => {
    localStorage.setItem('biomate_onboarding_done', '1')
    window.location.href = finalRedirectUrl()
  }

  // ── OAuth helpers ──────────────────────────────────────────────────────────

  const handleGoogleSignup = async () => {
    try {
      setIsLoading(true)
      await loginWithGoogle()
    } catch {
      toast({ variant: "destructive", title: "Sign up failed", description: "Google sign up is not configured yet." })
      setIsLoading(false)
    }
  }

  const handleGithubSignup = async () => {
    try {
      setIsLoading(true)
      await loginWithGithub()
    } catch {
      toast({ variant: "destructive", title: "Sign up failed", description: "GitHub sign up is not configured yet." })
      setIsLoading(false)
    }
  }

  // ── Step 2 UI: domain profile ─────────────────────────────────────────────

  if (step === "domain") {
    return (
      <div className="min-h-screen flex items-center justify-center p-4 bg-[#f6efde]">
        <div className="w-full max-w-2xl">
          <div className="flex justify-center mb-4">
            <img src="/biomate-logo.png" alt="BioMate" className="h-10 w-auto" />
          </div>
          <DomainProfileSelector
            onSave={handleSaveDomainProfile}
            onSkip={handleSkipDomainProfile}
          />
        </div>
      </div>
    )
  }

  // ── Step 3 UI: trial ──────────────────────────────────────────────────────

  if (step === "trial") {
    return (
      <div className="min-h-screen flex items-center justify-center p-4 bg-[#f6efde]">
        <Card className="w-full max-w-md">
          <CardHeader className="space-y-1 text-center">
            <div className="flex justify-center mb-2">
              <img src="/biomate-logo.png" alt="BioMate" className="h-10 w-auto" />
            </div>
            <CardTitle className="text-2xl font-bold">Start your 14-day Premium trial</CardTitle>
            <CardDescription>
              Get full Premium access with included credits.
            </CardDescription>
          </CardHeader>

          <CardContent className="space-y-4">
            {/* Trial benefits */}
            <div className="rounded-lg border bg-muted/30 p-4 space-y-2">
              {[
                "Full Premium features for 14 days",
                "Generous compute credits included",
                "Priority compute resources",
              ].map((benefit) => (
                <div key={benefit} className="flex items-center gap-2 text-sm">
                  <Check className="h-4 w-4 text-green-500 shrink-0" />
                  <span>{benefit}</span>
                </div>
              ))}
            </div>

            {/* Plan + price summary */}
            <div className="rounded-lg border p-4 flex items-center justify-between">
              <div>
                <p className="font-medium">Premium Plan</p>
                <p className="text-sm text-muted-foreground">$49 / month after trial</p>
              </div>
              <div className="text-right">
                <p className="font-bold text-lg">$0</p>
                <p className="text-xs text-muted-foreground">for 14 days</p>
              </div>
            </div>

            {/* Security notice */}
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Lock className="h-3 w-3" />
              <span>Secured by Stripe. Your card details are never stored on our servers.</span>
            </div>
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Shield className="h-3 w-3" />
              <span>Cancel anytime from your billing page. No cancellation fees.</span>
            </div>

            <Button className="w-full" onClick={handleStartTrial} disabled={isLoading}>
              {isLoading
                ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Setting up…</>
                : <><CreditCard className="mr-2 h-4 w-4" /> Add payment method &amp; start trial</>
              }
            </Button>

            <Button variant="ghost" className="w-full text-sm text-muted-foreground" onClick={handleSkipForNow} disabled={isLoading}>
              Skip for now — explore the free tier
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  // ── Step 1 UI ──────────────────────────────────────────────────────────────

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-[#f6efde]">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1 text-center">
          <div className="flex justify-center mb-2">
            <img src="/biomate-logo.png" alt="BioMate" className="h-10 w-auto" />
          </div>
          <CardTitle className="text-2xl font-bold">
            Create an account
          </CardTitle>
          <CardDescription>
            Get 14 days of Premium access with included credits
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleAccountSubmit} className="space-y-4">

            <div className="space-y-2">
              <Label htmlFor="name">Full Name</Label>
              <Input
                id="name"
                type="text"
                placeholder="Dr. Jane Smith"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                disabled={isLoading}
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="name@institution.edu"
                value={formData.email}
                onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                disabled={isLoading}
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="organization">
                Institution or Organization
              </Label>
              <Input
                id="organization"
                type="text"
                placeholder="e.g. Pfizer, Genentech, Stanford University"
                value={formData.organization}
                onChange={(e) => setFormData({ ...formData, organization: e.target.value })}
                disabled={isLoading}
                autoComplete="organization"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="role">
                Your Role
              </Label>
              <select
                id="role"
                value={formData.role}
                onChange={(e) => setFormData({ ...formData, role: e.target.value })}
                disabled={isLoading}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <option value="">Select your role…</option>
                <option>Principal Investigator / PI</option>
                <option>Postdoctoral Researcher</option>
                <option>PhD Student / Graduate Student</option>
                <option>Research Scientist</option>
                <option>Computational Biologist / Bioinformatician</option>
                <option>Core Facility Operator</option>
                <option>Pharma / Biotech Researcher</option>
                <option>Clinical Genomics</option>
                <option>Other</option>
              </select>
            </div>

            <div className="space-y-2">
              <Label htmlFor="inviteCode">
                Invite Code
                <span className="ml-1 text-xs text-muted-foreground">
                  {inviteRequired === null ? '' : inviteRequired ? '(required)' : '(optional)'}
                </span>
              </Label>
              <Input
                id="inviteCode"
                type="text"
                placeholder="BETA-XXXX-XXXX"
                value={formData.inviteCode}
                onChange={(e) => setFormData({ ...formData, inviteCode: e.target.value.toUpperCase() })}
                disabled={isLoading}
                required={inviteRequired === true}
                className="font-mono tracking-wider"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <div className="relative">
                <Input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  value={formData.password}
                  onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                  disabled={isLoading}
                  required
                  className="pr-10"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(v => !v)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                  tabIndex={-1}
                >
                  {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
              {formData.password && (
                <div className="space-y-1 mt-2">
                  {passwordRequirements.map((req, index) => (
                    <div key={index} className="flex items-center text-xs">
                      <Check
                        className={`h-3 w-3 mr-2 ${req.met ? "text-blue-600 dark:text-blue-400" : "text-muted-foreground"}`}
                      />
                      <span className={req.met ? "text-blue-600 dark:text-blue-400 font-medium" : "text-muted-foreground"}>
                        {req.label}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="space-y-2">
              <Label htmlFor="confirmPassword">Confirm Password</Label>
              <div className="relative">
                <Input
                  id="confirmPassword"
                  type={showConfirmPassword ? "text" : "password"}
                  value={formData.confirmPassword}
                  onChange={(e) => setFormData({ ...formData, confirmPassword: e.target.value })}
                  disabled={isLoading}
                  required
                  className="pr-10"
                />
                <button
                  type="button"
                  onClick={() => setShowConfirmPassword(v => !v)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                  tabIndex={-1}
                >
                  {showConfirmPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
            </div>

            <div className="flex items-start space-x-2">
              <Checkbox
                id="terms"
                checked={formData.agreeToTerms}
                onCheckedChange={(checked) =>
                  setFormData({ ...formData, agreeToTerms: checked as boolean })
                }
                disabled={isLoading}
              />
              <Label htmlFor="terms" className="text-sm font-normal cursor-pointer">
                I agree to the{" "}
                <Button type="button" variant="link" className="px-0 h-auto text-sm" onClick={() => window.open('/terms', '_blank')}>
                  Terms of Service
                </Button>{" "}
                and{" "}
                <Button type="button" variant="link" className="px-0 h-auto text-sm" onClick={() => window.open('/privacy', '_blank')}>
                  Privacy Policy
                </Button>
              </Label>
            </div>

            <Button type="submit" className="w-full" disabled={isLoading}>
              {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Create Account
            </Button>
          </form>

          {/*
            OAuth (Google / GitHub) sign-up hidden on dev-public — providers
            aren't configured yet, the buttons just toast "not configured".
            Re-enable once provider keys are in env + backend OAuth callback
            routes are wired. Handlers (handleGoogleSignup / handleGithubSignup)
            and the loginWithGoogle / loginWithGithub hooks are kept so
            re-enabling is a single un-comment.

            <div className="relative my-6">
              <div className="absolute inset-0 flex items-center"><Separator /></div>
              <div className="relative flex justify-center text-xs uppercase">
                <span className="bg-background px-2 text-muted-foreground">Or continue with</span>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              ... Google + GitHub OAuth buttons ...
            </div>
          */}
        </CardContent>
        <CardFooter>
          <div className="text-sm text-center w-full text-muted-foreground">
            Already have an account?{" "}
            <Button variant="link" className="px-1" onClick={() => setLocation('/login')}>
              Sign in
            </Button>
          </div>
        </CardFooter>
      </Card>
    </div>
  )
}
