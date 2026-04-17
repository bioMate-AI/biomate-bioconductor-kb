import { useState } from "react"
import { useLocation, useSearch } from "wouter"
import { useAuth } from "@/contexts/auth-context"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, Check, CreditCard, Lock, Shield, Zap, Mail, Eye, EyeOff } from "lucide-react"
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

  // Four-step: "account" → "email-sent" → "domain" → "trial"
  const [step, setStep] = useState<"account" | "email-sent" | "domain" | "trial">("account")
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirmPassword, setShowConfirmPassword] = useState(false)
  const [registeredEmail, setRegisteredEmail] = useState<string>("")
  const [verificationToken, setVerificationToken] = useState<string | null>(null)

  const [formData, setFormData] = useState({
    name: "",
    email: "",
    password: "",
    confirmPassword: "",
    inviteCode: prefilledCode,
    agreeToTerms: false
  })
  const [isLoading, setIsLoading] = useState(false)
  const [authToken, setAuthToken] = useState<string | null>(null)

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

    setIsLoading(true)
    try {
      const res = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          fullName: formData.name,
          email: formData.email,
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
      setRegisteredEmail(formData.email)
      // Keep verification token for dev bypass link (null in prod if not returned)
      setVerificationToken(data.user?.verificationToken ?? null)

      // Show email-sent confirmation before domain profile
      setStep("email-sent")
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
    // Best-effort: save profile then proceed to trial regardless of outcome
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
    setStep("trial")
  }

  const handleSkipDomainProfile = () => {
    setStep("trial")
  }

  // ── Step 3: start Stripe trial ─────────────────────────────────────────────

  const handleStartTrial = async () => {
    setIsLoading(true)
    try {
      const res = await fetch('/api/auth/start-trial', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`,
        },
        credentials: 'include',
        body: JSON.stringify({ returnUrl: `${window.location.origin}/dashboard` }),
      })

      // If endpoint doesn't exist or Stripe not configured, go straight to app
      if (!res.ok) {
        setLocation('/dashboard')
        return
      }

      const data = await res.json()
      if (data.devMode || !data.url) {
        setLocation('/dashboard')
        return
      }
      // Redirect to Stripe Checkout to collect payment method
      window.location.href = data.url
    } catch {
      // No Stripe / network error — proceed anyway
      setLocation('/dashboard')
    }
  }

  const handleSkipForNow = () => {
    setLocation('/')
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

  // ── Step 1.5 UI: email verification sent ──────────────────────────────────

  if (step === "email-sent") {
    return (
      <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-blue-500/10 via-purple-500/10 to-pink-500/10">
        <Card className="w-full max-w-md text-center">
          <CardHeader className="space-y-1">
            <div className="flex justify-center mb-4">
              <div className="rounded-full bg-blue-100 dark:bg-blue-900 p-3">
                <Mail className="h-8 w-8 text-blue-600 dark:text-blue-400" />
              </div>
            </div>
            <CardTitle className="text-2xl font-bold">Check your email</CardTitle>
            <CardDescription>
              We sent a verification link to <strong>{registeredEmail}</strong>.
              Click the link in your email to verify your account, then come back to log in.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            {verificationToken && (
              <div className="rounded-md border border-dashed p-3 text-xs text-left text-muted-foreground">
                <p className="font-semibold mb-1 text-foreground">Dev mode — email not configured</p>
                <p>Click this link to verify directly:</p>
                <a
                  href={`/verify-email?token=${verificationToken}`}
                  className="text-blue-600 dark:text-blue-400 underline break-all"
                >
                  /verify-email?token={verificationToken.slice(0, 16)}…
                </a>
              </div>
            )}
            <Button className="w-full" onClick={() => setStep("domain")}>
              Continue setup
            </Button>
            <Button variant="ghost" className="w-full text-sm text-muted-foreground" onClick={() => setLocation('/login')}>
              Go to login
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  // ── Step 2 UI: domain profile ─────────────────────────────────────────────

  if (step === "domain") {
    return (
      <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-blue-500/10 via-purple-500/10 to-pink-500/10">
        <div className="w-full max-w-2xl">
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
      <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-blue-500/10 via-purple-500/10 to-pink-500/10">
        <Card className="w-full max-w-md">
          <CardHeader className="space-y-1 text-center">
            <div className="flex justify-center mb-2">
              <div className="w-12 h-12 rounded-full bg-blue-100 dark:bg-blue-900 flex items-center justify-center">
                <Zap className="w-6 h-6 text-blue-600 dark:text-blue-400" />
              </div>
            </div>
            <CardTitle className="text-2xl font-bold">Start your 7-day free trial</CardTitle>
            <CardDescription>
              Add a payment method to activate your trial.<br />
              You won't be charged until the trial ends.
            </CardDescription>
          </CardHeader>

          <CardContent className="space-y-4">
            {/* Trial benefits */}
            <div className="rounded-lg border bg-muted/30 p-4 space-y-2">
              {[
                "Full access to all AI workflows",
                "Up to $5 compute credits included",
                "Cancel anytime before trial ends",
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
                <p className="font-medium">Academic Plan</p>
                <p className="text-sm text-muted-foreground">$29 / month after trial</p>
              </div>
              <div className="text-right">
                <p className="font-bold text-lg">$0</p>
                <p className="text-xs text-muted-foreground">for 7 days</p>
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
    <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-blue-500/10 via-purple-500/10 to-pink-500/10">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl font-bold text-center">
            Create an account
          </CardTitle>
          <CardDescription className="text-center">
            Start your 7-day free trial of BioMate
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
              <Label htmlFor="inviteCode">
                Invite Code
                <span className="ml-1 text-xs text-muted-foreground">(optional)</span>
              </Label>
              <Input
                id="inviteCode"
                type="text"
                placeholder="BETA-XXXX-XXXX"
                value={formData.inviteCode}
                onChange={(e) => setFormData({ ...formData, inviteCode: e.target.value.toUpperCase() })}
                disabled={isLoading}
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

          <div className="relative my-6">
            <div className="absolute inset-0 flex items-center">
              <Separator />
            </div>
            <div className="relative flex justify-center text-xs uppercase">
              <span className="bg-background px-2 text-muted-foreground">Or continue with</span>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <Button variant="outline" onClick={handleGoogleSignup} disabled={isLoading}>
              <svg className="mr-2 h-4 w-4" viewBox="0 0 24 24">
                <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4" />
                <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853" />
                <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05" />
                <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335" />
              </svg>
              Google
            </Button>
            <Button variant="outline" onClick={handleGithubSignup} disabled={isLoading}>
              <svg className="mr-2 h-4 w-4" viewBox="0 0 24 24">
                <path fill="currentColor" d="M12 2A10 10 0 0 0 2 12c0 4.42 2.87 8.17 6.84 9.5.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34-.46-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.87 1.52 2.34 1.07 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.92 0-1.11.38-2 1.03-2.71-.1-.25-.45-1.29.1-2.64 0 0 .84-.27 2.75 1.02.79-.22 1.65-.33 2.5-.33.85 0 1.71.11 2.5.33 1.91-1.29 2.75-1.02 2.75-1.02.55 1.35.2 2.39.1 2.64.65.71 1.03 1.6 1.03 2.71 0 3.82-2.34 4.66-4.57 4.91.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0 0 12 2z" />
              </svg>
              GitHub
            </Button>
          </div>
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
