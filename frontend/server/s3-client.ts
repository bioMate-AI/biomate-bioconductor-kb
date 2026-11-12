import { attachmentDisposition } from './content-disposition';
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  CreateMultipartUploadCommand,
  UploadPartCommand,
  CompleteMultipartUploadCommand,
  AbortMultipartUploadCommand,
  GetBucketLocationCommand,
  ListPartsCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { randomUUID } from 'crypto';

// URL-encodes S3 object tags so the billing Lambda can identify the owning user
function buildTagging(userId: string, extra: Record<string, string> = {}): string {
  const tags: Record<string, string> = { user_id: `bm_${userId}`, ...extra };
  return Object.entries(tags).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
}

interface S3Config {
  accessKeyId?: string;
  secretAccessKey?: string;
  region: string;
  bucket: string;
}

interface PresignedUploadUrl {
  uploadId: string;
  uploadUrl: string;
  key: string;
  expires_in: number;
}

interface MultipartUploadData {
  // S3-issued upload id (NOT a UUID — required verbatim by every UploadPart and CompleteMultipartUpload call)
  uploadId: string;
  // Single S3 object key that all parts compose into
  key: string;
  // Presigned PUT URLs for parts 1..N, in order
  partUrls: string[];
  // Bytes per part the client must use (S3 requires every non-final part be the same size)
  chunkSize: number;
  // Total parts the client must upload
  numParts: number;
}

interface CompletedPart {
  PartNumber: number;
  ETag: string;
}

export class S3Service {
  private s3Client!: S3Client;
  private bucket: string;

  constructor(config?: S3Config) {
    const configSuppliesStaticCredentials =
      config?.accessKeyId !== undefined || config?.secretAccessKey !== undefined;
    const accessKeyId = configSuppliesStaticCredentials
      ? config?.accessKeyId
      : process.env.AWS_ACCESS_KEY_ID;
    const secretAccessKey = configSuppliesStaticCredentials
      ? config?.secretAccessKey
      : process.env.AWS_SECRET_ACCESS_KEY;
    const region = config?.region || process.env.AWS_REGION || 'us-east-1';
    this.bucket = config?.bucket || process.env.S3_BUCKET_NAME || '';

    // Supplying one half of a static credential is always a configuration
    // error. Supplying neither is valid: the AWS SDK default provider chain
    // then resolves an EC2/ECS role, web identity, or shared profile. This is
    // essential for deployed services, where long-lived keys must not be
    // required merely to generate presigned URLs.
    if ((accessKeyId && !secretAccessKey) || (!accessKeyId && secretAccessKey)) {
      throw new Error('AWS static credentials are incomplete');
    }

    if (!this.bucket) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[S3Service] S3 bucket name not configured — S3 operations will fail at runtime (dev mode)');
        return;
      }
      throw new Error('S3 bucket name not configured');
    }

    // S3_ENDPOINT_URL is set on-prem to point to MinIO (e.g. http://minio:9000).
    // When set: use path-style addressing (MinIO requirement) and skip the
    // region-redirect feature (not applicable to MinIO). When absent: use the
    // default AWS S3 endpoint with region redirect for cross-region buckets.
    const endpointUrl = process.env.S3_ENDPOINT_URL;
    this.s3Client = this.createClient(region, accessKeyId && secretAccessKey
      ? { accessKeyId, secretAccessKey }
      : null, endpointUrl);
    this.configuredRegion = region;
    this.configuredCredentials = accessKeyId && secretAccessKey
      ? { accessKeyId, secretAccessKey }
      : null;
  }

  private configuredRegion: string = 'us-east-1';
  private configuredCredentials: { accessKeyId: string; secretAccessKey: string } | null = null;
  private bucketRegionEnsured = false;

  private createClient(
    region: string,
    credentials: { accessKeyId: string; secretAccessKey: string } | null,
    endpointUrl?: string,
  ): S3Client {
    return new S3Client({
      region,
      ...(credentials ? { credentials } : {}),
      // On-prem MinIO: fixed endpoint, path-style addressing, no region redirect.
      // AWS: if the bucket is actually in another region the SDK follows the 307
      // redirect for non-presigned calls; presigned URLs are signed for THIS
      // client's region, so ensureBucketRegion() rebuilds the client against the
      // bucket's real region.
      ...(endpointUrl
        ? { endpoint: endpointUrl, forcePathStyle: true }
        : { followRegionRedirects: true }),
    });
  }

  // Preserved from constructor so ensureBucketRegion can restore it when rebuilding.
  private configuredEndpoint: string | undefined = process.env.S3_ENDPOINT_URL;

  /**
   * Detect the bucket's real region (one GetBucketLocation, cached) and
   * rebuild the S3Client against it if it differs from what we were configured
   * with. Without this, presigned PUT URLs are signed for the wrong endpoint
   * and the browser PUT fails signature validation after the 307 redirect.
   *
   * Called lazily by every method that issues a presigned URL.
   * Skipped for MinIO (S3_ENDPOINT_URL set) — MinIO always returns us-east-1,
   * and region redirect is not applicable to MinIO anyway.
   */
  private async ensureBucketRegion(): Promise<void> {
    if (this.bucketRegionEnsured || !this.bucket) return;
    // Skip region detection for on-prem MinIO — the endpoint is fixed.
    if (this.configuredEndpoint) {
      this.bucketRegionEnsured = true;
      return;
    }
    try {
      const loc = await this.s3Client.send(
        new GetBucketLocationCommand({ Bucket: this.bucket })
      );
      // AWS legacy quirk: us-east-1 buckets return null/empty LocationConstraint.
      const actual = loc.LocationConstraint || 'us-east-1';
      if (actual !== this.configuredRegion) {
        console.log(
          `[S3Service] bucket ${this.bucket} is in ${actual}, ` +
          `not ${this.configuredRegion} — rebuilding client for presign correctness`
        );
        this.s3Client = this.createClient(actual, this.configuredCredentials);
        this.configuredRegion = actual;
      }
    } catch (err) {
      console.warn('[S3Service] GetBucketLocation failed (continuing with configured region):', err);
    } finally {
      // Cache the attempt either way — we don't want to retry on every call.
      this.bucketRegionEnsured = true;
    }
  }

  /**
   * Generate presigned URL for uploading a file (for files < 100MB)
   */
  async generatePresignedUploadUrl(
    userId: string,
    filename: string,
    contentType: string,
    expiresIn: number = 3600
  ): Promise<PresignedUploadUrl> {
    await this.ensureBucketRegion();
    const uploadId = randomUUID();
    const key = `users/${userId}/uploads/${uploadId}-${filename}`;

    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      ContentType: contentType,
      ServerSideEncryption: 'AES256',
      Tagging: buildTagging(userId, { upload_type: 'user_upload' }),
    });

    const uploadUrl = await getSignedUrl(this.s3Client, command, { expiresIn });

    return {
      uploadId,
      uploadUrl,
      key,
      expires_in: expiresIn,
    };
  }

  /**
   * Real S3 multipart upload for files larger than the single-PUT limit.
   *
   * Browser then performs:
   *   1. PUT each chunk to partUrls[i-1] (Blob.slice(start, end))
   *   2. Capture the ETag header on each 200 response
   *   3. POST {uploadId, key, parts: [{PartNumber, ETag}, ...]} to
   *      /api/uploads/multipart/complete to assemble the object.
   *
   * If the user cancels or the browser closes, the server can call
   * abortMultipartUpload(key, uploadId) so S3 stops billing the parts.
   *
   * S3 hard limits: every non-final part >= 5 MiB, <= 10,000 parts,
   * max object 5 TiB. Default 64 MiB chunks → 640 GiB before raising chunkSize.
   */
  async startMultipartUpload(
    userId: string,
    filename: string,
    fileSize: number,
    contentType: string,
    chunkSize: number = 64 * 1024 * 1024,
    expiresIn: number = 6 * 3600
  ): Promise<MultipartUploadData> {
    if (chunkSize < 5 * 1024 * 1024) {
      throw new Error('S3 requires chunkSize >= 5 MiB');
    }
    await this.ensureBucketRegion();
    const numParts = Math.ceil(fileSize / chunkSize);
    if (numParts > 10000) {
      throw new Error(
        `File would require ${numParts} parts; S3 caps at 10,000. ` +
        `Increase chunkSize to at least ${Math.ceil(fileSize / 10000)} bytes.`
      );
    }

    const objectKey = `users/${userId}/uploads/${randomUUID()}-${filename}`;

    const created = await this.s3Client.send(
      new CreateMultipartUploadCommand({
        Bucket: this.bucket,
        Key: objectKey,
        ContentType: contentType,
        ServerSideEncryption: 'AES256',
        Tagging: buildTagging(userId, { upload_type: 'user_upload_multipart' }),
      })
    );
    const s3UploadId = created.UploadId;
    if (!s3UploadId) throw new Error('S3 did not return UploadId');

    const partUrls: string[] = [];
    for (let partNumber = 1; partNumber <= numParts; partNumber++) {
      const url = await getSignedUrl(
        this.s3Client,
        new UploadPartCommand({
          Bucket: this.bucket,
          Key: objectKey,
          UploadId: s3UploadId,
          PartNumber: partNumber,
        }),
        { expiresIn }
      );
      partUrls.push(url);
    }

    return { uploadId: s3UploadId, key: objectKey, partUrls, chunkSize, numParts };
  }

  /** Assemble the parts into a single S3 object. */
  async completeMultipartUpload(
    key: string,
    uploadId: string,
    parts: CompletedPart[]
  ): Promise<{ key: string; bucket: string; location?: string }> {
    if (!parts.length) throw new Error('completeMultipartUpload: no parts supplied');
    await this.ensureBucketRegion();
    const sorted = [...parts].sort((a, b) => a.PartNumber - b.PartNumber);
    const out = await this.s3Client.send(
      new CompleteMultipartUploadCommand({
        Bucket: this.bucket,
        Key: key,
        UploadId: uploadId,
        MultipartUpload: { Parts: sorted },
      })
    );
    return { key, bucket: this.bucket, location: out.Location };
  }

  /** List parts already uploaded for an in-flight multipart upload (used for resume). */
  async listUploadedParts(
    key: string,
    uploadId: string,
  ): Promise<Array<{ PartNumber: number; ETag: string; Size: number }>> {
    await this.ensureBucketRegion();
    const parts: Array<{ PartNumber: number; ETag: string; Size: number }> = [];
    let partNumberMarker: string | undefined;
    // ListParts is paginated (max 1 000 per page).
    for (;;) {
      const out = await this.s3Client.send(
        new ListPartsCommand({
          Bucket: this.bucket,
          Key: key,
          UploadId: uploadId,
          ...(partNumberMarker !== undefined && { PartNumberMarker: partNumberMarker }),
        }),
      );
      for (const p of out.Parts ?? []) {
        if (p.PartNumber && p.ETag) {
          parts.push({ PartNumber: p.PartNumber, ETag: p.ETag, Size: p.Size ?? 0 });
        }
      }
      if (!out.IsTruncated) break;
      partNumberMarker = out.NextPartNumberMarker;
    }
    return parts;
  }

  /**
   * Generate fresh presigned URLs for a subset of parts in an existing multipart
   * upload. Used during resume when old presigned URLs have expired (AWS S3 path).
   */
  async refreshPartUrls(
    key: string,
    uploadId: string,
    partNumbers: number[],
    chunkSize: number,
  ): Promise<string[]> {
    await this.ensureBucketRegion();
    const { getSignedUrl: gsu } = await import('@aws-sdk/s3-request-presigner');
    return Promise.all(
      partNumbers.map(n =>
        gsu(
          this.s3Client,
          new UploadPartCommand({
            Bucket: this.bucket,
            Key: key,
            UploadId: uploadId,
            PartNumber: n,
            ContentLength: chunkSize,
          }),
          { expiresIn: 6 * 3600 },
        ),
      ),
    );
  }

  /** Abort an in-flight multipart upload (frees S3 from billing the parts). */
  async abortMultipartUpload(key: string, uploadId: string): Promise<void> {
    await this.ensureBucketRegion();
    await this.s3Client.send(
      new AbortMultipartUploadCommand({
        Bucket: this.bucket,
        Key: key,
        UploadId: uploadId,
      })
    );
  }

  /**
   * Generate presigned URL for downloading a file
   */
  async generatePresignedDownloadUrl(
    key: string,
    expiresIn: number = 3600,
    /** Set to make the browser SAVE the file under this name: a presigned URL is cross-origin, so
     *  an <a download> attribute is ignored and a text file would open in the tab instead. */
    attachmentName?: string,
  ): Promise<string> {
    await this.ensureBucketRegion();
    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key: key,
      ...(attachmentName ? { ResponseContentDisposition: attachmentDisposition(attachmentName) } : {}),
    });

    return await getSignedUrl(this.s3Client, command, { expiresIn });
  }

  /**
   * Check if a file exists in S3
   */
  async fileExists(key: string): Promise<boolean> {
    try {
      const command = new HeadObjectCommand({
        Bucket: this.bucket,
        Key: key,
      });
      await this.s3Client.send(command);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Get file size in bytes
   */
  async getFileSize(key: string): Promise<number> {
    const command = new HeadObjectCommand({
      Bucket: this.bucket,
      Key: key,
    });

    const response = await this.s3Client.send(command);
    return response.ContentLength || 0;
  }

  /** Read a bounded UTF-8 prefix for an already-authorized object. */
  async readTextPrefix(key: string, maxBytes: number = 256 * 1024): Promise<string> {
    if (!key) throw new Error('S3 object key is required');
    const end = Math.max(0, Math.min(Math.floor(maxBytes), 1024 * 1024) - 1);
    const response = await this.s3Client.send(new GetObjectCommand({
      Bucket: this.bucket,
      Key: key,
      Range: `bytes=0-${end}`,
    }));
    const body: any = response.Body;
    if (!body) return '';
    if (typeof body.transformToString === 'function') return body.transformToString('utf-8');
    const chunks: Buffer[] = [];
    for await (const chunk of body) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    return Buffer.concat(chunks).toString('utf8');
  }

  /**
   * Read up to `maxBytes` of an object as raw bytes — for staging a project file into the code
   * sandbox (run_code). The Range cap bounds a huge run output so it can never flood memory or the
   * sandbox; the caller checks getFileSize() first and refuses oversized files with a clear message.
   */
  async readBuffer(key: string, maxBytes: number): Promise<Buffer> {
    if (!key) throw new Error('S3 object key is required');
    const end = Math.max(0, Math.floor(maxBytes) - 1);
    const response = await this.s3Client.send(new GetObjectCommand({
      Bucket: this.bucket,
      Key: key,
      Range: `bytes=0-${end}`,
    }));
    const body: any = response.Body;
    if (!body) return Buffer.alloc(0);
    if (typeof body.transformToByteArray === 'function') return Buffer.from(await body.transformToByteArray());
    const chunks: Buffer[] = [];
    for await (const chunk of body) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    return Buffer.concat(chunks);
  }

  /**
   * Delete a file from S3
   */
  async deleteFile(key: string): Promise<boolean> {
    try {
      const command = new DeleteObjectCommand({
        Bucket: this.bucket,
        Key: key,
      });
      await this.s3Client.send(command);
      return true;
    } catch (error) {
      console.error(`Error deleting file ${key}:`, error);
      return false;
    }
  }

  /**
   * List objects under a prefix (non-recursive — returns both files and common prefixes / "folders")
   */
  async listObjects(prefix: string): Promise<{ key: string; size: number; lastModified: Date }[]> {
    const results: { key: string; size: number; lastModified: Date }[] = [];
    let continuationToken: string | undefined;
    do {
      const command = new ListObjectsV2Command({
        Bucket: this.bucket,
        Prefix: prefix,
        ContinuationToken: continuationToken,
        MaxKeys: 1000,
      });
      const response = await this.s3Client.send(command);
      for (const obj of response.Contents ?? []) {
        if (obj.Key) {
          results.push({ key: obj.Key, size: obj.Size ?? 0, lastModified: obj.LastModified ?? new Date() });
        }
      }
      continuationToken = response.NextContinuationToken;
    } while (continuationToken);
    return results;
  }

  /**
   * Upload a buffer directly to S3 (for server-side uploads via multer disk storage)
   */
  async putObject(key: string, body: Buffer, contentType: string, userId: string): Promise<void> {
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      Body: body,
      ContentType: contentType,
      ServerSideEncryption: 'AES256',
      Tagging: buildTagging(userId, { upload_type: 'project_file' }),
    });
    await this.s3Client.send(command);
  }

  /**
   * Get the S3 bucket name
   */
  getBucketName(): string {
    return this.bucket;
  }
}

// Export singleton instance
export const s3Service = new S3Service();
