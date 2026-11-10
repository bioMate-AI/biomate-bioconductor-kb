import type { Express } from 'express';
import { z } from 'zod';
import { pool } from './db';
import { authenticateToken } from './auth-middleware';
// Single source of truth for rendering the saved output formats as prompt text.
// output-requirements.ts is a pure, dependency-free module (no React / browser
// globals), so the server can import it directly and never diverge from the
// editor panel / chat composer rendering.
import { outputRequirementsToPrompt } from '../client/src/lib/output-requirements';
import { appendOutputRequirementsBlock, type OutputRequirementsScope } from './chat-context';

const settingsSchema = z.object({
  skillPackIds: z.array(z.string().min(1).max(200)).max(100),
  outputRequirements: z.string().max(3000),
}).strict();
let ready: Promise<unknown> | undefined;
function ensureTable() {
  return ready ??= pool.query(`CREATE TABLE IF NOT EXISTS project_instruction_settings (
    project_id UUID PRIMARY KEY REFERENCES projects(id) ON DELETE CASCADE,
    settings JSONB NOT NULL DEFAULT '{}', updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`).catch(error => { ready = undefined; throw error; });
}

/** Raw `outputRequirements` store string for a project (the JSON-array or legacy
 *  free text), or '' when none is set. Server-side read — no auth/role check, so
 *  callers that are already inside an authorized run/chat path (the LLM relay)
 *  can honor the formats WITHOUT the browser threading them. Safe-by-default:
 *  any error (missing table, bad row) returns '' so behavior is unchanged when
 *  nothing is configured. */
export async function loadProjectOutputRequirements(projectId: string | null | undefined): Promise<string> {
  if (!projectId) return '';
  try {
    await ensureTable();
    const result = await pool.query('SELECT settings FROM project_instruction_settings WHERE project_id = $1', [projectId]);
    const raw = result.rows[0]?.settings?.outputRequirements;
    return typeof raw === 'string' ? raw : '';
  } catch (error) {
    console.warn('[project instruction settings] outputRequirements load failed:', (error as any)?.message ?? error);
    return '';
  }
}

/** Same store, rendered to the model-facing prompt block (only enabled formats;
 *  '' when none enabled). This is what both the chat context and the deliverable
 *  generators inject, so every surface honors the exact same text. */
export async function loadProjectOutputRequirementsPrompt(projectId: string | null | undefined): Promise<string> {
  return outputRequirementsToPrompt(await loadProjectOutputRequirements(projectId));
}

/**
 * THE output-requirements chokepoint for LLM deliverable generators.
 *
 * Every LLM deliverable (methods-report, findings summary, IND docx narrative, a
 * figure-producing step) routes its prompt through here instead of hand-rolling
 * its own `loadProjectOutputRequirementsPrompt(...)` + inline concat. It loads the
 * project's rendered requirements and appends the scope-appropriate directive via
 * the pure `appendOutputRequirementsBlock` composer.
 *
 * Safe-by-default: a missing projectId, an unconfigured project, or a load error
 * returns the prompt UNCHANGED (the loader already swallows errors to '').
 *
 * NOTE: the chat stream path keeps using `appendProjectOutputRequirements`
 * (chat-context.ts) because it must DEDUPE against a browser-threaded
 * composerInstructions copy — a concern the deliverable generators don't have.
 */
export async function applyOutputRequirements(
  prompt: string,
  projectId: string | null | undefined,
  scope: OutputRequirementsScope,
): Promise<string> {
  const requirementsPrompt = await loadProjectOutputRequirementsPrompt(projectId);
  return appendOutputRequirementsBlock(prompt, requirementsPrompt, scope);
}

/** Separate persisted settings, with the same project access checks as content edits. */
export function registerProjectInstructionSettings(app: Express, getRole: (id: string, user: string) => Promise<string | null>) {
  app.get('/api/projects/:id/instruction-settings', authenticateToken, async (req, res) => {
    try {
      const role = await getRole(req.params.id, String((req as any).user.id));
      if (!role) return res.status(404).json({ error: 'Project not found' });
      await ensureTable();
      const result = await pool.query('SELECT settings FROM project_instruction_settings WHERE project_id = $1', [req.params.id]);
      res.json({ settings: { skillPackIds: [], outputRequirements: '', ...result.rows[0]?.settings } });
    } catch (error) { console.error('[project instruction settings]', error); res.status(500).json({ error: 'Could not load project settings' }); }
  });
  app.patch('/api/projects/:id/instruction-settings', authenticateToken, async (req, res) => {
    try {
      const role = await getRole(req.params.id, String((req as any).user.id));
      if (!role) return res.status(404).json({ error: 'Project not found' });
      if (role !== 'owner' && role !== 'editor') return res.status(403).json({ error: 'Project is read-only' });
      const parsed = settingsSchema.safeParse(req.body);
      if (!parsed.success) return res.status(400).json({ error: 'Invalid instruction settings' });
      await ensureTable();
      await pool.query(`INSERT INTO project_instruction_settings (project_id, settings) VALUES ($1, $2::jsonb)
        ON CONFLICT (project_id) DO UPDATE SET settings = EXCLUDED.settings, updated_at = now()`, [req.params.id, JSON.stringify(parsed.data)]);
      res.json({ settings: parsed.data });
    } catch (error) { console.error('[project instruction settings]', error); res.status(500).json({ error: 'Could not save project settings' }); }
  });
}
