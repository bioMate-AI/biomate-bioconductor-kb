// Unit tests for the real S3 multipart helpers. We mock @aws-sdk/client-s3 so
// the test exercises our orchestration (createUpload + N presigned URLs +
// complete/abort) without touching AWS.

import { describe, it, expect, vi, beforeEach } from 'vitest';

// --- Mocks must be hoisted before the import under test. -------------------
// vi.mock factories run before any top-level `const`, so capture the spy
// instances via vi.hoisted() instead of plain consts.
const { sendMock, getSignedUrlMock, clientConfigs } = vi.hoisted(() => ({
  sendMock: vi.fn(),
  getSignedUrlMock: vi.fn(),
  clientConfigs: [] as unknown[],
}));

vi.mock('@aws-sdk/client-s3', () => {
  class S3Client {
    constructor(cfg?: unknown) { clientConfigs.push(cfg); }
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
    GetBucketLocationCommand: makeCmd('GetBucketLocation'),
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
  clientConfigs.length = 0;
});

function mockBucketThen(result: unknown): void {
  sendMock
    .mockResolvedValueOnce({ LocationConstraint: 'us-west-2' })
    .mockResolvedValueOnce(result);
}

describe('S3Service credential providers', () => {
  it('uses the AWS SDK default credential chain when no static key is supplied', () => {
    const savedAccessKey = process.env.AWS_ACCESS_KEY_ID;
    const savedSecret = process.env.AWS_SECRET_ACCESS_KEY;
    delete process.env.AWS_ACCESS_KEY_ID;
    delete process.env.AWS_SECRET_ACCESS_KEY;
    try {
      new S3Service({ bucket: 'test-bucket', region: 'us-west-2' });
      expect(clientConfigs).toHaveLength(1);
      expect(clientConfigs[0]).not.toHaveProperty('credentials');
    } finally {
      process.env.AWS_ACCESS_KEY_ID = savedAccessKey;
      process.env.AWS_SECRET_ACCESS_KEY = savedSecret;
    }
  });

  it('rejects incomplete static credentials instead of silently mixing providers', () => {
    expect(() => new S3Service({
      bucket: 'test-bucket',
      accessKeyId: 'only-a-key',
      secretAccessKey: undefined,
    })).toThrow('AWS static credentials are incomplete');
  });
});

describe('S3Service.startMultipartUpload', () => {
  it('issues CreateMultipartUpload then N UploadPart presigned URLs', async () => {
    mockBucketThen({ UploadId: 'S3UPID-1' });
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

    expect(sendMock).toHaveBeenCalledTimes(2);
    const created = sendMock.mock.calls[1][0];
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
    sendMock.mockResolvedValueOnce({ LocationConstraint: 'us-west-2' });
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
    mockBucketThen({});
    const s3 = new S3Service();
    await expect(
      s3.startMultipartUpload('u', 'f', CHUNK_8MIB, 'application/gzip', CHUNK_8MIB),
    ).rejects.toThrow(/UploadId/);
  });
});

describe('S3Service.completeMultipartUpload', () => {
  it('sorts parts by PartNumber and sends CompleteMultipartUpload', async () => {
    mockBucketThen({ Location: 's3://test-bucket/users/u/abc' });
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

    const cmd = sendMock.mock.calls[1][0];
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
    mockBucketThen({});
    const s3 = new S3Service();
    await s3.abortMultipartUpload('users/u/uploads/x.gz', 'S3UPID-4');
    const cmd = sendMock.mock.calls[1][0];
    expect(cmd.constructor.cmdName).toBe('AbortMultipart');
    expect(cmd.input.Key).toBe('users/u/uploads/x.gz');
    expect(cmd.input.UploadId).toBe('S3UPID-4');
  });
});

describe('S3Service.readTextPrefix', () => {
  it('reads only a bounded object range and decodes the returned stream', async () => {
    sendMock.mockResolvedValueOnce({
      Body: (async function* () {
        yield Buffer.from('gene,count\nTP53,12\n');
      })(),
    });
    const s3 = new S3Service();
    await expect(s3.readTextPrefix('projects/p/inputs/counts.csv', 64)).resolves.toBe('gene,count\nTP53,12\n');

    const cmd = sendMock.mock.calls[0][0] as any;
    expect(cmd.constructor.cmdName).toBe('GetObject');
    expect(cmd.input.Bucket).toBe('test-bucket');
    expect(cmd.input.Key).toBe('projects/p/inputs/counts.csv');
    expect(cmd.input.Range).toBe('bytes=0-63');
  });

  it('caps a caller-supplied range at one MiB', async () => {
    sendMock.mockResolvedValueOnce({ Body: { transformToString: async () => 'ok' } });
    const s3 = new S3Service();
    await expect(s3.readTextPrefix('projects/p/inputs/a.csv', 99 * 1024 * 1024)).resolves.toBe('ok');
    expect((sendMock.mock.calls[0][0] as any).input.Range).toBe(`bytes=0-${1024 * 1024 - 1}`);
  });
});
