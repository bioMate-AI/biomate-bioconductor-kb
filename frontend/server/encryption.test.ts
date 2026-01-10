/**
 * Encryption Module Tests
 *
 * Tests for encryption/decryption functionality
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { encrypt, decrypt, hashData, testEncryption } from './encryption';
import crypto from 'crypto';

describe('Encryption Module', () => {
  const originalEnv = process.env.ENCRYPTION_KEY;

  // Set up a proper 32-byte base64 key for tests
  beforeAll(() => {
    // Generate a proper 32-byte key and encode as base64
    const testKey = crypto.randomBytes(32).toString('base64');
    process.env.ENCRYPTION_KEY = testKey;
  });

  afterAll(() => {
    // Restore original env
    if (originalEnv) {
      process.env.ENCRYPTION_KEY = originalEnv;
    } else {
      delete process.env.ENCRYPTION_KEY;
    }
  });

  describe('encrypt/decrypt', () => {
    it('should encrypt and decrypt text correctly', () => {
      const plaintext = 'Hello, World!';
      const encrypted = encrypt(plaintext);

      expect(encrypted).toHaveProperty('data');
      expect(encrypted).toHaveProperty('iv');
      expect(encrypted).toHaveProperty('authTag');
      expect(encrypted.data).not.toBe(plaintext);

      const decrypted = decrypt(encrypted);
      expect(decrypted).toBe(plaintext);
    });

    it('should produce different ciphertext for same plaintext', () => {
      const plaintext = 'Same text';
      const encrypted1 = encrypt(plaintext);
      const encrypted2 = encrypt(plaintext);

      expect(encrypted1.data).not.toBe(encrypted2.data);
      expect(encrypted1.iv).not.toBe(encrypted2.iv);
    });

    it('should encrypt and decrypt JSON objects', () => {
      const data = { user: 'test', score: 42 };
      const plaintext = JSON.stringify(data);
      const encrypted = encrypt(plaintext);
      const decrypted = decrypt(encrypted);

      expect(JSON.parse(decrypted)).toEqual(data);
    });

    it('should encrypt and decrypt with password', () => {
      const plaintext = 'Secret message';
      const password = 'mySecretPassword123';
      const encrypted = encrypt(plaintext, password);

      expect(encrypted).toHaveProperty('salt');

      const decrypted = decrypt(encrypted, password);
      expect(decrypted).toBe(plaintext);
    });

    it('should fail decryption with wrong password', () => {
      const plaintext = 'Secret message';
      const password = 'correctPassword';
      const wrongPassword = 'wrongPassword';
      const encrypted = encrypt(plaintext, password);

      expect(() => decrypt(encrypted, wrongPassword)).toThrow();
    });
  });

  describe('hashData', () => {
    it('should hash data consistently', () => {
      const data = 'sensitive data';
      const hashed1 = hashData(data);
      const hashed2 = hashData(data);

      expect(hashed1).toBe(hashed2);
      expect(hashed1).not.toBe(data);
    });

    it('should produce different hashes for different data', () => {
      const hash1 = hashData('data1');
      const hash2 = hashData('data2');

      expect(hash1).not.toBe(hash2);
    });

    it('should produce base64 encoded output', () => {
      const hashed = hashData('test data');
      // Base64 pattern - should be valid base64
      expect(hashed).toMatch(/^[A-Za-z0-9+/]+=*$/);
    });
  });

  describe('testEncryption', () => {
    it('should pass self-test', () => {
      expect(testEncryption()).toBe(true);
    });
  });
});
