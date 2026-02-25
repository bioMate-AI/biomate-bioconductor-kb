import React from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Play, Pause, CheckCircle, XCircle, Clock } from "lucide-react";
import { cn } from "@/lib/utils";

interface PhaseCardProps {
  phase: {
    id: string;
    name: string;
    description?: string;
    status: 'pending' | 'running' | 'completed' | 'failed' | 'paused';
    progress?: number;
  };
  onExecute?: () => void;
  onPause?: () => void;
  onResume?: () => void;
  className?: string;
}

export function PhaseCard({ phase, onExecute, onPause, onResume, className }: PhaseCardProps) {
  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'completed': return <CheckCircle className="h-5 w-5 text-green-500" />;
      case 'failed': return <XCircle className="h-5 w-5 text-red-500" />;
      case 'running': return <Clock className="h-5 w-5 text-blue-500 animate-pulse" />;
      case 'paused': return <Pause className="h-5 w-5 text-yellow-500" />;
      default: return <Clock className="h-5 w-5 text-gray-400" />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed': return 'bg-green-100 text-green-800';
      case 'failed': return 'bg-red-100 text-red-800';
      case 'running': return 'bg-blue-100 text-blue-800';
      case 'paused': return 'bg-yellow-100 text-yellow-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  return (
    <Card className={cn("w-full transition-all duration-200 hover:shadow-md", className)}>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <div className="flex items-center space-x-2">
          {getStatusIcon(phase.status)}
          <CardTitle className="text-lg font-medium">{phase.name}</CardTitle>
        </div>
        <Badge variant="secondary" className={getStatusColor(phase.status)}>
          {phase.status.charAt(0).toUpperCase() + phase.status.slice(1)}
        </Badge>
      </CardHeader>
      <CardContent>
        {phase.description && (
          <p className="text-sm text-muted-foreground mb-4">{phase.description}</p>
        )}
        
        <div className="flex justify-end space-x-2">
          {phase.status === 'pending' && onExecute && (
            <Button size="sm" onClick={onExecute}>
              <Play className="mr-2 h-4 w-4" /> Start
            </Button>
          )}
          {phase.status === 'running' && onPause && (
            <Button size="sm" variant="outline" onClick={onPause}>
              <Pause className="mr-2 h-4 w-4" /> Pause
            </Button>
          )}
          {phase.status === 'paused' && onResume && (
            <Button size="sm" onClick={onResume}>
              <Play className="mr-2 h-4 w-4" /> Resume
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
