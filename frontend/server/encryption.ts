/**
 * Encryption Module
 * Implements encryption at rest for sensitive data (SOC 2 CC6.6, HIPAA §164.312(a)(2)(iv))
 */

import crypto from 'crypto';

/**
 * Encryption configuration
 */
interface EncryptionConfig {
  algorithm: string;
  keyLength: number;
  ivLength: number;
  authTagLength: number;
  saltLength: number;
  iterations: number;
}

const DEFAULT_CONFIG: EncryptionConfig = {
  algorithm: 'aes-256-gcm', // AES-256-GCM for authenticated encryption
  keyLength: 32, // 256 bits
  ivLength: 16, // 128 bits
  authTagLength: 16, // 128 bits
  saltLength: 64, // 512 bits
  iterations: 100000, // PBKDF2 iterations
};

/**
 * Encrypted data structure
 */
export interface EncryptedData {
  data: string; // Base64 encoded encrypted data
  iv: string; // Base64 encoded initialization vector
  authTag: string; // Base64 encoded authentication tag
  salt?: string; // Base64 encoded salt (for password-based encryption)
}

/**
 * Get encryption key from environment or generate one
 * IMPORTANT: In production, use a secrets manager (AWS Secrets Manager, HashiCorp Vault, etc.)
 */
function getEncryptionKey(): Buffer {
  const keyEnv = process.env.ENCRYPTION_KEY;

  if (!keyEnv) {
    if (process.env.NODE_ENV === 'production') {
      throw new Error(
        'ENCRYPTION_KEY environment variable must be set in production. ' +
        'Generate one with: node -e "console.log(crypto.randomBytes(32).toString(\'base64\'))"'
      );
    }

    // Development: Generate a temporary key (not secure for production!)
    console.warn('[Encryption] WARNING: Using temporary encryption key. Set ENCRYPTION_KEY in .env for production!');
    return crypto.randomBytes(32);
  }

  // Convert base64 key to buffer
  return Buffer.from(keyEnv, 'base64');
}

/**
 * Derive encryption key from password using PBKDF2
 */
function deriveKey(password: string, salt: Buffer, config: EncryptionConfig = DEFAULT_CONFIG): Buffer {
  return crypto.pbkdf2Sync(password, salt, config.iterations, config.keyLength, 'sha256');
}

/**
 * Encrypt sensitive data using AES-256-GCM
 *
 * @param plaintext - Data to encrypt
 * @param password - Optional password for key derivation (if not using environment key)
 * @returns Encrypted data with IV and authentication tag
 */
export function encrypt(plaintext: string, password?: string): EncryptedData {
  const config = DEFAULT_CONFIG;

  // Generate random IV
  const iv = crypto.randomBytes(config.ivLength);

  // Get or derive encryption key
  let key: Buffer;
  let salt: Buffer | undefined;

  if (password) {
    // Password-based encryption
    salt = crypto.randomBytes(config.saltLength);
    key = deriveKey(password, salt, config);
  } else {
    // Environment-based encryption
    key = getEncryptionKey();
  }

  // Create cipher (cast to CipherGCM for getAuthTag)
  const cipher = crypto.createCipheriv(config.algorithm, key, iv) as crypto.CipherGCM;

  // Encrypt data
  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);

  // Get authentication tag
  const authTag = cipher.getAuthTag();

  // Return encrypted data structure
  return {
    data: encrypted.toString('base64'),
    iv: iv.toString('base64'),
    authTag: authTag.toString('base64'),
    salt: salt?.toString('base64'),
  };
}

/**
 * Decrypt data using AES-256-GCM
 *
 * @param encryptedData - Encrypted data structure
 * @param password - Optional password for key derivation
 * @returns Decrypted plaintext
 */
export function decrypt(encryptedData: EncryptedData, password?: string): string {
  const config = DEFAULT_CONFIG;

  // Convert base64 to buffers
  const data = Buffer.from(encryptedData.data, 'base64');
  const iv = Buffer.from(encryptedData.iv, 'base64');
  const authTag = Buffer.from(encryptedData.authTag, 'base64');

  // Get or derive encryption key
  let key: Buffer;

  if (password) {
    if (!encryptedData.salt) {
      throw new Error('Salt is required for password-based decryption');
    }
    const salt = Buffer.from(encryptedData.salt, 'base64');
    key = deriveKey(password, salt, config);
  } else {
    key = getEncryptionKey();
  }

  // Create decipher (cast to DecipherGCM for setAuthTag)
  const decipher = crypto.createDecipheriv(config.algorithm, key, iv) as crypto.DecipherGCM;
  decipher.setAuthTag(authTag);

  // Decrypt data
  const decrypted = Buffer.concat([
    decipher.update(data),
    decipher.final(),
  ]);

  return decrypted.toString('utf8');
}

/**
 * Hash sensitive data (one-way)
 * Useful for storing searchable hashes of SSN, medical record numbers, etc.
 */
export function hashData(data: string): string {
  return crypto
    .createHash('sha256')
    .update(data)
    .digest('base64');
}

/**
 * Secure random token generation
 */
export function generateSecureToken(length: number = 32): string {
  return crypto.randomBytes(length).toString('base64url');
}

/**
 * Encrypt object fields
 * Automatically encrypts sensitive fields in an object
 */
export function encryptFields<T extends Record<string, any>>(
  obj: T,
  fieldsToEncrypt: (keyof T)[],
  password?: string
): T & { _encrypted: string[] } {
  const result = { ...obj, _encrypted: [] as string[] };

  for (const field of fieldsToEncrypt) {
    if (obj[field] !== null && obj[field] !== undefined) {
      const plaintext = typeof obj[field] === 'string'
        ? obj[field]
        : JSON.stringify(obj[field]);

      result[field] = encrypt(plaintext, password) as any;
      result._encrypted.push(field as string);
    }
  }

  return result;
}

/**
 * Decrypt object fields
 */
export function decryptFields<T extends Record<string, any>>(
  obj: T & { _encrypted?: string[] },
  password?: string
): T {
  const result: Record<string, any> = { ...obj };
  const encryptedFields = obj._encrypted || [];

  for (const field of encryptedFields) {
    if (result[field]) {
      const encryptedData = result[field] as unknown as EncryptedData;
      const plaintext = decrypt(encryptedData, password);

      // Try to parse as JSON
      try {
        result[field] = JSON.parse(plaintext);
      } catch {
        result[field] = plaintext;
      }
    }
  }

  // Remove metadata
  delete result._encrypted;

  return result as T;
}

/**
 * Test encryption/decryption
 */
export function testEncryption(): boolean {
  try {
    // Test with environment key
    const plaintext = 'Hello, World!';
    const encrypted = encrypt(plaintext);
    const decrypted = decrypt(encrypted);

    if (plaintext !== decrypted) {
      console.error('[Encryption] Test failed: decryption mismatch');
      return false;
    }

    // Test with password
    const password = 'test-password-123';
    const encryptedPwd = encrypt(plaintext, password);
    const decryptedPwd = decrypt(encryptedPwd, password);

    if (plaintext !== decryptedPwd) {
      console.error('[Encryption] Test failed: password-based decryption mismatch');
      return false;
    }

    console.log('[Encryption] Self-test passed');
    return true;
  } catch (error) {
    console.error('[Encryption] Test failed:', error);
    return false;
  }
}
