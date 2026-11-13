/**
 * Voice settings must be reachable. The Chat Preferences block (and its
 * voice toggles) historically lived inside `{false && (<>…</>)}`, so the
 * sidebar never showed a Chat tab — "Settings → Chat → Voice" was unreachable.
 */
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const SRC = resolve(__dirname, 'settings-dialog.tsx')

describe('settings-dialog voice tab', () => {
  const src = readFileSync(SRC, 'utf8')

  it('exposes a sidebar Voice tab trigger', () => {
    expect(src).toMatch(/data-testid="tab-voice"/)
    expect(src).toMatch(/value="voice"/)
  })

  it('renders voice switches outside the {false && …} gate', () => {
    const gateStart = src.indexOf('{false && (<>')
    const gateEnd = src.indexOf('</>)}{/* end commented-out non-api-keys tabs */}')
    expect(gateStart).toBeGreaterThan(-1)
    expect(gateEnd).toBeGreaterThan(gateStart)

    const enabledIdx = src.indexOf('data-testid="switch-voice-enabled"')
    const handsFreeIdx = src.indexOf('data-testid="switch-voice-hands-free"')
    const voiceTabIdx = src.indexOf('data-testid="tab-content-voice"')

    expect(voiceTabIdx).toBeGreaterThan(gateEnd)
    expect(enabledIdx).toBeGreaterThan(gateEnd)
    expect(handsFreeIdx).toBeGreaterThan(gateEnd)
  })
})
