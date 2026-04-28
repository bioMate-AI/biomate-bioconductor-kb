# BioMate Multilingual Implementation Plan
**Date:** 2026-04-17  
**Folder:** `/biomate/i18n/` (side project — integrate into main when ready)

---

## Scope

Make BioMate's UI, AI assistant, and workflow descriptions available in:
- **EN** English (source of truth)
- **ZH** Chinese Simplified (zh-CN) — priority 1
- **JA** Japanese (ja) — priority 2
- **ES** Spanish (es) — priority 3

Scientific terms (gene names, SMILES, workflow IDs, parameter keys) stay in English in all locales.

---

## Architecture

```
Layer 1 — Frontend UI text         react-i18next + JSON locale files
Layer 2 — AI assistant language    System prompt injection (locale → LLM)
Layer 3 — Workflow DB content      workflow_i18n table + on-demand LLM translation
Layer 4 — Workflow output/reports  POST /api/translate-report endpoint
```

This side project covers **Layer 1** end-to-end, plus integration specs for Layers 2–4.

---

## Folder Structure

```
i18n/
├── PLAN.md                       ← this file
├── package.json                  ← standalone Vitest + i18next
├── vitest.config.ts
├── locales/
│   ├── en/common.json            ← source of truth (all keys)
│   ├── zh/common.json            ← Chinese Simplified
│   ├── ja/common.json            ← Japanese
│   └── es/common.json            ← Spanish
├── src/
│   ├── i18n.ts                   ← i18next instance config
│   ├── detector.ts               ← language detection logic
│   └── types.ts                  ← typed translation key paths
├── tests/
│   ├── completeness.test.ts      ← all EN keys present in every locale
│   ├── i18n-setup.test.ts        ← fallback, namespace, init
│   └── detector.test.ts          ← locale detection edge cases
└── scripts/
    └── extract-strings.ts        ← scan frontend src → report hardcoded strings
```

---

## Phase 1 — Foundation (this folder, done before integration)

### Step 1: Locale files
- Define all translation keys in `en/common.json` (grouped by domain)
- Provide full translations in `zh/common.json`, `ja/common.json`, `es/common.json`
- Key naming convention: `domain.context.label` e.g. `workflow.status.running`

### Step 2: i18next config (`src/i18n.ts`)
- Single namespace: `common`
- Language detection order: `localStorage('biomate-user-settings').language` → `navigator.language` → `en`
- Fallback: always `en`
- Missing key behavior: fall back to EN key, log warning in dev

### Step 3: Language detector (`src/detector.ts`)
- Reads from BioMate's existing `userSettingsService` (`localStorage`)
- Normalises locale codes: `zh-CN`, `zh-TW`, `zh-HK` → all map to `zh`
- Returns ISO 639-1 code

### Step 4: TypeScript types (`src/types.ts`)
- Auto-generate typed key paths from `en/common.json` so `t('workflow.status.running')` is type-safe

---

## Phase 2 — Test Suite (write before implementation)

Tests live in `tests/`. Run with `vitest`.

| Test file | What it asserts |
|-----------|----------------|
| `completeness.test.ts` | Every key in `en/common.json` exists in `zh`, `ja`, `es` (no missing keys) |
| `i18n-setup.test.ts` | i18next initialises without error; `t('nav.run')` returns correct string per locale; fallback to EN for unknown locale; missing key falls back to EN |
| `detector.test.ts` | `zh-CN`, `zh-HK`, `zh-TW` → `zh`; `ja-JP` → `ja`; `es-MX` → `es`; unknown → `en`; localStorage preference overrides navigator |

---

## Phase 3 — Integration into Main Frontend

Once all tests pass in the side project:

1. **Install dependencies** in `frontend/`:
   ```bash
   npm install react-i18next i18next i18next-browser-languagedetector
   ```

2. **Copy files:**
   - `i18n/locales/` → `frontend/client/src/locales/`
   - `i18n/src/i18n.ts` → `frontend/client/src/lib/i18n.ts`
   - `i18n/src/detector.ts` → `frontend/client/src/lib/i18n-detector.ts`

3. **Bootstrap in `main.tsx`:**
   ```tsx
   import './lib/i18n';  // must import before App
   ```

4. **Wrap components:**
   - Replace hardcoded strings with `t('key')` calls
   - Priority order: navigation, buttons, status badges, error messages, form placeholders

5. **Wire Settings UI:**
   - Add language selector to existing Settings panel
   - Persist to `userSettingsService.language` (already exists in localStorage schema)

6. **Backend (Layer 2):**
   - Add `preferred_language` column to users table
   - Inject into `galaxy-assistant.ts` system prompt

---

## Phase 4 — DB Content (Layer 3)

```sql
CREATE TABLE workflow_i18n (
    workflow_id  INTEGER     NOT NULL,
    locale       VARCHAR(10) NOT NULL,
    description  TEXT,
    annotation   TEXT,
    created_at   TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (workflow_id, locale)
);
```

- On first request for a workflow description in a non-EN locale, translate via Claude Haiku and cache in `workflow_i18n`
- FTS search always uses English fields — translations are display-only

---

## Phase 5 — Report Translation (Layer 4)

```
POST /api/translate-report
Body: { text: string, target_locale: string }
Returns: { translated_text: string }
```

- Prompt: `"Translate the following scientific report to {language}. Keep all numeric values, units, gene names, SMILES strings, workflow names, and parameter names in English. Only translate prose descriptions and section headings."`
- Cache by `sha256(text + locale)`

---

## Success Criteria

| Criterion | How to verify |
|-----------|--------------|
| All EN keys translated in ZH, JA, ES | `completeness.test.ts` passes |
| i18next initialises and resolves keys | `i18n-setup.test.ts` passes |
| Locale detection handles edge cases | `detector.test.ts` passes |
| No missing key warnings in production builds | `vitest` zero missing-key errors |
| Settings UI shows language selector | Manual smoke test |
| LLM responds in selected language | Manual smoke test |

---

## What NOT to Translate

- Workflow IDs and internal names (`cryosparc_standard_spa`, `herg_cardiac_safety_qsar`)
- Scientific parameter keys (`ctf_max_res`, `particle_diameter_angstroms`)
- Gene/protein names (`TP53`, `CYP3A4`, `BRCA1`)
- SMILES strings, PDB IDs, accession numbers
- Nextflow process names
- Log files and stack traces
- `versions.yml` in workflow outputs
