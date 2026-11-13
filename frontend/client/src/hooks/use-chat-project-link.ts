import { useEffect } from 'react';

/** Restore the project carried by a dataset-to-chat link on a fresh browser.
 * This selects UI context only; project and file access remain server-authorized.
 * Ordinary unfiled chats and unrelated links must not change project selection.
 */
export function useChatProjectLink(
  search: string,
  authenticated: boolean,
  setActiveProjectId: (id: string | null) => void,
) {
  useEffect(() => {
    if (!authenticated) return;
    const query = new URLSearchParams(search);
    const projectId = query.get('project')?.trim();
    const hasFiles = query.getAll('attachFile').some(id => id.trim().length > 0)
      || (query.get('attachFolder')?.trim().length ?? 0) > 0;
    if (projectId && hasFiles) setActiveProjectId(projectId);
    // Do not consume the query: the composer still needs every exact file ID.
  }, [search, authenticated, setActiveProjectId]);
}
