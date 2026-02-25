import React from 'react';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";

interface Parameter {
  id: string;
  name: string;
  type: 'string' | 'number' | 'boolean' | 'select' | 'file';
  label: string;
  defaultValue?: any;
  value?: any;
  options?: { label: string; value: any }[];
  description?: string;
  required?: boolean;
}

interface ParameterGroupProps {
  id: string;
  title: string;
  description?: string;
  parameters: Parameter[];
  onChange?: (id: string, value: any) => void;
  className?: string;
}

export function ParameterGroup({ id, title, description, parameters, onChange, className }: ParameterGroupProps) {
  const renderParameterInput = (param: Parameter) => {
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
          </div>
        );
      case 'select':
        return (
          <div className="space-y-1">
            <Label htmlFor={param.id}>{param.label}</Label>
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
            <Label htmlFor={param.id}>{param.label}</Label>
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
            <Label htmlFor={param.id}>{param.label}</Label>
            <Input 
              id={param.id} 
              type={param.type === 'number' ? 'number' : 'text'}
              value={param.value || ''}
              onChange={(e) => onChange && onChange(param.id, e.target.value)}
              placeholder={param.defaultValue ? String(param.defaultValue) : ''}
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
