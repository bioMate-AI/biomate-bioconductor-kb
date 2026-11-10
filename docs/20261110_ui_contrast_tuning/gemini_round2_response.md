```css
/* INJECTED AFTER EXISTING SHEETS */

:root {
  /* 1. SURFACE HIERARCHY & CONTRAST */
  /* Swapping hierarchy: White canvas with a tinted sidebar (per Reviewer #5).
     This resolves the odd footer band issue (Reviewer #2) and provides a calm, clean workspace. */
  --background: 0 0% 100%;
  --sidebar: 212 25% 97%; /* Subtle cool-grey tint for the sidebar to cleanly separate it */
  --sidebar-border: 212 18% 88%;
  --card: 0 0% 100%;
  --popover: 0 0% 100%;

  /* Darker borders everywhere for actual visible separation */
  --border: 212 18% 88%;
  --card-border: 212 18% 88%;
  --popover-border: 212 18% 88%;
  --input: 212 18% 88%;

  /* Crisp, near-black primary text (up from washed-out grey) */
  --foreground: 212 15% 15%;
  --card-foreground: 212 15% 15%;
  --sidebar-foreground: 212 15% 15%;
  --popover-foreground: 212 15% 15%;

  /* Much darker muted text (L:40%) to guarantee WCAG AA >= 4.5:1, fixing faint Run Manager meta */
  --muted: 212 25% 97%; /* Lightened background to prevent heavy grey bands on tab lists (Reviewer #6) */
  --muted-foreground: 212 10% 40%;
  
  --sidebar-accent: 212 20% 93%;
  --sidebar-accent-foreground: 212 15% 15%;

  /* 2. BRAND ACCENT (CERULEAN BLUE) - STRICTLY NO PURPLE */
  /* Explicitly defining primary across all scopes to fix black buttons (Reviewer #3) */
  --primary: 202 100% 37%;
  --primary-foreground: 0 0% 100%;
  --sidebar-primary: 202 100% 37%;
  --sidebar-primary-foreground: 0 0% 100%;
  --ring: 202 100% 37%;

  /* Replace any legacy purple charts/accents with a deep navy to satisfy the constraint */
  --chart-3: 215 60% 45%; 
  --bio-purple: 215 60% 45%; 

  /* 3. BIOMATE OKLCH TOKENS (GLOBAL) */
  --bm-bg: #ffffff; 
  --bm-surface: #ffffff; 
  --bm-surface-2: oklch(0.97 0.01 240); /* Subtle hover/inset background */
  --bm-surface-3: oklch(0.94 0.01 240);
  
  --bm-border: oklch(0.88 0.01 240);
  --bm-border-strong: oklch(0.80 0.01 240);
  
  --bm-text: oklch(0.20 0.01 240);
  --bm-text-muted: oklch(0.40 0.01 240); /* Boosted contrast for secondary text */
  --bm-text-dim: oklch(0.55 0.01 240);

  --bm-primary: #007fbd;
  --bm-accent: oklch(0.55 0.14 245);
  --bm-accent-soft: oklch(0.96 0.03 245);
  --bm-accent-ink: oklch(0.35 0.10 245);

  /* High saturation status colors for immediate recognition in Run Manager */
  --bm-ok: oklch(0.60 0.15 150);
  --bm-ok-soft: oklch(0.96 0.04 150);
  --bm-warn: oklch(0.65 0.18 75);
  --bm-warn-soft: oklch(0.96 0.05 75);
  --bm-err: oklch(0.55 0.20 25);
  --bm-err-soft: oklch(0.96 0.04 25);

  --bm-loop: oklch(0.50 0.12 220); /* Replaced purple speaker */

  /* Unprefixed aliases */
  --ok: var(--bm-ok);
  --ok-soft: var(--bm-ok-soft);
  --warn: var(--bm-warn);
  --warn-soft: var(--bm-warn-soft);
  --err: var(--bm-err);
  --err-soft: var(--bm-err-soft);
  --accent: var(--bm-accent);
  --accent-soft: var(--bm-accent-soft);
  --accent-ink: var(--bm-accent-ink);
  --run: var(--bm-accent);
  --run-soft: var(--bm-accent-soft);
  --surface: var(--bm-surface);
  --surface-3: var(--bm-surface-3);
  --border: var(--bm-border);
  --border-strong: var(--bm-border-strong);
  --text: var(--bm-text);
  --text-muted: var(--bm-text-muted);
  --text-dim: var(--bm-text-dim);
}

/* 4. WORKFLOW PANEL OVERRIDES */
.wf-panel {
  --bg: #ffffff; /* Match canvas */
  --surface: #ffffff; /* Keep cards crisp white */
  --surface-2: oklch(0.97 0.01 240);
  --surface-3: oklch(0.94 0.01 240);
  
  --border: oklch(0.88 0.01 240);
  --border-strong: oklch(0.80 0.01 240);
  
  --text: oklch(0.20 0.01 240);
  --text-muted: oklch(0.40 0.01 240);
  --text-dim: oklch(0.55 0.01 240);
  
  /* Guarantee "Run again" and standard buttons correctly pull the Cerulean primary (Reviewer #3) */
  --primary: 202 100% 37%;
  --primary-foreground: 0 0% 100%;
  --accent: oklch(0.55 0.14 245);
  --accent-soft: oklch(0.96 0.03 245);
  --accent-ink: oklch(0.35 0.10 245);
  --run: oklch(0.55 0.14 245);
  --run-soft: oklch(0.96 0.03 245);
  
  --ok: oklch(0.60 0.15 150);
  --ok-soft: oklch(0.96 0.04 150);
  --warn: oklch(0.65 0.18 75);
  --warn-soft: oklch(0.96 0.05 75);
  --err: oklch(0.55 0.20 25);
  --err-soft: oklch(0.96 0.04 25);
}

/* 5. GLOBAL ENFORCEMENT RULES */
html {
  /* Font size fix: In standard CSS, 1rem = 16px. Setting it to 14.5px previously *shrank* standard sizing. 
     Instead, scaling the base to 110% (17.6px) globally bumps standard Tailwind utilities 
     (like text-sm going from 14px -> ~15.4px) making the UI effortlessly readable. (Reviewer #1) */
  font-size: 110%;
}

body {
  color: hsl(var(--foreground));
  background-color: hsl(var(--background));
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

[data-sidebar="sidebar"] {
  background-color: hsl(var(--sidebar));
  border-right: 1px solid hsl(var(--sidebar-border));
}

.wf-panel {
  background-color: var(--surface);
  color: var(--text);
}
```

### Changes made & Why:
*   **Font Size Re-scaling:** Changed the blunt `14.5px` HTML font-size to `110%`. Since Tailwind utilities map to `rem` relative to a default 16px root, a 14.5px root *reduced* the app's standard size (causing the 12px issue to remain). Boosting to 110% (17.6px) uniformly scales standard small text to a highly readable ~15.5px without overriding classes.
*   **Reversed Surface Hierarchy:** Changed the main canvas back to pure white (`0 0% 100%`) and applied a subtle cool-grey tint *only* to the sidebar (`212 25% 97%`). This fixes the visual bleed into the chat composer footer and perfectly replicates the clean, calm layout of the prototype.
*   **Repaired Action Button Missing Brand Color:** Hardcoded `--primary` and `--primary-foreground` inside the `.wf-panel` block to guarantee that fallback shadcn primary components (like the "Run Again" button) map perfectly to Cerulean instead of defaulting back to a global black.
*   **Boosted Contrast for Status/Meta Text:** Sharpened `--muted-foreground` to a dark `212 10% 40%` and `.wf-panel`'s `--text-muted` to `L:0.40`. Because we are restricted from adding new HTML classes to colorize specific run-manager headers, drastically darkening the "muted" layer globally ensures those elements pass WCAG guidelines and are effortlessly readable.
*   **Subtle Tabs List Adjustment:** Softened `--muted` (used by tab lists in shadcn) so the backgrounds under "Workflow settings / Phases" don't present as an overly heavy grey block, integrating smoothly with the white panels.