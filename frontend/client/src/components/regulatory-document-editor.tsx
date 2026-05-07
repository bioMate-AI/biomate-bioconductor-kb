/**
 * RegulatoryDocumentEditor
 *
 * TipTap-based editable document editor for the IND Report right panel.
 * Replaces the static MarkdownSection viewer so regulatory writers can
 * edit AI-generated §2.6 text and track what has been changed.
 *
 * Features:
 *  - TipTap editor with StarterKit + Highlight (multicolor) + CharacterCount
 *  - AI-generated spans marked in light blue (#dbeafe) via Highlight extension
 *  - Highlight removed from paragraphs the user has edited (human-reviewed)
 *  - Diff badge: "N AI spans / N human-edited"
 *  - Section tabs (§2.6.1 … §2.6.6) that scroll the editor to the heading
 *  - Word count in footer via CharacterCount
 *  - Export as .txt download
 *  - Read-only mode when isLocked=true (post-eSig)
 */

import { useEffect, useRef, useCallback, useState } from "react"
import { useEditor, EditorContent } from "@tiptap/react"
import StarterKit from "@tiptap/starter-kit"
import { Highlight } from "@tiptap/extension-highlight"
import { CharacterCount } from "@tiptap/extension-character-count"
import { Placeholder } from "@tiptap/extension-placeholder"
import { Download, Lock } from "lucide-react"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

// ─────────────────────────────────────────────────────────────────────────────
// Props
// ─────────────────────────────────────────────────────────────────────────────

export interface RegulatoryDocumentEditorProps {
  /** Markdown string from IND assembly (the full §2.6 document) */
  content: string
  /** true after eSig — editor becomes read-only */
  isLocked: boolean
  /** Called on every edit with the current plain text */
  onEdit: (text: string) => void
  molecule: string
  generatedAt: string
}

// ─────────────────────────────────────────────────────────────────────────────
// Markdown → HTML converter (no external deps, regex-based)
// ─────────────────────────────────────────────────────────────────────────────

const AI_COLOR = "#dbeafe"
const AI_DATA_ATTR = "data-ai-generated"

/**
 * Converts a simple IND markdown string to HTML.
 * Supports: # h1, ## h2, ### h3, **bold**, *italic*, blank-line paragraphs.
 * Tables are rendered as plain paragraphs (regulatory content is prose-heavy).
 */
function markdownToHtml(md: string): string {
  const lines = md.split("\n")
  const out: string[] = []
  let inParagraph = false

  const closeP = () => {
    if (inParagraph) { out.push("</p>"); inParagraph = false }
  }

  const inlineFormat = (text: string): string => {
    // Bold: **text**
    text = text.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    // Italic: *text* (single asterisk, not at start of line)
    text = text.replace(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/g, "<em>$1</em>")
    return text
  }

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i]
    const trimmed = raw.trim()

    if (!trimmed) {
      closeP()
      continue
    }

    // Headings
    if (trimmed.startsWith("### ")) {
      closeP()
      out.push(`<h3>${inlineFormat(trimmed.slice(4))}</h3>`)
      continue
    }
    if (trimmed.startsWith("## ")) {
      closeP()
      out.push(`<h2>${inlineFormat(trimmed.slice(3))}</h2>`)
      continue
    }
    if (trimmed.startsWith("# ")) {
      closeP()
      out.push(`<h1>${inlineFormat(trimmed.slice(2))}</h1>`)
      continue
    }

    // Table separator — skip
    if (/^\|[-|: ]+\|$/.test(trimmed)) continue

    // Table row — render as paragraph (keeps regulatory tables readable)
    if (trimmed.startsWith("|") && trimmed.endsWith("|")) {
      closeP()
      const cells = trimmed
        .split("|")
        .filter((c) => c.trim() !== "")
        .map((c) => c.trim())
        .join(" · ")
      out.push(`<p>${inlineFormat(cells)}</p>`)
      continue
    }

    // Bullet list item
    if (/^[-*] /.test(trimmed)) {
      closeP()
      out.push(`<p>• ${inlineFormat(trimmed.slice(2))}</p>`)
      continue
    }

    // Regular paragraph line
    if (!inParagraph) {
      out.push(`<p>${inlineFormat(trimmed)}`)
      inParagraph = true
    } else {
      // Continuation line — append with space
      // Remove the closing tag from last item and add text
      const last = out[out.length - 1]
      if (last !== undefined) {
        out[out.length - 1] = last + " " + inlineFormat(trimmed)
      }
    }
  }

  closeP()
  return out.join("\n")
}

/**
 * Wraps every paragraph/heading in the HTML with an AI highlight mark.
 * We inject a <mark> wrapper inside each block so TipTap's Highlight
 * extension can track and remove the mark when the user edits.
 *
 * Strategy: we wrap the inner text of each block tag in a <mark> with
 * style="background-color: #dbeafe" and data-ai="true".
 */
function wrapWithAiHighlight(html: string): string {
  // Wrap content of p, h1, h2, h3 tags with <mark data-ai="true">
  return html.replace(
    /(<(p|h1|h2|h3)>)([\s\S]*?)(<\/\2>)/g,
    (_, openTag, _tag, content, closeTag) => {
      // Don't double-wrap if already marked
      if (content.includes('data-ai="true"')) return _
      // Skip empty content
      if (!content.trim()) return _
      return `${openTag}<mark data-color="${AI_COLOR}" style="background-color: ${AI_COLOR}; color: inherit" ${AI_DATA_ATTR}="true">${content}</mark>${closeTag}`
    }
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Diff tracking helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Extract text content of each block node as an array for comparison */
function extractBlockTexts(html: string): string[] {
  const blocks: string[] = []
  const re = /<(p|h1|h2|h3)[^>]*>([\s\S]*?)<\/\1>/g
  let m: RegExpExecArray | null
  while ((m = re.exec(html)) !== null) {
    // Strip inner tags for text comparison
    blocks.push(m[2].replace(/<[^>]+>/g, "").trim())
  }
  return blocks
}

// ─────────────────────────────────────────────────────────────────────────────
// Section tab constants (matching SECTION_TABS in ind-report.tsx)
// ─────────────────────────────────────────────────────────────────────────────

const SECTION_TABS = ["2.6.1", "2.6.2", "2.6.3", "2.6.4", "2.6.5", "2.6.6"]

// ─────────────────────────────────────────────────────────────────────────────
// Component
// ─────────────────────────────────────────────────────────────────────────────

export function RegulatoryDocumentEditor({
  content,
  isLocked,
  onEdit,
  molecule,
  generatedAt,
}: RegulatoryDocumentEditorProps) {
  // Original block texts captured at load time for diff tracking
  const originalBlocksRef = useRef<string[]>([])
  // Tracks which paragraph indices have been human-edited (highlight removed)
  const [humanEditedCount, setHumanEditedCount] = useState(0)
  const [aiSpanCount, setAiSpanCount] = useState(0)
  const [activeSection, setActiveSection] = useState("2.6.1")
  const editorContainerRef = useRef<HTMLDivElement>(null)

  // Build the initial HTML with AI highlights
  const buildInitialHtml = useCallback((md: string) => {
    const html = markdownToHtml(md)
    const withHighlights = wrapWithAiHighlight(html)
    originalBlocksRef.current = extractBlockTexts(html)
    return withHighlights
  }, [])

  const editor = useEditor({
    extensions: [
      StarterKit,
      Highlight.configure({ multicolor: true }),
      CharacterCount,
      Placeholder.configure({
        placeholder: "No document content yet. Run the IND pipeline to generate §2.6.",
      }),
    ],
    content: content ? buildInitialHtml(content) : "",
    editable: !isLocked,
    onUpdate: ({ editor: ed }) => {
      // Count AI vs human-edited spans by inspecting the DOM
      const container = editorContainerRef.current
      if (container) {
        const allMarks = container.querySelectorAll(`mark[${AI_DATA_ATTR}="true"]`)
        setAiSpanCount(allMarks.length)

        // Count blocks that have lost their AI mark
        const totalBlocks = originalBlocksRef.current.length
        const remaining = allMarks.length
        setHumanEditedCount(Math.max(0, totalBlocks - remaining))
      }

      // Notify parent with plain text
      onEdit(ed.getText())
    },
  })

  // Reinitialize editor content when the markdown source changes
  useEffect(() => {
    if (!editor || !content) return
    const newHtml = buildInitialHtml(content)
    editor.commands.setContent(newHtml, { emitUpdate: false })
    setHumanEditedCount(0)

    // Initial AI span count
    requestAnimationFrame(() => {
      const container = editorContainerRef.current
      if (container) {
        const allMarks = container.querySelectorAll(`mark[${AI_DATA_ATTR}="true"]`)
        setAiSpanCount(allMarks.length)
      }
    })
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [content, editor])

  // Sync editable flag when isLocked changes
  useEffect(() => {
    if (!editor) return
    editor.setEditable(!isLocked)
  }, [isLocked, editor])

  // ── Section tab scroll ────────────────────────────────────────────────────
  const scrollToSection = useCallback(
    (sectionId: string) => {
      setActiveSection(sectionId)
      if (!editorContainerRef.current) return

      // Look for any heading containing the section number
      const headings = editorContainerRef.current.querySelectorAll("h1, h2, h3")
      for (const heading of Array.from(headings)) {
        if (heading.textContent?.includes(sectionId)) {
          heading.scrollIntoView({ behavior: "smooth", block: "start" })
          return
        }
      }

      // Fallback: approximate position by section index
      const idx = SECTION_TABS.indexOf(sectionId)
      if (idx >= 0 && editorContainerRef.current) {
        const scrollEl = editorContainerRef.current.closest(".editor-scroll-area")
        if (scrollEl) {
          const fraction = idx / SECTION_TABS.length
          scrollEl.scrollTop = scrollEl.scrollHeight * fraction
        }
      }
    },
    []
  )

  // ── Export as plain text ──────────────────────────────────────────────────
  const handleExport = useCallback(() => {
    if (!editor) return
    const text = editor.getText()
    const blob = new Blob([text], { type: "text/plain" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `${molecule || "ind-document"}_§2.6_${generatedAt?.slice(0, 10) || "draft"}.txt`
    a.click()
    URL.revokeObjectURL(url)
  }, [editor, molecule, generatedAt])

  // ── Word count from CharacterCount storage ────────────────────────────────
  const wordCount = editor?.storage?.characterCount?.words?.() ?? 0
  const charCount = editor?.storage?.characterCount?.characters?.() ?? 0

  // ─────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div className="flex flex-col h-full min-h-0">
      {/* ── Lock banner ── */}
      {isLocked && (
        <div className="flex items-center gap-1.5 px-4 py-1.5 bg-emerald-50 dark:bg-emerald-950/40 border-b border-emerald-200 dark:border-emerald-800 text-emerald-700 dark:text-emerald-400 text-[11px] font-medium shrink-0">
          <Lock className="h-3 w-3" />
          Signed — read only
        </div>
      )}

      {/* ── Section tabs ── */}
      {content && (
        <div className="flex items-center gap-0.5 px-3 pt-2 pb-1 overflow-x-auto border-b border-border shrink-0">
          {SECTION_TABS.map((s) => (
            <button
              key={s}
              onClick={() => scrollToSection(s)}
              className={cn(
                "shrink-0 px-2 py-0.5 text-[10px] font-mono rounded transition-colors",
                activeSection === s
                  ? "bg-[var(--bm-accent)] text-white"
                  : "text-muted-foreground hover:bg-muted"
              )}
            >
              §{s}
            </button>
          ))}

          {/* Diff badge */}
          {(aiSpanCount > 0 || humanEditedCount > 0) && (
            <div className="ml-auto flex items-center gap-1.5 shrink-0 text-[10px]">
              <span
                className="px-1.5 py-0.5 rounded-full font-medium"
                style={{ backgroundColor: AI_COLOR, color: "#1e40af" }}
                title="Paragraphs still containing AI-generated (unedited) text"
              >
                {aiSpanCount} AI
              </span>
              {humanEditedCount > 0 && (
                <span
                  className="px-1.5 py-0.5 rounded-full bg-emerald-100 dark:bg-emerald-900/40 text-emerald-700 dark:text-emerald-400 font-medium"
                  title="Paragraphs you have edited (AI highlight removed)"
                >
                  {humanEditedCount} edited
                </span>
              )}
            </div>
          )}
        </div>
      )}

      {/* ── Editor area ── */}
      <div
        ref={editorContainerRef}
        className="editor-scroll-area flex-1 overflow-y-auto px-5 py-4 min-h-0"
      >
        <EditorContent
          editor={editor}
          className={cn(
            "prose prose-sm max-w-none",
            "[&_.tiptap]:outline-none",
            "[&_.tiptap_h1]:text-sm [&_.tiptap_h1]:font-semibold [&_.tiptap_h1]:mt-6 [&_.tiptap_h1]:mb-2 [&_.tiptap_h1]:border-b [&_.tiptap_h1]:border-border [&_.tiptap_h1]:pb-1",
            "[&_.tiptap_h2]:text-xs [&_.tiptap_h2]:font-semibold [&_.tiptap_h2]:text-zinc-500 [&_.tiptap_h2]:dark:text-zinc-400 [&_.tiptap_h2]:uppercase [&_.tiptap_h2]:tracking-widest [&_.tiptap_h2]:mt-5 [&_.tiptap_h2]:mb-1 [&_.tiptap_h2]:font-mono",
            "[&_.tiptap_h3]:text-[11px] [&_.tiptap_h3]:font-semibold [&_.tiptap_h3]:text-zinc-500 [&_.tiptap_h3]:uppercase [&_.tiptap_h3]:tracking-wider [&_.tiptap_h3]:mt-4 [&_.tiptap_h3]:mb-1",
            "[&_.tiptap_p]:text-[13px] [&_.tiptap_p]:leading-[1.7] [&_.tiptap_p]:py-0.5",
            "[&_.tiptap_mark]:rounded-sm [&_.tiptap_mark]:px-0 [&_.tiptap_mark]:py-0",
            // Placeholder
            "[&_.tiptap_p.is-editor-empty:first-child::before]:content-[attr(data-placeholder)] [&_.tiptap_p.is-editor-empty:first-child::before]:text-muted-foreground [&_.tiptap_p.is-editor-empty:first-child::before]:pointer-events-none [&_.tiptap_p.is-editor-empty:first-child::before]:float-left [&_.tiptap_p.is-editor-empty:first-child::before]:h-0",
            !content && "min-h-[200px]"
          )}
        />
      </div>

      {/* ── Footer ── */}
      <div className="shrink-0 border-t border-border px-4 py-1.5 flex items-center justify-between bg-[var(--bm-surface)]">
        <div className="flex items-center gap-3 text-[10px] text-muted-foreground font-mono">
          <span>{wordCount.toLocaleString()} words</span>
          <span>{charCount.toLocaleString()} chars</span>
          {generatedAt && (
            <span className="hidden sm:inline">
              Generated {generatedAt.slice(0, 10)}
            </span>
          )}
        </div>

        <Button
          size="sm"
          variant="ghost"
          className="h-6 text-[10px] gap-1 px-2"
          onClick={handleExport}
          disabled={!content}
          title="Download as plain text"
        >
          <Download className="h-3 w-3" />
          .txt
        </Button>
      </div>
    </div>
  )
}

export default RegulatoryDocumentEditor
