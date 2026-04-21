/**
 * TutorialTipOverlay — floating callout bubbles for demo videos.
 * Triggered from Playwright via: window.__biomate_tip(text, durationMs?)
 */
import { useState, useEffect } from 'react'

interface Tip {
  id: number
  text: string
}

let tipCounter = 0

export function TutorialTipOverlay() {
  const [tips, setTips] = useState<Tip[]>([])

  useEffect(() => {
    // Expose global function for Playwright to call
    ;(window as any).__biomate_tip = (text: string, durationMs = 4000) => {
      const id = ++tipCounter
      setTips(prev => [...prev, { id, text }])
      setTimeout(() => {
        setTips(prev => prev.filter(t => t.id !== id))
      }, durationMs)
    }
    return () => {
      delete (window as any).__biomate_tip
    }
  }, [])

  if (tips.length === 0) return null

  return (
    <div
      className="fixed bottom-6 left-6 z-[9999] flex flex-col gap-2 max-w-xs pointer-events-none"
      data-testid="tutorial-tip-overlay"
    >
      {tips.map(tip => (
        <div
          key={tip.id}
          className="animate-in slide-in-from-bottom-2 fade-in duration-300 rounded-xl border border-blue-200 bg-blue-600 px-4 py-3 text-sm font-medium text-white shadow-lg"
          data-testid="tutorial-tip-bubble"
        >
          <div className="flex items-start gap-2">
            <span className="mt-0.5 text-blue-200 shrink-0">💡</span>
            <span>{tip.text}</span>
          </div>
        </div>
      ))}
    </div>
  )
}
