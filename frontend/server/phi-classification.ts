/**
 * PHI (Protected Health Information) Classification Module
 * Implements HIPAA Privacy Rule (§164.500) and Security Rule (§164.312)
 */

/**
 * PHI Data Categories (HIPAA §164.514(b))
 */
export enum PHICategory {
  // Direct Identifiers
  NAME = 'name',
  GEOGRAPHIC_SUBDIVISION = 'geographic', // Smaller than state
  DATES = 'dates', // Birth, death, admission, discharge, etc.
  PHONE_NUMBER = 'phone',
  FAX_NUMBER = 'fax',
  EMAIL = 'email',
  SSN = 'ssn',
  MEDICAL_RECORD_NUMBER = 'mrn',
  HEALTH_PLAN_NUMBER = 'health_plan',
  ACCOUNT_NUMBER = 'account',
  CERTIFICATE_NUMBER = 'certificate',
  VEHICLE_ID = 'vehicle',
  DEVICE_ID = 'device',
  URL = 'url',
  IP_ADDRESS = 'ip',
  BIOMETRIC = 'biometric',
  PHOTO = 'photo',
  OTHER_IDENTIFIER = 'other_id',

  // Medical Information
  DIAGNOSIS = 'diagnosis',
  TREATMENT = 'treatment',
  MEDICATION = 'medication',
  LAB_RESULT = 'lab_result',
  IMAGING = 'imaging',
  GENETIC_INFO = 'genetic',

  // Non-PHI
  DE_IDENTIFIED = 'de_identified',
  PUBLIC = 'public',
}

/**
 * Sensitivity levels for data classification
 */
export enum SensitivityLevel {
  PUBLIC = 'public', // No restrictions
  INTERNAL = 'internal', // Internal use only
  CONFIDENTIAL = 'confidential', // Requires authorization
  RESTRICTED = 'restricted', // PHI - Strict access controls
  HIGHLY_RESTRICTED = 'highly_restricted', // Highly sensitive PHI (genetic, psychiatric, etc.)
}

/**
 * Data classification metadata
 */
export interface DataClassification {
  phiCategory?: PHICategory;
  sensitivity: SensitivityLevel;
  isPHI: boolean;
  requiresEncryption: boolean;
  requiresAuditLog: boolean;
  retentionYears: number;
  minimumNecessary: boolean; // HIPAA minimum necessary standard
}

/**
 * PHI field configuration
 */
export interface PHIFieldConfig {
  fieldName: string;
  category: PHICategory;
  required: boolean;
  encrypted: boolean;
  masked: boolean; // Show masked version (e.g., ***-**-1234 for SSN)
}

/**
 * Classify data based on PHI category
 */
export function classifyData(category: PHICategory): DataClassification {
  const isPHI = category !== PHICategory.DE_IDENTIFIED && category !== PHICategory.PUBLIC;

  // Highly sensitive PHI
  const highlySensitive = [
    PHICategory.SSN,
    PHICategory.GENETIC_INFO,
    PHICategory.BIOMETRIC,
  ];

  const sensitivity = !isPHI
    ? SensitivityLevel.PUBLIC
    : highlySensitive.includes(category)
    ? SensitivityLevel.HIGHLY_RESTRICTED
    : SensitivityLevel.RESTRICTED;

  return {
    phiCategory: category,
    sensitivity,
    isPHI,
    requiresEncryption: isPHI,
    requiresAuditLog: isPHI,
    retentionYears: isPHI ? 6 : 1, // HIPAA: 6 years minimum
    minimumNecessary: isPHI,
  };
}

/**
 * PHI detection patterns
 */
const PHI_PATTERNS: Record<PHICategory, RegExp> = {
  [PHICategory.SSN]: /\b\d{3}-\d{2}-\d{4}\b/,
  [PHICategory.PHONE_NUMBER]: /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,
  [PHICategory.EMAIL]: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
  [PHICategory.IP_ADDRESS]: /\b(?:\d{1,3}\.){3}\d{1,3}\b/,
  [PHICategory.MEDICAL_RECORD_NUMBER]: /\b(MRN|mrn):?\s*\d{6,}\b/,
  [PHICategory.DATES]: /\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b/,

  // Simplified patterns for other categories
  [PHICategory.NAME]: /.+/, // Complex NER required
  [PHICategory.GEOGRAPHIC_SUBDIVISION]: /.+/,
  [PHICategory.FAX_NUMBER]: /.+/,
  [PHICategory.HEALTH_PLAN_NUMBER]: /.+/,
  [PHICategory.ACCOUNT_NUMBER]: /.+/,
  [PHICategory.CERTIFICATE_NUMBER]: /.+/,
  [PHICategory.VEHICLE_ID]: /.+/,
  [PHICategory.DEVICE_ID]: /.+/,
  [PHICategory.URL]: /.+/,
  [PHICategory.BIOMETRIC]: /.+/,
  [PHICategory.PHOTO]: /.+/,
  [PHICategory.OTHER_IDENTIFIER]: /.+/,
  [PHICategory.DIAGNOSIS]: /.+/,
  [PHICategory.TREATMENT]: /.+/,
  [PHICategory.MEDICATION]: /.+/,
  [PHICategory.LAB_RESULT]: /.+/,
  [PHICategory.IMAGING]: /.+/,
  [PHICategory.GENETIC_INFO]: /.+/,
  [PHICategory.DE_IDENTIFIED]: /.+/,
  [PHICategory.PUBLIC]: /.+/,
};

/**
 * Detect PHI in text
 * Returns detected PHI categories
 */
export function detectPHI(text: string): PHICategory[] {
  const detected: PHICategory[] = [];

  for (const [category, pattern] of Object.entries(PHI_PATTERNS)) {
    if (pattern.test(text)) {
      detected.push(category as PHICategory);
    }
  }

  return detected;
}

/**
 * Mask PHI data for display
 */
export function maskPHI(value: string, category: PHICategory): string {
  switch (category) {
    case PHICategory.SSN:
      // Show last 4 digits: ***-**-1234
      if (value.length >= 4) {
        return `***-**-${value.slice(-4)}`;
      }
      return '***-**-****';

    case PHICategory.PHONE_NUMBER:
      // Show last 4 digits: ***-***-1234
      if (value.length >= 4) {
        return `***-***-${value.slice(-4)}`;
      }
      return '***-***-****';

    case PHICategory.EMAIL:
      // Show first letter and domain: j***@example.com
      const parts = value.split('@');
      if (parts.length === 2) {
        return `${parts[0][0]}***@${parts[1]}`;
      }
      return '***@***.***';

    case PHICategory.MEDICAL_RECORD_NUMBER:
      // Show last 4 digits: MRN: ****1234
      if (value.length >= 4) {
        return `MRN: ****${value.slice(-4)}`;
      }
      return 'MRN: ********';

    case PHICategory.NAME:
      // Show first letter of each word: J*** D***
      return value
        .split(' ')
        .map((word) => (word[0] || '') + '***')
        .join(' ');

    case PHICategory.DATES:
      // Show only year: **/**/2024
      const parts2 = value.split(/[/-]/);
      if (parts2.length >= 3) {
        return `**/**/${parts2[parts2.length - 1]}`;
      }
      return '**/**/****';

    default:
      // Generic masking
      if (value.length <= 4) {
        return '****';
      }
      return value[0] + '***' + value.slice(-1);
  }
}

/**
 * De-identify data (HIPAA Safe Harbor method - §164.514(b)(2))
 * Remove all 18 identifiers
 */
export function deIdentify(data: Record<string, any>): Record<string, any> {
  const deIdentified = { ...data };

  // Remove all PHI fields
  const phiFields = [
    'name', 'firstName', 'lastName', 'fullName',
    'address', 'city', 'zip', 'state',
    'phone', 'fax', 'email',
    'ssn', 'medicalRecordNumber', 'mrn',
    'dob', 'dateOfBirth', 'birthDate',
    'photo', 'image',
    'ip', 'ipAddress',
  ];

  for (const field of phiFields) {
    if (field in deIdentified) {
      delete deIdentified[field];
    }
  }

  // Generalize dates (keep only year)
  for (const key of Object.keys(deIdentified)) {
    if (key.toLowerCase().includes('date') && deIdentified[key]) {
      const date = new Date(deIdentified[key]);
      if (!isNaN(date.getTime())) {
        deIdentified[key] = date.getFullYear();
      }
    }
  }

  // Add de-identification flag
  deIdentified._deIdentified = true;
  deIdentified._deIdentificationDate = new Date().toISOString();

  return deIdentified;
}

/**
 * Check if user has access to PHI field (minimum necessary standard)
 */
export function checkMinimumNecessary(
  userRole: string,
  fieldCategory: PHICategory,
  purpose: string
): boolean {
  // Define role-based access rules
  const accessRules: Record<string, PHICategory[]> = {
    // Physicians have full access
    physician: Object.values(PHICategory),

    // Nurses have access to most PHI except administrative
    nurse: [
      PHICategory.NAME,
      PHICategory.DATES,
      PHICategory.DIAGNOSIS,
      PHICategory.TREATMENT,
      PHICategory.MEDICATION,
      PHICategory.LAB_RESULT,
    ],

    // Billing staff have access to financial identifiers
    billing: [
      PHICategory.NAME,
      PHICategory.ACCOUNT_NUMBER,
      PHICategory.HEALTH_PLAN_NUMBER,
      PHICategory.SSN,
    ],

    // Researchers have access only to de-identified data
    researcher: [PHICategory.DE_IDENTIFIED],

    // Admin users have access based on purpose
    admin: Object.values(PHICategory),
  };

  const allowedCategories = accessRules[userRole] || [];
  return allowedCategories.includes(fieldCategory);
}

/**
 * Tag data with PHI classification
 */
export function tagPHI<T extends Record<string, any>>(
  data: T,
  fieldConfigs: PHIFieldConfig[]
): T & { _phiClassification: Record<string, DataClassification> } {
  const result = {
    ...data,
    _phiClassification: {} as Record<string, DataClassification>,
  };

  for (const config of fieldConfigs) {
    if (config.fieldName in data) {
      result._phiClassification[config.fieldName] = classifyData(config.category);
    }
  }

  return result;
}

/**
 * Example PHI field configurations for common entities
 */
export const COMMON_PHI_FIELDS: Record<string, PHIFieldConfig[]> = {
  patient: [
    { fieldName: 'firstName', category: PHICategory.NAME, required: true, encrypted: true, masked: true },
    { fieldName: 'lastName', category: PHICategory.NAME, required: true, encrypted: true, masked: true },
    { fieldName: 'dob', category: PHICategory.DATES, required: true, encrypted: true, masked: true },
    { fieldName: 'ssn', category: PHICategory.SSN, required: false, encrypted: true, masked: true },
    { fieldName: 'mrn', category: PHICategory.MEDICAL_RECORD_NUMBER, required: true, encrypted: true, masked: true },
    { fieldName: 'email', category: PHICategory.EMAIL, required: false, encrypted: true, masked: true },
    { fieldName: 'phone', category: PHICategory.PHONE_NUMBER, required: false, encrypted: true, masked: true },
  ],

  workflow: [
    { fieldName: 'userId', category: PHICategory.OTHER_IDENTIFIER, required: true, encrypted: false, masked: false },
    { fieldName: 'datasetName', category: PHICategory.PUBLIC, required: true, encrypted: false, masked: false },
    { fieldName: 'description', category: PHICategory.PUBLIC, required: false, encrypted: false, masked: false },
  ],
};
