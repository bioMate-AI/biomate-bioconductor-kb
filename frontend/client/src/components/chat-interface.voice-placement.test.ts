/**
 * Guard: voice must live only inside ChatInput's toolbar.
 * A second LiveVoicePanel above the composer reintroduces the stacked
 * "Start voice" / Speak panels that ruined the live UI (2026-11-13).
 */
import fs from 'fs'
import path from 'path'
import { describe, expect, it } from 'vitest'

const root = __dirname

describe('composer voice placement', () => {
  it('does not mount LiveVoicePanel above ChatInput in chat-interface', () => {
    const src = fs.readFileSync(path.join(root, 'chat-interface.tsx'), 'utf-8')
    expect(src).not.toMatch(/import\s*\{\s*LiveVoicePanel\s*\}\s*from/)
    expect(src).not.toMatch(/<LiveVoicePanel\b/)
  })

  it('mounts Speak + Live only inside the chat-input toolbar', () => {
    const src = fs.readFileSync(path.join(root, 'chat-input.tsx'), 'utf-8')
    expect(src).toMatch(/import\s*\{\s*VoiceInput\s*\}\s*from\s*["']\.\/voice-controls["']/)
    expect(src).toMatch(/import\s*\{\s*LiveVoicePanel\s*\}\s*from\s*["']\.\/live-voice-panel["']/)
    expect(src).toMatch(/<VoiceInput\b/)
    expect(src).toMatch(/<LiveVoicePanel\b/)
    // Icons must sit inside the composer card, not as siblings above it.
    const cardIdx = src.indexOf('className="chat-input"')
    const speakIdx = src.indexOf('<VoiceInput')
    const liveIdx = src.indexOf('<LiveVoicePanel')
    expect(cardIdx).toBeGreaterThan(-1)
    expect(speakIdx).toBeGreaterThan(cardIdx)
    expect(liveIdx).toBeGreaterThan(cardIdx)
  })

  it('keeps vendor / AI-voice disclaimer copy out of voice UI surfaces', () => {
    const files = [
      'live-voice-panel.tsx',
      'voice-controls.tsx',
      'settings-dialog.tsx',
    ]
    // SDK package imports may mention the vendor; ban user-facing disclaimer prose only.
    const banned = [
      /Audio is sent to ElevenLabs/i,
      /Audio goes to ElevenLabs/i,
      /Recordings are sent to ElevenLabs/i,
      /AI-generated voice/i,
      /Replies use an AI-generated voice/i,
      /replies can use an AI-generated voice/i,
      /Read-aloud uses an AI-generated voice/i,
      /AI-generated voice by ElevenLabs/i,
    ]
    for (const file of files) {
      const src = fs.readFileSync(path.join(root, file), 'utf-8')
      for (const pattern of banned) {
        expect(src, `${file} matched ${pattern}`).not.toMatch(pattern)
      }
    }
  })
})
