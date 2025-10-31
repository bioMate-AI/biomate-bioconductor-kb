import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * Extract a simple, user-friendly name from a Galaxy tool_id
 *
 * Handles multiple tool ID formats:
 * 1. Toolshed: "toolshed.g2.bx.psu.edu/repos/nml/fastqc_stats/Repository_Actions_FastQC_Summary" → "fastqc_stats"
 * 2. QIIME2: "q2d2_qiime2__quality_control__evaluate_seqs_qiime2_quality-control_evaluate-seqs_..." → "qiime2 quality-control evaluate-seqs"
 * 3. Other prefix: "maciek_spamr_vet_tools_Quality_Control_FastP_Bracken_0.1.0..." → "Quality Control FastP Bracken"
 * 4. Simple: "FastQC" → "FastQC" (already simple)
 */
export function getSimpleToolName(toolId: string): string {
  if (!toolId) return 'Unknown Tool'

  // If it's a toolshed format, extract the tool_name from path
  // Pattern: toolshed.g2.bx.psu.edu/repos/{owner}/{tool_name}/{action}
  if (toolId.includes('toolshed') && toolId.includes('/repos/')) {
    const parts = toolId.split('/')
    if (parts.length >= 4) {
      // Index 3 is the tool_name (after domain/repos/owner)
      return parts[3]
    }
  }

  // If it's a QIIME2 format: q2d2_qiime2__module__function_qiime2_module_function_version
  if (toolId.startsWith('q2d2_qiime2__')) {
    // Pattern: q2d2_qiime2__quality_control__evaluate_seqs_qiime2_quality-control...
    // Extract everything after q2d2_qiime2__ and before the next _qiime2
    const match = toolId.match(/^q2d2_qiime2__(.+?)_qiime2/)
    if (match) {
      // Got: quality_control__evaluate_seqs
      // Convert to: qiime2 quality control evaluate seqs
      return 'qiime2 ' + match[1].replace(/__/g, ' ').replace(/_/g, ' ')
    }
    // Fallback if pattern doesn't match
    return toolId.replace(/^q2d2_/, '').replace(/__/g, ' ').replace(/_/g, ' ').split(' ')[0] || toolId
  }

  // If it contains underscores and looks like: owner_tool_Tool_Name_Version
  // Try to extract the readable tool name (parts with capitals)
  if (toolId.includes('_')) {
    // Split and look for the capitalized tool name sections
    const parts = toolId.split('_')

    // Find where the actual tool name starts (usually capitalized words)
    const capitalizedParts = []
    let foundCapital = false

    for (const part of parts) {
      // Skip version numbers and very short parts
      if (/^\d/.test(part) || part.length <= 1) continue

      // Check if part starts with capital letter
      if (/^[A-Z]/.test(part)) {
        foundCapital = true
        capitalizedParts.push(part)
      } else if (foundCapital) {
        // Stop when we hit lowercase after capitals (likely version string)
        break
      }
    }

    if (capitalizedParts.length > 0) {
      return capitalizedParts.join(' ')
    }
  }

  // If no special pattern matched, return as-is
  return toolId
}
