```json
{
 "tokens": {
  "--fs-xs": {
   "size": "11px",
   "line": "1.2",
   "use": "Micro labels, badges, counts, kbd (minimum readable size)"
  },
  "--fs-sm": {
   "size": "13px",
   "line": "1.4",
   "use": "Secondary UI, sidebar items, meta text, dense table cells"
  },
  "--fs-base": {
   "size": "15px",
   "line": "1.5",
   "use": "Primary body text, chat bubbles, standard readable content"
  },
  "--fs-lg": {
   "size": "18px",
   "line": "1.4",
   "use": "Card titles, subsection headings, primary buttons"
  },
  "--fs-xl": {
   "size": "24px",
   "line": "1.3",
   "use": "Page titles, hero text, main empty state headers"
  },
  "--fs-2xl": {
   "size": "36px",
   "line": "1.2",
   "use": "Display text, large metrics (preserves legacy large values)"
  },
  "--fs-mono": {
   "size": "13px",
   "line": "1.4",
   "use": "Run IDs, git hashes, inline code snippets"
  }
 },
 "px_map": {
  "7": "--fs-xs",
  "8": "--fs-xs",
  "9": "--fs-xs",
  "9.5": "--fs-xs",
  "10": "--fs-xs",
  "10.5": "--fs-xs",
  "11": "--fs-xs",
  "11.5": "--fs-sm",
  "12": "--fs-sm",
  "12.5": "--fs-sm",
  "13": "--fs-sm",
  "13.5": "--fs-base",
  "14": "--fs-base",
  "14.5": "--fs-base",
  "15": "--fs-base",
  "16": "--fs-lg",
  "17": "--fs-lg",
  "18": "--fs-lg",
  "20": "--fs-xl",
  "22": "--fs-xl",
  "24": "--fs-xl",
  "26": "--fs-2xl",
  "28": "--fs-2xl",
  "32": "--fs-2xl",
  "36": "--fs-2xl"
 },
 "tailwind": {
  "xs": "--fs-sm",
  "sm": "--fs-base",
  "base": "--fs-lg",
  "lg": "--fs-lg",
  "xl": "--fs-xl",
  "2xl": "--fs-xl"
 },
 "rationale": "Strictly obeys the no-shrink rule: the dominant 12px (text-xs) grows to 13px, and 14px (text-sm) grows to 15px, radically improving readability for core content. All illegible sub-11px values hit a hard 11px floor. Grouped headings strictly into 18px, 24px, and 36px to prevent vertical space waste while ensuring legacy values >24px do not shrink. Tailwind named scales are re-mapped to larger tokens to ensure zero regression in code."
}
```