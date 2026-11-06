import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { ProgressStreamBox } from './chat-progress-fold'
import type { Message } from '@shared/schema'

const messages = (count: number): Message[] => Array.from({ length: count }, (_, i) => ({
  id: `event-${i}`, role: 'assistant', content: `Update ${i}`, timestamp: new Date(),
}))

describe('inline progress reading', () => {
  it('keeps the reading position until the reader returns to the tail', () => {
    const { rerender } = render(<ProgressStreamBox messages={messages(10)} inline />)
    const log = screen.getByRole('log', { name: 'Workflow updates' })
    Object.defineProperties(log, {
      scrollHeight: { configurable: true, value: 1000 },
      clientHeight: { configurable: true, value: 132 },
    })
    log.scrollTop = 100
    fireEvent.scroll(log)
    rerender(<ProgressStreamBox messages={messages(11)} inline />)
    expect(log.scrollTop).toBe(100)
    log.scrollTop = 868
    fireEvent.scroll(log)
    rerender(<ProgressStreamBox messages={messages(12)} inline />)
    expect(log.scrollTop).toBe(1000)
    expect(log.getAttribute('aria-live')).toBe('off')
    expect(log.getAttribute('tabindex')).toBe('0')
    expect(log.querySelectorAll('details')).toHaveLength(0)
    expect(log.textContent).toContain('Update 0')
    expect(log.textContent).toContain('Update 11')
  })
})
