import { FolderOpen } from "lucide-react"
import { useLocation } from "wouter"
import { t } from "@/lib/i18n"

/** Untitled-session sentinels stored by chat-history ("New Chat") read as the localized label. */
export function displayChatTitle(title: string | null | undefined): string {
  const raw = (title || "").trim()
  if (!raw || /^new (chat|thread)$/i.test(raw)) return t("chat.new_chat")
  return raw
}

interface ChatHeaderTitleProps {
  title?: string | null
  projectId?: string | null
  projectName?: string | null
  live?: boolean
}

/**
 * The chat's one-line header: title + a small project chip. Replaces the
 * stacked "Unfiled / new chat" breadcrumb + title + separate project banner
 * (three lines saying the same thing; review §3 C4).
 */
export function ChatHeaderTitle({ title, projectId, projectName, live }: ChatHeaderTitleProps) {
  const [, navigate] = useLocation()
  return (
    <div
      data-testid="chat-header-title"
      style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 0, overflow: "hidden" }}
    >
      <span
        data-testid="chat-header-title-text"
        style={{
          fontWeight: 600, fontSize: "var(--fs-base)",
          color: "var(--bm-text, hsl(var(--foreground)))",
          fontFamily: "var(--bm-font-ui)",
          overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", minWidth: 0,
        }}
      >
        {displayChatTitle(title)}
      </span>
      {projectId && projectName && (
        <button
          type="button"
          data-testid="chat-header-project-chip"
          onClick={() => navigate(`/projects?project=${encodeURIComponent(projectId)}`)}
          title={t("chat.project_chip_title", { name: projectName })}
          style={{
            display: "inline-flex", alignItems: "center", gap: 4, flexShrink: 1, minWidth: 0, maxWidth: 220,
            padding: "1px 8px", borderRadius: 999, cursor: "pointer",
            border: "1px solid var(--bm-border, hsl(var(--border)))",
            background: "var(--bm-surface-2, hsl(var(--muted)))",
            color: "var(--bm-text-muted, hsl(var(--muted-foreground)))",
            fontSize: "var(--fs-xs)", lineHeight: "18px",
          }}
        >
          <FolderOpen style={{ width: 11, height: 11, flexShrink: 0, opacity: 0.8 }} />
          <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{projectName}</span>
        </button>
      )}
      {live && (
        <span
          data-testid="chat-header-live"
          title={t("chat.live")}
          aria-label={t("chat.live")}
          style={{ width: 6, height: 6, borderRadius: "50%", flexShrink: 0, background: "var(--bm-ok, oklch(0.62 0.13 150))" }}
        />
      )}
    </div>
  )
}
