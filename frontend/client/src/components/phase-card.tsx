import React, { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Play, Pause, CheckCircle, XCircle, Clock, ChevronDown, ChevronRight,
  FileText, FileImage, Table, FileCode, File, Loader2,
} from "lucide-react";
import { cn } from "@/lib/utils";

/** Map Nextflow trace status strings to our internal status */
function mapNfStatus(nfStatus: string): 'pending' | 'running' | 'completed' | 'failed' | 'paused' {
  switch (nfStatus.toUpperCase()) {
    case 'COMPLETED': return 'completed';
    case 'FAILED':    return 'failed';
    case 'RUNNING':
    case 'SUBMITTED': return 'running';
    default:          return 'pending';
  }
}

/** Derive a short display label from a fully-qualified Nextflow process name.
 *  "NFCORE_RNASEQ:RNASEQ:ALIGN_STAR:STAR_ALIGN" → "STAR_ALIGN"
 */
function shortProcessName(name: string): string {
  const parts = name.split(':');
  return parts[parts.length - 1] || name;
}

function fileIcon(filename: string) {
  const ext = filename.split('.').pop()?.toLowerCase() ?? '';
  if (['png','jpg','jpeg','svg','gif','pdf'].includes(ext))
    return <FileImage className="h-3 w-3 flex-shrink-0 text-blue-500" />;
  if (['csv','tsv','txt','bed','vcf','gtf'].includes(ext))
    return <Table className="h-3 w-3 flex-shrink-0 text-green-500" />;
  if (['html','htm'].includes(ext))
    return <FileCode className="h-3 w-3 flex-shrink-0 text-purple-500" />;
  if (['log','sh','env','out','err'].includes(ext))
    return <FileText className="h-3 w-3 flex-shrink-0 text-muted-foreground" />;
  return <File className="h-3 w-3 flex-shrink-0 text-muted-foreground" />;
}

interface PhaseCardProps {
  phase: {
    id: string;
    name: string;
    description?: string;
    /** Internal status ('pending' | 'running' | 'completed' | 'failed' | 'paused')
     *  OR raw Nextflow trace status ('COMPLETED' | 'FAILED' | 'RUNNING' | 'SUBMITTED')
     */
    status: string;
    progress?: number;
    /** Files produced by this task (from trace work_dir scan) */
    taskFiles?: string[];
    /** Full Nextflow process name (e.g. NFCORE_RNASEQ:RNASEQ:FASTQC) */
    processName?: string;
    /** Local work directory path for this task */
    workDir?: string;
    /** Run count (for step-level re-run tracking) */
    runCount?: number;
    /** Whether this step is executing */
    isExecuting?: boolean;
    /** Galaxy tool ID (required to enable step-level run button) */
    toolId?: string;
  };
  onExecute?: () => void;
  onPause?: () => void;
  onResume?: () => void;
  /** Step-level run handler (used in the per-step execution panel) */
  onRun?: () => void;
  runLabel?: string;
  runDisabled?: boolean;
  runLoading?: boolean;
  runButtonTestId?: string;
  className?: string;
}

export function PhaseCard({
  phase, onExecute, onPause, onResume,
  onRun, runLabel, runDisabled, runLoading, runButtonTestId,
  className,
}: PhaseCardProps) {
  const [filesExpanded, setFilesExpanded] = useState(false);

  const status = mapNfStatus(phase.status);
  const displayName = phase.processName ? shortProcessName(phase.processName) : phase.name;
  const fullName    = phase.processName ?? phase.name;
  const taskFiles   = phase.taskFiles ?? [];

  const statusIcon = {
    completed: <CheckCircle className="h-4 w-4 text-green-500" />,
    failed:    <XCircle    className="h-4 w-4 text-red-500"   />,
    running:   <Loader2    className="h-4 w-4 text-blue-500 animate-spin" />,
    paused:    <Pause      className="h-4 w-4 text-yellow-500" />,
    pending:   <Clock      className="h-4 w-4 text-muted-foreground" />,
  }[status];

  const badgeClass = {
    completed: 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300',
    failed:    'bg-red-100   text-red-800   dark:bg-red-900/40   dark:text-red-300',
    running:   'bg-blue-100  text-blue-800  dark:bg-blue-900/40  dark:text-blue-300',
    paused:    'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/40 dark:text-yellow-300',
    pending:   'bg-gray-100  text-gray-600  dark:bg-gray-800     dark:text-gray-400',
  }[status];

  return (
    <Card className={cn("w-full transition-all duration-200", className)} data-testid={`phase-card-${phase.id}`}>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 py-2 px-3">
        <div className="flex items-center gap-2 min-w-0">
          {statusIcon}
          <div className="min-w-0">
            <CardTitle
              className="text-sm font-medium leading-tight truncate"
              title={fullName}
            >
              {displayName}
            </CardTitle>
            {phase.description && (
              <p className="text-[11px] text-muted-foreground mt-0.5 truncate">{phase.description}</p>
            )}
          </div>
        </div>
        <div className="flex items-center gap-1.5 flex-shrink-0">
          <Badge variant="secondary" className={cn("text-[10px] uppercase px-1.5 py-0", badgeClass)}>
            {status}
          </Badge>
          {status === 'pending' && onExecute && (
            <Button size="sm" variant="ghost" className="h-6 px-2 text-xs" onClick={onExecute}>
              <Play className="h-3 w-3" />
            </Button>
          )}
          {status === 'running' && onPause && (
            <Button size="sm" variant="ghost" className="h-6 px-2 text-xs" onClick={onPause}>
              <Pause className="h-3 w-3" />
            </Button>
          )}
          {status === 'paused' && onResume && (
            <Button size="sm" variant="ghost" className="h-6 px-2 text-xs" onClick={onResume}>
              <Play className="h-3 w-3" />
            </Button>
          )}
          {onRun && (
            <Button
              size="sm"
              variant="ghost"
              className="h-6 px-2 text-xs"
              onClick={onRun}
              disabled={runDisabled}
              data-testid={runButtonTestId}
            >
              {runLoading
                ? <Loader2 className="h-3 w-3 animate-spin" />
                : <Play className="h-3 w-3" />}
              {runLabel && <span className="ml-1">{runLabel}</span>}
            </Button>
          )}
        </div>
      </CardHeader>

      {/* Task output files — shown when available from trace work_dir scan */}
      {taskFiles.length > 0 && (
        <CardContent className="pt-0 pb-2 px-3">
          <button
            className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
            onClick={() => setFilesExpanded(e => !e)}
          >
            {filesExpanded
              ? <ChevronDown className="h-3 w-3" />
              : <ChevronRight className="h-3 w-3" />}
            {taskFiles.length} output file{taskFiles.length !== 1 ? 's' : ''}
          </button>
          {filesExpanded && (
            <div className="mt-1.5 space-y-0.5 pl-3">
              {taskFiles.map((f, i) => (
                <div key={i} className="flex items-center gap-1.5 text-[11px]">
                  {fileIcon(f)}
                  <span className="font-mono truncate">{f}</span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      )}
    </Card>
  );
}
