import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { randomUUID } from 'crypto';

// URL-encodes S3 object tags so the billing Lambda can identify the owning user
function buildTagging(userId: string, extra: Record<string, string> = {}): string {
  const tags: Record<string, string> = { user_id: `bm_${userId}`, ...extra };
  return Object.entries(tags).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
}

interface S3Config {
  accessKeyId: string;
  secretAccessKey: string;
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
  uploadId: string;
  key: string;
  partUrls: string[];
  chunkSize: number;
}

export class S3Service {
  private s3Client: S3Client;
  private bucket: string;

  constructor(config?: S3Config) {
    const accessKeyId = config?.accessKeyId || process.env.AWS_ACCESS_KEY_ID;
    const secretAccessKey = config?.secretAccessKey || process.env.AWS_SECRET_ACCESS_KEY;
    const region = config?.region || process.env.AWS_REGION || 'us-east-1';
    this.bucket = config?.bucket || process.env.S3_BUCKET_NAME || '';

    if (!accessKeyId || !secretAccessKey) {
      throw new Error('AWS credentials not configured');
    }

    if (!this.bucket) {
      throw new Error('S3 bucket name not configured');
    }

    this.s3Client = new S3Client({
      region,
      credentials: {
        accessKeyId,
        secretAccessKey,
      },
    });
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
   * Generate multipart upload URLs for large files (>100MB)
   */
  async generateMultipartUploadUrls(
    userId: string,
    filename: string,
    fileSize: number,
    contentType: string,
    chunkSize: number = 10 * 1024 * 1024, // 10MB chunks
    expiresIn: number = 3600
  ): Promise<MultipartUploadData> {
    const uploadId = randomUUID();
    const key = `users/${userId}/uploads/${uploadId}-${filename}`;

    // Calculate number of parts
    const numParts = Math.ceil(fileSize / chunkSize);

    // Note: For full multipart upload support, we'd need to use S3's multipart upload API
    // For P0, we'll use a simplified approach with multiple PUT requests
    const partUrls: string[] = [];

    for (let partNumber = 1; partNumber <= numParts; partNumber++) {
      const partKey = `${key}.part${partNumber}`;
      const command = new PutObjectCommand({
        Bucket: this.bucket,
        Key: partKey,
        ContentType: contentType,
        ServerSideEncryption: 'AES256',
        Tagging: buildTagging(userId, { upload_type: 'user_upload_multipart', part: String(partNumber) }),
      });

      const partUrl = await getSignedUrl(this.s3Client, command, { expiresIn });
      partUrls.push(partUrl);
    }

    return {
      uploadId,
      key,
      partUrls,
      chunkSize,
    };
  }

  /**
   * Generate presigned URL for downloading a file
   */
  async generatePresignedDownloadUrl(
    key: string,
    expiresIn: number = 3600
  ): Promise<string> {
    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key: key,
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
   * Get the S3 bucket name
   */
  getBucketName(): string {
    return this.bucket;
  }
}

// Export singleton instance
export const s3Service = new S3Service();
