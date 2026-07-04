import React, { useState, useRef } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Loader2, Upload, CheckCircle2, Info } from "lucide-react";

interface WorkflowUploadModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function WorkflowUploadModal({ open, onOpenChange }: WorkflowUploadModalProps) {
  const [file, setFile] = useState<File | null>(null);
  const [workflowName, setWorkflowName] = useState('');
  const [description, setDescription] = useState('');
  const [isUploading, setIsUploading] = useState(false);
  const [result, setResult] = useState<{ workflow_name: string; message: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selected = e.target.files?.[0] || null;
    setFile(selected);
    setResult(null);
    setError(null);
    // Pre-fill name from filename if not set
    if (selected && !workflowName) {
      setWorkflowName(selected.name.replace(/\.[^.]+$/, ''));
    }
  };

  const handleSubmit = async () => {
    if (!file) {
      setError('Please select a file.');
      return;
    }
    setIsUploading(true);
    setError(null);
    setResult(null);

    try {
      const form = new FormData();
      form.append('file', file);
      form.append('workflowName', workflowName || file.name.replace(/\.[^.]+$/, ''));
      form.append('description', description);

      const response = await fetch('/api/workflows/upload-file', {
        method: 'POST',
        body: form,
      });

      const data = await response.json();
      if (!response.ok) {
        throw new Error(data.error || 'Upload failed');
      }
      setResult({ workflow_name: data.workflow_name, message: data.message });
    } catch (err: any) {
      setError(err.message || 'Upload failed');
    } finally {
      setIsUploading(false);
    }
  };

  const handleClose = () => {
    setFile(null);
    setWorkflowName('');
    setDescription('');
    setResult(null);
    setError(null);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-w-md" data-testid="workflow-upload-modal">
        <DialogHeader>
          <DialogTitle>Import Workflow</DialogTitle>
        </DialogHeader>

        {/* Click-tip: explain what this dialog does */}
        {!result && (
          <div
            style={{
              display: 'flex',
              gap: 8,
              padding: '10px 12px',
              background: 'oklch(0.97 0.01 240)',
              borderRadius: 6,
              border: '1px solid oklch(0.88 0.03 240)',
              marginBottom: 4,
            }}
            data-testid="import-workflow-tip"
          >
            <Info style={{ width: 14, height: 14, flexShrink: 0, marginTop: 1, color: 'oklch(0.50 0.12 240)' }} />
            <p style={{ fontSize: 12, lineHeight: 1.5, color: 'oklch(0.42 0.04 240)', margin: 0 }}>
              Upload your own <strong>Nextflow (.nf)</strong> or <strong>Galaxy (.ga / .yml)</strong> workflow.
              Once imported it appears under <em>Workflow History → My Imports</em> and can be launched from any chat.
              BioMate will run it on AWS Batch with your configured environment.
            </p>
          </div>
        )}

        {result ? (
          <div className="space-y-3 py-2">
            <div className="flex items-center gap-2 text-green-700 dark:text-green-400">
              <CheckCircle2 className="h-5 w-5 shrink-0" />
              <p className="text-sm font-medium">{result.workflow_name}</p>
            </div>
            <p className="text-xs text-muted-foreground">{result.message}</p>
          </div>
        ) : (
          <div className="space-y-4 py-2">
            {/* File picker */}
            <div className="space-y-1.5">
              <Label htmlFor="wf-file-input" className="text-sm">
                Workflow file <span className="text-muted-foreground text-xs">(.nf, .ga, .yml)</span>
              </Label>
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  className="shrink-0"
                  onClick={() => fileInputRef.current?.click()}
                >
                  <Upload className="mr-1.5 h-3.5 w-3.5" />
                  Choose file
                </Button>
                <span className="text-xs text-muted-foreground truncate">
                  {file ? file.name : 'No file chosen'}
                </span>
              </div>
              <input
                id="wf-file-input"
                ref={fileInputRef}
                type="file"
                accept=".nf,.ga,.yml,.yaml"
                className="hidden"
                onChange={handleFileChange}
                data-testid="workflow-file-input"
              />
            </div>

            {/* Workflow name */}
            <div className="space-y-1.5">
              <Label htmlFor="wf-name-input" className="text-sm">Workflow name</Label>
              <Input
                id="wf-name-input"
                value={workflowName}
                onChange={e => setWorkflowName(e.target.value)}
                placeholder="My custom workflow"
                className="text-sm"
                data-testid="workflow-name-input"
              />
            </div>

            {/* Description */}
            <div className="space-y-1.5">
              <Label htmlFor="wf-desc-input" className="text-sm">
                Description <span className="text-muted-foreground text-xs">(optional)</span>
              </Label>
              <textarea
                id="wf-desc-input"
                value={description}
                onChange={e => setDescription(e.target.value)}
                placeholder="What does this workflow do?"
                rows={3}
                className="flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 resize-none"
                data-testid="workflow-description-input"
              />
            </div>

            {error && (
              <p className="text-xs text-destructive">{error}</p>
            )}
          </div>
        )}

        <DialogFooter>
          {result ? (
            <Button variant="outline" onClick={handleClose}>Done</Button>
          ) : (
            <>
              <Button variant="outline" onClick={handleClose} disabled={isUploading}>
                Cancel
              </Button>
              <Button onClick={handleSubmit} disabled={isUploading || !file} data-testid="workflow-upload-submit">
                {isUploading ? (
                  <><Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />Uploading…</>
                ) : (
                  'Import Workflow'
                )}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
