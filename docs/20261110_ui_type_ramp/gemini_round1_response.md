```json
{
  "tokens": {
    "--fs-xs": {
      "size": "11px",
      "line": "1.2",
      "use": "Micro labels, badges, counts, uppercase eyebrows, kbd (minimum readable size)"
    },
    "--fs-sm": {
      "size": "12px",
      "line": "1.3",
      "use": "Dense table cells (workflow panel), small chips, tight secondary metadata"
    },
    "--fs-md": {
      "size": "13px",
      "line": "1.4",
      "use": "Secondary UI, sidebar items, meta text, standard table data"
    },
    "--fs-base": {
      "size": "14px",
      "line": "1.5",
      "use": "Primary body text, chat bubbles, standard readable content"
    },
    "--fs-lg": {
      "size": "16px",
      "line": "1.4",
      "use": "Card titles, subsection headings, primary buttons"
    },
    "--fs-xl": {
      "size": "20px",
      "line": "1.3",
      "use": "Page titles (e.g., 'Predict ADMET Properties'), empty state subheads"
    },
    "--fs-2xl": {
      "size": "24px",
      "line": "1.2",
      "use": "Hero text, main empty state headers ('What are you trying to do?')"
    },
    "--fs-mono": {
      "size": "12px",
      "line": "1.4",
      "use": "Run IDs, git hashes, inline code snippets (IBM Plex Mono)"
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
    "13": "--fs-md",
    "13.5": "--fs-md",
    "14": "--fs-base",
    "14.5": "--fs-base",
    "15": "--fs-base",
    "16": "--fs-lg",
    "17": "--fs-lg",
    "18": "--fs-lg",
    "20": "--fs-xl",
    "22": "--fs-xl",
    "24": "--fs-2xl",
    "26": "--fs-2xl",
    "28": "--fs-2xl",
    "32": "--fs-2xl",
    "36": "--fs-2xl"
  },
  "tailwind": {
    "xs": "--fs-xs",
    "sm": "--fs-sm",
    "md": "--fs-md",
    "base": "--fs-base",
    "lg": "--fs-lg",
    "xl": "--fs-xl",
    "2xl": "--fs-2xl",
    "mono": "--fs-mono"
  },
  "rationale": "Consolidated 25 ad-hoc sizes into a restrained 7-step scale. Eradicated illegible sub-11px text by hard-mapping all micro values up to 11px. Shifted standard UI body size up to 14px for readability in the chat view, while preserving 12px/13px steps to prevent blowing out dense data tables in the 480px workflow panel. Capped headings at 24px as oversized marketing typography wastes vertical space in dense scientific apps. Added a dedicated 12px mono token for IDs and code."
}
```