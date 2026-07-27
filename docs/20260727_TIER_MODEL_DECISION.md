# Tier Model — DECIDED (Free / Premium / Team / Enterprise)

**Date:** 2026-07-27
**Decision owner:** delegated to Claude ("you decide for me"); confirmed intent: a **clear boundary
between Team and Premium**.
**Supersedes** the "3 open decisions" in `docs/20260722_PROJECT_MODULE_PERF_AND_TIER_PROPOSAL.md`.

---

## The organizing principle

- **Free** — *try it.* Solo, capped.
- **Premium (Pro)** — *individual power.* Solo, unlimited, private, priority.
- **Team** — *collaboration.* Multiple people on the same work.
- **Enterprise** — *organization.* SSO, audit, custom.

## THE BOUNDARY — Premium ↔ Team = **collaboration**

> **Premium (Pro) is the most powerful _single-user_ plan.
> Team is the _only_ plan where a project can have more than one person.**

Everything built and tested in the project-module collaboration surface — **share links, member
invites, the viewer/editor roles + RBAC, member management, team dashboard/usage analytics** — is
**Team-exclusive**. The moment a *second named person* touches a project, it's Team.

This is deliberately crisp: Pro users never hit a "collaborator limit of N" — they simply can't add
collaborators at all. That removes ambiguity ("is 2 seats Pro or Team?") — **any** collaboration = Team.

## Tier matrix

| Capability | Free | **Premium (Pro)** | **Team** | Enterprise |
|---|:--:|:--:|:--:|:--:|
| Price | $0 | $20/mo | $40/user/mo | custom |
| Active projects | **3** | ∞ | ∞ | ∞ |
| Private projects | ✅ | ✅ | ✅ | ✅ |
| Templates · LLM context · files · runs | ✅ | ✅ | ✅ | ✅ |
| Storage / monthly credits | 2 GB / $5 | 20 GB / $30 | 100 GB / $60·seat | custom |
| Priority compute | ❌ | ✅ | ✅ | ✅ |
| **Share link / invite members** | ❌ | ❌ | ✅ | ✅ |
| **Viewer/Editor roles (RBAC)** | ❌ | ❌ | ✅ | ✅ |
| **Team dashboard / usage analytics** | ❌ | ❌ | ✅ | ✅ |
| SSO/SAML · audit log · BAA | ❌ | ❌ | ❌ | ✅ |

### The two upgrade drivers (both clear, non-overlapping)
- **Free → Pro** = *quantity + power*: unlimited projects (past the 3 cap), more storage/credits,
  priority compute. **Not** privacy — Free keeps private projects (public-only felt punitive and
  needs a discovery surface that doesn't exist). The Free wedge is the **3-project cap**.
- **Pro → Team** = *people*: the entire collaboration surface. This is the headline boundary.

## Resolution of the 3 open decisions
1. **Collaboration tier** → **Team-only.** (This IS the Pro↔Team boundary.)
2. **Free posture** → **cap at 3 active projects; private allowed.** (Simplest, least punitive; cap
   is the upgrade driver.)
3. **Plan scope** → **spec-the-target / TDD.** Write gate tests to the intended behavior; build
   enforcement; test allowed + blocked + downgrade paths.

---

## Implementation — prerequisite + plan (NOT yet built)

**Prerequisite (root-cause, not a workaround):** `subscriptionTier` is currently inconsistent
(`free` / `professional` / `academic` / `base`; no `team`/`enterprise`), and the only gating that
exists is compute-quota (`quota-middleware.ts` → 402 on `over_quota`). Enforcing this model requires
**first canonicalizing the tier vocabulary** to `free | pro | team | enterprise` across
`auth-service.ts`, the billing/Lago plan codes, and the pricing page. Hard-coding `=== 'team'` gates
today would gate against a value no user has — a workaround forbidden by CLAUDE.md.

**Then, two gates (with the canonical tiers):**
1. **Free project cap** — `POST /api/projects`: if `tier === 'free'` and active-project count ≥ 3 →
   `402` with an upgrade CTA. (Cleanly implementable the moment `free` is canonical — it already is.)
2. **Collaboration = Team** — gate the owner's plan on the collaboration endpoints:
   `POST /:id/share-link`, `POST /:id/members`, `PATCH /:id/members/:id` (role changes),
   and the invitee side of `POST /join/:token/accept`. Non-Team owner → `402` "Upgrade to Team to
   collaborate." Existing shares on downgrade: keep read access, block new invites (grandfather).
   UI: hide the share/invite panel unless owner is Team; show an "Upgrade to Team" prompt.

**Test plan (TDD):** per gate — below-limit allowed, at-limit `402`+CTA, downgrade behavior. The
teamwork E2E already covers the *mechanics* (TW/EI); the tier tests add the *entitlement* layer on top.

**Recommended sequencing:** (a) canonicalize tiers, (b) Free cap gate + tests, (c) collaboration=Team
gate + tests, (d) UI upgrade prompts. (a) is the blocker and touches billing — do it deliberately.
