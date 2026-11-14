import React, { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ExternalLink, Loader2 } from 'lucide-react';

export interface LicenseRequirement {
  tool_id: string;
  display_name: string;
  vendor: string;
  type: 'docker_auth' | 'license_key' | 'license_server' | 'license_agreement' | 'license_image' | 'license_file' | 'api_key' | 'none';
  registration_url: string;
  approval_time: string;
  cost: string;
  source: 'user' | 'biomate' | 'none';
  has_fallback?: boolean;
  open_alternatives: { id: string; label: string; note: string }[];
}

interface CredentialModalProps {
  tool: LicenseRequirement;
  onSaved: () => void;
  onClose: () => void;
}

export function CredentialModal({ tool, onSaved, onClose }: CredentialModalProps) {
  const [username, setUsername] = useState('');
  const [token, setToken] = useState('');
  const [licenseKey, setLicenseKey] = useState('');
  const [licenseServer, setLicenseServer] = useState('');
  const [containerImage, setContainerImage] = useState('');
  const [netmhcpanPath, setNetmhcpanPath] = useState('');
  const [netmhciipanPath, setNetmhciipanPath] = useState('');
  const [agreed, setAgreed] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setSaving(true);

    let data: Record<string, string> = {};
    if (tool.type === 'docker_auth') {
      data = { username: username.trim(), token: token.trim() };
    } else if (tool.type === 'license_key') {
      data = { license_key: licenseKey.trim() };
    } else if (tool.type === 'license_server') {
      data = { license_server: licenseServer.trim() };
    } else if (tool.type === 'license_image') {
      data = { container_image: containerImage.trim() };
    } else if (tool.type === 'license_file') {
      // At least one of the two licensed-tarball URIs; class II needs netMHCIIpan.
      data = {};
      if (netmhcpanPath.trim()) data.netmhcpan_path = netmhcpanPath.trim();
      if (netmhciipanPath.trim()) data.netmhciipan_path = netmhciipanPath.trim();
    } else if (tool.type === 'license_agreement') {
      data = { agreed: 'true' };
    }

    // Validate: license_file needs ≥1 URI; other credential types need every field.
    if (tool.type === 'license_file') {
      if (Object.keys(data).length === 0) {
        setError('Enter at least one licensed tarball URI (class I and/or class II).');
        setSaving(false);
        return;
      }
    } else if (tool.type !== 'license_agreement') {
      const empty = Object.values(data).some(v => !v);
      if (empty) {
        setError('All fields are required.');
        setSaving(false);
        return;
      }
    } else if (!agreed) {
      setError('You must agree to the license terms to continue.');
      setSaving(false);
      return;
    }

    try {
      const res = await fetch('/api/users/credentials', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tool: tool.tool_id, data }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body?.detail || `HTTP ${res.status}`);
      }
      onSaved();
    } catch (err: any) {
      setError(err.message || 'Failed to save credentials. Please try again.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={open => { if (!open) onClose(); }}>
      <DialogContent className="max-w-md" data-testid="credential-modal">
        <DialogHeader>
          <DialogTitle>{tool.display_name} Credentials</DialogTitle>
          <DialogDescription>
            {tool.display_name} requires registration to access.{' '}
            {tool.approval_time && <span>Approval time: {tool.approval_time}. </span>}
            {tool.cost && <span>Cost: {tool.cost}.</span>}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4 pt-2">
          {tool.type === 'docker_auth' && (
            <>
              <div className="space-y-1.5">
                <Label htmlFor="cred-username">Docker Hub username</Label>
                <Input
                  id="cred-username"
                  value={username}
                  onChange={e => setUsername(e.target.value)}
                  placeholder="your-dockerhub-username"
                  autoComplete="off"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cred-token">Access token</Label>
                <Input
                  id="cred-token"
                  type="password"
                  value={token}
                  onChange={e => setToken(e.target.value)}
                  placeholder="dckr_pat_..."
                  autoComplete="new-password"
                />
              </div>
            </>
          )}

          {tool.type === 'license_key' && (
            <div className="space-y-1.5">
              <Label htmlFor="cred-license-key">License key</Label>
              <Input
                id="cred-license-key"
                data-testid="credential-license-key"
                type="password"
                value={licenseKey}
                onChange={e => setLicenseKey(e.target.value)}
                placeholder="Paste your license key"
                autoComplete="new-password"
              />
            </div>
          )}

          {tool.type === 'license_server' && (
            <div className="space-y-1.5">
              <Label htmlFor="cred-license-server">License server</Label>
              <Input
                id="cred-license-server"
                value={licenseServer}
                onChange={e => setLicenseServer(e.target.value)}
                placeholder="27008@your-flexlm-host.example.com"
                autoComplete="off"
              />
              <p className="text-xs text-muted-foreground">
                Format: <code>port@hostname</code> — the FlexLM/FlexNet server address provided by your IT department.
              </p>
            </div>
          )}

          {tool.type === 'license_image' && (
            <div className="space-y-1.5">
              <Label htmlFor="cred-container-image">Licensed container image</Label>
              <Input
                id="cred-container-image"
                value={containerImage}
                onChange={e => setContainerImage(e.target.value)}
                placeholder="123456789012.dkr.ecr.us-west-2.amazonaws.com/your-amber/pmemd:latest"
                autoComplete="off"
              />
              <p className="text-xs text-muted-foreground">
                A container image you own that includes the licensed {tool.display_name} binary (e.g. pmemd.cuda).
                The run uses it for the dynamics steps. Leave this unset to run on the free OpenMM engine instead.
              </p>
            </div>
          )}

          {tool.type === 'license_file' && (
            <div className="space-y-3">
              <div className="space-y-1.5">
                <Label htmlFor="cred-netmhcpan">netMHCpan tarball URI — HLA class I (optional)</Label>
                <Input
                  id="cred-netmhcpan"
                  value={netmhcpanPath}
                  onChange={e => setNetmhcpanPath(e.target.value)}
                  placeholder="s3://your-bucket/netMHCpan-4.1b.Linux.tar.gz"
                  autoComplete="off"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cred-netmhciipan">netMHCIIpan tarball URI — HLA class II (DR/DP/DQ)</Label>
                <Input
                  id="cred-netmhciipan"
                  value={netmhciipanPath}
                  onChange={e => setNetmhciipanPath(e.target.value)}
                  placeholder="s3://your-bucket/netMHCIIpan-4.3e.Linux.tar.gz"
                  autoComplete="off"
                />
              </div>
              <p className="text-xs text-muted-foreground">
                {tool.display_name} is DTU-licensed and cannot be redistributed, so bring your own: register
                (free for academic/non-profit), download the tarball, upload it to your storage, and paste the
                s3:// URI here. Enter either or both — <strong>HLA class II requires netMHCIIpan</strong>. For
                class I you can instead use the license-free MHCflurry workflow with no credential.
              </p>
            </div>
          )}

          {tool.type === 'license_agreement' && (
            <div className="flex items-start gap-2 rounded-md border border-border bg-muted/40 p-3">
              <input
                id="cred-agree"
                type="checkbox"
                className="mt-0.5 h-4 w-4 cursor-pointer"
                checked={agreed}
                onChange={e => setAgreed(e.target.checked)}
              />
              <Label htmlFor="cred-agree" className="cursor-pointer text-sm leading-snug">
                I confirm that I am using {tool.display_name} under an academic/non-profit license
                and agree to the{' '}
                {tool.registration_url ? (
                  <a href={tool.registration_url} target="_blank" rel="noopener noreferrer"
                     className="text-blue-600 dark:text-blue-400 hover:underline">
                    license terms
                  </a>
                ) : 'license terms'}.
              </Label>
            </div>
          )}

          {error && (
            <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
          )}

          {tool.registration_url && (
            <a
              href={tool.registration_url}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1.5 text-xs text-blue-600 dark:text-blue-400 hover:underline"
            >
              <ExternalLink className="h-3 w-3" />
              Get your credentials at {tool.vendor || tool.display_name}
            </a>
          )}

          <DialogFooter className="pt-2">
            <Button type="button" variant="outline" size="sm" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" size="sm" disabled={saving} data-testid="credential-save">
              {saving && <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
              {tool.type === 'license_agreement' ? 'Confirm' : 'Save credentials'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
