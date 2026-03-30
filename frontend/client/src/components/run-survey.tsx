/**
 * RunSurvey — post-run satisfaction survey for pilot study evidence collection.
 * Shown automatically when a workflow transitions to "completed" status.
 * Submits to POST /api/feedback with type "run_survey".
 */
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { X } from 'lucide-react'

interface RunSurveyProps {
  invocationId: string
  workflowName?: string
  onDismiss: () => void
}

const QUESTIONS = [
  {
    id: 'publication_ready',
    text: 'The QC output is suitable for inclusion in a publication methods section.',
    scale: 5,
  },
  {
    id: 'time_saved',
    text: 'BioMate saved me significant time compared to my previous approach.',
    scale: 5,
  },
  {
    id: 'would_pay',
    text: 'I would pay $29/month to continue using BioMate.',
    options: ['Yes, from my lab budget', 'Yes, from my personal budget', 'Maybe', 'No'],
  },
  {
    id: 'prior_time_hours',
    text: 'How long would this analysis have taken without BioMate? (hours)',
    input: 'number',
  },
  {
    id: 'free_text',
    text: 'Any other feedback? (optional)',
    input: 'text',
  },
] as const

type QuestionId = typeof QUESTIONS[number]['id']

export function RunSurvey({ invocationId, workflowName, onDismiss }: RunSurveyProps) {
  const [answers, setAnswers] = useState<Record<string, string | number>>({})
  const [submitted, setSubmitted] = useState(false)
  const [submitting, setSubmitting] = useState(false)

  const handleSubmit = async () => {
    setSubmitting(true)
    try {
      await fetch('/api/feedback', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          feedback_type: 'run_survey',
          invocation_id: invocationId,
          workflow_name: workflowName,
          answers,
          submitted_at: new Date().toISOString(),
        }),
      })
      setSubmitted(true)
      setTimeout(onDismiss, 2000)
    } catch {
      // fail silently — never block the user
      onDismiss()
    } finally {
      setSubmitting(false)
    }
  }

  if (submitted) {
    return (
      <Card data-testid="run-survey" className="border-green-200 bg-green-50 dark:border-green-800 dark:bg-green-950/20">
        <CardContent className="pt-4 text-sm text-green-800 dark:text-green-200">
          ✓ Thank you for your feedback — it helps us improve BioMate.
        </CardContent>
      </Card>
    )
  }

  return (
    <Card data-testid="run-survey" className="border-blue-100 bg-blue-50/50 dark:border-blue-900 dark:bg-blue-950/10">
      <CardHeader className="pb-2 flex flex-row items-center justify-between">
        <CardTitle className="text-sm font-medium">
          Quick feedback on this run {workflowName ? `(${workflowName})` : ''}
        </CardTitle>
        <Button variant="ghost" size="icon" className="h-6 w-6" onClick={onDismiss}>
          <X className="h-3 w-3" />
        </Button>
      </CardHeader>
      <CardContent className="space-y-4 text-sm">
        {QUESTIONS.map((q) => (
          <div key={q.id}>
            <p className="mb-1 font-medium text-foreground">{q.text}</p>
            {'scale' in q && q.scale && (
              <div className="flex gap-2">
                {(['Strongly disagree', 'Disagree', 'Neutral', 'Agree', 'Strongly agree'] as const).map((label, i) => (
                  <button
                    key={i}
                    data-testid={`survey-${q.id}-${i + 1}`}
                    className={`flex-1 rounded border py-1 text-xs transition-colors ${
                      answers[q.id] === i + 1
                        ? 'border-blue-500 bg-blue-500 text-white'
                        : 'border-border hover:bg-muted'
                    }`}
                    onClick={() => setAnswers(a => ({ ...a, [q.id]: i + 1 }))}
                    title={label}
                  >
                    {i + 1}
                  </button>
                ))}
              </div>
            )}
            {'options' in q && q.options && (
              <div className="flex flex-wrap gap-2">
                {q.options.map((opt) => (
                  <button
                    key={opt}
                    data-testid={`survey-${q.id}-${opt.replace(/\s+/g, '-').toLowerCase()}`}
                    className={`rounded border px-3 py-1 text-xs transition-colors ${
                      answers[q.id] === opt
                        ? 'border-blue-500 bg-blue-500 text-white'
                        : 'border-border hover:bg-muted'
                    }`}
                    onClick={() => setAnswers(a => ({ ...a, [q.id]: opt }))}
                  >
                    {opt}
                  </button>
                ))}
              </div>
            )}
            {'input' in q && q.input === 'number' && (
              <input
                type="number"
                min={0}
                data-testid={`survey-${q.id}`}
                className="w-24 rounded border border-border bg-background px-2 py-1 text-sm"
                value={answers[q.id] ?? ''}
                onChange={(e) => setAnswers(a => ({ ...a, [q.id]: Number(e.target.value) }))}
              />
            )}
            {'input' in q && q.input === 'text' && (
              <textarea
                data-testid={`survey-${q.id}`}
                className="w-full rounded border border-border bg-background px-2 py-1 text-sm"
                rows={2}
                value={answers[q.id] ?? ''}
                onChange={(e) => setAnswers(a => ({ ...a, [q.id]: e.target.value }))}
              />
            )}
          </div>
        ))}
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="ghost" size="sm" onClick={onDismiss}>Skip</Button>
          <Button
            data-testid="survey-submit"
            size="sm"
            disabled={submitting}
            onClick={handleSubmit}
          >
            {submitting ? 'Sending…' : 'Submit feedback'}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}
