import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import { createDb } from './db.js';
import { buildRouter } from './routes.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function createApp(dbPath?: string) {
  const db = createDb(dbPath);
  const app = express();

  app.use(express.json());
  app.use(express.static(path.join(__dirname, '../public')));
  app.use('/api', buildRouter(db));

  return { app, db };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const PORT = process.env.PORT || 4000;
  const { app } = createApp();
  app.listen(PORT, () => console.log(`MFA prototype running at http://localhost:${PORT}`));
}
