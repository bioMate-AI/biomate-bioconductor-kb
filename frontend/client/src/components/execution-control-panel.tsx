/**
 * Unified Execution Control Panel
 *
 * Modern, consolidated workflow execution interface that combines:
 * - Sandbox/Production mode selection
 * - Tunable data scope configuration
 * - Parameter summary with quick edit
 * - Execution controls and progress tracking
 * - Iteration history and comparison
 *
 * Design principles:
 * - Single panel for all execution configuration
 * - Progressive disclosure - start simple, expand for details
 * - Clear visual hierarchy and mode distinction
 * - Inline editing where possible to reduce modal friction
 */

import { useState, useMemo, useCallback } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { Separator } from '@/components/ui/separator';
import { Slider } from '@/components/ui/slider';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Alert, AlertDescription } from '@/components/ui/alert';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import {
  Play,
  Pause,
  Square,
  RotateCcw,
  Settings2,
  ChevronDown,
  ChevronRight,
  FlaskConical,
  Rocket,
  Database,
  Percent,
  Clock,
  HardDrive,
  DollarSign,
  CheckCircle2,
  AlertCircle,
  Loader2,
  Lightbulb,
  ArrowRight,
  GitCompare,
  History,
  Sparkles,
  Info,
  Layers,
  Shuffle,
  ArrowUpRight,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import type {
  ExecutionConfig,
  DataScope,
  ExecutionRun,
  ExecutionRunStatus,
  StepExecution,
  ParameterRecommendation,
  TuningConfig,
} from '@shared/schema';

// ============================================================================
// Types
// ============================================================================

export type ExecutionMode = 'sandbox' | 'production';

export interface ExecutionControlPanelProps {
  /** Workflow name */
  workflowName: string;
  /** Total number of samples/inputs available */
  totalSamples: number;
  /** Total steps in workflow */
  totalSteps: number;
  /** Available strata columns for stratified sampling */
  strataColumns?: string[];
  /** Current execution run (if any) */
  currentRun?: ExecutionRun;
  /** Previous runs for comparison */
  previousRuns?: ExecutionRun[];
  /** Parameter recommendations */
  recommendations?: Record<string, ParameterRecommendation>;
  /** Callback when execution starts */
  onExecute: (config: ExecutionConfig) => Promise<void>;
  /** Callback when execution is paused */
  onPause?: () => Promise<void>;
  /** Callback when execution is resumed */
  onResume?: () => Promise<void>;
  /** Callback when execution is cancelled */
  onCancel?: () => Promise<void>;
  /** Callback to open parameter editor */
  onEditParameters?: () => void;
  /** Callback to apply a recommendation */
  onApplyRecommendation?: (paramKey: string, value: any) => void;
  /** Callback when promoting sandbox to production */
  onPromote?: (runId: string) => void;
  /** Loading state */
  isLoading?: boolean;
  /** Error message */
  error?: string;
  /** Compact mode for embedded use */
  compact?: boolean;
  className?: string;
}

// ============================================================================
// Constants
// ============================================================================

const PRESET_SCOPES = [
  { value: 0.05, label: '5%', description: 'Quick validation' },
  { value: 0.1, label: '10%', description: 'Standard pilot' },
  { value: 0.25, label: '25%', description: 'Extended test' },
  { value: 0.5, label: '50%', description: 'Half dataset' },
  { value: 1.0, label: '100%', description: 'Full dataset' },
];

const SAMPLING_STRATEGIES = [
  { value: 'random', label: 'Random', icon: Shuffle },
  { value: 'stratified', label: 'Stratified', icon: Layers },
  { value: 'first_n', label: 'First N', icon: Database },
] as const;

// ============================================================================
// Main Component
// ============================================================================

export function ExecutionControlPanel({
  workflowName,
  totalSamples,
  totalSteps,
  strataColumns = [],
  currentRun,
  previousRuns = [],
  recommendations = {},
  onExecute,
  onPause,
  onResume,
  onCancel,
  onEditParameters,
  onApplyRecommendation,
  onPromote,
  isLoading = false,
  error,
  compact = false,
  className,
}: ExecutionControlPanelProps) {
  // State
  const [mode, setMode] = useState<ExecutionMode>('sandbox');
  const [fraction, setFraction] = useState(0.1);
  const [samplingStrategy, setSamplingStrategy] = useState<DataScope['samplingStrategy']>('random');
  const [strataColumn, setStrataColumn] = useState<string | undefined>();
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [appliedRecs, setAppliedRecs] = useState<Set<string>>(new Set());

  // Derived values
  const absoluteCount = useMemo(() => {
    return Math.max(1, Math.ceil(totalSamples * fraction));
  }, [totalSamples, fraction]);

  const isRunning = currentRun?.execution.status === 'running';
  const isPaused = currentRun?.execution.status === 'paused';
  const isComplete = currentRun?.execution.status === 'completed';
  const isFailed = currentRun?.execution.status === 'failed';

  const recommendationCount = Object.keys(recommendations).length;
  const unappliedCount = recommendationCount - appliedRecs.size;

  // Build execution config
  const buildConfig = useCallback((): ExecutionConfig => {
    return {
      mode,
      dataScope: {
        fraction: mode === 'production' ? 1.0 : fraction,
        samplingStrategy,
        strataColumn: samplingStrategy === 'stratified' ? strataColumn : undefined,
      },
      environment: {
        historyPrefix: mode === 'sandbox' ? '[Sandbox]' : '[Production]',
        allowTuning: true,
        allowMidRunAdjustment: mode === 'sandbox',
      },
      tracking: {
        collectMetrics: true,
        collectDetailedMetrics: true,
        logLevel: 'detailed',
        notifyMilestones: true,
      },
    };
  }, [mode, fraction, samplingStrategy, strataColumn]);

  // Handlers
  const handleExecute = async () => {
    const config = buildConfig();
    await onExecute(config);
  };

  const handleApplyRecommendation = (key: string) => {
    const rec = recommendations[key];
    if (rec && onApplyRecommendation) {
      onApplyRecommendation(key, rec.recommended_value);
      setAppliedRecs(prev => new Set(prev).add(key));
    }
  };

  const handleApplyAll = () => {
    Object.keys(recommendations).forEach(key => {
      handleApplyRecommendation(key);
    });
  };

  // Render mode toggle
  const renderModeToggle = () => (
    <div className="flex items-center justify-center gap-1 p-1 bg-muted rounded-lg">
      <Button
        variant={mode === 'sandbox' ? 'default' : 'ghost'}
        size="sm"
        className={cn(
          "flex-1 gap-2 transition-all",
          mode === 'sandbox' && "bg-amber-500 hover:bg-amber-600 text-white"
        )}
        onClick={() => setMode('sandbox')}
      >
        <FlaskConical className="h-4 w-4" />
        Sandbox
      </Button>
      <Button
        variant={mode === 'production' ? 'default' : 'ghost'}
        size="sm"
        className={cn(
          "flex-1 gap-2 transition-all",
          mode === 'production' && "bg-green-600 hover:bg-green-700 text-white"
        )}
        onClick={() => setMode('production')}
      >
        <Rocket className="h-4 w-4" />
        Production
      </Button>
    </div>
  );

  // Render data scope section
  const renderDataScope = () => (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <Label className="text-sm font-medium flex items-center gap-2">
          <Database className="h-4 w-4 text-muted-foreground" />
          Data Scope
        </Label>
        <div className="flex items-center gap-2">
          <Badge variant="secondary" className="font-mono">
            {Math.round(fraction * 100)}%
          </Badge>
          <span className="text-xs text-muted-foreground">
            ({absoluteCount.toLocaleString()} of {totalSamples.toLocaleString()})
          </span>
        </div>
      </div>

      {mode === 'sandbox' ? (
        <>
          {/* Slider */}
          <Slider
            value={[fraction]}
            onValueChange={([v]) => setFraction(v)}
            min={0.01}
            max={1}
            step={0.01}
            className="cursor-pointer"
          />

          {/* Preset buttons */}
          <div className="flex gap-1 flex-wrap">
            {PRESET_SCOPES.map((preset) => (
              <TooltipProvider key={preset.value}>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      variant={Math.abs(fraction - preset.value) < 0.01 ? 'default' : 'outline'}
                      size="sm"
                      className="h-7 px-2.5 text-xs"
                      onClick={() => setFraction(preset.value)}
                    >
                      {preset.label}
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>
                    <p>{preset.description}</p>
                    <p className="text-muted-foreground">
                      ~{Math.ceil(totalSamples * preset.value).toLocaleString()} samples
                    </p>
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>
            ))}
          </div>

          {/* Advanced sampling options */}
          <Collapsible open={showAdvanced} onOpenChange={setShowAdvanced}>
            <CollapsibleTrigger asChild>
              <Button variant="ghost" size="sm" className="w-full justify-between h-8 text-xs">
                <span>Sampling Strategy</span>
                <ChevronDown className={cn("h-3 w-3 transition-transform", showAdvanced && "rotate-180")} />
              </Button>
            </CollapsibleTrigger>
            <CollapsibleContent className="space-y-2 pt-2">
              <div className="grid grid-cols-3 gap-1">
                {SAMPLING_STRATEGIES.map((strategy) => (
                  <Button
                    key={strategy.value}
                    variant={samplingStrategy === strategy.value ? 'default' : 'outline'}
                    size="sm"
                    className="h-8 text-xs gap-1"
                    onClick={() => setSamplingStrategy(strategy.value as DataScope['samplingStrategy'])}
                  >
                    <strategy.icon className="h-3 w-3" />
                    {strategy.label}
                  </Button>
                ))}
              </div>

              {samplingStrategy === 'stratified' && strataColumns.length > 0 && (
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Group by column</Label>
                  <Select value={strataColumn || ''} onValueChange={setStrataColumn}>
                    <SelectTrigger className="h-8 text-xs">
                      <SelectValue placeholder="Select column..." />
                    </SelectTrigger>
                    <SelectContent>
                      {strataColumns.map((col) => (
                        <SelectItem key={col} value={col} className="text-xs">
                          {col}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}
            </CollapsibleContent>
          </Collapsible>
        </>
      ) : (
        <div className="flex items-center gap-2 p-2 bg-green-50 dark:bg-green-900/20 rounded-md border border-green-200 dark:border-green-800">
          <CheckCircle2 className="h-4 w-4 text-green-600" />
          <span className="text-sm text-green-700 dark:text-green-300">
            Full dataset ({totalSamples.toLocaleString()} samples)
          </span>
        </div>
      )}
    </div>
  );

  // Render recommendations section
  const renderRecommendations = () => {
    if (recommendationCount === 0) return null;

    return (
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <Label className="text-sm font-medium flex items-center gap-2">
            <Lightbulb className="h-4 w-4 text-amber-500" />
            Recommendations
            <Badge variant="secondary" className="text-xs">
              {unappliedCount > 0 ? unappliedCount : 'All applied'}
            </Badge>
          </Label>
          {unappliedCount > 0 && (
            <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={handleApplyAll}>
              Apply All
            </Button>
          )}
        </div>

        <div className="space-y-1.5">
          {Object.entries(recommendations).slice(0, 3).map(([key, rec]) => (
            <div
              key={key}
              className={cn(
                "flex items-center justify-between p-2 rounded-md text-xs",
                appliedRecs.has(key) ? "bg-green-50 dark:bg-green-900/20" : "bg-muted/50"
              )}
            >
              <div className="flex-1 min-w-0">
                <span className="font-medium truncate">{rec.parameter_name}</span>
                <span className="text-muted-foreground mx-1">→</span>
                <span className="text-primary">{String(rec.recommended_value)}</span>
              </div>
              <Button
                variant={appliedRecs.has(key) ? "secondary" : "outline"}
                size="sm"
                className="h-6 text-xs ml-2 shrink-0"
                onClick={() => handleApplyRecommendation(key)}
                disabled={appliedRecs.has(key)}
              >
                {appliedRecs.has(key) ? (
                  <CheckCircle2 className="h-3 w-3" />
                ) : (
                  'Apply'
                )}
              </Button>
            </div>
          ))}
          {Object.keys(recommendations).length > 3 && (
            <Button variant="ghost" size="sm" className="w-full h-7 text-xs" onClick={onEditParameters}>
              View all {Object.keys(recommendations).length} recommendations...
            </Button>
          )}
        </div>
      </div>
    );
  };

  // Render progress section
  const renderProgress = () => {
    if (!currentRun) return null;

    const { progress, execution, steps } = currentRun;
    const completedSteps = steps?.filter(s => s.status === 'completed').length || 0;
    const currentStep = steps?.find(s => s.status === 'running');

    return (
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            {isRunning && <Loader2 className="h-4 w-4 animate-spin text-blue-500" />}
            {isPaused && <Pause className="h-4 w-4 text-amber-500" />}
            {isComplete && <CheckCircle2 className="h-4 w-4 text-green-500" />}
            {isFailed && <AlertCircle className="h-4 w-4 text-red-500" />}
            <span className="text-sm font-medium">
              {isRunning && 'Running...'}
              {isPaused && 'Paused'}
              {isComplete && 'Complete'}
              {isFailed && 'Failed'}
            </span>
          </div>
          <span className="text-sm text-muted-foreground">
            Step {completedSteps}/{totalSteps}
          </span>
        </div>

        <Progress value={progress?.percentComplete || 0} className="h-2" />

        {currentStep && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <Loader2 className="h-3 w-3 animate-spin" />
            <span className="truncate">{currentStep.stepName}</span>
          </div>
        )}

        {/* Execution controls */}
        <div className="flex gap-2">
          {isRunning && onPause && (
            <Button variant="outline" size="sm" className="flex-1" onClick={onPause}>
              <Pause className="h-4 w-4 mr-2" />
              Pause
            </Button>
          )}
          {isPaused && onResume && (
            <Button variant="outline" size="sm" className="flex-1" onClick={onResume}>
              <Play className="h-4 w-4 mr-2" />
              Resume
            </Button>
          )}
          {(isRunning || isPaused) && onCancel && (
            <Button variant="destructive" size="sm" onClick={onCancel}>
              <Square className="h-4 w-4" />
            </Button>
          )}
        </div>
      </div>
    );
  };

  // Render action buttons
  const renderActions = () => {
    if (isRunning || isPaused) return null;

    const canPromote = isComplete && currentRun?.mode === 'sandbox' && onPromote;

    return (
      <div className="flex gap-2">
        {onEditParameters && (
          <Button variant="outline" size="sm" onClick={onEditParameters}>
            <Settings2 className="h-4 w-4 mr-2" />
            Parameters
          </Button>
        )}
        <Button
          className={cn(
            "flex-1",
            mode === 'sandbox' && "bg-amber-500 hover:bg-amber-600",
            mode === 'production' && "bg-green-600 hover:bg-green-700"
          )}
          onClick={handleExecute}
          disabled={isLoading}
        >
          {isLoading ? (
            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
          ) : (
            <Play className="h-4 w-4 mr-2" />
          )}
          {mode === 'sandbox' ? `Run ${Math.round(fraction * 100)}%` : 'Run Full'}
        </Button>
        {canPromote && (
          <Button
            variant="default"
            className="bg-green-600 hover:bg-green-700"
            onClick={() => onPromote?.(currentRun!.id)}
          >
            <ArrowUpRight className="h-4 w-4 mr-2" />
            Promote
          </Button>
        )}
      </div>
    );
  };

  // Render previous runs
  const renderPreviousRuns = () => {
    if (previousRuns.length === 0) return null;

    return (
      <Collapsible>
        <CollapsibleTrigger asChild>
          <Button variant="ghost" size="sm" className="w-full justify-between h-8 text-xs">
            <span className="flex items-center gap-2">
              <History className="h-3 w-3" />
              Previous Runs ({previousRuns.length})
            </span>
            <ChevronDown className="h-3 w-3" />
          </Button>
        </CollapsibleTrigger>
        <CollapsibleContent className="pt-2">
          <div className="space-y-1.5">
            {previousRuns.slice(0, 3).map((run) => (
              <div
                key={run.id}
                className="flex items-center justify-between p-2 bg-muted/50 rounded-md text-xs"
              >
                <div className="flex items-center gap-2">
                  <Badge variant={run.mode === 'sandbox' ? 'outline' : 'default'} className="text-xs">
                    {run.mode}
                  </Badge>
                  <span className="text-muted-foreground">
                    {Math.round(run.dataScope.fraction * 100)}%
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  {run.metrics?.runtime?.totalSeconds && (
                    <span className="text-muted-foreground">
                      {Math.round(run.metrics.runtime.totalSeconds)}s
                    </span>
                  )}
                  <Badge
                    variant={run.execution.status === 'completed' ? 'default' : 'secondary'}
                    className="text-xs"
                  >
                    {run.execution.status}
                  </Badge>
                </div>
              </div>
            ))}
          </div>
        </CollapsibleContent>
      </Collapsible>
    );
  };

  // Error display
  const renderError = () => {
    if (!error) return null;

    return (
      <Alert variant="destructive">
        <AlertCircle className="h-4 w-4" />
        <AlertDescription>{error}</AlertDescription>
      </Alert>
    );
  };

  // Main render
  return (
    <Card className={cn("border-2", className, {
      "border-amber-200 dark:border-amber-800": mode === 'sandbox',
      "border-green-200 dark:border-green-800": mode === 'production',
    })}>
      <CardHeader className="p-4 pb-2">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base flex items-center gap-2">
            <Sparkles className="h-4 w-4" />
            {workflowName || 'Workflow Execution'}
          </CardTitle>
          <Badge variant="outline" className="text-xs">
            {totalSteps} steps
          </Badge>
        </div>
      </CardHeader>

      <CardContent className="p-4 pt-2 space-y-4">
        {/* Mode Toggle */}
        {renderModeToggle()}

        {/* Data Scope */}
        {renderDataScope()}

        <Separator />

        {/* Recommendations */}
        {renderRecommendations()}

        {/* Progress (when running) */}
        {currentRun && renderProgress()}

        {/* Error */}
        {renderError()}

        {/* Actions */}
        {renderActions()}

        {/* Previous Runs */}
        {renderPreviousRuns()}
      </CardContent>
    </Card>
  );
}

export default ExecutionControlPanel;
