import { useState } from "react"
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Check, X } from "lucide-react"
import { Switch } from "@/components/ui/switch"
import { Label } from "@/components/ui/label"

export default function PricingPage() {
  const [, setLocation] = useLocation()
  const [isAnnual, setIsAnnual] = useState(false)

  const plans = [
    {
      name: "Free",
      description: "Perfect for trying out BioMate",
      price: { monthly: 0, annual: 0 },
      credits: "$5",
      features: [
        { name: "$5 in monthly credits", included: true },
        { name: "Chat-based workflow design", included: true },
        { name: "Community support", included: true },
        { name: "2 GB storage included", included: true },
        { name: "Public workspace", included: true },
        { name: "Auto notifications", included: true },
        { name: "Priority compute", included: false },
        { name: "Team collaboration", included: false }
      ],
      cta: "Start Free",
      popular: false
    },
    {
      name: "Pro",
      description: "For individual researchers",
      price: { monthly: 20, annual: 18 },
      credits: "$30",
      features: [
        { name: "$30 in monthly credits", included: true },
        { name: "Unlimited workflow generation", included: true },
        { name: "Priority compute resources", included: true },
        { name: "Priority support", included: true },
        { name: "20 GB storage included", included: true },
        { name: "Private workspace", included: true },
        { name: "Auto notifications & alerts", included: true },
        { name: "Team collaboration", included: false }
      ],
      cta: "Start Free Trial",
      popular: true
    },
    {
      name: "Team",
      description: "For research teams",
      price: { monthly: 40, annual: 36 },
      credits: "$60",
      perUser: true,
      features: [
        { name: "$60 in monthly credits per user", included: true },
        { name: "Everything in Pro", included: true },
        { name: "Shared workspaces", included: true },
        { name: "100 GB storage per user", included: true },
        { name: "Team management dashboard", included: true },
        { name: "Usage analytics", included: true },
        { name: "Role-based access control", included: true },
        { name: "Dedicated support channel", included: true }
      ],
      cta: "Start Free Trial",
      popular: false
    },
    {
      name: "Enterprise",
      description: "For institutions",
      price: { monthly: "Custom", annual: "Custom" },
      credits: "Custom",
      features: [
        { name: "Custom credit allocation", included: true },
        { name: "Everything in Team", included: true },
        { name: "Unlimited users", included: true },
        { name: "Unlimited storage", included: true },
        { name: "SSO & SAML", included: true },
        { name: "Dedicated cloud resources", included: true },
        { name: "SLA guarantee (99.9%)", included: true },
        { name: "24/7 dedicated support", included: true }
      ],
      cta: "Contact Sales",
      popular: false
    }
  ]

  const handleSelectPlan = (planName: string) => {
    if (planName === "Enterprise") {
      setLocation('/contact')
    } else if (planName === "Free") {
      setLocation('/register')
    } else {
      setLocation(`/checkout/${planName.toLowerCase()}`)
    }
  }

  return (
    <div className="min-h-screen bg-background py-24">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="text-center mb-16">
          <h1 className="text-4xl font-bold mb-4">
            Simple, Usage-Based Pricing
          </h1>
          <p className="text-xl text-muted-foreground mb-4">
            Base subscription + monthly credits. Only pay for what you use beyond your credits.
          </p>
          <p className="text-sm text-muted-foreground max-w-2xl mx-auto mb-8">
            Credits cover compute time, storage, and data processing. When you exhaust your monthly credits,
            usage is billed automatically at competitive rates—just like your electricity bill.
          </p>

          {/* Billing Toggle */}
          <div className="flex items-center justify-center gap-4">
            <Label htmlFor="billing-toggle" className={!isAnnual ? "font-semibold" : ""}>
              Monthly
            </Label>
            <Switch
              id="billing-toggle"
              checked={isAnnual}
              onCheckedChange={setIsAnnual}
            />
            <Label htmlFor="billing-toggle" className={isAnnual ? "font-semibold" : ""}>
              Annual
              <Badge variant="secondary" className="ml-2">Save 10%</Badge>
            </Label>
          </div>
        </div>

        {/* Pricing Cards */}
        <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8">
          {plans.map((plan, index) => (
            <Card
              key={index}
              className={`relative flex flex-col ${
                plan.popular ? "border-primary shadow-lg scale-105" : ""
              }`}
            >
              {plan.popular && (
                <div className="absolute -top-4 left-1/2 transform -translate-x-1/2">
                  <Badge className="px-4 py-1">Most Popular</Badge>
                </div>
              )}

              <CardHeader>
                <CardTitle className="text-2xl">{plan.name}</CardTitle>
                <CardDescription>{plan.description}</CardDescription>
                <div className="mt-4">
                  {typeof plan.price.monthly === "number" ? (
                    <>
                      <span className="text-4xl font-bold">
                        ${isAnnual ? plan.price.annual : plan.price.monthly}
                      </span>
                      <span className="text-muted-foreground">/month{plan.perUser ? "/user" : ""}</span>
                      {isAnnual && plan.price.monthly > 0 && (
                        <div className="text-sm text-muted-foreground mt-1">
                          Billed ${plan.price.annual * 12}/year
                        </div>
                      )}
                    </>
                  ) : (
                    <span className="text-4xl font-bold">{plan.price.monthly}</span>
                  )}
                </div>
                {plan.credits && (
                  <div className="mt-3">
                    <Badge variant="secondary" className="text-sm">
                      {plan.credits} monthly credits{plan.perUser ? " per user" : ""}
                    </Badge>
                  </div>
                )}
              </CardHeader>

              <CardContent className="flex-1">
                <ul className="space-y-3">
                  {plan.features.map((feature, fIndex) => (
                    <li key={fIndex} className="flex items-start gap-2">
                      {feature.included ? (
                        <Check className="h-5 w-5 text-blue-600 dark:text-blue-400 shrink-0 mt-0.5" />
                      ) : (
                        <X className="h-5 w-5 text-muted-foreground shrink-0 mt-0.5" />
                      )}
                      <span
                        className={
                          feature.included ? "" : "text-muted-foreground line-through"
                        }
                      >
                        {feature.name}
                      </span>
                    </li>
                  ))}
                </ul>
              </CardContent>

              <CardFooter>
                <Button
                  className="w-full"
                  variant={plan.popular ? "default" : "outline"}
                  onClick={() => handleSelectPlan(plan.name)}
                >
                  {plan.cta}
                </Button>
              </CardFooter>
            </Card>
          ))}
        </div>

        {/* Credit & Usage Section */}
        <div className="mt-24 bg-muted/30 rounded-lg p-8">
          <h2 className="text-3xl font-bold text-center mb-4">
            How Credits & Usage-Based Pricing Work
          </h2>
          <p className="text-center text-muted-foreground mb-12 max-w-3xl mx-auto">
            BioMate uses a hybrid model: predictable base subscription + flexible usage-based charges.
            Your monthly credits cover most typical usage—only pay extra if you exceed them.
          </p>

          <div className="grid md:grid-cols-3 gap-8 max-w-5xl mx-auto">
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Credits Cover</CardTitle>
              </CardHeader>
              <CardContent>
                <ul className="space-y-2 text-sm text-muted-foreground">
                  <li>• Compute time (CPU/GPU hours)</li>
                  <li>• Storage (active & archive)</li>
                  <li>• Data transfer (egress)</li>
                  <li>• Workflow complexity</li>
                  <li>• AI model API calls</li>
                </ul>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Usage Rates (After Credits)</CardTitle>
              </CardHeader>
              <CardContent>
                <ul className="space-y-2 text-sm text-muted-foreground">
                  <li>• Compute: $0.10/hour (CPU)</li>
                  <li>• Compute: $1.50/hour (GPU)</li>
                  <li>• Storage: $0.15/GB/month</li>
                  <li>• Data egress: $0.08/GB</li>
                  <li>• AI calls: $0.02/request</li>
                </ul>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Example Usage</CardTitle>
              </CardHeader>
              <CardContent>
                <ul className="space-y-2 text-sm text-muted-foreground">
                  <li>• Simple workflow: ~$2-5</li>
                  <li>• Medium analysis: ~$10-20</li>
                  <li>• Complex pipeline: ~$30-50</li>
                  <li>• Most Pro users stay within $30 credits</li>
                </ul>
              </CardContent>
            </Card>
          </div>

          <div className="mt-8 text-center">
            <p className="text-sm text-muted-foreground">
              <strong>No surprises:</strong> Track real-time usage in your dashboard and set spending alerts.
              Credits roll over for up to 30 days if unused.
            </p>
          </div>
        </div>

        {/* FAQ Section */}
        <div className="mt-24">
          <h2 className="text-3xl font-bold text-center mb-12">
            Frequently asked questions
          </h2>
          <div className="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
            <div>
              <h3 className="font-semibold mb-2">What happens if I exceed my credits?</h3>
              <p className="text-muted-foreground">
                Your analyses continue running smoothly. Usage beyond your credits is billed automatically at our competitive rates. Track usage in real-time from your dashboard.
              </p>
            </div>
            <div>
              <h3 className="font-semibold mb-2">Do unused credits roll over?</h3>
              <p className="text-muted-foreground">
                Yes! Unused credits roll over for up to 30 days, giving you flexibility for variable workloads and burst usage.
              </p>
            </div>
            <div>
              <h3 className="font-semibold mb-2">Can I change plans later?</h3>
              <p className="text-muted-foreground">
                Yes, you can upgrade or downgrade your plan at any time. Changes take effect immediately, and credits adjust proportionally.
              </p>
            </div>
            <div>
              <h3 className="font-semibold mb-2">What payment methods do you accept?</h3>
              <p className="text-muted-foreground">
                We accept all major credit cards, PayPal, and wire transfers for Enterprise plans. Billing is automated monthly or annually.
              </p>
            </div>
            <div>
              <h3 className="font-semibold mb-2">Is there a free trial?</h3>
              <p className="text-muted-foreground">
                Yes, all paid plans include a 14-day free trial with full access to features and credits. No credit card required to start.
              </p>
            </div>
            <div>
              <h3 className="font-semibold mb-2">Can I set spending limits?</h3>
              <p className="text-muted-foreground">
                Absolutely. Set custom spending alerts and hard limits in your dashboard to control costs. We'll notify you before you exceed your budget.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
