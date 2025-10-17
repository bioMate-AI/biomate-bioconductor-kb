/**
 * Color Accessibility Guidelines for Red-Green Color Blindness
 *
 * This file provides utilities and color schemes that are accessible
 * to people with deuteranopia (red-green color blindness).
 */

/**
 * Colorblind-friendly color palette
 *
 * AVOID: Red/Green combinations
 * USE: Blue, Orange, Yellow, Purple, Teal
 */
export const accessibleColors = {
  // Success states - Use BLUE instead of green
  success: {
    light: 'bg-blue-100 text-blue-800 border-blue-200',
    dark: 'dark:bg-blue-900 dark:text-blue-200 dark:border-blue-800',
    text: 'text-blue-600 dark:text-blue-400',
    icon: 'text-blue-600 dark:text-blue-400'
  },

  // Error/Danger states - Use ORANGE instead of red
  error: {
    light: 'bg-orange-100 text-orange-800 border-orange-200',
    dark: 'dark:bg-orange-900 dark:text-orange-200 dark:border-orange-800',
    text: 'text-orange-600 dark:text-orange-400',
    icon: 'text-orange-600 dark:text-orange-400'
  },

  // Warning states - Use YELLOW
  warning: {
    light: 'bg-yellow-100 text-yellow-800 border-yellow-200',
    dark: 'dark:bg-yellow-900 dark:text-yellow-200 dark:border-yellow-800',
    text: 'text-yellow-600 dark:text-yellow-400',
    icon: 'text-yellow-600 dark:text-yellow-400'
  },

  // Info states - Use SKY BLUE
  info: {
    light: 'bg-sky-100 text-sky-800 border-sky-200',
    dark: 'dark:bg-sky-900 dark:text-sky-200 dark:border-sky-800',
    text: 'text-sky-600 dark:text-sky-400',
    icon: 'text-sky-600 dark:text-sky-400'
  },

  // Running/In-Progress states - Use PURPLE
  running: {
    light: 'bg-purple-100 text-purple-800 border-purple-200',
    dark: 'dark:bg-purple-900 dark:text-purple-200 dark:border-purple-800',
    text: 'text-purple-600 dark:text-purple-400',
    icon: 'text-purple-600 dark:text-purple-400'
  },

  // Neutral/Pending states - Use GRAY
  neutral: {
    light: 'bg-gray-100 text-gray-800 border-gray-200',
    dark: 'dark:bg-gray-800 dark:text-gray-200 dark:border-gray-700',
    text: 'text-gray-600 dark:text-gray-400',
    icon: 'text-gray-600 dark:text-gray-400'
  }
}

/**
 * Get accessible color classes for a given state
 */
export function getAccessibleColor(
  state: 'success' | 'error' | 'warning' | 'info' | 'running' | 'neutral'
) {
  return `${accessibleColors[state].light} ${accessibleColors[state].dark}`
}

/**
 * Get accessible text color for a given state
 */
export function getAccessibleTextColor(
  state: 'success' | 'error' | 'warning' | 'info' | 'running' | 'neutral'
) {
  return accessibleColors[state].text
}

/**
 * Get accessible icon color for a given state
 */
export function getAccessibleIconColor(
  state: 'success' | 'error' | 'warning' | 'info' | 'running' | 'neutral'
) {
  return accessibleColors[state].icon
}

/**
 * Best practices for accessibility:
 *
 * 1. NEVER rely on color alone to convey information
 *    - Always pair color with icons, text labels, or patterns
 *
 * 2. Use high contrast ratios
 *    - Minimum 4.5:1 for normal text
 *    - Minimum 3:1 for large text
 *
 * 3. Add visual indicators beyond color
 *    - ✓ Checkmarks for success
 *    - ✗ X marks for errors
 *    - ⚠ Warning triangles for warnings
 *    - ⓘ Info circles for information
 *
 * 4. Use patterns and shapes
 *    - Different border styles (solid, dashed, dotted)
 *    - Different shapes (circle, square, triangle)
 *
 * 5. Provide text labels
 *    - "Success", "Error", "Warning", etc.
 *    - Screen reader support with aria-labels
 */
