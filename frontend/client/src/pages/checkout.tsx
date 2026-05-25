import { useState, useEffect } from "react"
import { useLocation, useRoute, useSearch } from "wouter"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Separator } from "@/components/ui/separator"
import { Badge } from "@/components/ui/badge"
import { Loader2, AlertCircle, Lock, Check, ShieldCheck } from "lucide-react"

const PLANS: Record<string, {
  name: string
  priceMonthly: number
  priceYearly: number
  perUser?: boolean
  features: string[]
}> = {
  professional: {
    name: "Premium",
    priceMonthly: 49,
    priceYearly: 44,
    features: [
      "2,000+ validated workflows",
      "32 QC profiles",
      "Auto-loop quality assurance",
      "AI findings and audit reports",
      "Priority compute resources",
      "Email support",
    ],
  },
  academic: {
    name: "Academic",
    priceMonthly: 29,
    priceYearly: 26,
    features: [
      "2,000+ validated workflows",
      "32 QC profiles",
      "Auto-loop quality assurance",
      "AI findings and audit reports",
      "Email support",
    ],
  },
  team: {
    name: "Team",
    priceMonthly: 79,
    priceYearly: 71,
    perUser: true,
    features: [
      "Everything in Premium",
      "Shared workspaces and session history",
      "Team usage dashboard",
      "Priority support",
      "Custom workflow onboarding",
    ],
  },
}

export default function CheckoutPage() {
  const [, params] = useRoute('/checkout/:plan')
  const [, setLocation] = useLocation()
  const search = useSearch()
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [yearly, setYearly] = useState(false)
  const [authChecked, setAuthChecked] = useState(false)

  const planKey = (params?.plan || 'professional').toLowerCase()
  const plan = PLANS[planKey] || PLANS.premium
  const price = yearly ? plan.priceYearly : plan.priceMonthly
  const interval = yearly ? 'yearly' : 'monthly'
  const perLabel = plan.perUser ? '/ user / month' : '/ month'

  // Handle Stripe redirect back
  const urlParams = new URLSearchParams(search)
  const statusParam = urlParams.get('status')

  useEffect(() => {
    if (statusParam === 'success') { setAuthChecked(true); return }
    fetch('/api/auth/me', { credentials: 'include' }).then(r => {
      if (!r.ok) {
        setLocation(`/login?next=/checkout/${planKey}`)
      } else {
        setAuthChecked(true)
      }
    }).catch(() => {
      setLocation(`/login?next=/checkout/${planKey}`)
    })
  }, [planKey, statusParam])

  // Block render until auth check completes — prevents flash of checkout form before redirect
  if (!authChecked) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    )
  }

  if (statusParam === 'success') {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center py-12">
        <Card className="max-w-md w-full mx-4">
          <CardContent className="text-center pt-8 pb-8">
            <div className="flex justify-center mb-4">
              <img src="/biomate-logo.png" alt="BioMate" className="h-10 w-auto" />
            </div>
            <div className="w-14 h-14 rounded-full bg-blue-50 dark:bg-blue-950 border border-blue-200 dark:border-blue-800 flex items-center justify-center mx-auto mb-4">
              <Check className="h-7 w-7 text-blue-600 dark:text-blue-400" />
            </div>
            <h2 className="text-2xl font-bold mb-2">You're all set!</h2>
            <p className="text-muted-foreground mb-6">Your subscription is active. Head to the platform to get started.</p>
            <Button className="w-full" size="lg" onClick={() => setLocation('/')}>
              Go to BioMate
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  const handleCheckout = async () => {
    setError("")
    setIsLoading(true)
    try {
      const res = await fetch('/api/payments/create-checkout-session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ tier: planKey, interval }),
      })
      const data = await res.json()
      if (res.status === 503) {
        // Stripe not yet configured on this deployment
        setError('Payment is not yet active. Contact contact@biomate.ai to arrange access.')
        setIsLoading(false)
        return
      }
      if (!res.ok) throw new Error(data.message || data.error || 'Checkout failed')
      if (data.url) {
        window.location.href = data.url
      } else {
        setLocation('/')
      }
    } catch (err: any) {
      setError(err.message || 'Could not start checkout. Please try again or contact support.')
      setIsLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-background py-12">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center mb-8">
          <div className="flex justify-center mb-4">
            <img src="/biomate-logo.png" alt="BioMate" className="h-10 w-auto" />
          </div>
          <h1 className="text-3xl font-bold mb-2">Upgrade to {plan.name}</h1>
          <p className="text-muted-foreground">Secure checkout powered by Stripe — we never see your card details.</p>
        </div>

        <div className="grid lg:grid-cols-2 gap-8 items-start">
          {/* Plan summary */}
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center justify-between">
                {plan.name}
                <Badge variant="secondary">7-day free trial</Badge>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-5">
              {/* Billing interval toggle */}
              <div className="flex items-center gap-3 text-sm">
                <button
                  className={`px-3 py-1.5 rounded-md border transition-colors ${!yearly ? 'bg-primary text-primary-foreground border-primary' : 'border-border text-muted-foreground hover:text-foreground'}`}
                  onClick={() => setYearly(false)}
                >
                  Monthly
                </button>
                <button
                  className={`px-3 py-1.5 rounded-md border transition-colors ${yearly ? 'bg-primary text-primary-foreground border-primary' : 'border-border text-muted-foreground hover:text-foreground'}`}
                  onClick={() => setYearly(true)}
                >
                  Annual <span className="text-xs font-semibold ml-1">save 20%</span>
                </button>
              </div>

              {/* Price */}
              <div className="flex items-baseline gap-1">
                <span className="text-4xl font-bold">${price}</span>
                <span className="text-muted-foreground text-sm">{perLabel}</span>
                {yearly && <span className="text-xs text-muted-foreground ml-1">(billed annually)</span>}
              </div>

              <Separator />

              <ul className="space-y-2">
                {plan.features.map((f, i) => (
                  <li key={i} className="flex items-start gap-2 text-sm text-muted-foreground">
                    <Check className="h-4 w-4 text-blue-600 dark:text-blue-400 shrink-0 mt-0.5" />
                    {f}
                  </li>
                ))}
              </ul>

              <Separator />

              <div className="space-y-1 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Trial period (7 days)</span>
                  <span className="font-medium">Free</span>
                </div>
                <div className="flex justify-between font-semibold text-base">
                  <span>Due today</span>
                  <span>$0</span>
                </div>
                <p className="text-xs text-muted-foreground pt-1">
                  You'll be charged ${price}{plan.perUser ? '/user' : ''} on{" "}
                  {new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toLocaleDateString()}.
                  Cancel anytime before then.
                </p>
              </div>
            </CardContent>
          </Card>

          {/* Checkout action */}
          <div className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle className="text-base flex items-center gap-2">
                  <ShieldCheck className="h-4 w-4" />
                  Proceed to payment
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-5">
                {error && (
                  <Alert variant="destructive">
                    <AlertCircle className="h-4 w-4" />
                    <AlertDescription>{error}</AlertDescription>
                  </Alert>
                )}

                <p className="text-sm text-muted-foreground">
                  Payment is handled entirely by <strong>Stripe</strong>. Clicking below redirects you to Stripe's
                  hosted checkout — BioMate never stores or sees your card details.
                </p>

                <ul className="space-y-2">
                  {[
                    "Visa, Mastercard, Amex, and most major cards",
                    "Subscription starts after 7-day trial",
                    "Cancel anytime from your account settings",
                  ].map((item, i) => (
                    <li key={i} className="flex items-center gap-2 text-sm text-muted-foreground">
                      <Check className="h-3.5 w-3.5 text-blue-600 dark:text-blue-400 shrink-0" />
                      {item}
                    </li>
                  ))}
                </ul>

                <Button className="w-full" size="lg" disabled={isLoading} onClick={handleCheckout}>
                  {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                  Continue to payment →
                </Button>

                <div className="flex items-center justify-center gap-1.5 text-xs text-muted-foreground">
                  <Lock className="h-3 w-3" />
                  Secured by Stripe · 256-bit TLS encryption
                </div>

                <p className="text-center text-xs text-muted-foreground">
                  By continuing you agree to our{" "}
                  <a href="https://dev-public.biomate.ai/terms" target="_blank" rel="noopener" className="underline underline-offset-2 hover:text-foreground">Terms of Service</a>
                  {" "}and{" "}
                  <a href="https://dev-public.biomate.ai/privacy" target="_blank" rel="noopener" className="underline underline-offset-2 hover:text-foreground">Privacy Policy</a>.
                </p>
              </CardContent>
            </Card>

            <p className="text-center text-xs text-muted-foreground">
              Need Enterprise?{" "}
              <a href="mailto:contact@biomate.ai?subject=Enterprise%20inquiry" className="underline underline-offset-2 hover:text-foreground">
                Contact us
              </a>{" "}
              for custom pricing and SLAs.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
