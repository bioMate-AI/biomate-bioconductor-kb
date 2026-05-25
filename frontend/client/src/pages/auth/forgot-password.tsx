import { useState } from "react"
import { useLocation } from "wouter"
import { api } from "@/lib/api"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Loader2, CheckCircle2, ArrowLeft, Link2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"

export default function ForgotPasswordPage() {
  const [, setLocation] = useLocation()
  const { toast } = useToast()
  const [email, setEmail] = useState("")
  const [isLoading, setIsLoading] = useState(false)
  const [success, setSuccess] = useState(false)
  const [resetToken, setResetToken] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setIsLoading(true)

    try {
      const result = await api.forgotPassword(email) as any
      setSuccess(true)
      if (result?.resetToken) {
        setResetToken(result.resetToken)
      }
    } catch (error) {
      toast({
        variant: "destructive",
        title: "Failed to send reset request",
        description: error instanceof Error ? error.message : "Please try again.",
      })
    } finally {
      setIsLoading(false)
    }
  }

  if (success) {
    return (
      <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-blue-500/10 via-purple-500/10 to-pink-500/10">
        <Card className="w-full max-w-md">
          <CardHeader className="space-y-1 text-center">
            <div className="flex justify-center mb-3">
              <img src="/biomate-logo.png" alt="BioMate" className="h-10 w-auto" />
            </div>
            <div className="flex justify-center mb-2">
              <div className="rounded-full bg-blue-100 dark:bg-blue-900 p-3">
                <CheckCircle2 className="h-8 w-8 text-blue-600 dark:text-blue-400" />
              </div>
            </div>
            <CardTitle className="text-2xl font-bold">
              Check your email
            </CardTitle>
            <CardDescription>
              We've sent password reset instructions to <strong>{email}</strong>
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {resetToken ? (
              <div className="rounded-md border border-amber-300 bg-amber-50 dark:bg-amber-950 p-3 space-y-2">
                <p className="text-xs font-medium text-amber-800 dark:text-amber-200 flex items-center gap-1">
                  <Link2 className="h-3 w-3" /> Email not configured — click your reset link directly:
                </p>
                <a
                  href={`/reset-password?token=${resetToken}`}
                  className="text-xs break-all text-blue-600 dark:text-blue-400 underline"
                >
                  {window.location.origin}/reset-password?token={resetToken}
                </a>
              </div>
            ) : (
              <p className="text-sm text-muted-foreground text-center">
                Didn't receive the email? Check your spam folder or try again with a different email address.
              </p>
            )}
            <Button
              variant="outline"
              className="w-full"
              onClick={() => { setSuccess(false); setResetToken(null) }}
            >
              Try another email
            </Button>
          </CardContent>
          <CardFooter>
            <Button
              variant="link"
              className="w-full"
              onClick={() => setLocation('/login')}
            >
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back to login
            </Button>
          </CardFooter>
        </Card>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-blue-500/10 via-purple-500/10 to-pink-500/10">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1 text-center">
          <div className="flex justify-center mb-3">
            <img src="/biomate-logo.png" alt="BioMate" className="h-10 w-auto" />
          </div>
          <CardTitle className="text-2xl font-bold">
            Reset your password
          </CardTitle>
          <CardDescription className="text-center">
            Enter your email address and we'll send you a link to reset your password
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">

            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="name@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={isLoading}
                required
              />
            </div>

            <Button type="submit" className="w-full" disabled={isLoading}>
              {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Send Reset Link
            </Button>
          </form>
        </CardContent>
        <CardFooter>
          <Button
            variant="link"
            className="w-full"
            onClick={() => setLocation('/login')}
          >
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back to login
          </Button>
        </CardFooter>
      </Card>
    </div>
  )
}
