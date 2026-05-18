# BioMate IND Report — Production Port Sandbox

This folder is the **isolated build environment** for porting the Claude
Design IND Report prototype to the production frontend stack. **Nothing
in this folder is loaded by the production build.** The production app
at `frontend/client/src/pages/ind-report.tsx` (legacy implementation,
1,984 lines) is untouched. The new port replaces it only after every
checklist item below is green.

---

## Two validation modes

### A. Visual / design intent — open the Claude Design prototype

```bash
# Serve the repo root over HTTP (the prototype's relative paths assume it)
cd /home/yzhang/biomate
python -m http.server 7790
# Then open:
#   http://localhost:7790/reference/claude_design/IND_design/BioMate%20IND%20Report.html
```

This shows exactly what Claude Design delivered. The OKLCH design tokens,
three-column shell, region chips, step cards, doc panel — all rendered
verbatim from the prototype source. This is the **visual target**: my
port must match what this URL shows.

### B. Mechanical / port correctness — TypeScript type-check

```bash
cd /home/yzhang/biomate/frontend
npx tsc --noEmit -p sandbox/ind-port/tsconfig.json
```

Exit 0 means every type alignment is correct, every import resolves,
every component's prop shape matches its callers. Currently:

```
exit=0
```

This is run on every change to a port file. It is not a substitute for
visual review (it cannot catch styling regressions) but it catches
mechanical port errors immediately.

---

## Port progress

| Slice | Prototype file | Sandbox file | Status |
|---|---|---|---|
| Design tokens / styles | `ind/styles-ind.css` | `styles/ind-report.css` | ✅ verbatim copy |
| API client | — | `lib/ind-report-api.ts` | ✅ typed wrapper for 6 feedback endpoints |
| LeftNav | `ind/LeftNav.jsx` | `components/IndLeftNav.tsx` | ✅ ported, type-clean |
| Steps 1–5 | `ind/Steps.jsx` | `components/IndSteps.tsx` | ✅ ported, type-clean |
| Page shell | `BioMate IND Report.html` IndApp | `pages/IndReportPage.tsx` | ✅ wired against demo data |
| DocPanel + DocSection + CitePopover + RegenerateModal + VersionHistory | `ind/DocPanel.jsx` | `components/IndDocPanel.tsx` | ❌ not started |
| Sign + Audit + Empty overlays | `ind/Overlays.jsx` | `components/IndOverlays.tsx` | ❌ not started |
| Tour | `ind/IndTour.jsx` | optional | ❌ not started |

CroIcon → lucide-react mapping is in the handoff doc. Used so far in
the port: `Plus, Check, TriangleAlert, Upload, Eye, Download, Signature`.

---

## Integration checklist (do NOT touch the production tree until every box is checked)

- [x] CSS copied verbatim, tokens preserved
- [x] API client typed
- [x] LeftNav ported
- [x] Steps 1–5 ported
- [x] Sandbox page wires components against demo data
- [x] `tsc --noEmit -p sandbox/ind-port/tsconfig.json` exits 0
- [ ] DocPanel ported (5 sub-components)
- [ ] `contentEditable` replaced with TipTap in DocSection
- [ ] All 4 feedback surfaces (edit hint, dismiss picker, cite [+], regenerate dropdown) wired to `lib/ind-report-api.ts`
- [ ] Overlays (Sign + Audit + Empty) ported
- [ ] Full port runs end-to-end against the live backend
- [ ] User visually compares the running port to mode-A prototype, signs off on parity
- [ ] Production integration: copy sandbox files into `frontend/client/src/`, rewrite imports to `@/`-aliases, replace the legacy `ind-report.tsx`

Only when every box is ticked do production files move.

---

## File map (when integrated)

| Sandbox path | Production path |
|---|---|
| `styles/ind-report.css` | `frontend/client/src/styles/ind-report.css` |
| `lib/ind-report-api.ts` | `frontend/client/src/lib/ind-report-api.ts` |
| `components/IndLeftNav.tsx` | `frontend/client/src/components/ind-report/IndLeftNav.tsx` |
| `components/IndSteps.tsx` | `frontend/client/src/components/ind-report/IndSteps.tsx` |
| `components/IndDocPanel.tsx` (TODO) | `frontend/client/src/components/ind-report/IndDocPanel.tsx` |
| `components/IndOverlays.tsx` (TODO) | `frontend/client/src/components/ind-report/IndOverlays.tsx` |
| `pages/IndReportPage.tsx` | `frontend/client/src/pages/ind-report.tsx` (replaces legacy 1,984-line file) |

Imports rewrite from sandbox-relative (`../components/IndSteps`) to
production aliases (`@/components/ind-report/IndSteps`) at integration time.
