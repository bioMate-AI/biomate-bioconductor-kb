import * as React from "react"

import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { TabsTrigger } from "@/components/ui/tabs"

/**
 * Hover / keyboard-focus hints for navigation items and tabs.
 *
 * One look and one delay for every hint in the app, instead of native `title`
 * attributes (unstyled, slow, never shown on keyboard focus). The hint text
 * should say what the user finds behind the control — not repeat its label.
 * Hint strings live under `hint.*` in the locale bundles.
 *
 * Mount <HintScope> once at the app root: hints then share one provider, so
 * moving along a row of hinted items opens each next hint instantly
 * (skipDelayDuration). A hint rendered outside a scope (a test, an isolated
 * dialog) brings its own provider.
 */
const HINT_DELAY_MS = 400
const HintScopeContext = React.createContext(false)

export function HintScope({ children }: { children: React.ReactNode }) {
  return (
    <TooltipProvider delayDuration={HINT_DELAY_MS} skipDelayDuration={300}>
      <HintScopeContext.Provider value={true}>{children}</HintScopeContext.Provider>
    </TooltipProvider>
  )
}

function Scoped({ children }: { children: React.ReactNode }) {
  const inScope = React.useContext(HintScopeContext)
  return inScope ? <>{children}</> : <HintScope>{children}</HintScope>
}

type Side = "top" | "right" | "bottom" | "left"

function HintContent({ hint, side }: { hint: string; side: Side }) {
  return (
    <TooltipContent
      side={side}
      collisionPadding={8}
      className="max-w-[260px] text-xs leading-snug"
      data-testid="hint-tip"
    >
      {hint}
    </TooltipContent>
  )
}

/** Hint on a plain element (button, link, badge). Not for Radix TabsTrigger — use HintTabsTrigger. */
export function HintTip({
  hint,
  side = "right",
  children,
}: {
  hint?: string | null
  side?: Side
  children: React.ReactElement
}) {
  if (!hint) return children
  return (
    <Scoped>
      <Tooltip>
        <TooltipTrigger asChild>{children}</TooltipTrigger>
        <HintContent hint={hint} side={side} />
      </Tooltip>
    </Scoped>
  )
}

/**
 * A Radix TabsTrigger with a hint. Composed tabs-outside / tooltip-inside so the
 * Tabs attributes are applied last: wrapping a TabsTrigger in TooltipTrigger
 * would let the tooltip's `data-state` ("closed") overwrite the tab's
 * `data-state="active"`, and the selected tab would lose its styling.
 */
export const HintTabsTrigger = React.forwardRef<
  React.ElementRef<typeof TabsTrigger>,
  React.ComponentPropsWithoutRef<typeof TabsTrigger> & { hint?: string | null; side?: Side }
>(({ hint, side = "bottom", children, ...props }, ref) => {
  if (!hint) return <TabsTrigger ref={ref} {...props}>{children}</TabsTrigger>
  return (
    <Scoped>
      <Tooltip>
        <TabsTrigger asChild {...props}>
          <TooltipTrigger ref={ref}>{children}</TooltipTrigger>
        </TabsTrigger>
        <HintContent hint={hint} side={side} />
      </Tooltip>
    </Scoped>
  )
})
HintTabsTrigger.displayName = "HintTabsTrigger"
