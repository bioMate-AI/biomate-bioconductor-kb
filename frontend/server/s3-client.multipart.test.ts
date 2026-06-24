// Unit tests for the real S3 multipart helpers. We mock @aws-sdk/client-s3 so
// the test exercises our orchestration (createUpload + N presigned URLs +
// complete/abort) without touching AWS.

import { describe, it, expect, vi, beforeEach } from 'vitest';

// --- Mocks must be hoisted before the import under test. -------------------
// vi.mock factories run before any top-level `const`, so capture the spy
// instances via vi.hoisted() instead of plain consts.
const { sendMock, getSignedUrlMock } = vi.hoisted(() => ({
  sendMock: vi.fn(),
  getSignedUrlMock: vi.fn(),
}));

vi.mock('@aws-sdk/client-s3', () => {
  class S3Client {
    constructor(_cfg?: unknown) {}
    send = sendMock;
  }
  // The command classes need to be distinguishable so we can assert which one
  // was sent. Use simple identity wrappers.
  const makeCmd = (name: string) =>
    class {
      static cmdName = name;
      input: unknown;
      constructor(input: unknown) {
        this.input = input;
      }
    };
  return {
    S3Client,
    PutObjectCommand: makeCmd('PutObject'),
    GetObjectCommand: makeCmd('GetObject'),
    DeleteObjectCommand: makeCmd('DeleteObject'),
    HeadObjectCommand: makeCmd('HeadObject'),
    CreateMultipartUploadCommand: makeCmd('CreateMultipart'),
    UploadPartCommand: makeCmd('UploadPart'),
    CompleteMultipartUploadCommand: makeCmd('CompleteMultipart'),
    AbortMultipartUploadCommand: makeCmd('AbortMultipart'),
  };
});

vi.mock('@aws-sdk/s3-request-presigner', () => ({
  getSignedUrl: getSignedUrlMock,
}));

// s3-client.ts ends with `export const s3Service = new S3Service()` which runs
// at import time — env must be set BEFORE that import. Use vi.hoisted to set
// the env at hoist time (above the static import below).
vi.hoisted(() => {
  process.env.AWS_ACCESS_KEY_ID = 'test-key';
  process.env.AWS_SECRET_ACCESS_KEY = 'test-secret';
  process.env.S3_BUCKET_NAME = 'test-bucket';
});

import { S3Service } from './s3-client';

const CHUNK_8MIB = 8 * 1024 * 1024;

beforeEach(() => {
  sendMock.mockReset();
  getSignedUrlMock.mockReset();
});

describe('S3Service.startMultipartUpload', () => {
  it('issues CreateMultipartUpload then N UploadPart presigned URLs', async () => {
    sendMock.mockResolvedValueOnce({ UploadId: 'S3UPID-1' });
    getSignedUrlMock.mockImplementation(async (_c: unknown, cmd: any) =>
      `https://s3/part-${cmd.input.PartNumber}`,
    );

    const s3 = new S3Service();
    const out = await s3.startMultipartUpload(
      'user-42',
      'big.fastq.gz',
      CHUNK_8MIB * 3 + 1, // 4 parts (3 full + 1 tail)
      'application/gzip',
      CHUNK_8MIB,
    );

    expect(sendMock).toHaveBeenCalledTimes(1);
    const created = sendMock.mock.calls[0][0];
    expect(created.constructor.cmdName).toBe('CreateMultipart');
    expect(created.input.Bucket).toBe('test-bucket');
    expect(created.input.Key).toMatch(/^users\/user-42\/uploads\/.*-big\.fastq\.gz$/);

    expect(out.uploadId).toBe('S3UPID-1');
    expect(out.numParts).toBe(4);
    expect(out.partUrls).toHaveLength(4);
    expect(out.partUrls[0]).toBe('https://s3/part-1');
    expect(out.partUrls[3]).toBe('https://s3/part-4');
    expect(out.chunkSize).toBe(CHUNK_8MIB);

    // Every getSignedUrl call must use the SAME key + uploadId — that's
    // what makes the parts compose into one object.
    for (const call of getSignedUrlMock.mock.calls) {
      const cmd = call[1] as any;
      expect(cmd.constructor.cmdName).toBe('UploadPart');
      expect(cmd.input.Key).toBe(out.key);
      expect(cmd.input.UploadId).toBe('S3UPID-1');
    }
  });

  it('rejects chunkSize < 5 MiB (S3 minimum part size)', async () => {
    const s3 = new S3Service();
    await expect(
      s3.startMultipartUpload('u', 'f', 100, 'application/octet-stream', 1024),
    ).rejects.toThrow(/5 MiB/);
  });

  it('rejects files that would require > 10,000 parts', async () => {
    const s3 = new S3Service();
    await expect(
      s3.startMultipartUpload(
        'u', 'f',
        // 10,001 parts at 5 MiB
        (10_001) * (5 * 1024 * 1024),
        'application/octet-stream',
        5 * 1024 * 1024,
      ),
    ).rejects.toThrow(/10,000/);
  });

  it('throws if S3 omits UploadId', async () => {
    sendMock.mockResolvedValueOnce({});
    const s3 = new S3Service();
    await expect(
      s3.startMultipartUpload('u', 'f', CHUNK_8MIB, 'application/gzip', CHUNK_8MIB),
    ).rejects.toThrow(/UploadId/);
  });
});

describe('S3Service.completeMultipartUpload', () => {
  it('sorts parts by PartNumber and sends CompleteMultipartUpload', async () => {
    sendMock.mockResolvedValueOnce({ Location: 's3://test-bucket/users/u/abc' });
    const s3 = new S3Service();
    const out = await s3.completeMultipartUpload(
      'users/u/uploads/x.gz',
      'S3UPID-2',
      // out-of-order on purpose
      [
        { PartNumber: 3, ETag: '"c"' },
        { PartNumber: 1, ETag: '"a"' },
        { PartNumber: 2, ETag: '"b"' },
      ],
    );
    expect(out.key).toBe('users/u/uploads/x.gz');
    expect(out.bucket).toBe('test-bucket');
    expect(out.location).toBe('s3://test-bucket/users/u/abc');

    const cmd = sendMock.mock.calls[0][0];
    expect(cmd.constructor.cmdName).toBe('CompleteMultipart');
    expect(cmd.input.UploadId).toBe('S3UPID-2');
    expect(cmd.input.MultipartUpload.Parts.map((p: any) => p.PartNumber)).toEqual([1, 2, 3]);
  });

  it('rejects empty parts list', async () => {
    const s3 = new S3Service();
    await expect(
      s3.completeMultipartUpload('users/u/x', 'S3UPID-3', []),
    ).rejects.toThrow(/no parts/);
  });
});

describe('S3Service.abortMultipartUpload', () => {
  it('sends AbortMultipartUpload with the key + uploadId', async () => {
    sendMock.mockResolvedValueOnce({});
    const s3 = new S3Service();
    await s3.abortMultipartUpload('users/u/uploads/x.gz', 'S3UPID-4');
    const cmd = sendMock.mock.calls[0][0];
    expect(cmd.constructor.cmdName).toBe('AbortMultipart');
    expect(cmd.input.Key).toBe('users/u/uploads/x.gz');
    expect(cmd.input.UploadId).toBe('S3UPID-4');
  });
});
