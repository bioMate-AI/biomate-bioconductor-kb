/**
 * Job Log Viewer Component
 *
 * Displays real-time job logs from Galaxy workflow execution.
 * Shows stdout/stderr streams with syntax highlighting and filtering.
 */

import { useState, useEffect, useRef } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  Terminal,
  Search,
  Download,
  Trash2,
  ChevronDown,
  AlertCircle,
  Info,
  AlertTriangle,
  CheckCircle,
} from "lucide-react"
import { cn } from "@/lib/utils"

interface LogEntry {
  timestamp: string;
  level: 'info' | 'warning' | 'error' | 'success' | 'debug';
  message: string;
  source?: 'stdout' | 'stderr';
}

interface JobLogViewerProps {
  stepId: string;
  stepName: string;
  logs: string[];
  isRunning?: boolean;
  onClear?: () => void;
  onDownload?: () => void;
}

export function JobLogViewer({
  stepId,
  stepName,
  logs,
  isRunning = false,
  onClear,
  onDownload,
}: JobLogViewerProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [autoScroll, setAutoScroll] = useState(true);
  const [currentTab, setCurrentTab] = useState<'all' | 'stdout' | 'stderr'>('all');
  const scrollAreaRef = useRef<HTMLDivElement>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  // Parse raw log strings into structured entries
  const parseLogEntry = (rawLog: string, index: number): LogEntry => {
    // Try to detect log level from message content
    const lowerLog = rawLog.toLowerCase();
    let level: LogEntry['level'] = 'info';

    if (lowerLog.includes('error') || lowerLog.includes('fail')) {
      level = 'error';
    } else if (lowerLog.includes('warn')) {
      level = 'warning';
    } else if (lowerLog.includes('success') || lowerLog.includes('complete')) {
      level = 'success';
    } else if (lowerLog.includes('debug')) {
      level = 'debug';
    }

    // Try to detect stderr vs stdout
    const source: LogEntry['source'] = lowerLog.includes('stderr') ? 'stderr' : 'stdout';

    return {
      timestamp: new Date().toISOString(),
      level,
      message: rawLog,
      source,
    };
  };

  const logEntries: LogEntry[] = logs.map((log, index) => parseLogEntry(log, index));

  // Filter logs based on search query and current tab
  const filteredLogs = logEntries.filter((entry) => {
    const matchesSearch = searchQuery === '' ||
      entry.message.toLowerCase().includes(searchQuery.toLowerCase());

    const matchesTab = currentTab === 'all' || entry.source === currentTab;

    return matchesSearch && matchesTab;
  });

  // Auto-scroll to bottom when new logs arrive
  useEffect(() => {
    if (autoScroll && bottomRef.current) {
      bottomRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [logs, autoScroll]);

  const getLogLevelIcon = (level: LogEntry['level']) => {
    switch (level) {
      case 'error':
        return AlertCircle;
      case 'warning':
        return AlertTriangle;
      case 'success':
        return CheckCircle;
      case 'info':
      default:
        return Info;
    }
  };

  const getLogLevelColor = (level: LogEntry['level']) => {
    switch (level) {
      case 'error':
        return 'text-red-500';
      case 'warning':
        return 'text-yellow-500';
      case 'success':
        return 'text-green-500';
      case 'debug':
        return 'text-muted-foreground';
      case 'info':
      default:
        return 'text-blue-500';
    }
  };

  const getLogBackgroundColor = (level: LogEntry['level']) => {
    switch (level) {
      case 'error':
        return 'bg-red-50 dark:bg-red-950/20 border-l-2 border-red-500';
      case 'warning':
        return 'bg-yellow-50 dark:bg-yellow-950/20 border-l-2 border-yellow-500';
      case 'success':
        return 'bg-green-50 dark:bg-green-950/20 border-l-2 border-green-500';
      default:
        return 'bg-background';
    }
  };

  const formatTimestamp = (timestamp: string): string => {
    const date = new Date(timestamp);
    return date.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      fractionalSecondDigits: 3,
    });
  };

  const handleDownload = () => {
    if (onDownload) {
      onDownload();
    } else {
      // Default download behavior
      const logContent = logs.join('\n');
      const blob = new Blob([logContent], { type: 'text/plain' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${stepId}_${stepName.replace(/\s+/g, '_')}_logs.txt`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    }
  };

  const stdoutCount = logEntries.filter(e => e.source === 'stdout').length;
  const stderrCount = logEntries.filter(e => e.source === 'stderr').length;

  if (logs.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Terminal className="h-5 w-5" />
            Job Logs: {stepName}
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-center text-muted-foreground py-8">
            {isRunning ? (
              <div className="flex flex-col items-center gap-2">
                <Terminal className="h-8 w-8 animate-pulse text-blue-500" />
                <p>Waiting for job logs...</p>
              </div>
            ) : (
              <p>No logs available yet. Start the workflow to see execution logs.</p>
            )}
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card data-testid={`job-logs-${stepId}`}>
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="flex items-center gap-2">
            <Terminal className={cn(
              "h-5 w-5",
              isRunning && "animate-pulse text-blue-500"
            )} />
            Job Logs: {stepName}
          </CardTitle>
          <div className="flex items-center gap-2">
            <Badge variant="outline" className="text-xs">
              {filteredLogs.length} {filteredLogs.length === 1 ? 'entry' : 'entries'}
            </Badge>
            {isRunning && (
              <Badge variant="default" className="text-xs bg-blue-500">
                Live
              </Badge>
            )}
          </div>
        </div>

        {/* Search and controls */}
        <div className="flex items-center gap-2 pt-2">
          <div className="relative flex-1">
            <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search logs..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-8"
            />
          </div>
          <Button
            size="sm"
            variant="outline"
            onClick={() => setAutoScroll(!autoScroll)}
            className={cn(autoScroll && "bg-blue-50 dark:bg-blue-950/30")}
          >
            <ChevronDown className={cn(
              "h-4 w-4",
              autoScroll && "text-blue-500"
            )} />
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={handleDownload}
          >
            <Download className="h-4 w-4" />
          </Button>
          {onClear && (
            <Button
              size="sm"
              variant="outline"
              onClick={onClear}
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          )}
        </div>
      </CardHeader>

      <CardContent>
        <Tabs value={currentTab} onValueChange={(v) => setCurrentTab(v as any)}>
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="all">
              All ({logEntries.length})
            </TabsTrigger>
            <TabsTrigger value="stdout">
              stdout ({stdoutCount})
            </TabsTrigger>
            <TabsTrigger value="stderr">
              stderr ({stderrCount})
            </TabsTrigger>
          </TabsList>

          <TabsContent value={currentTab} className="mt-4">
            <ScrollArea className="h-[400px] w-full rounded-md border bg-muted/20">
              <div className="p-4 font-mono text-xs space-y-1">
                {filteredLogs.length === 0 ? (
                  <div className="text-center text-muted-foreground py-8">
                    No logs match your search criteria
                  </div>
                ) : (
                  filteredLogs.map((entry, index) => {
                    const LevelIcon = getLogLevelIcon(entry.level);

                    return (
                      <div
                        key={index}
                        className={cn(
                          "flex items-start gap-2 p-2 rounded",
                          getLogBackgroundColor(entry.level)
                        )}
                      >
                        <LevelIcon
                          className={cn(
                            "h-3 w-3 mt-0.5 flex-shrink-0",
                            getLogLevelColor(entry.level)
                          )}
                        />
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            <span className="text-muted-foreground text-[10px]">
                              {formatTimestamp(entry.timestamp)}
                            </span>
                            {entry.source && (
                              <Badge
                                variant="outline"
                                className={cn(
                                  "text-[9px] h-4 px-1",
                                  entry.source === 'stderr' && "border-red-500 text-red-500"
                                )}
                              >
                                {entry.source}
                              </Badge>
                            )}
                          </div>
                          <pre className="whitespace-pre-wrap break-words text-foreground">
                            {entry.message}
                          </pre>
                        </div>
                      </div>
                    );
                  })
                )}
                <div ref={bottomRef} />
              </div>
            </ScrollArea>
          </TabsContent>
        </Tabs>

        {/* Auto-scroll indicator */}
        {!autoScroll && isRunning && (
          <div className="mt-2 text-xs text-muted-foreground text-center">
            Auto-scroll disabled. Click <ChevronDown className="h-3 w-3 inline" /> to re-enable.
          </div>
        )}
      </CardContent>
    </Card>
  );
}
