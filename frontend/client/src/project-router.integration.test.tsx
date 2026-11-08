/** Project navigation integration.
 * Imports the production router and real project detail; only unrelated heavy children are mocked.
 */
import React from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { Router } from 'wouter';
import { memoryLocation } from 'wouter/memory-location';
import { ProjectsRouter } from './App';

const context = vi.hoisted(() => ({ setActiveProjectId: vi.fn() }));
vi.mock('@/contexts/active-project-context', () => ({
  useActiveProject: () => context,
  useActiveProjectSafe: () => context,
  ActiveProjectProvider: ({children}: any) => children,
}));
vi.mock('@/components/project-file-tree', () => ({ ProjectFileTree: () => <div data-testid="file-tree"/> }));
vi.mock('@/components/nextflow-workflow-viewer', () => ({ NextflowWorkflowViewer: () => null }));
vi.mock('@/lib/projects', () => ({ projectService: { getProject: () => null } }));

function mountProject(query: string) {
  const location = memoryLocation({ path: '/projects', record: true });
  render(<Router hook={location.hook} searchHook={() => query}><ProjectsRouter/></Router>);
  return location;
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal('fetch', vi.fn(async (input: any) => {
    const url = String(input);
    let payload: any = {};
    if (url === '/api/projects/proj-qa') payload = {
      project: {id:'proj-qa',name:'Existing project QA',description:'',status:'active',tags:[],instructions:''},
      context:{},isOwner:true,role:'owner',canEdit:true,
    };
    else if (url.includes('/sessions')) payload = {sessions:[{session_id:'saved-chat-qa',title:'Existing saved conversation',message_count:4,created_at:'2026-11-07T12:00:00Z'}]};
    else if (url.includes('/members')) payload = {members:[]};
    return {ok:true,status:200,json:async()=>payload};
  }));
});

describe('actual Project route reads saved Chats without launching anything', () => {
  it.each(['?project=proj-qa', '?project=proj-qa&tab=chat'])('opens saved Chats for %s', async query => {
    const location = mountProject(query);
    expect(await screen.findByText('Existing saved conversation')).toBeTruthy();
    expect(screen.getByTestId('tab-project-chat').getAttribute('data-state')).toBe('active');
    expect(context.setActiveProjectId).toHaveBeenCalledWith('proj-qa');
    expect(location.history).toEqual(['/projects']);
    expect(screen.getByTestId('button-new-project-chat')).toBeTruthy();
    expect((fetch as any).mock.calls.every(([, options]: any[]) => !options?.method || options.method === 'GET')).toBe(true);
  });

  it('preserves explicit Files navigation instead of treating it as Chats', async () => {
    const location = mountProject('?project=proj-qa&tab=files');
    await waitFor(() => expect(location.history).toContain('/files'));
  });

  it('switches the same project from Files to saved Chats instead of retaining the old tab state', async () => {
    const location = memoryLocation({ path:'/projects',record:true });
    const view = render(<Router hook={location.hook} searchHook={() => '?project=proj-qa&tab=files'}><ProjectsRouter/></Router>);
    await waitFor(() => expect(location.history).toContain('/files'));
    view.rerender(<Router hook={location.hook} searchHook={() => '?project=proj-qa&tab=chat'}><ProjectsRouter/></Router>);
    expect(await screen.findByText('Existing saved conversation')).toBeTruthy();
    expect(screen.getByTestId('tab-project-chat').getAttribute('data-state')).toBe('active');
    expect((fetch as any).mock.calls.every(([, options]: any[]) => !options?.method || options.method === 'GET')).toBe(true);
  });

  it('preserves Instructions without redirecting to Data', async () => {
    const location = mountProject('?project=proj-qa&tab=instructions');
    await waitFor(() => expect(context.setActiveProjectId).toHaveBeenCalledWith('proj-qa'));
    expect(location.history).toEqual(['/projects']);
    expect(screen.queryByTestId('session-row-saved-chat-qa')).toBeNull();
  });
});
