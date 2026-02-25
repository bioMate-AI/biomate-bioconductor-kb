-- Migration: 0001_invite_codes
-- Adds invite code tables for closed-beta access control
-- and the invite_code_id column on users.

CREATE TABLE "invite_codes" (
	"id" varchar PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"code" varchar(32) NOT NULL,
	"description" text,
	"created_by" varchar,
	"max_uses" integer DEFAULT 1,
	"used_count" integer DEFAULT 0 NOT NULL,
	"trial_days" integer,
	"quota_override_usd" numeric(10, 2),
	"subscription_tier" text DEFAULT 'academic',
	"expires_at" timestamp,
	"active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "invite_codes_code_unique" UNIQUE("code")
);

CREATE TABLE "invite_code_uses" (
	"id" varchar PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"invite_code_id" varchar NOT NULL,
	"user_id" varchar NOT NULL,
	"used_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "invite_code_uses_invite_code_id_fkey"
		FOREIGN KEY ("invite_code_id") REFERENCES "invite_codes"("id"),
	CONSTRAINT "invite_code_uses_user_id_fkey"
		FOREIGN KEY ("user_id") REFERENCES "users"("id")
);

-- Add invite_code_id to users (nullable, FK added separately due to schema ordering)
ALTER TABLE "users"
	ADD COLUMN IF NOT EXISTS "invite_code_id" varchar;

-- FK from users to invite_codes (deferred; safe to add after both tables exist)
ALTER TABLE "users"
	ADD CONSTRAINT "users_invite_code_id_fkey"
	FOREIGN KEY ("invite_code_id") REFERENCES "invite_codes"("id")
	ON DELETE SET NULL;

-- Index for fast lookup by code
CREATE INDEX "invite_codes_code_idx" ON "invite_codes"("code");

-- Index for querying all uses of a given code
CREATE INDEX "invite_code_uses_invite_code_id_idx" ON "invite_code_uses"("invite_code_id");

-- Drizzle journal metadata (appended manually because we wrote this migration by hand)
-- Run: npx drizzle-kit migrate  OR  psql $DATABASE_URL -f migrations/0001_invite_codes.sql
