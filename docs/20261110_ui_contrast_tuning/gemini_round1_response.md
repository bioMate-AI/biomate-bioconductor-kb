```css
/* INJECTED AFTER EXISTING SHEETS */

:root {
  /* 1. SURFACE HIERARCHY & CONTRAST */
  /* Tinted canvas to establish depth and separate from white cards/sidebar */
  --background: 212 20% 97%;
  /* Pure white sidebar to pop against the tinted canvas */
  --sidebar: 0 0% 100%;
  /* Pure white cards to stand out clearly on the tinted canvas */
  --card: 0 0% 100%;
  --popover: 0 0% 100%;

  /* Near-black primary text for crisp readability (up from washed-out grey) */
  --foreground: 212 10% 12%;
  --card-foreground: 212 10% 12%;
  --sidebar-foreground: 212 10% 12%;
  --popover-foreground: 212 10% 12%;

  /* Darkened borders (L:86% down from 89%) so they actually delineate elements */
  --border: 212 15% 86%;
  --card-border: 212 15% 86%;
  --sidebar-border: 212 15% 86%;
  --popover-border: 212 15% 86%;
  --input: 212 15% 86%;

  /* Muted text darkened to L:42% to guarantee WCAG AA >= 4.5:1 on light surfaces */
  --muted: 212 20% 94%;
  --muted-foreground: 212 10% 42%;
  
  /* Sidebar hover states mapped to a subtle cool tint */
  --sidebar-accent: 212 20% 94%;
  --sidebar-accent-foreground: 212 10% 12%;

  /* 2. BRAND ACCENT (CERULEAN BLUE) - STRICTLY NO PURPLE */
  --primary: 202 100% 37%;
  --primary-foreground: 0 0% 100%;
  --sidebar-primary: 202 100% 37%;
  --sidebar-primary-foreground: 0 0% 100%;
  --ring: 202 100% 37%;

  /* Re-mapping legacy chart/bio colors to eliminate purple */
  --chart-3: 215 60% 45%; /* Replaced purple with deep navy */
  --bio-purple: 215 60% 45%; /* Overridden to deep navy to satisfy constraint */

  /* 3. BIOMATE OKLCH TOKENS */
  /* Tinted background matching the HSL canvas */
  --bm-bg: oklch(0.975 0.006 240); 
  /* Pure white surface for cards and panels */
  --bm-surface: #ffffff; 
  /* Subtle offsets for nested/elevated containers */
  --bm-surface-2: oklch(0.96 0.01 240); 
  --bm-surface-3: oklch(0.94 0.01 240);
  
  /* Stronger borders for clear separation in OKLCH */
  --bm-border: oklch(0.88 0.01 240);
  --bm-border-strong: oklch(0.80 0.01 240);
  
  /* High contrast text in OKLCH */
  --bm-text: oklch(0.20 0.01 240); /* Near black */
  --bm-text-muted: oklch(0.45 0.01 240); /* WCAG AA secondary text */
  --bm-text-dim: oklch(0.55 0.01 240);

  /* Brand Cerulean Blue */
  --bm-accent: oklch(0.55 0.14 245);
  --bm-accent-soft: oklch(0.96 0.03 245); /* Soft, readable background tint */
  --bm-accent-ink: oklch(0.35 0.10 245); /* Darker ink for text inside soft tints */
  --bm-primary: #007fbd;

  /* Saturated Status Colors for immediate recognition */
  --bm-ok: oklch(0.60 0.15 150); /* Saturated, readable green */
  --bm-ok-soft: oklch(0.96 0.04 150);
  --bm-warn: oklch(0.65 0.18 75); /* Saturated, readable amber */
  --bm-warn-soft: oklch(0.96 0.05 75);
  --bm-err: oklch(0.55 0.20 25); /* Saturated, readable red */
  --bm-err-soft: oklch(0.96 0.04 25);

  /* Speaker palette - Purging purple */
  --bm-loop: oklch(0.50 0.12 220); /* Replaced purple with slate/navy */

  /* Unprefixed aliases pointing to the updated OKLCH tokens */
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

/* 4. WORKFLOW PANEL SCOPE */
.wf-panel {
  /* Match the global surface logic inside the workflow panel */
  --bg: oklch(0.975 0.006 240); /* Tinted canvas */
  --surface: #ffffff; /* White panels */
  --surface-2: oklch(0.96 0.01 240);
  --surface-3: oklch(0.94 0.01 240);
  --border: oklch(0.88 0.01 240); /* Visible border */
  --border-strong: oklch(0.80 0.01 240);
  
  --text: oklch(0.20 0.01 240); /* Near black */
  --text-muted: oklch(0.45 0.01 240); /* WCAG AA */
  --text-dim: oklch(0.55 0.01 240);
  
  /* Brand Cerulean overrides for the panel */
  --accent: oklch(0.55 0.14 245);
  --accent-soft: oklch(0.96 0.03 245);
  --accent-ink: oklch(0.35 0.10 245);
  --run: oklch(0.55 0.14 245);
  --run-soft: oklch(0.96 0.03 245);
  
  /* Saturated Status overrides */
  --ok: oklch(0.60 0.15 150);
  --ok-soft: oklch(0.96 0.04 150);
  --warn: oklch(0.65 0.18 75);
  --warn-soft: oklch(0.96 0.05 75);
  --err: oklch(0.55 0.20 25);
  --err-soft: oklch(0.96 0.04 25);
}

/* 5. GLOBAL ENFORCEMENT RULES */
html, body {
  /* Bump base font size to fix "tiny text" issue (was ~12/13px, now ~14.5px) */
  font-size: 14.5px;
  /* Enforce high-contrast text and the tinted canvas background globally */
  color: hsl(var(--foreground));
  background-color: hsl(var(--background));
  /* High-end antialiasing */
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

/* Ensure sidebar strictly manifests as a white surface against the tinted canvas */
[data-sidebar="sidebar"] {
  background-color: hsl(var(--sidebar));
  border-right: 1px solid hsl(var(--sidebar-border));
}

/* Ensure workflow panel correctly applies the text and background variables */
.wf-panel {
  background-color: var(--surface);
  color: var(--text);
}
```

### What changed and why:
*   **Surface Hierarchy**: Flipped the app to use a slightly tinted cool-grey canvas (`--background`) with crisp, pure white cards (`--card`) and a pure white sidebar (`--sidebar`). This creates instant architectural depth (Linear/Stripe aesthetic) without needing heavy shadows.
*   **Typography & Readability**: Increased the base `font-size` on `html, body` to `14.5px` to eliminate the "tiny" feel. Deepened primary text to near-black (`L:12%` / `L:0.20`) and secondary text to `L:42%` (`L:0.45`), strictly enforcing a WCAG AA ≥4.5:1 contrast ratio.
*   **Visible Borders**: Darkened all borders globally (from lightness `89%` down to `86%`). Borders now actually frame elements rather than washing out into the background.
*   **Brand Integrity (No Purple)**: Re-routed all accent logic (including unprefixed aliases and shadcn primary variables) to your exact brand Cerulean Blue. Stripped all purple/violet from the charts and workflow loop tokens, replacing them with a deep navy/slate. 
*   **Status Color Saturation**: Boosted the chroma and balanced the lightness of the OKLCH status tokens (`--bm-ok`, `--bm-warn`, `--bm-err`) so they are vibrant enough to read instantly at a glance. Added `--accent-ink` to ensure colored text on soft backgrounds has sufficient contrast.