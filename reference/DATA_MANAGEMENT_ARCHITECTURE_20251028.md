# BioMate Data Management Architecture

**Document Created:** 2025-10-28
**Priority:** P0 - Critical for Launch
**Status:** Architecture Specification
**Estimated Implementation:** 3-4 days

---

## Executive Summary

This document defines the data management architecture for BioMate platform, covering cloud storage, file transfer, data lifecycle, and cost optimization. The architecture must handle large genomics files (10GB-10TB), ensure HIPAA compliance, support multi-user access, and scale cost-effectively.

**Key Decisions:**
- **Cloud Provider:** AWS (S3 for storage, CloudFront for CDN)
- **Upload Protocol:** Multipart upload with chunking and resume capability
- **Data Lifecycle:** Automated tiering (S3 Standard → Intelligent-Tiering → Glacier)
- **Cost Strategy:** 1.5-2.5x markup on storage, aggressive lifecycle policies

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Cloud Storage Strategy](#cloud-storage-strategy)
3. [File Upload/Download Protocols](#file-uploaddownload-protocols)
4. [Data Lifecycle Management](#data-lifecycle-management)
5. [Security & Compliance](#security--compliance)
6. [Cost Optimization](#cost-optimization)
7. [Implementation Plan](#implementation-plan)
8. [Performance Targets](#performance-targets)
9. [Risk Mitigation](#risk-mitigation)

---

## Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         BioMate Platform                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   Frontend   │───▶│   Backend    │───▶│   Workflow   │      │
│  │  (Browser)   │    │   (Node.js)  │    │   (Galaxy)   │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                    │                    │              │
│         │                    │                    │              │
│         ▼                    ▼                    ▼              │
│  ┌──────────────────────────────────────────────────────┐      │
│  │              AWS Infrastructure                       │      │
│  │                                                        │      │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │      │
│  │  │    S3    │  │CloudFront│  │ Lifecycle│           │      │
│  │  │ Standard │─▶│   (CDN)  │  │ Manager  │           │      │
│  │  └──────────┘  └──────────┘  └──────────┘           │      │
│  │       │              │              │                 │      │
│  │       │              │              ▼                 │      │
│  │       │         ┌────────────────────────┐           │      │
│  │       │         │  S3 Intelligent-Tiering │          │      │
│  │       │         └────────────────────────┘           │      │
│  │       │                     │                         │      │
│  │       │                     ▼                         │      │
│  │       │         ┌────────────────────────┐           │      │
│  │       │         │    S3 Glacier Deep     │           │      │
│  │       │         │       Archive          │           │      │
│  │       │         └────────────────────────┘           │      │
│  │       │                                               │      │
│  │       ▼                                               │      │
│  │  ┌──────────┐                                        │      │
│  │  │ DynamoDB │ (Metadata, access logs)                │      │
│  │  └──────────┘                                        │      │
│  │                                                        │      │
│  └────────────────────────────────────────────────────────┘      │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    External Data Sources                         │
├─────────────────────────────────────────────────────────────────┤
│  • Lab Instruments (LIMS/OpenELIS/SENAITE)                      │
│  • User Local Files                                              │
│  • Public Repositories (SRA, GEO, TCGA)                         │
│  • Cloud Storage (User's own S3/Azure/GCS buckets)              │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Upload:** User → Frontend → Presigned S3 URL → S3 Standard
2. **Processing:** Galaxy downloads from S3 → Computes → Uploads results to S3
3. **Download:** User requests → Backend generates presigned URL → User downloads
4. **Lifecycle:** S3 Lifecycle policies automatically tier data based on age/access

---

## Cloud Storage Strategy

### Provider Selection: AWS

**Why AWS:**
- Industry standard for genomics (NCBI SRA, 1000 Genomes all on AWS)
- Best support for large files (S3 multipart up to 5TB per file)
- Intelligent-Tiering automates cost optimization
- Galaxy has excellent AWS integration
- HIPAA-compliant BAA available

**Alternatives Considered:**
- **Azure Blob:** Good for Microsoft shops, but less genomics ecosystem
- **Google Cloud Storage:** Excellent for BigQuery integration, but smaller genomics presence
- **Multi-cloud:** Too complex for MVP, defer to P3

### Storage Classes

| Storage Class | Use Case | Cost (GB/month) | Retrieval Time | Lifecycle Trigger |
|---------------|----------|-----------------|----------------|-------------------|
| **S3 Standard** | Active datasets, workflow inputs/outputs | $0.023 | Instant | New uploads |
| **S3 Intelligent-Tiering** | Workflows completed, may reuse | $0.023-0.0125 | Instant | After 30 days |
| **S3 Glacier Instant Retrieval** | Archived results, rarely accessed | $0.004 | Instant | After 90 days |
| **S3 Glacier Deep Archive** | Long-term compliance storage | $0.00099 | 12 hours | After 180 days |

**Default Policy:**
- Days 0-30: S3 Standard
- Days 31-90: S3 Intelligent-Tiering (automatic optimization)
- Days 91-180: Glacier Instant Retrieval
- Days 181+: Glacier Deep Archive

**User Override:** Users can configure custom lifecycle policies per project.

### Bucket Structure

```
biomate-production/
├── users/
│   ├── {user_id}/
│   │   ├── uploads/           # User uploaded files
│   │   ├── datasets/          # Processed datasets
│   │   └── results/           # Workflow outputs
│   └── shared/                # Shared datasets across users
├── workflows/
│   ├── inputs/                # Workflow input staging
│   ├── outputs/               # Workflow outputs
│   └── temp/                  # Temporary processing files (delete after 7 days)
├── reference/                 # Reference genomes, databases
│   ├── genomes/
│   ├── annotations/
│   └── databases/
└── system/
    ├── logs/                  # System logs
    └── backups/               # Database backups
```

**Permissions:**
- Users can read/write only their own `users/{user_id}/` folders
- Galaxy has read/write access to `workflows/` and `users/` (via IAM role)
- Reference data is read-only for all users
- System data is admin-only

---

## File Upload/Download Protocols

### Upload Architecture

**Approach: Presigned URLs with Multipart Upload**

**Why Presigned URLs:**
- Eliminates backend as bottleneck (user uploads directly to S3)
- Scalable (no backend bandwidth limits)
- Secure (time-limited, scoped permissions)
- Cost-effective (no data transfer through backend)

**Implementation:**

```typescript
// Backend generates presigned URL
POST /api/upload/init
{
  "filename": "sample_R1.fastq.gz",
  "fileSize": 5368709120,  // 5GB
  "contentType": "application/gzip",
  "projectId": "proj_12345"
}

Response:
{
  "uploadId": "upload_abc123",
  "uploadUrl": "https://biomate-production.s3.amazonaws.com/...",
  "expiresIn": 3600,  // 1 hour
  "chunkSize": 10485760,  // 10MB chunks
  "multipart": {
    "uploadId": "aws_multipart_xyz",
    "partUrls": [
      "https://...",  // URLs for each part
      "https://...",
      // ... 512 parts for 5GB file
    ]
  }
}
```

**Frontend Upload Flow:**

```typescript
// 1. Initialize upload
const { uploadId, partUrls, chunkSize } = await initUpload(file);

// 2. Split file into chunks
const chunks = splitFileIntoChunks(file, chunkSize);

// 3. Upload chunks in parallel (max 5 concurrent)
const parts = await Promise.all(
  chunks.map((chunk, index) =>
    uploadChunk(chunk, partUrls[index], index + 1)
  )
);

// 4. Complete multipart upload
await completeUpload(uploadId, parts);
```

**Features:**
- **Chunking:** 10MB chunks (configurable, AWS allows 5MB-5GB per chunk)
- **Parallelization:** Up to 5 concurrent chunk uploads
- **Resume Capability:** Store uploaded parts, retry only failed chunks
- **Progress Tracking:** Report progress per chunk
- **Validation:** MD5 checksum per chunk, verify integrity

### Download Architecture

**Approach: Presigned URLs with Streaming**

**Implementation:**

```typescript
GET /api/download/{fileId}

Response:
{
  "downloadUrl": "https://biomate-production.s3.amazonaws.com/...",
  "expiresIn": 3600,  // 1 hour
  "filename": "results.bam",
  "fileSize": 10737418240,  // 10GB
  "contentType": "application/octet-stream"
}
```

**Features:**
- **CDN Acceleration:** CloudFront for frequently accessed files (reference genomes)
- **Byte-Range Requests:** Support partial downloads (resume capability)
- **Compression:** Gzip on-the-fly for text files (BAM, SAM, VCF)
- **Expiration:** 1-hour URLs (prevents sharing, ensures access control)

### Progress Tracking

**Database Schema (DynamoDB):**

```json
{
  "uploadId": "upload_abc123",
  "userId": "user_12345",
  "filename": "sample_R1.fastq.gz",
  "fileSize": 5368709120,
  "status": "uploading",  // uploading | completed | failed
  "progress": {
    "bytesUploaded": 1073741824,  // 1GB
    "percentComplete": 20,
    "chunksCompleted": [1, 2, 3, 4, 5],
    "chunksFailed": [],
    "startTime": "2025-10-28T10:00:00Z",
    "lastUpdate": "2025-10-28T10:05:00Z"
  },
  "s3Key": "users/user_12345/uploads/sample_R1.fastq.gz",
  "metadata": {
    "projectId": "proj_12345",
    "contentType": "application/gzip",
    "md5Checksum": "abc123..."
  }
}
```

**Real-time Updates:** WebSocket connection pushes progress to frontend.

---

## Data Lifecycle Management

### Automated Tiering

**S3 Lifecycle Policy:**

```json
{
  "Rules": [
    {
      "Id": "TierUserData",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "users/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "INTELLIGENT_TIERING"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER_IR"
        },
        {
          "Days": 180,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ]
    },
    {
      "Id": "DeleteTempFiles",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "workflows/temp/"
      },
      "Expiration": {
        "Days": 7
      }
    },
    {
      "Id": "ArchiveReferencePermanently",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "reference/"
      },
      "Transitions": [
        {
          "Days": 0,
          "StorageClass": "GLACIER_IR"
        }
      ]
    }
  ]
}
```

### User-Configurable Policies

**Interface:**

```typescript
// Users can configure per-project policies
PUT /api/projects/{projectId}/lifecycle
{
  "policy": "aggressive",  // aggressive | standard | archive | custom
  "retentionDays": 365,    // Delete after 1 year
  "archiveAfterDays": 90   // Move to Deep Archive after 90 days
}

Presets:
- aggressive: Standard (7d) → Glacier (30d) → Deep Archive (90d)
- standard: Standard (30d) → Intelligent-Tiering (90d) → Glacier (180d)
- archive: Standard (90d) → Deep Archive (180d)
- custom: User-defined
```

### Data Deletion

**Soft Delete (Default):**
- Mark file as deleted in DynamoDB
- Move to `deleted/` prefix in S3
- Permanent deletion after 30 days
- User can restore within 30 days

**Permanent Delete (GDPR/User Request):**
- Immediate deletion from S3
- Metadata purged from DynamoDB
- No recovery possible

---

## Security & Compliance

### HIPAA Compliance

**Requirements:**
1. ✅ **Encryption at Rest:** S3 SSE-S3 (AES-256) or SSE-KMS
2. ✅ **Encryption in Transit:** TLS 1.2+ for all transfers
3. ✅ **Access Logging:** S3 access logs to separate bucket
4. ✅ **BAA with AWS:** Signed before handling PHI
5. ✅ **Access Controls:** IAM policies, bucket policies, presigned URLs

**Implementation:**

```json
// S3 Bucket Policy (enforces encryption, logging, HTTPS)
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedObjectUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::biomate-production/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "AES256"
        }
      }
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::biomate-production",
        "arn:aws:s3:::biomate-production/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**KMS Encryption (P1 - Post-Launch):**
- Use AWS KMS for customer-managed keys
- Separate keys per customer (enterprise customers)
- Key rotation every 90 days
- Audit trail via CloudTrail

### Access Control

**IAM Roles:**

```yaml
# Galaxy Workflow Role
GalaxyWorkflowRole:
  Permissions:
    - s3:GetObject (users/*, workflows/*, reference/*)
    - s3:PutObject (workflows/*, users/*/results/*)
    - s3:DeleteObject (workflows/temp/*)

# Backend API Role
BackendAPIRole:
  Permissions:
    - s3:GetObject (users/*)
    - s3:PutObject (users/*)
    - s3:DeleteObject (users/*)
    - s3:GeneratePresignedUrl (*)

# User Role (via presigned URLs only)
UserRole:
  Permissions:
    - NONE (all access via time-limited presigned URLs)
```

### Audit Logging

**S3 Access Logs:**
- Log all requests to separate bucket (`biomate-logs`)
- Retain for 90 days (compliance requirement)
- Analyze via AWS Athena for security monitoring

**DynamoDB Event Logging:**
- Track all file uploads, downloads, deletions
- User attribution (userId, timestamp, action)
- Compliance reporting (who accessed what PHI data)

---

## Cost Optimization

### Storage Costs

**Assumptions (per pilot customer):**
- Average dataset: 50GB per upload
- 10 uploads per month
- 100 workflow executions per month
- 500GB total storage per customer

**Monthly Costs (per customer):**

| Component | Volume | Unit Cost | Total Cost |
|-----------|--------|-----------|------------|
| S3 Standard (0-30 days) | 250GB | $0.023/GB | $5.75 |
| Intelligent-Tiering (31-90 days) | 150GB | $0.018/GB | $2.70 |
| Glacier IR (91+ days) | 100GB | $0.004/GB | $0.40 |
| Data Transfer Out | 50GB | $0.09/GB | $4.50 |
| API Requests | 10,000 | $0.005/1000 | $0.05 |
| **Total** | - | - | **$13.40** |

**Customer Pricing:**
- Charge $25-50/month per customer for storage (1.8-3.7x markup)
- Additional overage charges: $0.10/GB over 500GB

### Transfer Optimization

**CloudFront CDN:**
- Cache reference genomes (hg38, GRCh38, mm10)
- Cache common tool outputs (e.g., pre-built indices)
- Reduce S3 data transfer costs by 60-80%

**S3 Transfer Acceleration:**
- Enable for large uploads (>1GB)
- Routes upload through AWS edge locations
- 50-500% faster for international users
- Cost: +$0.04-0.08/GB (worth it for user experience)

### Lifecycle Cost Savings

**Scenario: 1TB dataset over 1 year**

| Storage Class | Duration | Cost |
|---------------|----------|------|
| S3 Standard (30 days) | $23.00 | $23.00 |
| Intelligent-Tiering (60 days) | $18.00/month × 2 | $36.00 |
| Glacier IR (90 days) | $4.00/month × 3 | $12.00 |
| Deep Archive (185 days) | $0.99/month × 6 | $5.94 |
| **Total** | - | **$76.94** |

**Without Lifecycle:** $23/month × 12 = $276
**Savings:** $199.06 (72% reduction)

---

## Implementation Plan

### Phase 1: MVP (Days 1-4) - P0 Critical

**Day 1:**
- [ ] Set up AWS account and S3 bucket
- [ ] Configure bucket policies (encryption, HTTPS)
- [ ] Create IAM roles (Galaxy, Backend, Users)
- [ ] Enable S3 access logging

**Day 2:**
- [ ] Implement presigned URL generation (backend)
- [ ] Implement multipart upload (frontend)
- [ ] Create DynamoDB table for upload tracking
- [ ] WebSocket integration for progress updates

**Day 3:**
- [ ] Implement download via presigned URLs
- [ ] Add chunked upload resume capability
- [ ] File validation (MD5 checksum)
- [ ] Basic error handling

**Day 4:**
- [ ] Testing with 1GB, 10GB, 100GB files
- [ ] Performance benchmarking
- [ ] Documentation
- [ ] Deploy to staging

**Deliverable:** Functional upload/download with large file support

---

### Phase 2: Lifecycle & Optimization (Week 2-3) - P1

**Week 2:**
- [ ] Configure S3 lifecycle policies
- [ ] CloudFront CDN for reference data
- [ ] S3 Transfer Acceleration for uploads
- [ ] Cost tracking dashboard

**Week 3:**
- [ ] User-configurable lifecycle policies
- [ ] Soft delete implementation
- [ ] Storage usage reporting per user
- [ ] Cost attribution and billing integration

---

### Phase 3: Advanced Features (Month 2-3) - P2

**Month 2:**
- [ ] KMS encryption for enterprise customers
- [ ] Cross-region replication (disaster recovery)
- [ ] S3 Select for querying large files
- [ ] Integration with user's own cloud storage

**Month 3:**
- [ ] Multi-cloud support (Azure, GCS)
- [ ] Data export to public repositories (SRA, GEO)
- [ ] Advanced audit reporting
- [ ] GDPR compliance features (data portability, right to be forgotten)

---

## Performance Targets

### Upload Performance

| File Size | Target Time (95th percentile) | Max Concurrent Users |
|-----------|-------------------------------|----------------------|
| 1GB | 2 minutes (100 Mbps) | 100 |
| 10GB | 15 minutes (100 Mbps) | 50 |
| 100GB | 2 hours (100 Mbps) | 10 |
| 1TB | 20 hours (100 Mbps) | 5 |

**Assumptions:** 100 Mbps network (typical lab connection)

### Download Performance

| File Size | Target Time (95th percentile) | CDN Hit Rate |
|-----------|-------------------------------|--------------|
| 10MB (results summary) | 5 seconds | N/A |
| 100MB (small BAM) | 30 seconds | N/A |
| 1GB (medium BAM) | 2 minutes | N/A |
| 10GB (large BAM) | 15 minutes | N/A |

**Reference Data (CDN):** 95%+ cache hit rate, <1 second latency

### Reliability

- **Uptime:** 99.9% (AWS S3 SLA)
- **Durability:** 99.999999999% (11 nines, AWS S3 guarantee)
- **Data Loss:** Zero tolerance (multi-AZ replication)

---

## Risk Mitigation

### Risk 1: Large File Upload Failures

**Risk:** Users upload 100GB+ files, network interruptions cause failures

**Mitigation:**
- ✅ Multipart upload with resume capability
- ✅ Store completed chunks, only retry failed chunks
- ✅ 24-hour presigned URL expiration (plenty of time)
- ✅ Retry logic with exponential backoff

**Fallback:** Manual upload via AWS CLI (for extreme cases >1TB)

---

### Risk 2: Cost Overruns

**Risk:** Users upload massive datasets, costs spiral out of control

**Mitigation:**
- ✅ User quota limits (500GB free tier, then overage charges)
- ✅ Automated lifecycle policies (aggressive archiving)
- ✅ Cost monitoring dashboard with alerts
- ✅ Require credit card for >1TB storage

**Fallback:** Manual review and approval for >5TB uploads

---

### Risk 3: HIPAA Violation

**Risk:** Unencrypted data, unauthorized access, audit trail gaps

**Mitigation:**
- ✅ Bucket policy enforces encryption (reject unencrypted uploads)
- ✅ Presigned URLs expire in 1 hour (prevents link sharing)
- ✅ S3 access logs capture all requests
- ✅ DynamoDB audit trail for all file operations
- ✅ AWS BAA signed before launch

**Fallback:** Immediate incident response plan, notify affected users within 24 hours

---

### Risk 4: Data Loss

**Risk:** Accidental deletion, corruption, disaster

**Mitigation:**
- ✅ S3 versioning enabled (retain all versions)
- ✅ Soft delete with 30-day recovery window
- ✅ Cross-region replication (P2, for critical data)
- ✅ Daily backups of DynamoDB metadata

**Fallback:** Restore from S3 versioning or cross-region replica

---

## Alternatives Considered

### Alternative 1: Self-Hosted Storage (MinIO)

**Pros:**
- Lower cost for massive datasets (>100TB)
- Full control over infrastructure
- No vendor lock-in

**Cons:**
- Complex infrastructure management (maintenance burden)
- No automatic lifecycle management
- Scalability limits (hardware constraints)
- HIPAA compliance harder (self-managed security)

**Decision:** Reject for MVP, reconsider at >100TB scale

---

### Alternative 2: Azure Blob Storage

**Pros:**
- Good for Microsoft-heavy customers
- Competitive pricing
- Excellent .NET integration

**Cons:**
- Smaller genomics ecosystem than AWS
- Less familiarity in bioinformatics community
- Galaxy integration less mature

**Decision:** Defer to P3 multi-cloud support

---

### Alternative 3: User's Own Cloud Storage

**Pros:**
- Zero storage costs for BioMate
- User retains full control
- Compliance (user's responsibility)

**Cons:**
- Complex integration (S3, Azure, GCS, on-prem)
- IAM cross-account permissions (security risk)
- Performance unpredictable (user's bandwidth)

**Decision:** Offer as P2 feature for enterprise customers

---

## Success Metrics

### Launch (Week 2)
- ✅ Successfully upload and download files up to 100GB
- ✅ <5% upload failure rate
- ✅ <2 minute upload time for 1GB files (95th percentile)
- ✅ Zero security incidents

### Month 1
- ✅ 50+ successful uploads >10GB
- ✅ 95%+ user satisfaction with upload/download speed
- ✅ <$20/customer/month storage costs
- ✅ CloudFront CDN hit rate >90% for reference data

### Month 3
- ✅ Support 100+ concurrent users
- ✅ 1PB total storage managed
- ✅ 70%+ cost savings via lifecycle policies
- ✅ Zero data loss incidents

---

## Appendix

### Useful AWS Services

**For MVP:**
- S3 (storage)
- CloudFront (CDN)
- DynamoDB (metadata)
- IAM (access control)

**For P1-P2:**
- KMS (encryption keys)
- Athena (log analysis)
- CloudWatch (monitoring)
- Lambda (automation, triggers)

**For P3:**
- DataSync (hybrid cloud)
- Storage Gateway (on-prem integration)
- Snowball (physical data transfer for >10TB)

### Reference Genomes (Commonly Used)

| Genome | Size | Storage Class | Update Frequency |
|--------|------|---------------|------------------|
| hg38 (human) | 3.2GB | Glacier IR | Yearly |
| GRCh38 (human) | 3.2GB | Glacier IR | Yearly |
| mm10 (mouse) | 2.7GB | Glacier IR | Yearly |
| GRCm39 (mouse) | 2.7GB | Glacier IR | Yearly |

**Strategy:** Pre-load to S3, cache via CloudFront, never delete

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Next Review:** Before implementation (Week 1, Day 1)
**Owner:** BioMate Engineering Team
