import type { Express } from 'express';
import { z } from 'zod';
import { pool } from './db';
import { authenticateToken } from './auth-middleware';

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
