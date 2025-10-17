import { useState, useEffect } from "react"
import { useLocation, useRoute } from "wouter"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Separator } from "@/components/ui/separator"
import { Badge } from "@/components/ui/badge"
import { Loader2, AlertCircle, CreditCard, Lock, Check } from "lucide-react"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"

export default function CheckoutPage() {
  const [, params] = useRoute('/checkout/:plan')
  const [, setLocation] = useLocation()
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [paymentMethod, setPaymentMethod] = useState("card")

  const plan = params?.plan || 'pro'

  const planDetails = {
    pro: { name: "Pro", price: 49, features: ["Unlimited workflows", "Advanced AI", "Priority support"] },
    team: { name: "Team", price: 149, features: ["Everything in Pro", "10 team members", "Shared workspaces"] }
  }

  const selectedPlan = planDetails[plan as keyof typeof planDetails] || planDetails.pro

  const [formData, setFormData] = useState({
    cardNumber: "",
    cardName: "",
    expiryDate: "",
    cvv: "",
    billingAddress: "",
    city: "",
    zipCode: "",
    country: ""
  })

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")
    setIsLoading(true)

    // Simulate payment processing
    setTimeout(() => {
      // TODO: Implement actual payment processing
      setLocation('/dashboard')
    }, 2000)
  }

  return (
    <div className="min-h-screen bg-background py-12">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center mb-8">
          <h1 className="text-3xl font-bold mb-2">Complete your subscription</h1>
          <p className="text-muted-foreground">
            Secure checkout powered by Stripe
          </p>
        </div>

        <div className="grid lg:grid-cols-3 gap-8">
          {/* Order Summary */}
          <div className="lg:col-span-1">
            <Card>
              <CardHeader>
                <CardTitle>Order Summary</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <span className="font-semibold">{selectedPlan.name} Plan</span>
                    <Badge>14-day trial</Badge>
                  </div>
                  <ul className="space-y-2 text-sm text-muted-foreground">
                    {selectedPlan.features.map((feature, index) => (
                      <li key={index} className="flex items-start gap-2">
                        <Check className="h-4 w-4 text-blue-600 dark:text-blue-400 shrink-0 mt-0.5" />
                        <span>{feature}</span>
                      </li>
                    ))}
                  </ul>
                </div>

                <Separator />

                <div className="space-y-2">
                  <div className="flex justify-between text-sm">
                    <span>Subtotal</span>
                    <span>${selectedPlan.price}/mo</span>
                  </div>
                  <div className="flex justify-between text-sm text-muted-foreground">
                    <span>Trial period (14 days)</span>
                    <span>Free</span>
                  </div>
                  <Separator />
                  <div className="flex justify-between font-semibold text-lg">
                    <span>Due today</span>
                    <span>$0</span>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    You'll be charged ${selectedPlan.price} on{" "}
                    {new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toLocaleDateString()}
                  </p>
                </div>
              </CardContent>
            </Card>

            <Card className="mt-4">
              <CardHeader>
                <div className="flex items-center gap-2">
                  <Lock className="h-4 w-4" />
                  <CardTitle className="text-base">Secure Checkout</CardTitle>
                </div>
              </CardHeader>
              <CardContent className="text-sm text-muted-foreground">
                Your payment information is encrypted and secure. We never store your full card details.
              </CardContent>
            </Card>
          </div>

          {/* Payment Form */}
          <div className="lg:col-span-2">
            <Card>
              <CardHeader>
                <CardTitle>Payment Details</CardTitle>
                <CardDescription>
                  Enter your payment information to start your free trial
                </CardDescription>
              </CardHeader>
              <CardContent>
                <form onSubmit={handleSubmit} className="space-y-6">
                  {error && (
                    <Alert variant="destructive">
                      <AlertCircle className="h-4 w-4" />
                      <AlertDescription>{error}</AlertDescription>
                    </Alert>
                  )}

                  {/* Payment Method Selection */}
                  <div className="space-y-3">
                    <Label>Payment Method</Label>
                    <RadioGroup value={paymentMethod} onValueChange={setPaymentMethod}>
                      <div className="flex items-center space-x-2 border rounded-lg p-4">
                        <RadioGroupItem value="card" id="card" />
                        <Label htmlFor="card" className="flex-1 cursor-pointer">
                          <div className="flex items-center gap-2">
                            <CreditCard className="h-4 w-4" />
                            <span>Credit or Debit Card</span>
                          </div>
                        </Label>
                        <div className="flex gap-2">
                          <img src="https://js.stripe.com/v3/fingerprinted/img/visa-729c05c240c4bdb47b03ac81d9945bfe.svg" alt="Visa" className="h-6" />
                          <img src="https://js.stripe.com/v3/fingerprinted/img/mastercard-4d8844094130711885b5e41b28c9848f.svg" alt="Mastercard" className="h-6" />
                          <img src="https://js.stripe.com/v3/fingerprinted/img/amex-a49b82f46c5cd6a96a6e418a6ca1717c.svg" alt="Amex" className="h-6" />
                        </div>
                      </div>
                    </RadioGroup>
                  </div>

                  {/* Card Information */}
                  <div className="space-y-4">
                    <div className="space-y-2">
                      <Label htmlFor="cardNumber">Card Number</Label>
                      <Input
                        id="cardNumber"
                        placeholder="1234 5678 9012 3456"
                        value={formData.cardNumber}
                        onChange={(e) => setFormData({ ...formData, cardNumber: e.target.value })}
                        disabled={isLoading}
                        required
                      />
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="cardName">Cardholder Name</Label>
                      <Input
                        id="cardName"
                        placeholder="John Doe"
                        value={formData.cardName}
                        onChange={(e) => setFormData({ ...formData, cardName: e.target.value })}
                        disabled={isLoading}
                        required
                      />
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                      <div className="space-y-2">
                        <Label htmlFor="expiryDate">Expiry Date</Label>
                        <Input
                          id="expiryDate"
                          placeholder="MM/YY"
                          value={formData.expiryDate}
                          onChange={(e) => setFormData({ ...formData, expiryDate: e.target.value })}
                          disabled={isLoading}
                          required
                        />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="cvv">CVV</Label>
                        <Input
                          id="cvv"
                          placeholder="123"
                          value={formData.cvv}
                          onChange={(e) => setFormData({ ...formData, cvv: e.target.value })}
                          disabled={isLoading}
                          required
                        />
                      </div>
                    </div>
                  </div>

                  <Separator />

                  {/* Billing Address */}
                  <div className="space-y-4">
                    <h3 className="font-semibold">Billing Address</h3>

                    <div className="space-y-2">
                      <Label htmlFor="billingAddress">Street Address</Label>
                      <Input
                        id="billingAddress"
                        placeholder="123 Main St"
                        value={formData.billingAddress}
                        onChange={(e) => setFormData({ ...formData, billingAddress: e.target.value })}
                        disabled={isLoading}
                        required
                      />
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                      <div className="space-y-2">
                        <Label htmlFor="city">City</Label>
                        <Input
                          id="city"
                          placeholder="San Francisco"
                          value={formData.city}
                          onChange={(e) => setFormData({ ...formData, city: e.target.value })}
                          disabled={isLoading}
                          required
                        />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="zipCode">ZIP Code</Label>
                        <Input
                          id="zipCode"
                          placeholder="94102"
                          value={formData.zipCode}
                          onChange={(e) => setFormData({ ...formData, zipCode: e.target.value })}
                          disabled={isLoading}
                          required
                        />
                      </div>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="country">Country</Label>
                      <Input
                        id="country"
                        placeholder="United States"
                        value={formData.country}
                        onChange={(e) => setFormData({ ...formData, country: e.target.value })}
                        disabled={isLoading}
                        required
                      />
                    </div>
                  </div>

                  <Alert>
                    <AlertDescription className="text-sm">
                      By confirming your subscription, you agree to our{" "}
                      <Button variant="link" className="px-0 h-auto text-sm" onClick={() => window.open('/terms', '_blank')}>
                        Terms of Service
                      </Button>{" "}
                      and{" "}
                      <Button variant="link" className="px-0 h-auto text-sm" onClick={() => window.open('/privacy', '_blank')}>
                        Privacy Policy
                      </Button>
                      . Your subscription will automatically renew after the trial period.
                    </AlertDescription>
                  </Alert>

                  <Button type="submit" className="w-full" size="lg" disabled={isLoading}>
                    {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Start Free Trial
                  </Button>
                </form>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    </div>
  )
}
