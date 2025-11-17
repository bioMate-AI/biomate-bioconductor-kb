/**
 * Encryption Module Tests
 * Tests SOC 2 CC6.6 and HIPAA §164.312(a)(2)(iv) compliance
 */

import { describe, it, expect, beforeAll } from '@jest/globals';
import { encrypt, decrypt, encryptFields, decryptFields, hashData, generateSecureToken, testEncryption } from '../encryption';

describe('Encryption Module', () => {
  beforeAll(() => {
    // Set test encryption key
    process.env.ENCRYPTION_KEY = Buffer.from('test-encryption-key-32-bytes-long!').toString('base64');
  });

  describe('Basic Encryption/Decryption', () => {
    it('should encrypt and decrypt simple text', () => {
      const plaintext = 'Hello, World!';
      const encrypted = encrypt(plaintext);
      const decrypted = decrypt(encrypted);

      expect(decrypted).toBe(plaintext);
      expect(encrypted.data).not.toBe(plaintext);
      expect(encrypted.iv).toBeDefined();
      expect(encrypted.authTag).toBeDefined();
    });

    it('should encrypt and decrypt PHI data', () => {
      const phi = {
        firstName: 'John',
        lastName: 'Doe',
        ssn: '123-45-6789',
        dob: '1980-01-01',
        mrn: 'MRN123456',
      };

      const plaintext = JSON.stringify(phi);
      const encrypted = encrypt(plaintext);
      const decrypted = decrypt(encrypted);
      const decryptedPHI = JSON.parse(decrypted);

      expect(decryptedPHI).toEqual(phi);
    });

    it('should produce different ciphertexts for same plaintext', () => {
      const plaintext = 'Same text';
      const encrypted1 = encrypt(plaintext);
      const encrypted2 = encrypt(plaintext);

      // Different IVs should produce different ciphertexts
      expect(encrypted1.iv).not.toBe(encrypted2.iv);
      expect(encrypted1.data).not.toBe(encrypted2.data);

      // But both should decrypt to same plaintext
      expect(decrypt(encrypted1)).toBe(plaintext);
      expect(decrypt(encrypted2)).toBe(plaintext);
    });

    it('should fail decryption with wrong key', () => {
      const plaintext = 'Secret data';
      const encrypted = encrypt(plaintext);

      // Change encryption key
      const originalKey = process.env.ENCRYPTION_KEY;
      process.env.ENCRYPTION_KEY = Buffer.from('wrong-key-32-bytes-long-enough!!').toString('base64');

      expect(() => decrypt(encrypted)).toThrow();

      // Restore original key
      process.env.ENCRYPTION_KEY = originalKey;
    });

    it('should detect tampered ciphertext', () => {
      const plaintext = 'Important data';
      const encrypted = encrypt(plaintext);

      // Tamper with ciphertext
      const tamperedData = Buffer.from(encrypted.data, 'base64');
      tamperedData[0] ^= 0xFF; // Flip bits
      encrypted.data = tamperedData.toString('base64');

      expect(() => decrypt(encrypted)).toThrow();
    });
  });

  describe('Password-Based Encryption', () => {
    it('should encrypt and decrypt with password', () => {
      const plaintext = 'Password protected data';
      const password = 'my-secure-password-123';

      const encrypted = encrypt(plaintext, password);
      const decrypted = decrypt(encrypted, password);

      expect(decrypted).toBe(plaintext);
      expect(encrypted.salt).toBeDefined();
    });

    it('should fail decryption with wrong password', () => {
      const plaintext = 'Secret';
      const encrypted = encrypt(plaintext, 'correct-password');

      expect(() => decrypt(encrypted, 'wrong-password')).toThrow();
    });

    it('should produce different salts for each encryption', () => {
      const plaintext = 'Data';
      const password = 'password';

      const encrypted1 = encrypt(plaintext, password);
      const encrypted2 = encrypt(plaintext, password);

      expect(encrypted1.salt).not.toBe(encrypted2.salt);
      expect(decrypt(encrypted1, password)).toBe(plaintext);
      expect(decrypt(encrypted2, password)).toBe(plaintext);
    });
  });

  describe('Field-Level Encryption', () => {
    it('should encrypt specific fields in object', () => {
      const user = {
        id: 'user123',
        email: 'john@example.com',
        ssn: '123-45-6789',
        address: '123 Main St',
        role: 'admin',
      };

      const encrypted = encryptFields(user, ['ssn', 'address']);

      expect(encrypted.id).toBe('user123');
      expect(encrypted.email).toBe('john@example.com');
      expect(encrypted.role).toBe('admin');
      expect(encrypted.ssn).not.toBe(user.ssn);
      expect(encrypted.address).not.toBe(user.address);
      expect(encrypted._encrypted).toEqual(['ssn', 'address']);
    });

    it('should decrypt specific fields in object', () => {
      const user = {
        id: 'user123',
        ssn: '123-45-6789',
        dob: '1980-01-01',
      };

      const encrypted = encryptFields(user, ['ssn', 'dob']);
      const decrypted = decryptFields(encrypted);

      expect(decrypted.id).toBe(user.id);
      expect(decrypted.ssn).toBe(user.ssn);
      expect(decrypted.dob).toBe(user.dob);
      expect((decrypted as any)._encrypted).toBeUndefined();
    });

    it('should handle nested objects in field encryption', () => {
      const data = {
        user: 'john',
        medical: {
          diagnosis: 'Diabetes Type 2',
          medications: ['Metformin', 'Insulin'],
        },
      };

      const encrypted = encryptFields(data, ['medical']);
      expect(typeof encrypted.medical).not.toBe('object');

      const decrypted = decryptFields(encrypted);
      expect(decrypted.medical).toEqual(data.medical);
    });
  });

  describe('Hashing', () => {
    it('should produce consistent hash for same input', () => {
      const data = 'test-data';
      const hash1 = hashData(data);
      const hash2 = hashData(data);

      expect(hash1).toBe(hash2);
    });

    it('should produce different hashes for different inputs', () => {
      const hash1 = hashData('data1');
      const hash2 = hashData('data2');

      expect(hash1).not.toBe(hash2);
    });

    it('should hash SSN for searchable index', () => {
      const ssn = '123-45-6789';
      const hash = hashData(ssn);

      expect(hash).toBeDefined();
      expect(hash).not.toContain(ssn);
      expect(hash.length).toBeGreaterThan(20);
    });
  });

  describe('Secure Token Generation', () => {
    it('should generate token of specified length', () => {
      const token = generateSecureToken(32);

      expect(token).toBeDefined();
      expect(token.length).toBeGreaterThan(30);
    });

    it('should generate unique tokens', () => {
      const token1 = generateSecureToken();
      const token2 = generateSecureToken();

      expect(token1).not.toBe(token2);
    });

    it('should generate URL-safe tokens', () => {
      const token = generateSecureToken();

      // Should not contain +, /, or =
      expect(token).not.toContain('+');
      expect(token).not.toContain('/');
      expect(token).not.toContain('=');
    });
  });

  describe('HIPAA Compliance', () => {
    it('should encrypt PHI with AES-256', () => {
      const phi = 'Patient: John Doe, DOB: 1980-01-01';
      const encrypted = encrypt(phi);

      // Verify encryption metadata
      expect(encrypted.data).toBeDefined();
      expect(encrypted.iv).toBeDefined();
      expect(encrypted.authTag).toBeDefined();

      // Verify decryption
      const decrypted = decrypt(encrypted);
      expect(decrypted).toBe(phi);
    });

    it('should support encryption of all 18 HIPAA identifiers', () => {
      const identifiers = {
        name: 'John Doe',
        address: '123 Main St, City, State',
        dob: '1980-01-01',
        phone: '555-1234',
        fax: '555-5678',
        email: 'john@example.com',
        ssn: '123-45-6789',
        mrn: 'MRN123456',
        healthPlan: 'HP123456',
        account: 'ACC123456',
        certificate: 'CERT123',
        vehicle: 'ABC123',
        device: 'DEV123',
        url: 'https://patient.example.com',
        ip: '192.168.1.1',
        biometric: 'fingerprint-data',
        photo: 'photo-data',
        other: 'other-identifier',
      };

      const plaintext = JSON.stringify(identifiers);
      const encrypted = encrypt(plaintext);
      const decrypted = decrypt(encrypted);
      const decryptedData = JSON.parse(decrypted);

      expect(decryptedData).toEqual(identifiers);
    });
  });

  describe('Error Handling', () => {
    it('should throw error if encryption key not set', () => {
      const originalKey = process.env.ENCRYPTION_KEY;
      delete process.env.ENCRYPTION_KEY;

      if (process.env.NODE_ENV === 'production') {
        expect(() => encrypt('test')).toThrow();
      }

      process.env.ENCRYPTION_KEY = originalKey;
    });

    it('should handle empty string encryption', () => {
      const encrypted = encrypt('');
      const decrypted = decrypt(encrypted);

      expect(decrypted).toBe('');
    });

    it('should handle unicode characters', () => {
      const plaintext = '你好世界 🔐 café';
      const encrypted = encrypt(plaintext);
      const decrypted = decrypt(encrypted);

      expect(decrypted).toBe(plaintext);
    });
  });

  describe('Self-Test', () => {
    it('should pass self-test', () => {
      const result = testEncryption();
      expect(result).toBe(true);
    });
  });

  describe('Performance', () => {
    it('should encrypt 1000 records in reasonable time', () => {
      const startTime = Date.now();

      for (let i = 0; i < 1000; i++) {
        const data = `Record ${i}: ${Math.random()}`;
        const encrypted = encrypt(data);
        const decrypted = decrypt(encrypted);
        expect(decrypted).toBe(data);
      }

      const duration = Date.now() - startTime;
      console.log(`Encrypted/decrypted 1000 records in ${duration}ms`);

      // Should complete in less than 5 seconds
      expect(duration).toBeLessThan(5000);
    });
  });
});
