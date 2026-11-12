import { useState, useEffect } from "react"
import { Sparkles, ChevronDown, ChevronRight, Check } from "lucide-react"
import { t } from "@/lib/i18n"
import { Popover, PopoverTrigger, PopoverContent } from "@/components/ui/popover"

/**
 * A single expert / skill pack surfaced in the composer (spec 06 §6.5 /
 * §0.9.2). Mirrors the shape returned by GET /api/skills — the backend
 * serialises each expert pack as `{ id, title, description, domains }`
 * (see backend `skill_manager.py::SkillPack.to_dict`). We keep only the
 * fields the composer actually renders; a `label` is derived from `title`
 * so callers can inject a leaner shape in tests.
 */
export interface SkillPack {
  id: string
  /** Display name (backend `title`). */
  label: string
  /** One-line description; may be empty for expert packs (honest-empty). */
  description?: string
}

/** Raw pack shape as returned by GET /api/skills. */
interface RawSkill {
  id: string
  title?: string
  description?: string
  domains?: string[]
}

/**
 * Normalise a /api/skills entry into the leaner SkillPack the composer
 * renders. Falls back to the domain list when a pack carries no
 * description, so a real (if terse) hint always shows rather than a blank.
 */
export function normalizeSkillPack(raw: RawSkill): SkillPack {
  const desc =
    (raw.description && raw.description.trim()) ||
    (raw.domains && raw.domains.length ? raw.domains.join(" · ") : "")
  return {
    id: raw.id,
    label: raw.title?.trim() || raw.id,
    description: desc || undefined,
  }
}

interface SkillsSelectorProps {
  /**
   * The ids currently toggled on. Controlled by the parent so the selection
   * can thread into the send payload.
   */
  selectedIds: string[]
  onChange: (ids: string[]) => void
  /**
   * Injected packs. When provided (e.g. in tests), NO network fetch happens
   * and these are rendered verbatim. When omitted, the component fetches
   * GET /api/skills. An empty array is a legitimate, honest state:
   * "No expert packs available yet".
   */
  packs?: SkillPack[]
}

const DIM = "var(--bm-text-dim, oklch(0.62 0.010 260))"
const TEXT = "var(--bm-text, oklch(0.22 0.01 260))"
const BORDER = "var(--bm-border, oklch(0.88 0.004 240))"
const PRIMARY = "var(--bm-primary, oklch(0.55 0.20 265))"

/**
 * SkillsSelector — a bounded popover of expert/skill packs with per-pack
 * on/off toggles and an "N on" summary chip, surfaced in the composer next
 * to the Instructions affordance. Honest by construction:
 *   - injected `packs` are rendered verbatim (testable, back-end-ready);
 *   - with no prop it fetches GET /api/skills (a real endpoint);
 *   - when there are zero packs it shows "No expert packs available yet"
 *     rather than fabricating toggles that do nothing.
 * The selected ids are owned by the parent so a run can record them.
 */
export function SkillsSelector({ selectedIds, onChange, packs }: SkillsSelectorProps) {
  const [open, setOpen] = useState(false)
  const [fetched, setFetched] = useState<SkillPack[] | null>(null)
  const [loading, setLoading] = useState(false)

  // Fetch packs only when none are injected. Injected packs (tests / a
  // parent that already has the list) short-circuit the network entirely.
  useEffect(() => {
    if (packs !== undefined) return
    let cancelled = false
    setLoading(true)
    fetch("/api/skills")
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((data) => {
        if (cancelled) return
        const raw: RawSkill[] = Array.isArray(data?.skills) ? data.skills : []
        setFetched(raw.map(normalizeSkillPack))
      })
      .catch(() => {
        if (!cancelled) setFetched([])
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [packs])

  const resolved: SkillPack[] = packs !== undefined ? packs : fetched ?? []
  // Keep the "N on" count honest — only count selections that map to a
  // real, available pack.
  const availableIds = new Set(resolved.map((p) => p.id))
  const onCount = selectedIds.filter((id) => availableIds.has(id)).length

  const toggle = (id: string) => {
    onChange(
      selectedIds.includes(id)
        ? selectedIds.filter((x) => x !== id)
        : [...selectedIds, id],
    )
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
      <button
        type="button"
        data-testid="composer-experts-toggle"
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 6,
          border: `1px solid ${BORDER}`,
          borderRadius: 5,
          background: "var(--bm-accent-soft)",
          cursor: "pointer",
          fontSize: 'var(--fs-sm)',
          color: "var(--bm-accent-ink)",
          padding: "4px 7px",
        }}
      >
        {/* Design composer row: "Skills & experts · N on ▾" — inline count,
            caret on the right (not a separate pill / left chevron). */}
        <span>
          {t('composer.skills_and_experts')}
          {onCount > 0 && (
            <>
              {' · '}
              <span data-testid="composer-experts-count" style={{ fontVariantNumeric: "tabular-nums" }}>
                {t('composer.count_on', { n: onCount })}
              </span>
            </>
          )}
        </span>
        <ChevronDown
          className="w-3 h-3"
          style={{ transform: open ? "rotate(180deg)" : undefined, transition: "transform .15s" }}
        />
      </button>
      </PopoverTrigger>

        <PopoverContent
          side="top"
          align="start"
          collisionPadding={16}
          sideOffset={8}
          aria-label={t('composer.skills_and_experts')}
          data-testid="composer-experts-popover"
          style={{
            zIndex: 50,
            width: "min(420px, calc(100vw - 32px))",
            maxHeight: "min(440px, 60vh, var(--radix-popover-content-available-height))",
            overflowY: "auto",
            overflowX: "hidden",
            overscrollBehavior: "contain",
            background: "var(--bm-bg-elev, hsl(var(--background)))",
            border: `1px solid ${BORDER}`,
            borderRadius: "var(--bm-r-md, 8px)",
            boxShadow: "var(--bm-shadow-md, 0 4px 16px rgba(15,23,42,0.10))",
            padding: 6,
          }}
        >
          <p
            style={{
              fontSize: 'var(--fs-xs)',
              color: DIM,
              padding: "4px 6px 6px",
              margin: 0,
              borderBottom: `1px solid ${BORDER}`,
            }}
          >
            {t('composer.experts_header')}
          </p>

          {loading ? (
            <p data-testid="composer-experts-loading" style={{ fontSize: 'var(--fs-sm)', color: DIM, padding: "10px 6px", margin: 0 }}>
              {t('composer.loading_expert_packs')}
            </p>
          ) : resolved.length === 0 ? (
            // Honest-empty: no fabricated packs. This is the real state when
            // the backend catalogue is unpopulated.
            <p data-testid="composer-experts-empty" style={{ fontSize: 'var(--fs-sm)', color: DIM, padding: "10px 6px", margin: 0 }}>
              {t('composer.no_expert_packs')}
            </p>
          ) : (
            <div style={{ marginTop: 4 }}>
              {resolved.map((pack) => {
                const active = selectedIds.includes(pack.id)
                return (
                  <button
                    key={pack.id}
                    type="button"
                    data-testid={`composer-expert-pack-${pack.id}`}
                    data-active={active}
                    aria-pressed={active}
                    onClick={() => toggle(pack.id)}
                    style={{
                      width: "100%",
                      display: "flex",
                      alignItems: "flex-start",
                      gap: 8,
                      padding: "6px",
                      border: "none",
                      borderRadius: "var(--bm-r-sm, 6px)",
                      background: active ? "var(--bm-surface, oklch(0.97 0.002 240))" : "transparent",
                      cursor: "pointer",
                      textAlign: "left",
                    }}
                  >
                    <span
                      aria-hidden
                      style={{
                        marginTop: 1,
                        width: 15,
                        height: 15,
                        flexShrink: 0,
                        borderRadius: 4,
                        display: "inline-flex",
                        alignItems: "center",
                        justifyContent: "center",
                        border: `1px solid ${active ? PRIMARY : BORDER}`,
                        background: active ? PRIMARY : "transparent",
                        color: "white",
                      }}
                    >
                      {active && <Check className="w-2.5 h-2.5" />}
                    </span>
                    <span style={{ flex: 1, minWidth: 0 }}>
                      <span style={{ display: "block", fontSize: 'var(--fs-base)', fontWeight: 500, color: TEXT }}>
                        {pack.label}
                      </span>
                      {pack.description && (
                        <span style={{ display: "block", fontSize: 'var(--fs-xs)', color: DIM, lineHeight: 1.35 }}>
                          {pack.description}
                        </span>
                      )}
                    </span>
                  </button>
                )
              })}
              {onCount > 0 && (
                <button
                  type="button"
                  data-testid="composer-experts-clear"
                  onClick={() => onChange(selectedIds.filter((id) => !availableIds.has(id)))}
                  style={{
                    width: "100%",
                    marginTop: 4,
                    padding: "5px 6px",
                    border: "none",
                    borderTop: `1px solid ${BORDER}`,
                    background: "transparent",
                    cursor: "pointer",
                    textAlign: "left",
                    fontSize: 'var(--fs-xs)',
                    color: DIM,
                  }}
                >
                  Clear all
                </button>
              )}
            </div>
          )}
        </PopoverContent>
    </Popover>
  )
}
