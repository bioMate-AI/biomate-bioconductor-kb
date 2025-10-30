# Instrument Connection Services - Deployment Guide

**Document Created:** 2025-10-29
**Purpose:** Deploy and test instrument connection services for bioMate

---

## Quick Start

Deploy all instrument services with one command:

```bash
cd /home/yzhang/biomate
docker-compose -f docker/docker-compose.instruments.yml up -d
```

**Services Started:**
- SENAITE (60+ instruments) on port 8082
- SENAITE API Wrapper on port 8083
- OpenELIS (13+ instruments) on port 8084
- OpenELIS API Wrapper on port 8085
- Unified Instrument Service on port 8086

---

## Prerequisites

### System Requirements

- Docker 20.10+
- Docker Compose 2.0+
- 8GB RAM minimum
- 50GB disk space

### Environment Variables

Create `.env` file:

```bash
# Galaxy Configuration
GALAXY_URL=http://localhost:8080
GALAXY_API_KEY=your_galaxy_api_key_here

# AWS S3 for file storage (optional)
AWS_S3_BUCKET=biomate-instruments
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-east-1

# Logging
LOG_LEVEL=INFO
```

---

## Step-by-Step Deployment

### Step 1: Prepare Network

Create bioMate network if it doesn't exist:

```bash
docker network create biomate-network
```

### Step 2: Deploy Instrument Services

```bash
cd /home/yzhang/biomate

# Deploy all services
docker-compose -f docker/docker-compose.instruments.yml up -d

# Check status
docker-compose -f docker/docker-compose.instruments.yml ps
```

Expected output:
```
NAME                        STATUS    PORTS
biomate-senaite             Up        0.0.0.0:8082->8080/tcp
biomate-senaite-api         Up        0.0.0.0:8083->8000/tcp
biomate-openelis            Up        0.0.0.0:8084->8080/tcp
biomate-openelis-db         Up        5432/tcp
biomate-openelis-api        Up        0.0.0.0:8085->8000/tcp
biomate-instrument-service  Up        0.0.0.0:8086->8000/tcp
```

### Step 3: Wait for Services to Initialize

SENAITE and OpenELIS take 1-2 minutes to start:

```bash
# Watch logs
docker-compose -f docker/docker-compose.instruments.yml logs -f

# Check health
curl http://localhost:8083/health  # SENAITE API
curl http://localhost:8085/health  # OpenELIS API
curl http://localhost:8086/health  # Unified Service
```

Wait for:
```json
{
  "status": "healthy",
  "backends": {
    "senaite": "healthy",
    "openelis": "healthy",
    "galaxy": "connected",
    "s3": "configured"
  }
}
```

---

## Testing

### Test 1: List Supported Instruments

```bash
# Via Unified Service (recommended)
curl http://localhost:8086/instruments | jq

# Via SENAITE directly
curl http://localhost:8083/instruments | jq

# Via OpenELIS directly
curl http://localhost:8085/instruments | jq
```

Expected: List of 70+ instruments

### Test 2: Import Sample File

Create test file `test_cobas.txt`:
```
Sample ID,Glucose,Creatinine,BUN
SAM001,120,1.1,18
SAM002,95,0.9,15
```

Import via API:
```bash
curl -X POST http://localhost:8086/import \
  -F "file=@test_cobas.txt" \
  -F "instrument=Cobas_C311" \
  -F "backend=auto" | jq
```

Expected response:
```json
{
  "success": true,
  "message": "Imported 2 samples",
  "backend_used": "openelis",
  "samples": [
    {
      "sample_id": "SAM001",
      "results": [
        {"test_name": "Glucose", "value": "120", "unit": "mg/dL"},
        {"test_name": "Creatinine", "value": "1.1", "unit": "mg/dL"},
        {"test_name": "BUN", "value": "18", "unit": "mg/dL"}
      ]
    }
  ],
  "galaxy_dataset_id": "abc123",
  "s3_url": "s3://biomate-instruments/2025/10/29/test_cobas.txt"
}
```

### Test 3: Backend Selection

```bash
# Force SENAITE backend
curl -X POST http://localhost:8086/import \
  -F "file=@test_file.txt" \
  -F "instrument=Sysmex_XN" \
  -F "backend=senaite" | jq

# Force OpenELIS backend
curl -X POST http://localhost:8086/import \
  -F "file=@test_file.txt" \
  -F "instrument=Cobas_C311" \
  -F "backend=openelis" | jq

# Auto-route (recommended)
curl -X POST http://localhost:8086/import \
  -F "file=@test_file.txt" \
  -F "instrument=Cobas_C311" \
  -F "backend=auto" | jq
```

---

## API Documentation

### Unified Instrument Service (Port 8086)

#### GET /health
Health check for all backends

**Response:**
```json
{
  "status": "healthy",
  "backends": {
    "senaite": "healthy",
    "openelis": "healthy",
    "galaxy": "connected",
    "s3": "configured"
  }
}
```

#### GET /instruments
List all supported instruments

**Response:**
```json
[
  {
    "manufacturer": "Roche",
    "model": "Cobas C311",
    "type": "Chemistry",
    "protocol": "File",
    "backend": "openelis"
  },
  ...
]
```

#### POST /import
Import instrument file

**Request:**
```
POST /import
Content-Type: multipart/form-data

file: <file>
instrument: Cobas_C311
backend: auto (optional, default: auto)
sample_id: SAM001 (optional, filter results)
create_galaxy_dataset: true (optional, default: true)
```

**Response:**
```json
{
  "success": true,
  "message": "Imported 2 samples",
  "backend_used": "openelis",
  "samples": [...],
  "galaxy_dataset_id": "abc123",
  "s3_url": "s3://...",
  "errors": []
}
```

#### GET /backends
List available backends

**Response:**
```json
{
  "senaite": {
    "name": "SENAITE",
    "instruments": "60+",
    "license": "GPL-2.0 (network-isolated)",
    "status": "available"
  },
  "openelis": {
    "name": "OpenELIS Global 2",
    "instruments": "13+",
    "license": "MPL-2.0 (commercial-friendly)",
    "status": "available"
  }
}
```

---

## Sample Files for Testing

### Roche Cobas C311 (Chemistry)

**File:** `cobas_c311_sample.txt`
```
H|\^&|||Roche Diagnostics^COBAS c111^001|||||||P|1|
P|1||SAM001||Smith^John||19800101|M
O|1|SAM001||^^^GLU\^^^CREA\^^^BUN|R||20251029093000
R|1|^^^GLU|120|mg/dL|||N|||
R|2|^^^CREA|1.1|mg/dL|||N|||
R|3|^^^BUN|18|mg/dL|||N|||
L|1|N
```

### Sysmex XN (Hematology)

**File:** `sysmex_xn_sample.csv`
```
Sample ID,WBC,RBC,HGB,HCT,MCV,MCH,MCHC,PLT
SAM001,7.2,4.5,14.2,42.1,93.6,31.6,33.7,250
SAM002,6.8,4.7,15.1,44.2,94.0,32.1,34.2,285
```

### Import Commands

```bash
# Cobas C311
curl -X POST http://localhost:8086/import \
  -F "file=@cobas_c311_sample.txt" \
  -F "instrument=Cobas_C311" | jq

# Sysmex XN
curl -X POST http://localhost:8086/import \
  -F "file=@sysmex_xn_sample.csv" \
  -F "instrument=Sysmex_XN" | jq
```

---

## Troubleshooting

### Issue: Services Won't Start

**Check logs:**
```bash
docker-compose -f docker/docker-compose.instruments.yml logs
```

**Common issues:**
1. Port conflicts (8082-8086 already in use)
2. Insufficient memory (need 8GB+)
3. Missing network (create biomate-network)

**Solution:**
```bash
# Stop conflicting services
docker stop $(docker ps -q)

# Recreate network
docker network rm biomate-network
docker network create biomate-network

# Restart
docker-compose -f docker/docker-compose.instruments.yml up -d
```

### Issue: SENAITE Not Responding

**Check status:**
```bash
docker logs biomate-senaite
```

**Common causes:**
- Still initializing (wait 2 minutes)
- Database corruption
- Memory limits

**Solution:**
```bash
# Restart SENAITE
docker-compose -f docker/docker-compose.instruments.yml restart senaite

# Check health
curl http://localhost:8082/senaite
```

### Issue: OpenELIS Database Error

**Check database:**
```bash
docker logs biomate-openelis-db
```

**Solution:**
```bash
# Reset database
docker-compose -f docker/docker-compose.instruments.yml down -v
docker-compose -f docker/docker-compose.instruments.yml up -d
```

### Issue: Galaxy Dataset Not Created

**Check Galaxy connection:**
```bash
# Test Galaxy API
curl http://localhost:8080/api/version?key=$GALAXY_API_KEY
```

**Solution:**
1. Verify `GALAXY_API_KEY` in `.env`
2. Ensure Galaxy is running
3. Check API key has permissions

### Issue: S3 Upload Fails

**Check AWS credentials:**
```bash
# Test S3 access
aws s3 ls s3://$AWS_S3_BUCKET
```

**Solution:**
1. Verify AWS credentials in `.env`
2. Check bucket exists
3. Verify IAM permissions

---

## Production Deployment

### Security Hardening

1. **Change Default Passwords:**
```yaml
# docker-compose.instruments.yml
senaite:
  environment:
    - ADMIN_PASSWORD=${SENAITE_PASSWORD}

openelis:
  environment:
    - DEFAULT_PW=${OPENELIS_PASSWORD}
```

2. **Enable HTTPS:**
```yaml
# Add nginx reverse proxy
nginx:
  image: nginx:alpine
  ports:
    - "443:443"
  volumes:
    - ./nginx.conf:/etc/nginx/nginx.conf
    - ./ssl:/etc/nginx/ssl
```

3. **Restrict Network Access:**
```yaml
# Internal network only
networks:
  instruments_network:
    internal: true
```

### Monitoring

**Prometheus metrics:**
```yaml
# Add to docker-compose
prometheus:
  image: prom/prometheus
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml
```

**Health check endpoints:**
- http://localhost:8086/health (Unified)
- http://localhost:8083/health (SENAITE)
- http://localhost:8085/health (OpenELIS)

### Backup

**Database backup:**
```bash
# OpenELIS database
docker exec biomate-openelis-db pg_dump -U openelis openelis > backup.sql

# SENAITE data
docker exec biomate-senaite tar czf - /data > senaite_backup.tar.gz
```

---

## Performance Tuning

### Scale Containers

```yaml
# docker-compose.instruments.yml
instrument-service:
  deploy:
    replicas: 3
  scale: 3
```

### Resource Limits

```yaml
senaite:
  deploy:
    resources:
      limits:
        cpus: '2'
        memory: 4G
      reservations:
        cpus: '1'
        memory: 2G
```

---

## Next Steps

1. **Integration with Frontend:**
   - Add instrument upload UI
   - Display parsed results
   - Trigger workflows automatically

2. **Add More Parsers:**
   - Implement direct parsers for Illumina, ONT, PacBio
   - Add custom instrument support

3. **Enhance Features:**
   - Real-time ASTM protocol support
   - Bi-directional instrument communication
   - Automated QC validation

---

## Support

- **Documentation:** `/home/yzhang/biomate/INSTRUMENT_CONNECTION_ARCHITECTURE.md`
- **GPL Isolation:** `/home/yzhang/biomate/GPL_ISOLATION_STRATEGY.md`
- **API Reference:** http://localhost:8086/docs (FastAPI Swagger UI)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-29
