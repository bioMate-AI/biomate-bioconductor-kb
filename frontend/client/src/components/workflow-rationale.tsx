/**
 * WorkflowRationale — collapsible scientific context panel shown below workflow cards.
 * Sections: When to use, When NOT to use, Data requirements, Key assumptions,
 * Common pitfalls, Parameter notes.
 */

import { useState } from "react"
import { cn } from "@/lib/utils"
import { ChevronDown, CheckCircle2, XCircle, Database, Info, AlertTriangle, Settings2 } from "lucide-react"
import { Button } from "@/components/ui/button"

export interface WorkflowRationale {
  when_to_use: string
  when_not_to_use: string
  data_requirements: string
  key_assumptions: string
  common_pitfalls: string
  parameter_notes: string
}

interface WorkflowRationaleProps {
  rationale: WorkflowRationale
  className?: string
}

interface RationaleSectionProps {
  icon: React.ReactNode
  label: string
  text: string
  iconClass?: string
}

function RationaleSection({ icon, label, text, iconClass }: RationaleSectionProps) {
  return (
    <div className="flex gap-2.5 text-sm">
      <div className={cn("mt-0.5 shrink-0", iconClass)}>{icon}</div>
      <div className="min-w-0">
        <span className="font-medium text-foreground">{label}: </span>
        <span className="text-muted-foreground leading-relaxed">{text}</span>
      </div>
    </div>
  )
}

export function WorkflowRationale({ rationale, className }: WorkflowRationaleProps) {
  const [open, setOpen] = useState(false)

  return (
    <div className={cn("rounded-md border border-border/60 overflow-hidden mt-2", className)}>
      <Button
        variant="ghost"
        size="sm"
        onClick={() => setOpen(v => !v)}
        className="w-full flex items-center justify-between px-3 py-2 h-auto rounded-none text-xs font-medium text-muted-foreground hover:text-foreground hover:bg-muted/40"
        aria-expanded={open}
      >
        <span className="flex items-center gap-1.5">
          <Info className="h-3.5 w-3.5" />
          Scientific Rationale &amp; Usage Guide
        </span>
        <ChevronDown
          className={cn("h-3.5 w-3.5 transition-transform duration-200", open && "rotate-180")}
        />
      </Button>

      {open && (
        <div className="px-3 pb-3 pt-2 space-y-3 border-t border-border/40 bg-muted/10">
          <RationaleSection
            icon={<CheckCircle2 className="h-3.5 w-3.5" />}
            iconClass="text-emerald-500"
            label="When to use"
            text={rationale.when_to_use}
          />
          <RationaleSection
            icon={<XCircle className="h-3.5 w-3.5" />}
            iconClass="text-orange-500"
            label="When NOT to use"
            text={rationale.when_not_to_use}
          />
          <RationaleSection
            icon={<Database className="h-3.5 w-3.5" />}
            iconClass="text-blue-500"
            label="Data requirements"
            text={rationale.data_requirements}
          />
          <RationaleSection
            icon={<Info className="h-3.5 w-3.5" />}
            iconClass="text-slate-500"
            label="Key assumptions"
            text={rationale.key_assumptions}
          />
          <RationaleSection
            icon={<AlertTriangle className="h-3.5 w-3.5" />}
            iconClass="text-amber-500"
            label="Common pitfalls"
            text={rationale.common_pitfalls}
          />
          <RationaleSection
            icon={<Settings2 className="h-3.5 w-3.5" />}
            iconClass="text-purple-500"
            label="Parameter notes"
            text={rationale.parameter_notes}
          />
        </div>
      )}
    </div>
  )
}
