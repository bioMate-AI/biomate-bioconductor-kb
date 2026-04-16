import { useEffect, useState } from "react"
import { useLocation, useSearch } from "wouter"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { CheckCircle2, XCircle, Loader2 } from "lucide-react"
import { api } from "@/lib/api"

type Status = "verifying" | "success" | "error"

export default function VerifyEmailPage() {
  const [, setLocation] = useLocation()
  const search = useSearch()
  const token = new URLSearchParams(search).get("token") ?? ""

  const [status, setStatus] = useState<Status>("verifying")
  const [message, setMessage] = useState("")

  useEffect(() => {
    if (!token) {
      setStatus("error")
      setMessage("No verification token found. Please use the link from your email.")
      return
    }

    api.verifyEmail(token)
      .then(() => {
        setStatus("success")
        setMessage("Your email has been verified. You now have full access to BioMate.")
      })
      .catch((err) => {
        setStatus("error")
        setMessage(
          err instanceof Error && err.message
            ? err.message
            : "Verification failed. The link may have expired or already been used."
        )
      })
  }, [token])

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-blue-500/10 via-purple-500/10 to-pink-500/10">
      <Card className="w-full max-w-md text-center">
        <CardHeader className="space-y-1">
          <div className="flex justify-center mb-4">
            {status === "verifying" && (
              <div className="rounded-full bg-blue-100 dark:bg-blue-900 p-3">
                <Loader2 className="h-8 w-8 text-blue-600 dark:text-blue-400 animate-spin" />
              </div>
            )}
            {status === "success" && (
              <div className="rounded-full bg-green-100 dark:bg-green-900 p-3">
                <CheckCircle2 className="h-8 w-8 text-green-600 dark:text-green-400" />
              </div>
            )}
            {status === "error" && (
              <div className="rounded-full bg-red-100 dark:bg-red-900 p-3">
                <XCircle className="h-8 w-8 text-red-600 dark:text-red-400" />
              </div>
            )}
          </div>

          <CardTitle className="text-2xl font-bold">
            {status === "verifying" && "Verifying your email…"}
            {status === "success" && "Email verified!"}
            {status === "error" && "Verification failed"}
          </CardTitle>
          <CardDescription>{message}</CardDescription>
        </CardHeader>

        <CardContent className="space-y-3">
          {status === "success" && (
            <Button className="w-full" onClick={() => setLocation("/login")}>
              Go to Login
            </Button>
          )}
          {status === "error" && (
            <>
              <Button className="w-full" onClick={() => setLocation("/login")}>
                Go to Login
              </Button>
              <p className="text-xs text-muted-foreground">
                You can request a new verification email from your account settings after logging in.
              </p>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
