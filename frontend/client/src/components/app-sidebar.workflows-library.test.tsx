/**
 * AppSidebar — the "Workflows" entry navigates to the full-page /workflows
 * library (consistent with /models), NOT the dead StarredWorkflowsDialog.
 *
 * Only fetch is mocked; the auth/active-project contexts and the heavy dialogs
 * are stubbed so the test stays scoped to the sidebar nav wiring.
 */
import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';

const { setLocationSpy } = vi.hoisted(() => ({ setLocationSpy: vi.fn() }));
vi.mock('wouter', () => ({ useLocation: () => ['/', setLocationSpy] }));
vi.mock('@/contexts/auth-context', () => ({
  useAuth: () => ({ user: { id: 1, email: 'lifeifei163361@163.com' }, logout: vi.fn() }),
}));
vi.mock('@/contexts/active-project-context', () => ({
  useActiveProject: () => ({ activeProjectId: null, setActiveProjectId: vi.fn() }),
}));
vi.mock('../settings-dialog', () => ({ SettingsDialog: () => null }));
vi.mock('../workflow-history-dialog', () => ({ WorkflowHistoryDialog: () => null }));
// The dead dialog must never be rendered by the sidebar.
vi.mock('./starred-workflows-dialog', () => ({
  StarredWorkflowsDialog: () => <div data-testid="dead-starred-dialog" />,
}));
// Sentinel library dialog that reflects its `open` prop.
vi.mock('./workflows-library-dialog', () => ({
  WorkflowsLibraryDialog: ({ open }: { open: boolean }) =>
    open ? <div data-testid="workflows-library-open" /> : null,
}));

import { AppSidebar } from './app-sidebar';

beforeEach(() => {
  try { localStorage.clear(); } catch { /* ignore */ }
  global.fetch = vi.fn(async () => ({
    ok: true, status: 200, json: async () => ({ projects: [], total: 0 }), text: async () => '[]',
  })) as any;
});
afterEach(() => { vi.clearAllMocks(); });

describe('AppSidebar — Workflows library entry', () => {
  it('renders a Workflows nav entry', () => {
    render(<AppSidebar chatSessions={[] as any} />);
    expect(screen.getByTestId('button-workflows-nav')).toBeInTheDocument();
  });

  it('clicking Workflows navigates to the /workflows page, not the dead Starred dialog', () => {
    render(<AppSidebar chatSessions={[] as any} />);
    expect(screen.queryByTestId('dead-starred-dialog')).not.toBeInTheDocument();

    fireEvent.click(screen.getByTestId('button-workflows-nav'));

    expect(setLocationSpy).toHaveBeenCalledWith('/workflows');
    expect(screen.queryByTestId('dead-starred-dialog')).not.toBeInTheDocument();
  });
});
