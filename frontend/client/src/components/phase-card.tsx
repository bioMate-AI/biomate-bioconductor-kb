import React, { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import {
  Play, Pause, CheckCircle, XCircle, Clock, ChevronDown, ChevronRight,
  FileText, FileImage, Table, FileCode, File, Loader2, Settings2, Eye,
  SkipForward, PauseCircle, SlidersHorizontal, Download,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { StepOutputPreview } from "./step-output-preview";

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
    /** Step-level parameter map for inline overrides */
    parameters?: Record<string, any>;
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
  /** Adjust parameters and rerun from this step */
  onAdjustAndRerun?: () => void;
  /** Structured output files (name, path, extension) for inline preview */
  outputFiles?: Array<{ name: string; path: string; extension: string }>;
  /** Called when the user clicks the eye/preview button on a file */
  onPreviewFile?: (file: { name: string; path: string; extension: string }) => void;
  /** Run ID — enables inline StepOutputPreview and download */
  runId?: string;
  /** Skip this step (pending only) */
  onSkip?: () => void;
  /** Toggle pause-after-this-step */
  onTogglePauseAfter?: () => void;
  /** Whether the workflow should pause after this step */
  pauseAfterEnabled?: boolean;
  /** Called with updated param overrides when user clicks Save */
  onSaveParamOverrides?: (overrides: Record<string, any>) => void;
  className?: string;
}

const VISUALIZABLE_EXTS = new Set([
  'png','jpg','jpeg','gif','svg','pdf',
  'csv','tsv','json','tabular','star',
  'fasta','fa','fastq','fq',
  'vcf','pdb','mmcif','cif','mrc','map','mrcs','rec',
  'bed','gff','gtf','html','htm','log','txt',
]);

export function PhaseCard({
  phase, onExecute, onPause, onResume,
  onRun, runLabel, runDisabled, runLoading, runButtonTestId,
  onAdjustAndRerun, outputFiles, onPreviewFile,
  runId, onSkip, onTogglePauseAfter, pauseAfterEnabled, onSaveParamOverrides,
  className,
}: PhaseCardProps) {
  const [filesExpanded, setFilesExpanded] = useState(false);
  const [paramsExpanded, setParamsExpanded] = useState(false);
  const [inlinePreviewFile, setInlinePreviewFile] = useState<{ name: string; path: string; extension: string } | null>(null);
  const [paramOverrides, setParamOverrides] = useState<Record<string, any>>({});
  const [paramsDirty, setParamsDirty] = useState(false);

  const status = mapNfStatus(phase.status);
  const displayName = phase.processName ? shortProcessName(phase.processName) : phase.name;
  const fullName    = phase.processName ?? phase.name;
  const taskFiles   = phase.taskFiles ?? [];

  // Prefer structured outputFiles; fall back to legacy taskFiles string array
  const displayFiles: Array<{ name: string; path: string; extension: string }> =
    outputFiles ??
    taskFiles.map(f => ({
      name: f,
      path: f,
      extension: f.split('.').pop()?.toLowerCase() ?? '',
    }));

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
    <Card className={cn("w-full transition-all duration-200", className)} data-testid={`phase-card-${phase.id}`} data-status={status}>
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
          <Badge variant="secondary" className={cn("text-[10px] uppercase px-1.5 py-0", badgeClass)} data-testid={`step-status-badge-${phase.id}`} data-status={status}>
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
          {onAdjustAndRerun && status === 'completed' && (
            <Button
              size="sm"
              variant="ghost"
              className="h-6 px-2 text-xs"
              onClick={onAdjustAndRerun}
              title="Adjust parameters and rerun from this step"
              data-testid={`button-adjust-step-${phase.id}`}
            >
              <Settings2 className="h-3 w-3" />
            </Button>
          )}
          {/* Skip step (pending only) */}
          {status === 'pending' && onSkip && (
            <Button
              size="sm"
              variant="ghost"
              className="h-6 px-2 text-xs text-muted-foreground"
              onClick={onSkip}
              title="Skip this step"
              data-testid={`button-skip-step-${phase.id}`}
            >
              <SkipForward className="h-3 w-3" />
            </Button>
          )}
          {/* Pause-after toggle */}
          {onTogglePauseAfter && (
            <Button
              size="sm"
              variant="ghost"
              className={cn("h-6 px-2 text-xs", pauseAfterEnabled && "text-amber-600")}
              onClick={onTogglePauseAfter}
              title={pauseAfterEnabled ? "Cancel pause after this step" : "Pause workflow after this step"}
              data-testid={`button-pause-after-${phase.id}`}
            >
              <PauseCircle className="h-3 w-3" />
            </Button>
          )}
          {/* Param overrides toggle */}
          {onSaveParamOverrides && phase.parameters && Object.keys(phase.parameters as object).length > 0 && (
            <Button
              size="sm"
              variant="ghost"
              className={cn("h-6 px-2 text-xs", paramsExpanded && "text-primary")}
              onClick={() => setParamsExpanded(e => !e)}
              title="Edit step parameters"
              data-testid={`button-params-step-${phase.id}`}
            >
              <SlidersHorizontal className="h-3 w-3" />
            </Button>
          )}
        </div>
      </CardHeader>

      {/* Pause-after banner */}
      {pauseAfterEnabled && (
        <div className="mx-3 mb-1 px-2 py-1 rounded text-[11px] bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300 flex items-center gap-1">
          <PauseCircle className="h-3 w-3 flex-shrink-0" />
          Workflow will pause after this step
        </div>
      )}

      {/* Inline param override panel */}
      {paramsExpanded && phase.parameters && (
        <CardContent className="pt-0 pb-2 px-3">
          <div className="space-y-1.5 border rounded-md p-2 bg-muted/30">
            {Object.entries(phase.parameters as Record<string, any>).map(([key, defaultVal]) => {
              const current = key in paramOverrides ? paramOverrides[key] : defaultVal;
              const type = typeof defaultVal;
              return (
                <div key={key} className="flex items-center gap-2 text-[11px]">
                  <Label className="text-[11px] font-mono w-28 flex-shrink-0 truncate" title={key}>{key}</Label>
                  {type === 'boolean' ? (
                    <Switch
                      checked={!!current}
                      onCheckedChange={(v) => { setParamOverrides(p => ({...p, [key]: v})); setParamsDirty(true); }}
                    />
                  ) : (
                    <Input
                      type={type === 'number' ? 'number' : 'text'}
                      value={current ?? ''}
                      className="h-6 text-[11px] font-mono"
                      onChange={e => {
                        const v = type === 'number' ? parseFloat(e.target.value) : e.target.value;
                        setParamOverrides(p => ({...p, [key]: v}));
                        setParamsDirty(true);
                      }}
                    />
                  )}
                </div>
              );
            })}
            <Button
              size="sm"
              variant="outline"
              className="h-6 text-[11px] mt-1"
              disabled={!paramsDirty}
              onClick={() => {
                const merged = { ...(phase.parameters as Record<string, any>), ...paramOverrides };
                onSaveParamOverrides!(merged);
                setParamsDirty(false);
              }}
            >
              Save &amp; Apply Overrides
            </Button>
          </div>
        </CardContent>
      )}

      {/* Task output files — shown when available from trace work_dir scan */}
      {displayFiles.length > 0 && (
        <CardContent className="pt-0 pb-2 px-3">
          <button
            className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
            onClick={() => setFilesExpanded(e => !e)}
          >
            {filesExpanded
              ? <ChevronDown className="h-3 w-3" />
              : <ChevronRight className="h-3 w-3" />}
            {displayFiles.length} output file{displayFiles.length !== 1 ? 's' : ''}
          </button>
          {filesExpanded && (
            <div className="mt-1.5 space-y-0.5 pl-3">
              {displayFiles.map((f, i) => {
                const canInlinePreview = runId && VISUALIZABLE_EXTS.has(f.extension.toLowerCase().replace(/^\./, ''));
                const canPreview = onPreviewFile && VISUALIZABLE_EXTS.has(f.extension.toLowerCase().replace(/^\./, ''));
                return (
                  <div key={i} className="flex items-center gap-1.5 text-[11px]">
                    {fileIcon(f.name)}
                    <span className="font-mono truncate">{f.name}</span>
                    <div className="ml-auto flex items-center gap-1 flex-shrink-0">
                      {canInlinePreview && (
                        <button
                          className="text-muted-foreground hover:text-foreground transition-colors"
                          onClick={() => setInlinePreviewFile(prev => prev?.path === f.path ? null : f)}
                          title="Preview inline"
                          data-testid={`phase-card-preview-btn-${f.name}`}
                        >
                          <Eye className="h-3 w-3" />
                        </button>
                      )}
                      {!canInlinePreview && canPreview && (
                        <button
                          className="text-muted-foreground hover:text-foreground transition-colors"
                          onClick={() => onPreviewFile!(f)}
                          title="Preview file"
                          data-testid={`phase-card-preview-btn-${f.name}`}
                        >
                          <Eye className="h-3 w-3" />
                        </button>
                      )}
                      {runId && (
                        <a
                          href={`/api/workflows/runs/${encodeURIComponent(runId)}/step-file?path=${encodeURIComponent(f.path)}&download=1`}
                          className="text-muted-foreground hover:text-foreground transition-colors"
                          title="Download file"
                          data-testid={`phase-card-download-btn-${f.name}`}
                          onClick={e => e.stopPropagation()}
                        >
                          <Download className="h-3 w-3" />
                        </a>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
          {/* Inline StepOutputPreview */}
          {inlinePreviewFile && runId && (
            <div className="mt-2">
              <StepOutputPreview
                runId={runId}
                file={inlinePreviewFile}
                onClose={() => setInlinePreviewFile(null)}
              />
            </div>
          )}
        </CardContent>
      )}
    </Card>
  );
}
