/** A registered Galaxy entry point alone does not prove a live notebook. */
export interface InteractiveReadinessDependencies {
  getJob: (id: string) => Promise<{ state?: string }>;
  tokenForJob: (id: string) => { token: string; entry_url: string } | null;
  targetForToken: (token: string) => { host: string; port: number } | null;
  probe?: (url: string, timeoutMs: number) => Promise<number>;
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
}
export type InteractiveReadiness = { ready: true; url: string } | { ready: false; reason: 'failed' | 'unavailable' | 'timeout' };
const terminal = new Set(['error', 'deleted', 'ok', 'failed', 'stopped', 'discarded']);
async function bounded<T>(work: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try { return await Promise.race([work, new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error('Lookup timeout')), ms); })]); }
  finally { if (timer) clearTimeout(timer); }
}
export async function waitForInteractiveSession(jobId: string | undefined, dependencies: InteractiveReadinessDependencies, options: { timeoutMs?: number; maxAttempts?: number } = {}): Promise<InteractiveReadiness> {
  if (!jobId) return { ready: false, reason: 'unavailable' };
  const now = dependencies.now ?? Date.now;
  const deadline = now() + (options.timeoutMs ?? 30000);
  const sleep = dependencies.sleep ?? (ms => new Promise(resolve => setTimeout(resolve, ms)));
  const probe = dependencies.probe ?? (async (url, timeoutMs) => {
    const response = await fetch(url, { method: 'GET', redirect: 'manual', signal: AbortSignal.timeout(timeoutMs) });
    await response.body?.cancel();
    return response.status;
  });
  for (let attempt = 0; attempt < (options.maxAttempts ?? 30) && now() < deadline; attempt++) {
    try {
      const job = await bounded(dependencies.getJob(jobId), Math.max(1, Math.min(3000, deadline - now())));
      if (terminal.has(String(job.state))) return { ready: false, reason: 'failed' };
      if (job.state === 'running') {
        const entry = dependencies.tokenForJob(jobId);
        if (entry && /^[a-zA-Z0-9]{6,32}$/.test(entry.token)) {
          const target = dependencies.targetForToken(entry.token);
          const path = entry.entry_url.replace(/^\/+/, '');
          if (target && /^[a-zA-Z0-9.:-]+$/.test(target.host) && Number.isInteger(target.port) && target.port > 0 && target.port <= 65535 && !/[\\\r\n?#]/.test(path) && !path.split('/').includes('..') && now() < deadline) {
            const status = await probe(`http://${target.host}:${target.port}/${path}`, Math.max(1, Math.min(2000, deadline - now()))).catch(() => 0);
            if (status >= 200 && status < 400 && now() < deadline) {
              const confirmed = await bounded(dependencies.getJob(jobId), Math.max(1, Math.min(3000, deadline - now())));
              if (terminal.has(String(confirmed.state))) return { ready: false, reason: 'failed' };
              if (confirmed.state === 'running') return { ready: true, url: `/interactive/${entry.token}/${path}` };
            }
          }
        }
      }
    } catch { return { ready: false, reason: 'unavailable' }; }
    const remaining = deadline - now();
    if (remaining > 0) await sleep(Math.min(1000, remaining));
  }
  return { ready: false, reason: 'timeout' };
}
