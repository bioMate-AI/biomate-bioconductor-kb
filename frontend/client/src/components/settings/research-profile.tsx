import { useState, useEffect, useCallback } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Skeleton } from "@/components/ui/skeleton"
import { DomainProfileSelector } from "@/components/domain-profile-selector"
import type { DomainProfile } from "@/components/domain-profile-selector"
import { CheckCircle2, FlaskConical } from "lucide-react"

// ── API helpers ───────────────────────────────────────────────────────────────

async function fetchDomainProfile(): Promise<DomainProfile> {
  const res = await fetch("/api/user/domain-profile", { credentials: "include" })
  if (!res.ok) return { domains: [], topics: [] }
  return res.json() as Promise<DomainProfile>
}

async function saveDomainProfile(profile: DomainProfile): Promise<void> {
  const res = await fetch("/api/user/domain-profile", {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(profile),
  })
  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw new Error((body as { error?: string }).error ?? "Failed to save profile")
  }
}

// ── Domain label map (matches taxonomy) ──────────────────────────────────────

const DOMAIN_LABELS: Record<string, string> = {
  genomics: "Genomics",
  transcriptomics: "Transcriptomics",
  single_cell: "Single Cell",
  epigenomics: "Epigenomics",
  proteomics: "Proteomics",
  metabolomics: "Metabolomics",
  metagenomics: "Metagenomics",
  structural_biology: "Structural Biology",
  drug_discovery: "Drug Discovery",
  cryo_em: "Cryo-EM",
  pharmacology: "Pharmacology",
  systems_biology: "Systems Biology",
  synthetic_biology: "Synthetic Biology",
  bioimaging: "Bioimaging",
}

// ── Component ─────────────────────────────────────────────────────────────────

interface ResearchProfilePanelProps {
  /** Optional callback invoked after a successful save. */
  onSaved?: (profile: DomainProfile) => void
}

export function ResearchProfilePanel({ onSaved }: ResearchProfilePanelProps) {
  const [profile, setProfile] = useState<DomainProfile | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [savedAt, setSavedAt] = useState<Date | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const p = await fetchDomainProfile()
      setProfile(p)
      setEditing(p.domains.length === 0)
    } catch {
      setProfile({ domains: [], topics: [] })
      setEditing(true)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const handleSave = async (updated: DomainProfile) => {
    setSaving(true)
    setError(null)
    try {
      await saveDomainProfile(updated)
      setProfile(updated)
      setSavedAt(new Date())
      setEditing(false)
      onSaved?.(updated)
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Unexpected error")
    } finally {
      setSaving(false)
    }
  }

  const handleSkip = () => {
    setEditing(false)
    if (!profile || profile.domains.length === 0) {
      setProfile({ domains: [], topics: [] })
    }
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center gap-2">
          <FlaskConical className="h-5 w-5 text-primary" />
          <CardTitle className="text-base">Research Profile</CardTitle>
        </div>
        <CardDescription className="text-xs leading-relaxed">
          BioMate uses this as your starting context for workflow recommendations.
          Your current conversation always takes precedence.
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        {loading ? (
          <div className="space-y-3">
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-3/4" />
            <Skeleton className="h-8 w-1/2" />
          </div>
        ) : editing ? (
          <>
            {error && (
              <Alert variant="destructive" className="py-2">
                <AlertDescription className="text-xs">{error}</AlertDescription>
              </Alert>
            )}
            <DomainProfileSelector
              initialProfile={profile ?? undefined}
              onSave={handleSave}
              onSkip={handleSkip}
            />
            {saving && (
              <p className="text-xs text-muted-foreground text-center">Saving…</p>
            )}
          </>
        ) : (
          <>
            {savedAt && (
              <div className="flex items-center gap-2 text-xs text-emerald-600 dark:text-emerald-400">
                <CheckCircle2 className="h-4 w-4 shrink-0" />
                Profile saved
              </div>
            )}

            {profile && profile.domains.length > 0 ? (
              <div className="space-y-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
                    Domains
                  </p>
                  <div className="flex flex-wrap gap-1.5">
                    {profile.domains.map(d => (
                      <Badge key={d} variant="secondary" className="text-xs">
                        {DOMAIN_LABELS[d] ?? d}
                      </Badge>
                    ))}
                  </div>
                </div>

                {profile.topics.length > 0 && (
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
                      Topics
                    </p>
                    <div className="flex flex-wrap gap-1.5">
                      {profile.topics.map(t => (
                        <Badge key={t} variant="outline" className="text-xs font-normal">
                          {t}
                        </Badge>
                      ))}
                    </div>
                  </div>
                )}

                <button
                  type="button"
                  onClick={() => setEditing(true)}
                  className="text-xs text-primary underline-offset-4 hover:underline mt-1"
                >
                  Edit profile
                </button>
              </div>
            ) : (
              <div className="text-center py-4 space-y-2">
                <p className="text-sm text-muted-foreground">No research profile set.</p>
                <button
                  type="button"
                  onClick={() => setEditing(true)}
                  className="text-xs text-primary underline-offset-4 hover:underline"
                >
                  Set up your profile
                </button>
              </div>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}
