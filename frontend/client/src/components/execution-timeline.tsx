/**
 * Execution Timeline Component
 *
 * Displays workflow execution history with real-time updates.
 * Shows actual Galaxy job states and elapsed times (NO fake progress).
 */

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"
import {
  CheckCircle,
  Circle,
  Clock,
  AlertCircle,
  Loader2,
  Pause,
  Play,
} from "lucide-react"
import { cn } from "@/lib/utils"

interface TimelineEvent {
  stepId: string;
  stepName: string;
  state: 'new' | 'queued' | 'running' | 'ok' | 'error' | 'paused' | 'waiting';
  timestamp: string;
  elapsedMs?: number;
  jobId?: string;
}

interface ExecutionTimelineProps {
  events: TimelineEvent[];
  currentStepId?: string;
  formatElapsedTime: (ms: number) => string;
  onPauseJob?: (jobId: string) => void;
  onResumeJob?: (jobId: string) => void;
}

export function ExecutionTimeline({
  events,
  currentStepId,
  formatElapsedTime,
  onPauseJob,
  onResumeJob,
}: ExecutionTimelineProps) {
  const getStateIcon = (state: TimelineEvent['state']) => {
    switch (state) {
      case 'new':
      case 'waiting':
        return Circle;
      case 'queued':
        return Clock;
      case 'running':
        return Loader2;
      case 'ok':
        return CheckCircle;
      case 'error':
        return AlertCircle;
      case 'paused':
        return Pause;
      default:
        return Circle;
    }
  };

  const getStateColor = (state: TimelineEvent['state']) => {
    switch (state) {
      case 'new':
      case 'waiting':
        return 'text-muted-foreground';
      case 'queued':
        return 'text-yellow-500';
      case 'running':
        return 'text-blue-500';
      case 'ok':
        return 'text-green-500';
      case 'error':
        return 'text-red-500';
      case 'paused':
        return 'text-orange-500';
      default:
        return 'text-muted-foreground';
    }
  };

  const getStateBadgeVariant = (state: TimelineEvent['state']): 'default' | 'secondary' | 'destructive' | 'outline' => {
    switch (state) {
      case 'running':
        return 'default';
      case 'ok':
        return 'secondary';
      case 'error':
        return 'destructive';
      default:
        return 'outline';
    }
  };

  const getStateLabel = (state: TimelineEvent['state']): string => {
    switch (state) {
      case 'new':
        return 'Created';
      case 'queued':
        return 'Queued';
      case 'running':
        return 'Running';
      case 'ok':
        return 'Completed';
      case 'error':
        return 'Failed';
      case 'paused':
        return 'Paused';
      case 'waiting':
        return 'Waiting';
      default:
        return state;
    }
  };

  const formatTimestamp = (timestamp: string): string => {
    const date = new Date(timestamp);
    return date.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  };

  if (events.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Execution Timeline</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-center text-muted-foreground py-8">
            No execution events yet. Start the workflow to see progress.
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card data-testid="execution-timeline">
      <CardHeader>
        <CardTitle>Execution Timeline</CardTitle>
        <p className="text-sm text-muted-foreground">
          Real-time workflow execution history
        </p>
      </CardHeader>
      <CardContent>
        <ScrollArea className="h-[400px]">
          <div className="space-y-4">
            {events.map((event, index) => {
              const StateIcon = getStateIcon(event.state);
              const isCurrentStep = event.stepId === currentStepId;

              return (
                <div
                  key={`${event.stepId}-${index}`}
                  data-testid={`timeline-event-${event.stepId}`}
                  className={cn(
                    "flex items-start gap-4 pb-4",
                    index < events.length - 1 && "border-b"
                  )}
                >
                  {/* Timeline indicator */}
                  <div className="relative flex flex-col items-center">
                    <div
                      className={cn(
                        "rounded-full p-2 bg-background border-2",
                        isCurrentStep ? "border-primary" : "border-muted",
                        event.state === 'running' && "animate-pulse"
                      )}
                    >
                      <StateIcon
                        className={cn(
                          "h-4 w-4",
                          getStateColor(event.state),
                          event.state === 'running' && "animate-spin"
                        )}
                      />
                    </div>
                    {index < events.length - 1 && (
                      <div className="w-0.5 h-full mt-2 bg-muted" />
                    )}
                  </div>

                  {/* Event details */}
                  <div className="flex-1 space-y-1">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <span className="font-medium">{event.stepName}</span>
                        {isCurrentStep && (
                          <Badge variant="outline" className="text-xs">
                            Current
                          </Badge>
                        )}
                      </div>
                      <Badge
                        variant={getStateBadgeVariant(event.state)}
                        data-testid={`timeline-event-status-${getStateLabel(event.state).toLowerCase()}`}
                      >
                        {getStateLabel(event.state)}
                      </Badge>
                    </div>

                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-4 text-sm text-muted-foreground">
                        <div className="flex items-center gap-1">
                          <Clock className="h-3 w-3" />
                          <span>{formatTimestamp(event.timestamp)}</span>
                        </div>

                        {event.elapsedMs !== undefined && event.elapsedMs > 0 && (
                          <div className="flex items-center gap-1">
                            <span>Elapsed: {formatElapsedTime(event.elapsedMs)}</span>
                          </div>
                        )}

                        {event.jobId && (
                          <div className="text-xs">
                            Job: {event.jobId.substring(0, 8)}...
                          </div>
                        )}
                      </div>

                      {/* Pause/Resume Controls */}
                      {event.jobId && (
                        <div className="flex items-center gap-2">
                          {/* Show Pause button for running/queued jobs */}
                          {(event.state === 'running' || event.state === 'queued') && onPauseJob && (
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => onPauseJob(event.jobId!)}
                              className="h-7 text-xs"
                            >
                              <Pause className="h-3 w-3 mr-1" />
                              Pause
                            </Button>
                          )}

                          {/* Show Resume button for paused jobs */}
                          {event.state === 'paused' && onResumeJob && (
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => onResumeJob(event.jobId!)}
                              className="h-7 text-xs"
                            >
                              <Play className="h-3 w-3 mr-1" />
                              Resume
                            </Button>
                          )}
                        </div>
                      )}
                    </div>

                    {/* State-specific messages */}
                    {event.state === 'queued' && (
                      <p className="text-xs text-muted-foreground italic">
                        Waiting in queue for available resources
                      </p>
                    )}
                    {event.state === 'running' && (
                      <p className="text-xs text-blue-600 dark:text-blue-400 italic">
                        Executing...
                      </p>
                    )}
                    {event.state === 'ok' && (
                      <p className="text-xs text-green-600 dark:text-green-400 italic">
                        Step completed successfully
                      </p>
                    )}
                    {event.state === 'error' && (
                      <p className="text-xs text-red-600 dark:text-red-400 italic">
                        Execution failed - check logs for details
                      </p>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </ScrollArea>
      </CardContent>
    </Card>
  );
}
