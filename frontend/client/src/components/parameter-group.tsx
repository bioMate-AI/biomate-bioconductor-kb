import React, { useState, useRef } from 'react';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import { Info, ExternalLink, Pencil, Check, X } from "lucide-react";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

export interface Parameter {
  id: string;
  name: string;
  type: 'string' | 'number' | 'boolean' | 'select' | 'file';
  label: string;
  defaultValue?: any;
  value?: any;
  options?: { label: string; value: any }[];
  description?: string;
  required?: boolean;
  minimum?: number;
  maximum?: number;
  /** Rationale for auto-filled value (from tool_knowledge or parameter_hints) */
  rationale?: string;
  /** Primary citation for the recommended value */
  citation?: {
    pmid?: string;
    doi?: string;
    title?: string;
    authors?: string[];
    journal?: string;
    year?: number;
    url?: string;
  };
  /** Whether this value was auto-filled by the AI from tool knowledge */
  autoFilled?: boolean;
}

interface ParameterGroupProps {
  id: string;
  title: string;
  description?: string;
  parameters: Parameter[];
  onChange?: (id: string, value: any) => void;
  /** Called when user clicks Browse on a file-type parameter. Parent opens the dataset browser. */
  onBrowseDataset?: (paramId: string, paramLabel: string) => void;
  className?: string;
  /** Open the accordion by default (true when workflow has parameters to fill) */
  defaultOpen?: boolean;
}

function KnowledgeBadge({ param }: { param: Parameter }) {
  if (!param.rationale && !param.citation) return null;

  const pmidUrl = param.citation?.pmid
    ? `https://pubmed.ncbi.nlm.nih.gov/${param.citation.pmid}`
    : param.citation?.url;

  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <button
            type="button"
            data-testid={`param-knowledge-badge-${param.id}`}
            className="inline-flex items-center text-blue-500 hover:text-blue-700 ml-1 align-middle"
            aria-label={`Why this value? ${param.rationale || ''}`}
          >
            <Info className="h-3 w-3" />
          </button>
        </TooltipTrigger>
        <TooltipContent side="right" className="max-w-xs text-xs space-y-1.5 p-3">
          {param.autoFilled && (
            <Badge variant="secondary" className="text-xs mb-1">AI-recommended</Badge>
          )}
          {param.rationale && (
            <p className="text-foreground leading-snug">{param.rationale}</p>
          )}
          {param.citation && (
            <div className="text-muted-foreground border-t border-border pt-1.5 mt-1.5">
              {param.citation.title && (
                <p className="font-medium text-foreground leading-snug line-clamp-2">{param.citation.title}</p>
              )}
              {param.citation.authors && param.citation.authors.length > 0 && (
                <p>{param.citation.authors.slice(0, 2).join(', ')}{param.citation.authors.length > 2 ? ' et al.' : ''}</p>
              )}
              {param.citation.journal && param.citation.year && (
                <p>{param.citation.journal} {param.citation.year}</p>
              )}
              {pmidUrl && (
                <a
                  href={pmidUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-0.5 text-blue-500 hover:text-blue-700 mt-0.5"
                >
                  {param.citation.pmid ? `PMID:${param.citation.pmid}` : 'View publication'}
                  <ExternalLink className="h-2.5 w-2.5" />
                </a>
              )}
            </div>
          )}
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}

function EditableParamRow({ param, onChange }: { param: Parameter; onChange?: (id: string, value: any) => void }) {
  const [isEditing, setIsEditing] = useState(false);
  const [editValue, setEditValue] = useState(String(param.value ?? ''));
  const inputRef = useRef<HTMLInputElement>(null);

  const commitEdit = () => {
    // Read from DOM ref as source of truth — handles cases where React state
    // hasn't updated yet (e.g. programmatic value changes, fast typing + Enter).
    const rawVal = inputRef.current?.value ?? editValue;
    const committed = param.type === 'number' ? Number(rawVal) : rawVal;
    onChange?.(param.id, committed);
    setIsEditing(false);
  };

  const cancelEdit = () => {
    setEditValue(String(param.value ?? ''));
    setIsEditing(false);
  };

  if (!param.autoFilled || param.type === 'boolean' || param.type === 'select' || param.type === 'file') {
    return null;
  }

  if (isEditing) {
    return (
      <div className="flex items-center gap-1 mt-0.5">
        <Input
          ref={inputRef}
          data-testid={`param-inline-edit-${param.id}`}
          className="h-6 text-xs px-1.5 py-0"
          defaultValue={editValue}
          type={param.type === 'number' ? 'number' : 'text'}
          onChange={(e) => setEditValue(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') commitEdit(); if (e.key === 'Escape') cancelEdit(); }}
          autoFocus
        />
        <button type="button" data-testid={`param-confirm-btn-${param.id}`} onClick={commitEdit} className="text-green-600 hover:text-green-700">
          <Check className="h-3 w-3" />
        </button>
        <button type="button" data-testid={`param-cancel-btn-${param.id}`} onClick={cancelEdit} className="text-red-500 hover:text-red-700">
          <X className="h-3 w-3" />
        </button>
      </div>
    );
  }

  return (
    <button
      type="button"
      data-testid={`param-override-btn-${param.id}`}
      onClick={() => setIsEditing(true)}
      className="inline-flex items-center gap-0.5 text-xs text-muted-foreground hover:text-foreground ml-1 align-middle"
      title="Override AI-recommended value"
    >
      <Pencil className="h-2.5 w-2.5" />
      Override
    </button>
  );
}

export function ParameterGroup({ id, title, description, parameters, onChange, onBrowseDataset, className, defaultOpen }: ParameterGroupProps) {
  // Controlled accordion: Radix's defaultValue is honored only at mount.
  // When inline_parameters arrives asynchronously via SSE, defaultOpen flips
  // from false→true after mount, but Radix ignores the prop change. We track
  // the open state in React so prop updates actually re-open the accordion.
  const [accordionValue, setAccordionValue] = React.useState<string>(defaultOpen ? id : '');
  React.useEffect(() => {
    if (defaultOpen) setAccordionValue(id);
  }, [defaultOpen, id]);
  const renderParameterInput = (param: Parameter) => {
    const hasKnowledge = !!(param.rationale || param.citation);
    const LabelWithKnowledge = () => (
      <span className="flex items-center gap-0.5">
        <Label htmlFor={param.id}>{param.label}</Label>
        {param.required && <span className="text-destructive text-xs ml-0.5">*</span>}
        {hasKnowledge && <KnowledgeBadge param={param} />}
      </span>
    );

    switch (param.type) {
      case 'boolean':
        return (
          <div className="flex items-center space-x-2">
            <Switch
              id={param.id}
              checked={param.value}
              onCheckedChange={(checked) => onChange && onChange(param.id, checked)}
            />
            <Label htmlFor={param.id} className="cursor-pointer">{param.label}</Label>
            {hasKnowledge && <KnowledgeBadge param={param} />}
          </div>
        );
      case 'select':
        return (
          <div className="space-y-1">
            <LabelWithKnowledge />
            <Select onValueChange={(val) => onChange && onChange(param.id, val)} value={param.value}>
              <SelectTrigger>
                <SelectValue placeholder="Select an option" />
              </SelectTrigger>
              <SelectContent>
                {param.options?.map((opt) => (
                  <SelectItem key={opt.value} value={opt.value}>
                    {opt.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        );
      case 'file': {
        const idLower = param.id.toLowerCase();
        const _ML_SUFFIXES = ['_csv', '_tsv', '_fasta', '_fa', '_sequences', '_actives', '_library', '_smiles'];
        const isMultilineFile = _ML_SUFFIXES.some(s => idLower.endsWith(s));
        if (isMultilineFile) {
          return (
            <div className="space-y-1">
              <LabelWithKnowledge />
              <Textarea
                id={param.id}
                value={param.value ?? ''}
                rows={5}
                onChange={(e) => onChange && onChange(param.id, e.target.value)}
                placeholder="Paste inline content (CSV / SMILES / FASTA) or enter a file path…"
                className={`font-mono text-xs resize-y ${param.autoFilled ? 'border-blue-300/60 bg-blue-50/30 dark:bg-blue-950/10' : ''}`}
              />
            </div>
          );
        }
        // Only show Browse button for actual file-path params (ends with _path, _dir, _file, _input, _output, _paths)
        const _PATH_SUFFIXES = ['_path', '_paths', '_dir', '_directory', '_input', '_output', '_file', '_files'];
        const isActualPath = _PATH_SUFFIXES.some(s => idLower.endsWith(s));
        return (
          <div className="space-y-1">
            <LabelWithKnowledge />
            <div className={isActualPath ? "flex gap-2" : undefined}>
              <Input
                id={param.id}
                type="text"
                value={param.value || ''}
                onChange={(e) => onChange && onChange(param.id, e.target.value)}
                placeholder={isActualPath ? "Dataset path or ID" : ""}
                className={param.autoFilled ? 'border-blue-300/60 bg-blue-50/30 dark:bg-blue-950/10' : ''}
              />
              {isActualPath && (
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  className="flex-shrink-0"
                  onClick={() => onBrowseDataset?.(param.id, param.label)}
                >
                  Browse
                </Button>
              )}
            </div>
          </div>
        );
      }
      default: {
        // Detect params that hold multi-line content (CSV, SMILES lists, FASTA, etc.)
        const _MULTILINE_SUFFIXES = ['_csv', '_tsv', '_fasta', '_fa', '_sequences', '_actives', '_library', '_smiles'];
        const isMultiline = _MULTILINE_SUFFIXES.some(s => param.id.toLowerCase().endsWith(s));
        if (isMultiline) {
          return (
            <div className="space-y-1">
              <div className="flex items-center gap-1 flex-wrap">
                <LabelWithKnowledge />
              </div>
              <Textarea
                id={param.id}
                value={param.value ?? ''}
                rows={5}
                onChange={(e) => onChange && onChange(param.id, e.target.value)}
                placeholder={param.defaultValue != null ? String(param.defaultValue) : 'Paste CSV / SMILES / FASTA content here…'}
                className={`font-mono text-xs resize-y ${param.autoFilled ? 'border-blue-300/60 bg-blue-50/30 dark:bg-blue-950/10' : ''}`}
              />
            </div>
          );
        }
        // Detect secret/credential params — render as password field
        const _idLower = param.id.toLowerCase();
        const isSecret = ['license', 'password', 'secret', 'token', 'api_key', 'apikey', 'credential', 'passphrase', 'passwd'].some(
          kw => _idLower.includes(kw)
        );
        if (isSecret) {
          return (
            <div className="space-y-1">
              <LabelWithKnowledge />
              <Input
                id={param.id}
                type="password"
                autoComplete="off"
                value={param.value ?? ''}
                onChange={(e) => onChange && onChange(param.id, e.target.value)}
                placeholder="Enter securely — value is masked"
                className={param.autoFilled ? 'border-blue-300/60 bg-blue-50/30 dark:bg-blue-950/10' : ''}
              />
            </div>
          );
        }
        return (
          <div className="space-y-1">
            <div className="flex items-center gap-1 flex-wrap">
              <LabelWithKnowledge />
              <EditableParamRow param={param} onChange={onChange} />
            </div>
            <Input
              id={param.id}
              type={param.type === 'number' ? 'number' : 'text'}
              value={param.value ?? ''}
              min={param.type === 'number' ? param.minimum : undefined}
              max={param.type === 'number' ? param.maximum : undefined}
              onChange={(e) => onChange && onChange(param.id, param.type === 'number' ? Number(e.target.value) : e.target.value)}
              placeholder={param.defaultValue != null ? String(param.defaultValue) : ''}
              className={param.autoFilled ? 'border-blue-300/60 bg-blue-50/30 dark:bg-blue-950/10' : ''}
            />
            {param.minimum != null && param.maximum != null && (
              <p className="text-[10px] text-muted-foreground">Range: {param.minimum} – {param.maximum}</p>
            )}
          </div>
        );
      }
    }
  };

  return (
    <Accordion type="single" collapsible value={accordionValue} onValueChange={setAccordionValue} className={cn("w-full border rounded-lg bg-card text-card-foreground shadow-sm", className)}>
      <AccordionItem value={id} className="border-b-0">
        <AccordionTrigger className="px-4 py-3 hover:bg-accent/50 hover:no-underline transition-colors">
          <div className="flex flex-col items-start text-left">
            <span className="font-semibold">{title}</span>
            {description && accordionValue !== id && <span className="text-sm text-muted-foreground font-normal mt-1">{description}</span>}
          </div>
        </AccordionTrigger>
        <AccordionContent className="px-4 py-4 space-y-4 border-t">
          {parameters.map((param) => (
            <div key={param.id} className="grid w-full items-center gap-1.5">
              {renderParameterInput(param)}
              {/* param description hidden — replace with type/range constraints when available */}
              {/* {param.description && <p className="text-xs text-muted-foreground">{param.description}</p>} */}
            </div>
          ))}
        </AccordionContent>
      </AccordionItem>
    </Accordion>
  );
}
