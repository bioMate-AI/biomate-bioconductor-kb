# Accessibility Guidelines - Color Blindness Support

This document outlines how BioMate's website is designed to be accessible for users with red-green color blindness (deuteranopia and protanopia).

## Color Palette Strategy

### ❌ AVOID: Red/Green Combinations
We **never** use red and green together to convey information, as approximately 8% of men and 0.5% of women have red-green color blindness.

### ✅ USE: Colorblind-Friendly Palette

| State | Color | Usage | Icon |
|-------|-------|-------|------|
| **Success** | 🔵 **Blue** (not green) | Completed workflows, successful operations | ✓ CheckCircle |
| **Error** | 🟠 **Orange** (not red) | Errors, failed operations | ✗ XCircle |
| **Warning** | 🟡 **Yellow** | Warnings, caution states | ⚠ AlertCircle |
| **Info** | 🔷 **Sky Blue** | Information, neutral notices | ⓘ InfoCircle |
| **Running** | 🟣 **Purple** | In-progress operations | ⟳ Loader2 |
| **Pending** | ⚪ **Gray** | Pending, neutral states | 🕐 Clock |

## Design Principles

### 1. Never Rely on Color Alone
**Every** colored indicator includes additional visual cues:

```tsx
// ❌ BAD: Color only
<div className="text-green-500">Success</div>

// ✅ GOOD: Color + Icon + Text
<StatusBadge status="success">
  <CheckCircle className="h-4 w-4" />
  Success
</StatusBadge>
```

### 2. Use Icons to Reinforce Meaning

- ✓ **CheckCircle** - Success states
- ✗ **XCircle** - Error states
- ⚠ **AlertCircle** - Warning states
- ⓘ **Info** - Information
- ⟳ **Loader2** (spinning) - Running/loading
- 🕐 **Clock** - Pending/waiting

### 3. High Contrast Ratios

All color combinations meet WCAG AA standards:
- **Normal text**: Minimum 4.5:1 contrast ratio
- **Large text**: Minimum 3:1 contrast ratio

### 4. Text Labels

Status indicators always include text labels:
- "Success" instead of just a green checkmark
- "Error" instead of just a red X
- "Running" instead of just a spinner

## Component Usage

### StatusBadge Component

Use `StatusBadge` for all status indicators:

```tsx
import { StatusBadge } from "@/components/ui/status-badge"

// Success (blue with checkmark)
<StatusBadge status="success">Completed</StatusBadge>

// Error (orange with X)
<StatusBadge status="error">Failed</StatusBadge>

// Warning (yellow with alert)
<StatusBadge status="warning">Caution</StatusBadge>

// Info (sky blue with info icon)
<StatusBadge status="info">Notice</StatusBadge>

// Running (purple with spinner)
<StatusBadge status="running">In Progress</StatusBadge>

// Pending (gray with clock)
<StatusBadge status="pending">Waiting</StatusBadge>
```

### Feature Lists

For feature lists with checkmarks:

```tsx
// ✅ Included features - Blue checkmark
<Check className="h-5 w-5 text-blue-600 dark:text-blue-400" />

// ❌ Excluded features - Gray X with strikethrough text
<X className="h-5 w-5 text-muted-foreground" />
<span className="text-muted-foreground line-through">Feature</span>
```

### Success Messages

For success confirmation pages:

```tsx
<div className="rounded-full bg-blue-100 dark:bg-blue-900 p-3">
  <CheckCircle2 className="h-8 w-8 text-blue-600 dark:text-blue-400" />
</div>
<h2>Success!</h2>
```

### Password Requirements

```tsx
// Met requirement - Blue with checkmark
<Check className="h-3 w-3 text-blue-600 dark:text-blue-400" />
<span className="text-blue-600 dark:text-blue-400 font-medium">
  Requirement met
</span>

// Unmet requirement - Muted gray
<Check className="h-3 w-3 text-muted-foreground" />
<span className="text-muted-foreground">
  Not yet met
</span>
```

## Accessibility Utility

Import the accessibility helper:

```tsx
import { getAccessibleColor, getAccessibleIconColor } from "@/lib/accessibility"

// Get full color classes
const colorClasses = getAccessibleColor('success') // Returns blue classes

// Get icon color
const iconColor = getAccessibleIconColor('error') // Returns orange
```

## Testing for Color Blindness

To test the website for color blindness:

1. **Chrome Extension**: [Colorblindly](https://chrome.google.com/webstore/detail/colorblindly)
2. **Firefox Extension**: [Let's get color blind](https://addons.mozilla.org/en-US/firefox/addon/let-s-get-color-blind/)
3. **Online Tool**: [Coblis - Color Blindness Simulator](https://www.color-blindness.com/coblis-color-blindness-simulator/)

## Color Combinations to Always Avoid

| ❌ Never Use | ✅ Use Instead |
|-------------|---------------|
| Red + Green | Blue + Orange |
| Red text on green background | Orange text on blue background |
| Green success / Red error | Blue success / Orange error |
| Traffic light colors (R/Y/G) | Blue / Yellow / Orange |

## Checklist for New Components

Before releasing any new component with color states:

- [ ] Does it include an icon in addition to color?
- [ ] Does it include text labels?
- [ ] Does it use blue for success (not green)?
- [ ] Does it use orange for errors (not red)?
- [ ] Does it meet WCAG AA contrast requirements?
- [ ] Have you tested it with a color blindness simulator?

## Additional Resources

- [WebAIM: Color Blindness](https://webaim.org/articles/visual/colorblind)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [Accessible Color Palette Builder](https://toolness.github.io/accessible-color-matrix/)
- [Colorblind Safe Color Schemes](https://davidmathlogic.com/colorblind/)

## Support

For questions about accessibility, contact: accessibility@biomate.ai
