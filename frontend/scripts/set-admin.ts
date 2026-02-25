/**
 * set-admin.ts — Promote a registered user to admin tier
 *
 * Usage:
 *   DATABASE_URL=postgres://... npx tsx scripts/set-admin.ts user@example.com
 *   DATABASE_URL=postgres://... npx tsx scripts/set-admin.ts --list
 *
 * What it does:
 *   - Sets subscription_tier = 'admin' on the given user
 *   - Admin users can access /api/admin/* endpoints (invite code management, etc.)
 *
 * To revert:
 *   DATABASE_URL=postgres://... npx tsx scripts/set-admin.ts --revoke user@example.com
 */

import 'dotenv/config';
import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import { eq } from 'drizzle-orm';
import { users } from '../shared/schema';

async function main() {
  if (!process.env.DATABASE_URL) {
    console.error('ERROR: DATABASE_URL environment variable is required');
    process.exit(1);
  }

  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const db = drizzle(pool);

  const args = process.argv.slice(2);

  if (args[0] === '--list') {
    const admins = await db
      .select({ id: users.id, email: users.email, fullName: users.fullName, createdAt: users.createdAt })
      .from(users)
      .where(eq(users.subscriptionTier, 'admin'));

    if (admins.length === 0) {
      console.log('No admin users found.');
    } else {
      console.log(`Admin users (${admins.length}):`);
      for (const u of admins) {
        console.log(`  ${u.email}  (id: ${u.id}, name: ${u.fullName}, created: ${u.createdAt?.toISOString()})`);
      }
    }
    await pool.end();
    return;
  }

  const revoke = args[0] === '--revoke';
  const email = revoke ? args[1] : args[0];

  if (!email) {
    console.error('Usage:');
    console.error('  npx tsx scripts/set-admin.ts <email>           # promote to admin');
    console.error('  npx tsx scripts/set-admin.ts --revoke <email>  # revert to academic');
    console.error('  npx tsx scripts/set-admin.ts --list            # list all admins');
    process.exit(1);
  }

  const [user] = await db.select().from(users).where(eq(users.email, email)).limit(1);
  if (!user) {
    console.error(`ERROR: No user found with email: ${email}`);
    await pool.end();
    process.exit(1);
  }

  const newTier = revoke ? 'academic' : 'admin';
  await db
    .update(users)
    .set({ subscriptionTier: newTier, updatedAt: new Date() })
    .where(eq(users.id, user.id));

  const action = revoke ? 'Revoked admin from' : 'Promoted to admin';
  console.log(`${action}: ${user.email} (id: ${user.id})`);
  console.log(`subscription_tier is now: ${newTier}`);

  await pool.end();
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
