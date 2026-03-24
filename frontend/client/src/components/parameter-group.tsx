import React, { useState } from 'react';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
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
  className?: string;
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

  const commitEdit = () => {
    onChange?.(param.id, editValue);
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
          className="h-6 text-xs px-1.5 py-0"
          value={editValue}
          type={param.type === 'number' ? 'number' : 'text'}
          onChange={(e) => setEditValue(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') commitEdit(); if (e.key === 'Escape') cancelEdit(); }}
          autoFocus
        />
        <button type="button" onClick={commitEdit} className="text-green-600 hover:text-green-700">
          <Check className="h-3 w-3" />
        </button>
        <button type="button" onClick={cancelEdit} className="text-red-500 hover:text-red-700">
          <X className="h-3 w-3" />
        </button>
      </div>
    );
  }

  return (
    <button
      type="button"
      onClick={() => setIsEditing(true)}
      className="inline-flex items-center gap-0.5 text-xs text-muted-foreground hover:text-foreground ml-1 align-middle"
      title="Override AI-recommended value"
    >
      <Pencil className="h-2.5 w-2.5" />
      Override
    </button>
  );
}

export function ParameterGroup({ id, title, description, parameters, onChange, className }: ParameterGroupProps) {
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
      case 'file':
        return (
          <div className="space-y-1">
            <LabelWithKnowledge />
            <Input
              id={param.id}
              type="file"
              onChange={(e) => onChange && onChange(param.id, e.target.files?.[0])}
              className="file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-violet-50 file:text-violet-700 hover:file:bg-violet-100"
            />
          </div>
        );
      default:
        return (
          <div className="space-y-1">
            <div className="flex items-center gap-1 flex-wrap">
              <LabelWithKnowledge />
              <EditableParamRow param={param} onChange={onChange} />
            </div>
            <Input
              id={param.id}
              type={param.type === 'number' ? 'number' : 'text'}
              value={param.value || ''}
              onChange={(e) => onChange && onChange(param.id, e.target.value)}
              placeholder={param.defaultValue ? String(param.defaultValue) : ''}
              className={param.autoFilled ? 'border-blue-300/60 bg-blue-50/30 dark:bg-blue-950/10' : ''}
            />
          </div>
        );
    }
  };

  return (
    <Accordion type="single" collapsible className={cn("w-full border rounded-lg bg-card text-card-foreground shadow-sm", className)}>
      <AccordionItem value={id} className="border-b-0">
        <AccordionTrigger className="px-4 py-3 hover:bg-accent/50 transition-colors">
          <div className="flex flex-col items-start text-left">
            <span className="font-semibold">{title}</span>
            {description && <span className="text-sm text-muted-foreground font-normal mt-1">{description}</span>}
          </div>
        </AccordionTrigger>
        <AccordionContent className="px-4 py-4 space-y-4 border-t">
          {parameters.map((param) => (
            <div key={param.id} className="grid w-full items-center gap-1.5">
              {renderParameterInput(param)}
              {param.description && <p className="text-xs text-muted-foreground">{param.description}</p>}
            </div>
          ))}
        </AccordionContent>
      </AccordionItem>
    </Accordion>
  );
}
