/**
 * Data Scope Configuration Component
 *
 * Allows users to configure tunable data scope for workflow execution:
 * - Fraction slider (1% - 100%)
 * - Sampling strategy selection
 * - Strata column selection (for stratified sampling)
 * - Distribution preview
 */

import { useState, useMemo } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Button } from '@/components/ui/button';
import { ChevronDown, Database, Percent, Shuffle, Layers, Info } from 'lucide-react';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import type { DataScope } from '@shared/schema';

export interface DataScopeConfigProps {
  /** Total number of samples available */
  totalSamples: number;
  /** Available strata columns for stratified sampling */
  strataColumns?: string[];
  /** Sample metadata for distribution preview */
  sampleMetadata?: Array<{ id: string; [key: string]: any }>;
  /** Initial data scope configuration */
  initialConfig?: Partial<DataScope>;
  /** Callback when configuration changes */
  onChange: (config: DataScope) => void;
  /** Whether the component is in read-only mode */
  readOnly?: boolean;
  /** Whether to show compact version */
  compact?: boolean;
}

const SAMPLING_STRATEGIES = [
  {
    value: 'random',
    label: 'Random',
    description: 'Randomly select samples without bias',
    icon: Shuffle,
  },
  {
    value: 'stratified',
    label: 'Stratified',
    description: 'Maintain proportions from each group',
    icon: Layers,
  },
  {
    value: 'first_n',
    label: 'First N',
    description: 'Select first N samples in order',
    icon: Database,
  },
  {
    value: 'representative',
    label: 'Representative',
    description: 'Select diverse representative samples',
    icon: Info,
  },
] as const;

const PRESET_FRACTIONS = [
  { value: 0.05, label: '5%' },
  { value: 0.1, label: '10%' },
  { value: 0.25, label: '25%' },
  { value: 0.5, label: '50%' },
  { value: 1.0, label: '100%' },
];

export function DataScopeConfig({
  totalSamples,
  strataColumns = [],
  sampleMetadata = [],
  initialConfig,
  onChange,
  readOnly = false,
  compact = false,
}: DataScopeConfigProps) {
  const [fraction, setFraction] = useState(initialConfig?.fraction ?? 0.1);
  const [samplingStrategy, setSamplingStrategy] = useState<DataScope['samplingStrategy']>(
    initialConfig?.samplingStrategy ?? 'random'
  );
  const [strataColumn, setStrataColumn] = useState<string | undefined>(
    initialConfig?.strataColumn
  );
  const [isExpanded, setIsExpanded] = useState(!compact);

  // Calculate actual sample count
  const absoluteCount = useMemo(() => {
    return Math.max(1, Math.ceil(totalSamples * fraction));
  }, [totalSamples, fraction]);

  // Calculate strata distribution if stratified sampling
  const strataDistribution = useMemo(() => {
    if (samplingStrategy !== 'stratified' || !strataColumn || sampleMetadata.length === 0) {
      return undefined;
    }

    const groups: Record<string, number> = {};
    sampleMetadata.forEach((sample) => {
      const value = sample[strataColumn] || 'Unknown';
      groups[value] = (groups[value] || 0) + 1;
    });

    // Calculate proportional samples for each group
    const distribution: Record<string, number> = {};
    Object.entries(groups).forEach(([key, count]) => {
      const proportion = count / totalSamples;
      distribution[key] = Math.max(1, Math.round(absoluteCount * proportion));
    });

    return distribution;
  }, [samplingStrategy, strataColumn, sampleMetadata, totalSamples, absoluteCount]);

  // Emit changes
  const emitChange = (updates: Partial<DataScope>) => {
    const newConfig: DataScope = {
      fraction: updates.fraction ?? fraction,
      absoluteCount: updates.absoluteCount ?? absoluteCount,
      totalAvailable: totalSamples,
      samplingStrategy: updates.samplingStrategy ?? samplingStrategy,
      sampledIds: [],
      strataDistribution: updates.strataDistribution ?? strataDistribution,
      strataColumn: updates.strataColumn ?? strataColumn,
    };
    onChange(newConfig);
  };

  const handleFractionChange = (value: number[]) => {
    const newFraction = value[0];
    setFraction(newFraction);
    emitChange({ fraction: newFraction });
  };

  const handleStrategyChange = (value: string) => {
    const newStrategy = value as DataScope['samplingStrategy'];
    setSamplingStrategy(newStrategy);
    emitChange({ samplingStrategy: newStrategy });
  };

  const handleStrataColumnChange = (value: string) => {
    setStrataColumn(value);
    emitChange({ strataColumn: value });
  };

  const strategyConfig = SAMPLING_STRATEGIES.find((s) => s.value === samplingStrategy);
  const StrategyIcon = strategyConfig?.icon || Database;

  if (compact) {
    return (
      <Collapsible open={isExpanded} onOpenChange={setIsExpanded}>
        <CollapsibleTrigger asChild>
          <div className="flex items-center justify-between p-2 rounded-md border cursor-pointer hover:bg-accent/50 transition-colors">
            <div className="flex items-center gap-2">
              <Percent className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm font-medium">Data Scope</span>
              <Badge variant="outline" className="ml-2">
                {Math.round(fraction * 100)}% ({absoluteCount} samples)
              </Badge>
            </div>
            <ChevronDown
              className={`h-4 w-4 transition-transform ${isExpanded ? 'rotate-180' : ''}`}
            />
          </div>
        </CollapsibleTrigger>
        <CollapsibleContent className="pt-2">
          <DataScopeConfigContent
            fraction={fraction}
            absoluteCount={absoluteCount}
            totalSamples={totalSamples}
            samplingStrategy={samplingStrategy}
            strataColumn={strataColumn}
            strataColumns={strataColumns}
            strataDistribution={strataDistribution}
            readOnly={readOnly}
            onFractionChange={handleFractionChange}
            onStrategyChange={handleStrategyChange}
            onStrataColumnChange={handleStrataColumnChange}
          />
        </CollapsibleContent>
      </Collapsible>
    );
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <Database className="h-4 w-4" />
          Data Scope
        </CardTitle>
        <CardDescription>
          Configure how much of your data to include in this run
        </CardDescription>
      </CardHeader>
      <CardContent>
        <DataScopeConfigContent
          fraction={fraction}
          absoluteCount={absoluteCount}
          totalSamples={totalSamples}
          samplingStrategy={samplingStrategy}
          strataColumn={strataColumn}
          strataColumns={strataColumns}
          strataDistribution={strataDistribution}
          readOnly={readOnly}
          onFractionChange={handleFractionChange}
          onStrategyChange={handleStrategyChange}
          onStrataColumnChange={handleStrataColumnChange}
        />
      </CardContent>
    </Card>
  );
}

interface DataScopeConfigContentProps {
  fraction: number;
  absoluteCount: number;
  totalSamples: number;
  samplingStrategy: DataScope['samplingStrategy'];
  strataColumn?: string;
  strataColumns: string[];
  strataDistribution?: Record<string, number>;
  readOnly: boolean;
  onFractionChange: (value: number[]) => void;
  onStrategyChange: (value: string) => void;
  onStrataColumnChange: (value: string) => void;
}

function DataScopeConfigContent({
  fraction,
  absoluteCount,
  totalSamples,
  samplingStrategy,
  strataColumn,
  strataColumns,
  strataDistribution,
  readOnly,
  onFractionChange,
  onStrategyChange,
  onStrataColumnChange,
}: DataScopeConfigContentProps) {
  return (
    <div className="space-y-4">
      {/* Fraction Slider */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <Label className="text-sm font-medium">Sample Fraction</Label>
          <div className="flex items-center gap-2">
            <Badge variant="secondary" className="font-mono">
              {Math.round(fraction * 100)}%
            </Badge>
            <span className="text-sm text-muted-foreground">
              ({absoluteCount} of {totalSamples})
            </span>
          </div>
        </div>

        <Slider
          value={[fraction]}
          onValueChange={onFractionChange}
          min={0.01}
          max={1}
          step={0.01}
          disabled={readOnly}
          className="cursor-pointer"
        />

        {/* Preset buttons */}
        <div className="flex gap-1 flex-wrap">
          {PRESET_FRACTIONS.map((preset) => (
            <Button
              key={preset.value}
              variant={Math.abs(fraction - preset.value) < 0.01 ? 'default' : 'outline'}
              size="sm"
              className="h-7 px-2 text-xs"
              disabled={readOnly}
              onClick={() => onFractionChange([preset.value])}
            >
              {preset.label}
            </Button>
          ))}
        </div>
      </div>

      {/* Sampling Strategy */}
      <div className="space-y-2">
        <Label className="text-sm font-medium">Sampling Strategy</Label>
        <Select
          value={samplingStrategy}
          onValueChange={onStrategyChange}
          disabled={readOnly}
        >
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {SAMPLING_STRATEGIES.map((strategy) => (
              <SelectItem key={strategy.value} value={strategy.value}>
                <div className="flex items-center gap-2">
                  <strategy.icon className="h-4 w-4" />
                  <div>
                    <div className="font-medium">{strategy.label}</div>
                    <div className="text-xs text-muted-foreground">
                      {strategy.description}
                    </div>
                  </div>
                </div>
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* Strata Column (for stratified sampling) */}
      {samplingStrategy === 'stratified' && strataColumns.length > 0 && (
        <div className="space-y-2">
          <Label className="text-sm font-medium">Group By</Label>
          <Select
            value={strataColumn || ''}
            onValueChange={onStrataColumnChange}
            disabled={readOnly}
          >
            <SelectTrigger>
              <SelectValue placeholder="Select column..." />
            </SelectTrigger>
            <SelectContent>
              {strataColumns.map((col) => (
                <SelectItem key={col} value={col}>
                  {col}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      )}

      {/* Distribution Preview */}
      {strataDistribution && Object.keys(strataDistribution).length > 0 && (
        <div className="space-y-2">
          <Label className="text-sm font-medium">Distribution Preview</Label>
          <div className="bg-muted/50 rounded-md p-3 space-y-2">
            {Object.entries(strataDistribution).map(([group, count]) => {
              const percentage = Math.round((count / absoluteCount) * 100);
              return (
                <div key={group} className="flex items-center justify-between text-sm">
                  <span className="truncate max-w-[150px]" title={group}>
                    {group}
                  </span>
                  <div className="flex items-center gap-2">
                    <div className="w-20 h-2 bg-muted rounded-full overflow-hidden">
                      <div
                        className="h-full bg-primary rounded-full transition-all"
                        style={{ width: `${percentage}%` }}
                      />
                    </div>
                    <span className="text-muted-foreground w-16 text-right">
                      {count} ({percentage}%)
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Info tooltip */}
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            <div className="flex items-center gap-1 text-xs text-muted-foreground cursor-help">
              <Info className="h-3 w-3" />
              <span>Why configure data scope?</span>
            </div>
          </TooltipTrigger>
          <TooltipContent className="max-w-xs">
            <p>
              Running on a subset of your data first helps you:
            </p>
            <ul className="list-disc list-inside mt-1 space-y-1">
              <li>Validate parameters quickly</li>
              <li>Estimate full run time and cost</li>
              <li>Catch errors early</li>
              <li>Iterate faster during development</li>
            </ul>
          </TooltipContent>
        </Tooltip>
      </TooltipProvider>
    </div>
  );
}

export default DataScopeConfig;
