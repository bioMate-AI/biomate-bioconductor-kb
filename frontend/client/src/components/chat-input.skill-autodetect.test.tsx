/**
 * Empty / default-only skill selection must NOT send skillPackIds, so the
 * server auto-detects experts from the message. Sending [] or only
 * biomate-universe marks the selection explicit and skips auto-detect.
 */
import React from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ChatInput } from './chat-input';
import { DEFAULT_SKILL_ID } from './skills-selector';

const PACKS = [
  { id: DEFAULT_SKILL_ID, label: 'BioMate Platform', description: 'Capability map.', source: 'expert' },
  { id: 'drug-discovery-chemist', label: 'Drug Discovery Chemist', description: 'Medchem.', source: 'expert' },
];

async function openExpertsPopover() {
  fireEvent.click(screen.getByTestId('composer-experts-toggle'));
  expect(await screen.findByTestId('composer-experts-popover')).toBeTruthy();
}

describe('ChatInput — skillPackIds auto-detect contract', () => {
  afterEach(() => { vi.unstubAllGlobals(); window.history.replaceState(null, '', '/'); });

  it('omits skillPackIds when only the locked default is selected (project active)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: true,
      json: async () => ({ settings: { outputRequirements: '', skillPackIds: [] } }),
    })));
    const onSend = vi.fn();
    render(
      <ChatInput
        activeProjectId="project-a"
        onSend={onSend}
        skillPacks={PACKS}
        projects={[{ id: 'project-a', name: 'Pilot' }]}
      />,
    );
    fireEvent.input(screen.getByTestId('chat-input'), { target: { value: 'Dock these SMILES vs EGFR.' } });
    // Send stays disabled while project instruction-settings load; wait for ready.
    await waitFor(() => expect(screen.getByTestId('chat-send-button')).not.toBeDisabled());

    // Confirm the locked default is in UI selection (auto-injected) without sending it alone.
    await openExpertsPopover();
    expect(screen.getByTestId(`composer-expert-pack-${DEFAULT_SKILL_ID}`)).toHaveAttribute('data-active', 'true');
    expect(screen.getByTestId(`composer-expert-pack-${DEFAULT_SKILL_ID}`)).toHaveAttribute('data-locked', 'true');

    fireEvent.click(screen.getByTestId('chat-send-button'));
    expect(onSend).toHaveBeenCalledTimes(1);
    const ctx = onSend.mock.calls[0][2] as Record<string, unknown> | undefined;
    expect(ctx?.skillPackIds).toBeUndefined();
  });

  it('sends default + explicit expert when the user toggles an expert on', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: true,
      json: async () => ({ settings: { outputRequirements: '', skillPackIds: [] } }),
    })));
    const onSend = vi.fn();
    render(
      <ChatInput
        activeProjectId="project-a"
        onSend={onSend}
        skillPacks={PACKS}
        projects={[{ id: 'project-a', name: 'Pilot' }]}
      />,
    );
    fireEvent.input(screen.getByTestId('chat-input'), { target: { value: 'Prioritize these leads.' } });
    await waitFor(() => expect(screen.getByTestId('chat-send-button')).not.toBeDisabled());

    await openExpertsPopover();
    fireEvent.click(screen.getByTestId('composer-expert-pack-drug-discovery-chemist'));
    expect(screen.getByTestId('composer-expert-pack-drug-discovery-chemist')).toHaveAttribute('data-active', 'true');

    fireEvent.click(screen.getByTestId('chat-send-button'));
    expect(onSend).toHaveBeenCalledTimes(1);
    expect(onSend.mock.calls[0][2].skillPackIds).toEqual([
      DEFAULT_SKILL_ID,
      'drug-discovery-chemist',
    ]);
  });
});
