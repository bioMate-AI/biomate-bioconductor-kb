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
    ListPartsCommand: makeCmd('ListParts'),
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

describe('S3Service.listUploadedParts', () => {
  it('returns all parts from a single-page response', async () => {
    mockBucketThen({
      Parts: [
        { PartNumber: 1, ETag: '"aaa"', Size: 8388608 },
        { PartNumber: 2, ETag: '"bbb"', Size: 8388608 },
      ],
      IsTruncated: false,
    });
    const s3 = new S3Service();
    const parts = await s3.listUploadedParts('users/u/uploads/x.gz', 'S3UPID-5');
    expect(parts).toHaveLength(2);
    expect(parts[0]).toEqual({ PartNumber: 1, ETag: '"aaa"', Size: 8388608 });
    expect(parts[1]).toEqual({ PartNumber: 2, ETag: '"bbb"', Size: 8388608 });
    const cmd = sendMock.mock.calls[1][0];
    expect(cmd.constructor.cmdName).toBe('ListParts');
    expect(cmd.input.UploadId).toBe('S3UPID-5');
  });

  it('paginates until IsTruncated is false', async () => {
    sendMock
      .mockResolvedValueOnce({ LocationConstraint: 'us-west-2' }) // GetBucketLocation
      .mockResolvedValueOnce({
        Parts: [{ PartNumber: 1, ETag: '"p1"', Size: 1 }],
        IsTruncated: true,
        NextPartNumberMarker: 1,
      })
      .mockResolvedValueOnce({
        Parts: [{ PartNumber: 2, ETag: '"p2"', Size: 1 }],
        IsTruncated: false,
      });
    const s3 = new S3Service();
    const parts = await s3.listUploadedParts('users/u/uploads/x.gz', 'S3UPID-6');
    expect(parts).toHaveLength(2);
    expect(parts.map(p => p.PartNumber)).toEqual([1, 2]);
  });
});

describe('S3Service.refreshPartUrls', () => {
  it('generates fresh presigned URLs for the requested part numbers', async () => {
    sendMock.mockResolvedValueOnce({ LocationConstraint: 'us-west-2' });
    getSignedUrlMock.mockImplementation(async (_c: unknown, cmd: any) =>
      `https://s3/fresh-part-${cmd.input.PartNumber}`,
    );
    const s3 = new S3Service();
    const urls = await s3.refreshPartUrls('users/u/uploads/x.gz', 'S3UPID-7', [2, 4], CHUNK_8MIB);
    expect(urls).toEqual(['https://s3/fresh-part-2', 'https://s3/fresh-part-4']);
    expect(getSignedUrlMock).toHaveBeenCalledTimes(2);
    for (const call of getSignedUrlMock.mock.calls) {
      const cmd = call[1] as any;
      expect(cmd.constructor.cmdName).toBe('UploadPart');
      expect(cmd.input.Key).toBe('users/u/uploads/x.gz');
      expect(cmd.input.UploadId).toBe('S3UPID-7');
    }
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
});

describe('S3Service.readTextPrefix (audit R1: no silent clamp)', () => {
  it('requests exactly the bytes asked for — 3 MiB is not clamped to 1 MiB', async () => {
    sendMock.mockResolvedValueOnce({ Body: { transformToString: async () => 'id,v\n' } });
    const s3 = new S3Service();
    await s3.readTextPrefix('projects/p/inputs/big.csv', 3 * 1024 * 1024);
    const cmd = sendMock.mock.calls[0][0];
    expect(cmd.input).toMatchObject({ Key: 'projects/p/inputs/big.csv', Range: `bytes=0-${3 * 1024 * 1024 - 1}` });
  });

  it('refuses (throws) instead of clamping above the text read limit or for a bad size', async () => {
    const { READ_TEXT_MAX } = await import('./s3-client');
    const s3 = new S3Service();
    await expect(s3.readTextPrefix('k', READ_TEXT_MAX + 1)).rejects.toThrow(RangeError);
    await expect(s3.readTextPrefix('k', 0)).rejects.toThrow(RangeError);
    expect(sendMock).not.toHaveBeenCalled();
  });
});

describe('S3Service.generatePresignedDownloadUrl (audit R14: download names)', () => {
  it('signs Content-Disposition attachment with the display basename; RFC 5987-escapes \' ( ) *', async () => {
    sendMock.mockResolvedValueOnce({ LocationConstraint: 'us-west-2' });
    getSignedUrlMock.mockResolvedValueOnce('https://signed');
    const s3 = new S3Service();
    await s3.generatePresignedDownloadUrl('projects/p/inputs/run1/o-2.csv.v2', 900, "run1/o'brien (1)*.csv");
    const cmd = getSignedUrlMock.mock.calls[0][1];
    expect(cmd.input.Key).toBe('projects/p/inputs/run1/o-2.csv.v2');
    expect(cmd.input.ResponseContentDisposition).toBe(
      `attachment; filename="o'brien (1)*.csv"; filename*=UTF-8''o%27brien%20%281%29%2A.csv`,
    );
  });
});
