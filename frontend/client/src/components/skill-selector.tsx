/**
 * SkillSelector — chip UI for activating expert role Skills in a chat session.
 * Sits in the chat header. Active skills are injected into every system prompt.
 */
import { useState, useEffect, useRef } from "react";
import { Brain, ChevronDown, X, Check, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

interface Skill {
  id: string;
  title: string;
  triggers: string[];
  domains: string[];
}

interface SkillSelectorProps {
  activeSkillIds: string[];
  onChange: (ids: string[]) => void;
  className?: string;
}

const DOMAIN_COLORS: Record<string, string> = {
  genomics:       "bg-blue-50 text-blue-700 border-blue-200",
  transcriptomics:"bg-violet-50 text-violet-700 border-violet-200",
  single_cell:    "bg-purple-50 text-purple-700 border-purple-200",
  drug_discovery: "bg-amber-50 text-amber-700 border-amber-200",
  clinical:       "bg-green-50 text-green-700 border-green-200",
  proteomics:     "bg-rose-50 text-rose-700 border-rose-200",
};

function domainColor(domains: string[]): string {
  for (const d of domains) {
    if (DOMAIN_COLORS[d]) return DOMAIN_COLORS[d];
  }
  return "bg-gray-50 text-gray-700 border-gray-200";
}

export function SkillSelector({ activeSkillIds, onChange, className }: SkillSelectorProps) {
  const [skills, setSkills] = useState<Skill[]>([]);
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetch("/api/skills")
      .then(r => r.json())
      .then(data => setSkills(data.skills || []))
      .catch(() => {});
  }, []);

  // Close on outside click
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const toggle = (id: string) => {
    onChange(
      activeSkillIds.includes(id)
        ? activeSkillIds.filter(s => s !== id)
        : [...activeSkillIds, id]
    );
  };

  const activeSkills = skills.filter(s => activeSkillIds.includes(s.id));

  return (
    <div ref={ref} className={cn("relative flex items-center gap-1.5", className)}>
      {/* Active skill chips */}
      {activeSkills.map(skill => (
        <span
          key={skill.id}
          className={cn(
            "inline-flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-full border",
            domainColor(skill.domains)
          )}
        >
          <Sparkles className="h-2.5 w-2.5" />
          {skill.title}
          <button
            onClick={() => toggle(skill.id)}
            className="ml-0.5 hover:opacity-70"
          >
            <X className="h-2.5 w-2.5" />
          </button>
        </span>
      ))}

      {/* Picker toggle */}
      <Button
        variant="ghost"
        size="sm"
        className="h-6 px-2 text-xs gap-1 text-muted-foreground hover:text-foreground"
        onClick={() => setOpen(o => !o)}
      >
        <Brain className="h-3.5 w-3.5" />
        {activeSkills.length === 0 ? "Expert mode" : ""}
        <ChevronDown className={cn("h-3 w-3 transition-transform", open && "rotate-180")} />
      </Button>

      {/* Dropdown panel */}
      {open && (
        <div className="absolute top-8 left-0 z-50 w-72 bg-popover border rounded-lg shadow-lg p-2 space-y-1">
          <p className="text-xs text-muted-foreground px-2 pb-1 border-b mb-1">
            Select expert role(s) — active skills inject domain knowledge into every response
          </p>
          {skills.length === 0 && (
            <p className="text-xs text-muted-foreground px-2 py-2">Loading skills…</p>
          )}
          {skills.map(skill => {
            const active = activeSkillIds.includes(skill.id);
            return (
              <button
                key={skill.id}
                onClick={() => toggle(skill.id)}
                className={cn(
                  "w-full flex items-start gap-2 px-2 py-2 rounded-md text-left transition-colors text-sm",
                  active ? "bg-primary/5 text-primary" : "hover:bg-muted"
                )}
              >
                <span className={cn(
                  "mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded border",
                  active ? "bg-primary border-primary text-primary-foreground" : "border-border"
                )}>
                  {active && <Check className="h-2.5 w-2.5" />}
                </span>
                <span className="flex-1 min-w-0">
                  <span className="font-medium block">{skill.title}</span>
                  <span className="text-xs text-muted-foreground block truncate">
                    {skill.domains.join(", ")}
                  </span>
                </span>
              </button>
            );
          })}
          {activeSkills.length > 0 && (
            <button
              onClick={() => onChange([])}
              className="w-full text-xs text-muted-foreground hover:text-foreground px-2 py-1 text-left border-t mt-1"
            >
              Clear all
            </button>
          )}
        </div>
      )}
    </div>
  );
}
