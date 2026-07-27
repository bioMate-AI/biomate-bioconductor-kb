# Tier Model — DECIDED (Free / Premium / Team / Enterprise)

**Date:** 2026-07-27
**Decision owner:** delegated to Claude ("you decide for me"); confirmed intent: a **clear boundary
between Team and Premium**.
**Supersedes** the "3 open decisions" in `docs/20260722_PROJECT_MODULE_PERF_AND_TIER_PROPOSAL.md`.

---

## The organizing principle

- **Free** — *try it.* Solo, capped. Self-serve.
- **Premium** — *individual power.* Solo, unlimited, private, priority. Self-serve, $100/mo.
- **Team** — *collaboration.* Multiple people on the same work. Custom, sales-led.
- **Enterprise** — *organization.* SSO, audit, on-prem, BAA. Custom, sales-led.

## THE BOUNDARY — Premium ↔ Team = **collaboration** (and it doubles as self-serve ↔ custom)

> **Premium is the most powerful _single-user_ plan.
> Team is the _only_ plan where a project can have more than one person — and it's the point where
> pricing goes from self-serve ($100/mo) to _custom / contact-us_.**

The line runs along two aligned axes at once:
- **Self-serve, single-user:** Free ($0) and Premium ($100/mo) — sign up and go.
- **Custom, multi-user:** Team and Enterprise — a sales conversation, priced to the org.

Everything built and tested in the project-module collaboration surface — **share links, member
invites, the viewer/editor roles + RBAC, member management, team dashboard/usage analytics** — is
**Team-exclusive**. The moment a *second named person* touches a project, it's Team (custom).

Deliberately crisp: Premium users never hit a "collaborator limit of N" — they simply can't add
collaborators at all. **Any** collaboration = Team. No ambiguity about "is 2 seats Premium or Team?"

## Tier matrix

| Capability | Free | **Premium** | **Team** | Enterprise |
|---|:--:|:--:|:--:|:--:|
| Price | $0 | **$100/mo** | **custom** | **custom** |
| Sales motion | self-serve | self-serve | sales-led | sales-led |
| Active projects | **3** | ∞ | ∞ | ∞ |
| Private projects | ✅ | ✅ | ✅ | ✅ |
| Templates · LLM context · files · runs | ✅ | ✅ | ✅ | ✅ |
| Storage / monthly credits | 2 GB / $5 | 100 GB / $120 | custom | custom |
| Priority compute | ❌ | ✅ | ✅ | ✅ |
| **Share link / invite members** | ❌ | ❌ | ✅ | ✅ |
| **Viewer/Editor roles (RBAC)** | ❌ | ❌ | ✅ | ✅ |
| **Team dashboard / usage analytics** | ❌ | ❌ | ✅ | ✅ |
| SSO/SAML · audit log · BAA | ❌ | ❌ | ❌ | ✅ |

### The two upgrade drivers (both clear, non-overlapping)
- **Free → Premium** = *quantity + power*: unlimited projects (past the 3 cap), more storage/credits,
  priority compute. **Not** privacy — Free keeps private projects (public-only felt punitive and
  needs a discovery surface that doesn't exist). The Free wedge is the **3-project cap**.
- **Premium → Team** = *people*: the entire collaboration surface. This is the headline boundary, and
  also where self-serve ($100/mo) hands off to a **custom / sales-led** conversation.

## Resolution of the 3 open decisions
1. **Collaboration tier** → **Team-only.** (This IS the Premium↔Team boundary.)
2. **Free posture** → **cap at 3 active projects; private allowed.** (Simplest, least punitive; cap
   is the upgrade driver.)
3. **Plan scope** → **spec-the-target / TDD.** Write gate tests to the intended behavior; build
   enforcement; test allowed + blocked + downgrade paths.

---

## Implementation — prerequisite + plan (NOT yet built)

**Prerequisite (root-cause, not a workaround):** `subscriptionTier` is currently inconsistent
(`free` / `professional` / `academic` / `base`; no `team`/`enterprise`), and the only gating that
exists is compute-quota (`quota-middleware.ts` → 402 on `over_quota`). Enforcing this model requires
**first canonicalizing the tier vocabulary** to `free | premium | team | enterprise` across
`auth-service.ts`, the billing/Lago plan codes, and the pricing page. Hard-coding `=== 'team'` gates
today would gate against a value no user has — a workaround forbidden by CLAUDE.md.

**Legacy → canonical tier mapping (per product owner):**
| legacy value | canonical |
|---|---|
| `academic` | **`free`** — academic == free tier (no separate academic tier) |
| `base` | `free` (default/unset) |
| `free` | `free` |
| `professional` | `premium` (the paid self-serve individual tier, now $100/mo) |
| (none yet) | `team`, `enterprise` — new, provisioned via sales/billing |

Apply this mapping once (migration + read-time normalization) so gates can trust a 4-value enum.

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
