// Create an isolated synthetic trial user without emails, billing, or acceptance of legal terms.
const fs = require('node:fs');
const crypto = require('node:crypto');
const { createRequire } = require('node:module');
const appRequire = createRequire('/opt/biomate-trial/app/frontend/package.json');
const bcrypt = appRequire('bcrypt');
const { Client } = appRequire('pg');
const root = '/opt/biomate-trial';

(async () => {
  const credentialPath = root + '/ui-trial-credentials.json';
  if (fs.existsSync(credentialPath)) throw new Error('Synthetic user already seeded; preserve existing credentials');
  const suffix = crypto.randomBytes(5).toString('hex');
  const email = `trial-ui-${suffix}@example.org`;
  const password = crypto.randomBytes(24).toString('base64url');
  const bootstrap = fs.readFileSync(root + '/galaxy-state/bootstrap-admin.key', 'utf8').trim();
  async function galaxy(path, body) {
    const response = await fetch('http://127.0.0.1:8082/api' + path, {
      method: 'POST', headers: { 'x-api-key': bootstrap, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error(`Galaxy provisioning HTTP ${response.status}`);
    return response.json();
  }
  const galaxyUser = await galaxy('/users', { email, username: 'trial-ui-' + suffix, password });
  const galaxyKey = await galaxy('/users/' + galaxyUser.id + '/api_key', {});
  const secrets = JSON.parse(fs.readFileSync(root + '/app-secrets.json', 'utf8'));
  const key = crypto.createHash('sha256').update(secrets.FIELD_ENCRYPTION_SECRET).digest();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(galaxyKey, 'utf8'), cipher.final()]);
  const storedKey = [iv, cipher.getAuthTag(), encrypted].map(x => x.toString('base64')).join(':');
  const db = new Client({ host: '/var/run/postgresql', database: 'biomate_trial', user: 'ubuntu' });
  await db.connect();
  try {
    const result = await db.query(`INSERT INTO users (email,password,full_name,email_verified,marketing_emails_opt_in,galaxy_user_id,galaxy_api_key,galaxy_username)
      VALUES ($1,$2,$3,true,false,$4,$5,$6) RETURNING id`, [email, await bcrypt.hash(password, 12), 'Synthetic BioMate Trial', String(galaxyUser.id), storedKey, 'trial-ui-' + suffix]);
    fs.writeFileSync(credentialPath, JSON.stringify({ email, password, user_id: result.rows[0].id, galaxy_user_id: galaxyUser.id }), { mode: 0o600, flag: 'wx' });
    console.log(JSON.stringify({ seeded: true, user_id: result.rows[0].id, credentials_file: credentialPath }));
  } finally { await db.end(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
