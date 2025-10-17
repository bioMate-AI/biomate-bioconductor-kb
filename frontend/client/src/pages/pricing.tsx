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
      features: [
        { name: "5 workflows per month", included: true },
        { name: "Basic AI assistance", included: true },
        { name: "Community support", included: true },
        { name: "1 GB storage", included: true },
        { name: "Public workspace", included: true },
        { name: "Advanced tools", included: false },
        { name: "Priority support", included: false },
        { name: "Team collaboration", included: false }
      ],
      cta: "Start Free",
      popular: false
    },
    {
      name: "Pro",
      description: "For individual researchers",
      price: { monthly: 49, annual: 39 },
      features: [
        { name: "Unlimited workflows", included: true },
        { name: "Advanced AI models", included: true },
        { name: "Priority support", included: true },
        { name: "50 GB storage", included: true },
        { name: "Private workspace", included: true },
        { name: "Advanced tools access", included: true },
        { name: "Export capabilities", included: true },
        { name: "Team collaboration", included: false }
      ],
      cta: "Start Free Trial",
      popular: true
    },
    {
      name: "Team",
      description: "For research teams",
      price: { monthly: 149, annual: 119 },
      features: [
        { name: "Everything in Pro", included: true },
        { name: "Up to 10 team members", included: true },
        { name: "Shared workspaces", included: true },
        { name: "500 GB storage", included: true },
        { name: "Team management", included: true },
        { name: "Advanced analytics", included: true },
        { name: "Custom integrations", included: true },
        { name: "Dedicated support", included: true }
      ],
      cta: "Start Free Trial",
      popular: false
    },
    {
      name: "Enterprise",
      description: "For institutions",
      price: { monthly: "Custom", annual: "Custom" },
      features: [
        { name: "Everything in Team", included: true },
        { name: "Unlimited team members", included: true },
        { name: "Unlimited storage", included: true },
        { name: "SSO & SAML", included: true },
        { name: "Dedicated infrastructure", included: true },
        { name: "SLA guarantee", included: true },
        { name: "Custom legal terms", included: true },
        { name: "24/7 phone support", included: true }
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
            Choose the right plan for you
          </h1>
          <p className="text-xl text-muted-foreground mb-8">
            All plans include a 14-day free trial. No credit card required.
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
              <Badge variant="secondary" className="ml-2">Save 20%</Badge>
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
                      <span className="text-muted-foreground">/month</span>
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

        {/* FAQ Section */}
        <div className="mt-24">
          <h2 className="text-3xl font-bold text-center mb-12">
            Frequently asked questions
          </h2>
          <div className="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
            <div>
              <h3 className="font-semibold mb-2">Can I change plans later?</h3>
              <p className="text-muted-foreground">
                Yes, you can upgrade or downgrade your plan at any time. Changes take effect immediately.
              </p>
            </div>
            <div>
              <h3 className="font-semibold mb-2">What payment methods do you accept?</h3>
              <p className="text-muted-foreground">
                We accept all major credit cards, PayPal, and wire transfers for Enterprise plans.
              </p>
            </div>
            <div>
              <h3 className="font-semibold mb-2">Is there a free trial?</h3>
              <p className="text-muted-foreground">
                Yes, all paid plans include a 14-day free trial. No credit card required to start.
              </p>
            </div>
            <div>
              <h3 className="font-semibold mb-2">Can I cancel anytime?</h3>
              <p className="text-muted-foreground">
                Absolutely. You can cancel your subscription at any time from your account settings.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
