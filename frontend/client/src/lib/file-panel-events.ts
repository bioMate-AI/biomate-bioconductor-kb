/** Open a project file in the chat's right panel, next to the conversation (founder 2026-11-12:
 *  switching between the Data page and the chat to read a generated file is inconvenient).
 *  Returns true when a chat view handled it; otherwise the caller navigates to the Data page. */
export const OPEN_FILE_IN_PANEL = "biomate:open-file-in-panel"

export interface OpenFileInPanelDetail { projectId: string; fileId: string }

export function openFileInPanel(detail: OpenFileInPanelDetail): boolean {
  const ev = new CustomEvent<OpenFileInPanelDetail>(OPEN_FILE_IN_PANEL, { detail, cancelable: true })
  return !window.dispatchEvent(ev) // a listener calls preventDefault() when it shows the file
}
