import React, { useState } from 'react'
import { KeyRound, ArrowRight, Loader2, CheckCircle, AlertCircle } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

export interface CredentialRequiredInfo {
  missing_credential: string   // e.g. "boltz2"
  tool_name: string            // e.g. "Boltz-2"
  fallback_method: string      // e.g. "chai1"
  fallback_name: string        // e.g. "Chai-1"
  message: string
}

interface Props {
  info: CredentialRequiredInfo
  onUseAlternative: (alternativeMethod: string, alternativeName: string) => void
  onCredentialSaved: (toolName: string) => void
}

export function WorkflowCredentialRequiredCard({ info, onUseAlternative, onCredentialSaved }: Props) {
  const [apiKey, setApiKey] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState(false)

  const handleSave = async () => {
    if (!apiKey.trim()) {
      setError('Please enter your API key.')
      return
    }
    setError('')
    setSaving(true)
    try {
      const res = await fetch('/api/users/credentials', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tool: info.missing_credential,
          data: { api_key: apiKey.trim() },
        }),
      })
      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        throw new Error(body?.detail || `HTTP ${res.status}`)
      }
      setSaved(true)
      onCredentialSaved(info.tool_name)
    } catch (err: any) {
      setError(err.message || 'Failed to save credential.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="rounded-lg border border-amber-200 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/30 p-4 space-y-3 max-w-xl">
      <div className="flex items-start gap-2.5">
        <KeyRound className="h-4 w-4 mt-0.5 text-amber-600 dark:text-amber-400 shrink-0" />
        <div className="space-y-1">
          <p className="text-sm font-medium text-amber-900 dark:text-amber-200">
            {info.tool_name} requires a credential
          </p>
          <p className="text-xs text-amber-700 dark:text-amber-400 leading-relaxed">
            {info.message}
          </p>
        </div>
      </div>

      {!saved ? (
        <>
          <div className="space-y-1.5">
            <Label htmlFor="cred-api-key" className="text-xs text-amber-800 dark:text-amber-300">
              {info.tool_name} API key
            </Label>
            <Input
              id="cred-api-key"
              type="password"
              value={apiKey}
              onChange={e => { setApiKey(e.target.value); setError('') }}
              placeholder="Paste your API key here"
              autoComplete="new-password"
              className="h-8 text-sm bg-white dark:bg-zinc-900 border-amber-300 dark:border-amber-700"
              onKeyDown={e => { if (e.key === 'Enter') handleSave() }}
            />
            {error && (
              <p className="text-xs text-red-600 dark:text-red-400 flex items-center gap-1">
                <AlertCircle className="h-3 w-3 shrink-0" />{error}
              </p>
            )}
          </div>

          <div className="flex items-center gap-2 pt-1">
            <Button
              size="sm"
              className="h-7 text-xs bg-amber-600 hover:bg-amber-700 text-white"
              onClick={handleSave}
              disabled={saving || !apiKey.trim()}
            >
              {saving ? (
                <><Loader2 className="h-3 w-3 mr-1.5 animate-spin" />Saving…</>
              ) : (
                <>Save &amp; run with {info.tool_name}</>
              )}
            </Button>

            <span className="text-xs text-muted-foreground">or</span>

            <Button
              variant="outline"
              size="sm"
              className="h-7 text-xs"
              onClick={() => onUseAlternative(info.fallback_method, info.fallback_name)}
            >
              Use {info.fallback_name} instead
              <ArrowRight className="h-3 w-3 ml-1" />
            </Button>
          </div>
        </>
      ) : (
        <div className="flex items-center gap-2 text-sm text-green-700 dark:text-green-400">
          <CheckCircle className="h-4 w-4 shrink-0" />
          Credential saved — re-running with {info.tool_name}…
        </div>
      )}
    </div>
  )
}
