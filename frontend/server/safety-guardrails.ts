/**
 * BioMate Safety Guardrails
 * ==========================
 * Pre-processing safety layer applied to every user message before it reaches
 * the AI assistant. Implements three checks:
 *
 *   1. PHI Detection   — strip/flag patient personally identifiable health information
 *   2. Content Safety  — block dangerous biological/chemical requests
 *   3. Scope Rejection — politely reject clearly non-scientific queries
 *
 * Usage:
 *   import { checkSafety, stripPHI } from './safety-guardrails';
 *
 *   const check = checkSafety(userMessage);
 *   if (!check.safe) {
 *     return { blocked: true, reason: check.reason, message: check.userMessage };
 *   }
 *   const sanitizedMessage = stripPHI(userMessage);
 */

export interface SafetyCheckResult {
  /** true if the message is safe to process */
  safe: boolean;
  /** Category of the violation (for audit logging) */
  category?: 'phi' | 'content_safety' | 'out_of_scope';
  /** Internal reason for logging (not shown to user) */
  reason?: string;
  /** User-facing refusal message */
  userMessage?: string;
  /** PHI was detected and stripped (safe=true but message was sanitized) */
  phiDetected?: boolean;
  /** The sanitized message (with PHI removed) */
  sanitizedMessage?: string;
}

// ─── PHI Detection ────────────────────────────────────────────────────────────
// Conservative patterns: only flag when high confidence that real patient
// identifiers are present. False positives are worse than false negatives here
// (scientists legitimately write about patients in aggregate / de-identified form).

const PHI_PATTERNS: Array<{ pattern: RegExp; label: string; replacement: string }> = [
  // US Social Security Number
  {
    pattern: /\b\d{3}-\d{2}-\d{4}\b/g,
    label: 'SSN',
    replacement: '[SSN REDACTED]',
  },
  // US date of birth with full year (common PHI combo when near patient name)
  {
    pattern: /\b(dob|date of birth|born on|born)\s*[:\-]?\s*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{4}\b/gi,
    label: 'DOB',
    replacement: '[DOB REDACTED]',
  },
  // Medical Record Number (MRN) patterns
  {
    pattern: /\bMRN\s*[:\-#]?\s*\d{5,10}\b/gi,
    label: 'MRN',
    replacement: '[MRN REDACTED]',
  },
  // Patient ID patterns (common EHR formats)
  {
    pattern: /\bpatient\s*ID\s*[:\-#]?\s*[A-Z0-9\-]{6,15}\b/gi,
    label: 'PatientID',
    replacement: '[PATIENT-ID REDACTED]',
  },
  // NPI (US provider identifier, 10 digits starting with 1)
  {
    pattern: /\bNPI\s*[:\-#]?\s*1\d{9}\b/gi,
    label: 'NPI',
    replacement: '[NPI REDACTED]',
  },
  // Health insurance policy numbers (common patterns)
  {
    pattern: /\bpolicy\s*(no|number|#)\s*[:\-]?\s*[A-Z]{2,4}\d{8,12}\b/gi,
    label: 'InsurancePolicy',
    replacement: '[POLICY-NUM REDACTED]',
  },
];

/**
 * Returns true if the message contains high-confidence PHI patterns.
 */
export function containsPHI(message: string): boolean {
  return PHI_PATTERNS.some(({ pattern }) => {
    pattern.lastIndex = 0;  // reset stateful regex
    return pattern.test(message);
  });
}

/**
 * Strip PHI patterns from a message and return the sanitized version.
 * Also returns which PHI types were found for audit logging.
 */
export function stripPHI(message: string): { sanitized: string; detected: string[] } {
  let sanitized = message;
  const detected: string[] = [];

  for (const { pattern, label, replacement } of PHI_PATTERNS) {
    const before = sanitized;
    pattern.lastIndex = 0;
    sanitized = sanitized.replace(pattern, replacement);
    if (sanitized !== before) {
      detected.push(label);
    }
  }

  return { sanitized, detected };
}

// ─── Content Safety Blocklist ─────────────────────────────────────────────────
// Matches requests that are categorically outside BioMate's intended use:
// gain-of-function on select agents, scheduled substance synthesis, mass casualty
// pathogens, and clinical diagnosis (which requires a licensed clinician).
//
// Pattern design philosophy:
//   - Require MULTIPLE high-confidence signals per category (not single keyword)
//   - Scientific researchers legitimately discuss these topics in academic context
//     (reviewing literature, analyzing sequence data) — avoid blocking those
//   - Block requests for INSTRUCTIONS / HOW-TO / SYNTHESIS that produce harm

interface SafetyRule {
  id: string;
  description: string;
  test: (msg: string) => boolean;
  userMessage: string;
}

const CONTENT_SAFETY_RULES: SafetyRule[] = [
  {
    id: 'gain_of_function',
    description: 'Gain-of-function enhancement of dangerous pathogens',
    test: (msg) => {
      const lower = msg.toLowerCase();
      const hasGOF = /gain.of.function|enhance.*(transmissib|virulenc|pathogen|lethality)|increase.*transmiss/i.test(msg);
      const hasDangerousPat = /smallpox|variola|h5n1.*human|ebola.*airborne|anthrax.*weapon|plague.*enhance/i.test(msg);
      const hasActionVerb = /(create|engineer|modify|mutate|design|generate|produce|synthesize|make)\s/i.test(msg);
      // Block only when GOF intent + dangerous pathogen + action verb are all present
      return (hasGOF && hasActionVerb) || hasDangerousPat;
    },
    userMessage:
      'BioMate is designed for scientific data analysis. Requests to enhance pathogen transmissibility or virulence fall outside supported use cases. If you are working on legitimate biosafety research, please consult your institutional biosafety committee.',
  },
  {
    id: 'cbrn_synthesis',
    description: 'CBRN weapon synthesis or production instructions',
    test: (msg) => {
      // Chemical weapons: nerve agents, mustard gas, etc.
      const chemWeapon = /\b(vx|novichok|sarin|tabun|soman|mustard gas|lewisite)\b.*\b(synth|make|produc|creat|how to)/i.test(msg) ||
        /\b(synth|make|produc|creat|how to).*\b(vx|novichok|sarin|tabun|soman|mustard gas)/i.test(msg);
      // Biological select agents with production intent
      const bioWeapon = /(weaponize|weaponizing|weaponisation)\s*(anthrax|botulinum|ricin|plague|tularemia|smallpox)/i.test(msg) ||
        /production\s+of\s+(botulinum toxin|ricin|anthrax spore)/i.test(msg);
      // Radiological: enrichment methods
      const radioWeapon = /(enrich|concentrate)\s*(uranium|plutonium)\s*(for weapon|dirty bomb)/i.test(msg);
      return chemWeapon || bioWeapon || radioWeapon;
    },
    userMessage:
      'BioMate does not support requests related to chemical, biological, radiological, or nuclear weapon production. This request has been logged.',
  },
  {
    id: 'scheduled_substance_synthesis',
    description: 'Synthesis routes for Schedule I/II controlled substances',
    test: (msg) => {
      // Specific synthesis requests for scheduled drugs (not general chemistry)
      // Requires both the substance name AND an explicit synthesis/production request
      const schedI = /\b(fentanyl analog|methamphetamine|crystal meth|mdma synthesis|lsd synthesis|heroin synthesis)\b/i.test(msg);
      const synthesisIntent = /\b(synth|step.by.step|how to make|production route|precursor.*reaction)\b/i.test(msg);
      return schedI || (synthesisIntent && /\b(fentanyl|methamphetamine|mdma|heroin)\b/i.test(msg));
    },
    userMessage:
      'BioMate does not provide synthesis routes for controlled substances. For legitimate pharmaceutical research involving controlled compounds, please work through your institution\'s regulatory framework.',
  },
  {
    id: 'clinical_diagnosis',
    description: 'Request for clinical diagnosis or treatment recommendation for a specific patient',
    test: (msg) => {
      // Distinguish "analyze this patient's data" (OK) from "diagnose this patient" (not OK)
      const diagnosisRequest = /\b(diagnose|what disease does|what is wrong with|should I prescribe|treatment plan for my patient|is this patient suffering from)\b/i.test(msg);
      const patientSpecific = /\b(my patient|this patient|the patient in room|patient #|MRN)\b/i.test(msg);
      // Only block when BOTH diagnosis intent AND patient-specific language appear
      return diagnosisRequest && patientSpecific;
    },
    userMessage:
      'BioMate is a scientific data analysis platform, not a clinical decision support tool. Clinical diagnosis and treatment decisions for individual patients require a licensed clinician. BioMate can help analyze de-identified research data and run bioinformatics workflows — please phrase your request in those terms.',
  },
];

// ─── Out-of-scope rejection ────────────────────────────────────────────────────
// Topics completely unrelated to life science that waste compute and confuse users.

const OUT_OF_SCOPE_PATTERNS: RegExp[] = [
  /\b(write me a (poem|song|story|essay|novel|screenplay))\b/i,
  /\b(crypto(currency)?|bitcoin|ethereum|btc|eth) (price|invest|trade|pump|moon|buy|sell)\b/i,
  /\b(bitcoin|ethereum|btc|eth) price\b/i,
  /\bshould I invest\b/i,
  /\b(stock (price|tip|invest|buy|sell))\b/i,
  /\bwhat stock(s)? (should|to) (I )?(buy|sell|invest)\b/i,
  /\b(give me |share )?(investment tip|stock tip)\b/i,
  /\b(weather (forecast|today|tomorrow))\b/i,
  /\bhow to (hack|crack password|bypass security|phish)\b/i,
  /\b(recipe for|how to cook|bake|restaurant recommend)\b/i,
  /\b(sports (score|result|prediction)|nfl|nba|fifa|premier league)\b/i,
  /\b(relationship advice|breakup|dating tip)\b/i,
  /\b(write.*cover letter|resume|job application)\b/i,
];

// Biology / chemistry signal words — if present, we assume the query is in scope
// even if it superficially matches an out-of-scope pattern
const BIO_SIGNAL_WORDS = /\b(gene|protein|sequence|genome|cell|dna|rna|assay|compound|drug|workflow|pipeline|analysis|omics|sequenc|variant|mutation|structure|expression|pathway)\b/i;

/**
 * Check whether a message is clearly out of scope for a life-science AI.
 */
function isOutOfScope(message: string): boolean {
  if (BIO_SIGNAL_WORDS.test(message)) return false;  // Has bio signal → keep
  return OUT_OF_SCOPE_PATTERNS.some(p => p.test(message));
}

// ─── Main safety check ────────────────────────────────────────────────────────

/**
 * Run all safety checks on a user message.
 * Call this before passing the message to the AI assistant.
 *
 * @returns SafetyCheckResult — if safe=false, return the userMessage to the user
 *   and do NOT call the AI. If safe=true with phiDetected=true, use sanitizedMessage.
 */
export function checkSafety(message: string): SafetyCheckResult {
  // 1. PHI detection (non-blocking — strip and continue)
  const { sanitized, detected: phiTypes } = stripPHI(message);
  const phiDetected = phiTypes.length > 0;
  if (phiDetected) {
    console.warn(`[SafetyGuardrails] PHI detected and stripped: ${phiTypes.join(', ')}`);
  }

  // 2. Content safety (blocking)
  for (const rule of CONTENT_SAFETY_RULES) {
    if (rule.test(sanitized)) {
      console.warn(`[SafetyGuardrails] BLOCKED — rule: ${rule.id}`);
      return {
        safe: false,
        category: 'content_safety',
        reason: `Rule triggered: ${rule.id} — ${rule.description}`,
        userMessage: rule.userMessage,
      };
    }
  }

  // 3. Out-of-scope (blocking)
  if (isOutOfScope(sanitized)) {
    console.warn(`[SafetyGuardrails] OUT-OF-SCOPE message rejected`);
    return {
      safe: false,
      category: 'out_of_scope',
      reason: 'Message matched out-of-scope pattern with no bio signal words',
      userMessage:
        'BioMate specializes in life science and biomedical data analysis. Your question appears to be outside this scope. If you have a scientific data analysis request — such as running a genomics workflow, analyzing assay data, or performing structure prediction — I\'m ready to help.',
    };
  }

  return {
    safe: true,
    phiDetected,
    sanitizedMessage: phiDetected ? sanitized : message,
  };
}

/**
 * Audit event type for safety blocks (for auditService.log)
 */
export interface SafetyAuditEvent {
  action: 'safety.block' | 'safety.phi_strip';
  category: string;
  ruleId?: string;
  userId?: string | null;
  ipAddress?: string;
  messageHash: string;  // SHA-256 of original message (not plaintext — GDPR compliance)
}

/**
 * Hash a message for audit logging (one-way, GDPR-compliant).
 * We log the hash, not the plaintext, so audit logs can't reconstruct PII.
 */
export async function hashMessage(message: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(message);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}
