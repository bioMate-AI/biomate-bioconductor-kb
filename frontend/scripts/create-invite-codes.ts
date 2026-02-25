/**
 * create-invite-codes.ts — Generate invite codes directly against the database
 *
 * Usage:
 *   DATABASE_URL=postgres://... npx tsx scripts/create-invite-codes.ts \
 *     --prefix NEURO \
 *     --count 50 \
 *     --trial-days 30 \
 *     --quota 25.00 \
 *     --description "Neuroscience beta cohort 1"
 *
 * Options:
 *   --prefix <str>      Code prefix, e.g. NEURO → "NEURO-A1B2C3-D4E5F6"  (default: BETA)
 *   --count <n>         Number of codes to create                           (default: 1)
 *   --trial-days <n>    Trial duration in days                              (default: 7)
 *   --quota <usd>       Monthly compute quota in USD                        (default: null = platform default)
 *   --max-uses <n>      Max registrations per code                          (default: 1)
 *   --expires <date>    Expiry date, ISO 8601 e.g. 2026-06-01              (default: no expiry)
 *   --description <str> Internal note stored with the codes
 *   --list              List all active codes with use counts
 *   --deactivate <id>   Deactivate a code by its UUID
 */

import 'dotenv/config';
import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import { eq, desc } from 'drizzle-orm';
import { randomBytes } from 'crypto';
import { inviteCodes } from '../shared/schema';

function generateCode(prefix: string): string {
  const part1 = randomBytes(3).toString('hex').toUpperCase();
  const part2 = randomBytes(3).toString('hex').toUpperCase();
  return `${prefix.toUpperCase()}-${part1}-${part2}`;
}

function parseArgs(argv: string[]): Record<string, string> {
  const args: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const key = argv[i].slice(2);
      args[key] = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : 'true';
    }
  }
  return args;
}

async function main() {
  if (!process.env.DATABASE_URL) {
    console.error('ERROR: DATABASE_URL environment variable is required');
    process.exit(1);
  }

  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const db = drizzle(pool);
  const args = parseArgs(process.argv.slice(2));

  // --list
  if (args['list']) {
    const codes = await db
      .select()
      .from(inviteCodes)
      .orderBy(desc(inviteCodes.createdAt));

    if (codes.length === 0) {
      console.log('No invite codes found.');
    } else {
      console.log(`\nInvite codes (${codes.length} total):\n`);
      for (const c of codes) {
        const status = !c.active ? 'INACTIVE' : (c.expiresAt && c.expiresAt < new Date()) ? 'EXPIRED' : 'active';
        const uses = c.maxUses === null ? `${c.usedCount}/∞` : `${c.usedCount}/${c.maxUses}`;
        console.log(`  ${c.code.padEnd(20)}  ${uses.padEnd(6)}  ${status.padEnd(10)}  ${c.description ?? ''}`);
      }
      console.log();
    }
    await pool.end();
    return;
  }

  // --deactivate <id>
  if (args['deactivate']) {
    await db
      .update(inviteCodes)
      .set({ active: false })
      .where(eq(inviteCodes.id, args['deactivate']));
    console.log(`Deactivated invite code: ${args['deactivate']}`);
    await pool.end();
    return;
  }

  // Create codes
  const prefix = args['prefix'] ?? 'BETA';
  const count = parseInt(args['count'] ?? '1', 10);
  const trialDays = args['trial-days'] ? parseInt(args['trial-days'], 10) : null;
  const quotaOverrideUsd = args['quota'] ? args['quota'] : null;
  const maxUses = parseInt(args['max-uses'] ?? '1', 10);
  const expiresAt = args['expires'] ? new Date(args['expires']) : null;
  const description = args['description'] ?? null;

  if (isNaN(count) || count < 1 || count > 10000) {
    console.error('ERROR: --count must be between 1 and 10000');
    process.exit(1);
  }

  const values = Array.from({ length: count }, () => ({
    code: generateCode(prefix),
    description,
    maxUses,
    trialDays,
    quotaOverrideUsd,
    subscriptionTier: 'academic',
    expiresAt,
    active: true,
  }));

  const created = await db.insert(inviteCodes).values(values).returning();

  console.log(`\nCreated ${created.length} invite code(s):\n`);
  for (const c of created) {
    console.log(`  ${c.code}`);
  }
  console.log();

  if (trialDays) console.log(`Trial: ${trialDays} days`);
  if (quotaOverrideUsd) console.log(`Quota: $${quotaOverrideUsd}`);
  if (expiresAt) console.log(`Expires: ${expiresAt.toISOString().slice(0, 10)}`);
  if (maxUses !== 1) console.log(`Max uses per code: ${maxUses}`);
  console.log();

  await pool.end();
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
