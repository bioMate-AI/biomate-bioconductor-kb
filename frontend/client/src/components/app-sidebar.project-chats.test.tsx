/**
 * Project chats in the sidebar (founder 2026-11-12): "+ 新建对话" sits ABOVE the chat list
 * (moveNewChatAboveChatList.png), and the chat list folds ("make chat list foldable").
 */
import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

vi.mock('wouter', () => ({ useLocation: () => ['/', vi.fn()] }));
vi.mock('@/contexts/auth-context', () => ({ useAuth: () => ({ user: { id: 1, email: 'lifeifei163361@163.com' }, logout: vi.fn() }) }));
vi.mock('@/contexts/active-project-context', () => ({ useActiveProject: () => ({ activeProjectId: null, setActiveProjectId: vi.fn() }) }));
vi.mock('./settings-dialog', () => ({ SettingsDialog: () => null }));
vi.mock('./workflow-history-dialog', () => ({ WorkflowHistoryDialog: () => null }));
vi.mock('./workflows-library-dialog', () => ({ WorkflowsLibraryDialog: () => null }));
import { AppSidebar } from './app-sidebar';

beforeEach(() => {
  try { localStorage.clear(); } catch { /* ignore */ }
  global.fetch = vi.fn(async (url: string) => ({
    ok: true, status: 200,
    json: async () => String(url).endsWith('/sessions')
      ? { sessions: [{ session_id: 's1', title: '对该数据集运行质量控制' }, { session_id: 's2', title: 'Generate 500 candidates' }] }
      : { projects: [{ id: 'p1', name: 'test', status: 'active' }] },
    text: async () => '',
  })) as any;
});

describe('project chats in the sidebar', () => {
  it('new chat comes before the chat list, and the list folds and stays folded', async () => {
    const { unmount } = render(<AppSidebar chatSessions={[] as any} />);
    fireEvent.click(await screen.findByTestId('button-project-p1'));
    await screen.findByTestId('button-project-chat-s1');
    const newChat = screen.getByTestId('project-new-chat-p1');
    const firstChat = screen.getByTestId('button-project-chat-s1');
    expect(newChat.compareDocumentPosition(firstChat) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    const toggle = screen.getByTestId('project-chats-toggle-p1');
    expect(toggle.textContent).toContain('2');
    fireEvent.click(toggle);
    expect(screen.queryByTestId('button-project-chat-s1')).toBeNull();
    expect(screen.getByTestId('project-new-chat-p1')).toBeInTheDocument(); // still reachable when folded
    unmount();
    render(<AppSidebar chatSessions={[] as any} />);
    fireEvent.click(await screen.findByTestId('button-project-p1'));
    await waitFor(() => expect(screen.getByTestId('project-chats-toggle-p1')).toBeInTheDocument());
    expect(screen.queryByTestId('button-project-chat-s1')).toBeNull(); // remembered
  });
});
