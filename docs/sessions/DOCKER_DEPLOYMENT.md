# BioMate Docker Deployment Guide

## Quick Start

### 1. Prerequisites
- Docker and Docker Compose installed
- Your Anthropic API key

### 2. Setup Environment Variables

```bash
# Copy example env file
cp .env.example .env

# Edit .env and add your API key
nano .env
```

### 3. Deploy with Docker Compose

```bash
# Build and start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

### 4. Access the Application

- **Frontend**: http://localhost:3000
- **Galaxy Backend**: http://localhost:8080
- **API Docs**: http://localhost:8080/docs

## Docker Files Overview

### `backend/Dockerfile`
- **Base**: Python 3.9-slim
- **Port**: 8080
- **Health Check**: `/api/version`
- **Key Features**:
  - Multi-stage build optimized
  - Health checks enabled
  - Volume support for database/logs

### `frontend/Dockerfile`
- **Base**: Node 18-alpine
- **Port**: 3000
- **Multi-stage Build**:
  - Stage 1: Build Vite frontend + esbuild backend
  - Stage 2: Production runtime with minimal image size

### `docker-compose.yml`
Orchestrates both services with:
- Health checks
- Automatic restart
- Volume persistence
- Network isolation

## Production Deployment

### AWS EC2 Deployment

1. **Launch EC2 Instance** (t3.small, Ubuntu 22.04)

2. **Install Docker**:
```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo usermod -aG docker ubuntu
```

3. **Clone Repository**:
```bash
git clone <your-repo>
cd biomate
```

4. **Configure Environment**:
```bash
cp .env.example .env
nano .env  # Add your ANTHROPIC_API_KEY
```

5. **Deploy**:
```bash
docker-compose up -d
```

6. **Setup Nginx Reverse Proxy** (Optional):
```nginx
server {
    listen 80;
    server_name yourdomain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    location /api/ {
        proxy_pass http://localhost:8080/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
}
```

## Docker Commands Reference

### Build
```bash
# Build all services
docker-compose build

# Build specific service
docker-compose build galaxy-backend
docker-compose build frontend
```

### Run
```bash
# Start services
docker-compose up -d

# Start with rebuild
docker-compose up -d --build

# View logs
docker-compose logs -f
docker-compose logs -f galaxy-backend
docker-compose logs -f frontend
```

### Manage
```bash
# Stop services
docker-compose stop

# Remove containers
docker-compose down

# Remove containers and volumes
docker-compose down -v

# Restart services
docker-compose restart
```

### Debug
```bash
# Execute shell in container
docker-compose exec galaxy-backend bash
docker-compose exec frontend sh

# View service status
docker-compose ps

# Inspect container
docker inspect biomate-galaxy
```

## Environment Variables

### Required
- `ANTHROPIC_API_KEY`: Your Claude API key

### Optional
- `OPENAI_API_KEY`: OpenAI fallback key
- `GALAXY_CONFIG_FILE`: Galaxy config path (default: /app/config/galaxy.yml)
- `NODE_ENV`: Node environment (default: production)
- `PORT`: Frontend port (default: 3000)
- `GALAXY_API_URL`: Backend URL for frontend (default: http://galaxy-backend:8080)

## Volume Persistence

Data is persisted in Docker volumes:
- `galaxy-database`: Galaxy tool search database
- `galaxy-logs`: Application logs

To backup:
```bash
docker-compose down
docker run --rm -v biomate_galaxy-database:/data -v $(pwd):/backup ubuntu tar czf /backup/database-backup.tar.gz -C /data .
```

To restore:
```bash
docker run --rm -v biomate_galaxy-database:/data -v $(pwd):/backup ubuntu tar xzf /backup/database-backup.tar.gz -C /data
```

## Troubleshooting

### Backend not starting
```bash
# Check logs
docker-compose logs galaxy-backend

# Common issues:
# - Missing API key: Check .env file
# - Port conflict: Change port in docker-compose.yml
# - Database permissions: Check volume permissions
```

### Frontend can't connect to backend
```bash
# Verify network
docker network ls
docker network inspect biomate_biomate-network

# Check GALAXY_API_URL in docker-compose.yml
```

### Out of memory
```bash
# Increase Docker memory limit
# Docker Desktop: Settings > Resources > Memory

# Or use smaller instance
# t3.small: 2GB RAM
# t3.medium: 4GB RAM
```

## Health Monitoring

Both services have health checks enabled:

```bash
# Check health status
docker-compose ps

# Should show "healthy" after startup
```

Backend health endpoint: `http://localhost:8080/api/version`
Frontend health check: Internal Node.js HTTP request

## Cost Estimates (AWS)

### t3.small (Budget)
- **EC2**: $15.18/month
- **EBS**: $1.60/month (20GB)
- **Total**: ~$17/month

### t3.medium (Recommended)
- **EC2**: $30.37/month
- **EBS**: $2.40/month (30GB)
- **Total**: ~$33/month

## Security Best Practices

1. **Never commit .env files** - Use .env.example
2. **Rotate API keys** regularly
3. **Use firewall rules**:
   - Only allow ports 22, 80, 443
   - Restrict SSH to known IPs
4. **Enable SSL/TLS** with Let's Encrypt
5. **Regular updates**:
   ```bash
   docker-compose pull
   docker-compose up -d
   ```

## Performance Tuning

### For t3.small (2GB RAM)
Already optimized in backend:
- Lazy loading components
- Database-only queries
- No in-memory indexing

### For Production
1. Enable Docker logging limits:
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

2. Use Redis for session storage (optional)
3. Enable gzip compression in Nginx
4. Use CDN for static assets

## Support

For issues or questions:
- Backend API docs: http://localhost:8080/docs
- Session summary: See `SESSION_SUMMARY_2025-10-15.md`
- Integration guide: See `FRONTEND_BACKEND_INTEGRATION_TODO.md`
