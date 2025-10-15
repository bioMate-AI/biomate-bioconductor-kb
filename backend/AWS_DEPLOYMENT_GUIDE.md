# BioMate AWS Deployment Guide
**Single EC2 Instance Deployment (Budget: $30/month)**
**Last Updated: October 15, 2025**

This guide will help you deploy the entire BioMate system on a single AWS EC2 instance.

## Prerequisites ✅
- [x] AWS Account
- [x] AWS CLI installed and configured
- [x] Domain name registered
- [x] SSH key pair for EC2 access

---

## Step 1: Launch EC2 Instance

### 1.1 Choose the Right Instance Type
For a budget of $30/month, we'll use **t3.medium** (2 vCPU, 4 GB RAM):
- Cost: ~$30/month
- Sufficient for moderate traffic
- Free tier eligible for first 12 months (if applicable)

### 1.2 Launch Instance via AWS CLI

```bash
# Set your variables
REGION="us-east-1"  # Change to your preferred region
KEY_NAME="biomate-key"  # Your SSH key pair name
SECURITY_GROUP_NAME="biomate-sg"

# Create security group
aws ec2 create-security-group \
  --group-name $SECURITY_GROUP_NAME \
  --description "Security group for BioMate application" \
  --region $REGION

# Get the security group ID
SG_ID=$(aws ec2 describe-security-groups \
  --group-names $SECURITY_GROUP_NAME \
  --region $REGION \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# Add inbound rules
# SSH (port 22)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region $REGION

# HTTP (port 80)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region $REGION

# HTTPS (port 443)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --region $REGION

# Launch Ubuntu 22.04 LTS instance
aws ec2 run-instances \
  --image-id ami-0c7217cdde317cfec \
  --instance-type t3.medium \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --block-device-mappings DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3} \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=BioMate-Production}]' \
  --region $REGION
```

### 1.3 Get Instance IP Address

```bash
# Get the instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=BioMate-Production" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text \
  --region $REGION)

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --region $REGION)

echo "Your EC2 instance IP: $PUBLIC_IP"
```

---

## Step 2: Connect to EC2 Instance

```bash
# SSH into your instance
ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$PUBLIC_IP
```

---

## Step 3: Install Required Software

Run these commands on your EC2 instance:

### 3.1 Update System

```bash
sudo apt update && sudo apt upgrade -y
```

### 3.2 Install Docker and Docker Compose

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add ubuntu user to docker group
sudo usermod -aG docker ubuntu

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version

# Re-login to apply docker group changes
exit
```

```bash
# SSH back in
ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$PUBLIC_IP
```

### 3.3 Install Node.js and Python

```bash
# Install Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install Python 3.9 and pip
sudo apt install -y python3.9 python3.9-venv python3-pip

# Verify installations
node --version
npm --version
python3.9 --version
```

### 3.4 Install Nginx

```bash
sudo apt install -y nginx
sudo systemctl enable nginx
```

---

## Step 4: Clone and Setup Application

### 4.1 Clone Repository

```bash
# Create app directory
sudo mkdir -p /opt/biomate
sudo chown ubuntu:ubuntu /opt/biomate
cd /opt/biomate

# Clone your repository
git clone https://github.com/YOUR_USERNAME/biomate.git .
# Or use the correct repo URL

# Checkout the production branch
cd /opt/biomate/backend
git checkout frontend_backend_connection
```

### 4.2 Setup Backend (Galaxy)

```bash
cd /opt/biomate/backend

# Create Python virtual environment
python3.9 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install --upgrade pip wheel
pip install -r requirements.txt

# Copy and configure galaxy.yml
cp config/galaxy.yml.sample config/galaxy.yml

# Edit configuration
nano config/galaxy.yml
```

**Update `config/galaxy.yml`:**

```yaml
galaxy:
  # Enable AI Assistant
  enable_ai_assistant: true

  # Claude Sonnet 4.5 Configuration
  ai_llm_provider: anthropic
  ai_llm_model: claude-sonnet-4-5
  ai_llm_api_key: YOUR_ANTHROPIC_API_KEY_HERE

  # Basic Galaxy settings
  admin_users: admin@galaxy.org
  database_connection: sqlite:///./database/universe.sqlite?isolation_level=IMMEDIATE
  file_path: database/files
  new_file_path: database/tmp
  tool_dependency_dir: database/dependencies
  check_migrate_tools: false
  tool_config_file: config/tool_conf.xml.sample,config/shed_tool_conf.xml

  # Memory optimization
  preload_tool_panel: false

gravity:
  gunicorn:
    workers: 2  # Adjust based on your instance size
    timeout: 300
    worker_class: sync
    max_requests: 1000
    max_requests_jitter: 50
    preload: false
    bind: 0.0.0.0:8080
```

### 4.3 Setup Frontend

```bash
cd /opt/biomate/frontend/client

# Install dependencies
npm install

# Create production build
npm run build
```

---

## Step 5: Setup Environment Variables

```bash
# Create .env file for backend
cat > /opt/biomate/backend/.env << 'EOF'
ANTHROPIC_API_KEY=your_anthropic_api_key_here
GALAXY_CONFIG_FILE=/opt/biomate/backend/config/galaxy.yml
EOF

# Create .env file for frontend (if needed)
cat > /opt/biomate/frontend/client/.env.production << 'EOF'
VITE_API_BASE_URL=https://yourdomain.com/api
VITE_GALAXY_URL=https://yourdomain.com
EOF
```

---

## Step 6: Create Systemd Services

### 6.1 Galaxy Backend Service

```bash
sudo nano /etc/systemd/system/biomate-galaxy.service
```

```ini
[Unit]
Description=BioMate Galaxy Backend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/biomate/backend
Environment="PATH=/opt/biomate/backend/.venv/bin:/usr/local/bin:/usr/bin:/bin"
Environment="GALAXY_CONFIG_FILE=/opt/biomate/backend/config/galaxy.yml"
EnvironmentFile=/opt/biomate/backend/.env
ExecStart=/opt/biomate/backend/.venv/bin/python /opt/biomate/backend/run.sh start --daemon
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### 6.2 Frontend Service (Production Build with Serve)

```bash
# Install serve globally
sudo npm install -g serve

sudo nano /etc/systemd/system/biomate-frontend.service
```

```ini
[Unit]
Description=BioMate Frontend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/biomate/frontend/client
ExecStart=/usr/bin/serve -s dist -l 5173
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### 6.3 Enable and Start Services

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable services to start on boot
sudo systemctl enable biomate-galaxy
sudo systemctl enable biomate-frontend

# Start services
sudo systemctl start biomate-galaxy
sudo systemctl start biomate-frontend

# Check status
sudo systemctl status biomate-galaxy
sudo systemctl status biomate-frontend
```

---

## Step 7: Configure Nginx Reverse Proxy

### 7.1 Create Nginx Configuration

```bash
sudo nano /etc/nginx/sites-available/biomate
```

```nginx
# Rate limiting
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=general_limit:10m rate=30r/s;

# Upstream servers
upstream galaxy_backend {
    server 127.0.0.1:8080;
}

upstream frontend {
    server 127.0.0.1:5173;
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name yourdomain.com www.yourdomain.com;

    # SSL certificates (will be set up with Certbot)
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Max upload size
    client_max_body_size 100M;

    # Frontend (React app)
    location / {
        limit_req zone=general_limit burst=20 nodelay;

        proxy_pass http://frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Galaxy API
    location /api/ {
        limit_req zone=api_limit burst=5 nodelay;

        proxy_pass http://galaxy_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts for AI operations
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }

    # Static files
    location /static/ {
        alias /opt/biomate/backend/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

### 7.2 Enable Nginx Configuration

```bash
# Create symlink
sudo ln -s /etc/nginx/sites-available/biomate /etc/nginx/sites-enabled/

# Remove default site
sudo rm /etc/nginx/sites-enabled/default

# Test configuration
sudo nginx -t

# Don't restart yet - we need SSL certificates first
```

---

## Step 8: Setup SSL with Let's Encrypt

### 8.1 Install Certbot

```bash
sudo apt install -y certbot python3-certbot-nginx
```

### 8.2 Create Certbot Directory

```bash
sudo mkdir -p /var/www/certbot
```

### 8.3 Point Your Domain to EC2

**Before running Certbot, update your domain's DNS:**

1. Go to your domain registrar's DNS management
2. Add an A record:
   - Name: `@` (or yourdomain.com)
   - Type: `A`
   - Value: Your EC2 Public IP
   - TTL: 300
3. Add CNAME for www (optional):
   - Name: `www`
   - Type: `CNAME`
   - Value: `yourdomain.com`

**Wait 5-10 minutes for DNS propagation**, then verify:

```bash
# Check DNS propagation
nslookup yourdomain.com
```

### 8.4 Obtain SSL Certificate

```bash
# Temporarily start Nginx without SSL
sudo sed -i 's/listen 443 ssl/listen 443/' /etc/nginx/sites-available/biomate
sudo sed -i 's/ssl_certificate/#ssl_certificate/' /etc/nginx/sites-available/biomate
sudo nginx -t && sudo systemctl restart nginx

# Obtain certificate
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com

# Restore SSL config
sudo nano /etc/nginx/sites-available/biomate
# (Uncomment the SSL lines we commented out)

# Restart Nginx
sudo nginx -t && sudo systemctl restart nginx
```

### 8.5 Auto-Renewal

```bash
# Test renewal
sudo certbot renew --dry-run

# Certbot auto-renewal is already set up via systemd timer
sudo systemctl status certbot.timer
```

---

## Step 9: Database Setup

### 9.1 Initialize Galaxy Database

```bash
cd /opt/biomate/backend
source .venv/bin/activate

# Initialize database
./run.sh start
sleep 30
./run.sh stop

# Copy tools database
cp /path/to/galaxy_ai_tools.db /opt/biomate/backend/
```

---

## Step 10: Final Checks and Monitoring

### 10.1 Check All Services

```bash
# Check service status
sudo systemctl status biomate-galaxy
sudo systemctl status biomate-frontend
sudo systemctl status nginx

# Check logs
sudo journalctl -u biomate-galaxy -f
sudo journalctl -u biomate-frontend -f
sudo tail -f /var/log/nginx/error.log
```

### 10.2 Test Application

```bash
# Test frontend
curl https://yourdomain.com

# Test Galaxy API
curl https://yourdomain.com/api/version

# Test AI Assistant
curl -X POST https://yourdomain.com/api/ai_assistant/generate_workflow \
  -H 'Content-Type: application/json' \
  -d '{"request_text":"DIA-LCMS proteomics analysis"}'
```

### 10.3 Setup CloudWatch Monitoring (Optional but Recommended)

```bash
# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb

# Configure CloudWatch agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard
```

---

## Step 11: Backup Strategy

### 11.1 Setup Daily Backups

```bash
# Create backup script
sudo nano /opt/biomate/backup.sh
```

```bash
#!/bin/bash
BACKUP_DIR="/opt/biomate/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup database
cp /opt/biomate/backend/database/universe.sqlite $BACKUP_DIR/universe_$DATE.sqlite

# Backup tool database
cp /opt/biomate/backend/galaxy_ai_tools.db $BACKUP_DIR/galaxy_ai_tools_$DATE.db

# Keep only last 7 days
find $BACKUP_DIR -name "*.sqlite" -mtime +7 -delete
find $BACKUP_DIR -name "*.db" -mtime +7 -delete

echo "Backup completed: $DATE"
```

```bash
# Make executable
sudo chmod +x /opt/biomate/backup.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/biomate/backup.sh >> /var/log/biomate-backup.log 2>&1") | crontab -
```

### 11.2 Setup S3 Backup (Optional)

```bash
# Install AWS CLI if not already installed
sudo apt install -y awscli

# Create S3 bucket
aws s3 mb s3://biomate-backups-$(date +%s) --region us-east-1

# Sync backups to S3 daily
(crontab -l 2>/dev/null; echo "0 3 * * * aws s3 sync /opt/biomate/backups s3://your-bucket-name/ --delete") | crontab -
```

---

## Cost Optimization Tips

### 1. Use Reserved Instances
If you plan to run for 1+ year, buy a Reserved Instance (save ~40%):

```bash
# Check current pricing
aws ec2 describe-reserved-instances-offerings \
  --instance-type t3.medium \
  --region us-east-1
```

### 2. Enable Cost Alerts

```bash
# Set up billing alerts in AWS Console
# Budgets → Create budget → Set threshold at $30
```

### 3. Use Auto Scaling (Future)
When traffic grows, consider auto-scaling with Application Load Balancer.

---

## Troubleshooting

### Galaxy Service Won't Start

```bash
# Check logs
sudo journalctl -u biomate-galaxy -n 100

# Check Galaxy directly
cd /opt/biomate/backend
source .venv/bin/activate
./run.sh start --daemon=False
```

### Frontend Not Loading

```bash
# Check if build was successful
ls /opt/biomate/frontend/client/dist

# Rebuild if needed
cd /opt/biomate/frontend/client
npm run build

# Restart service
sudo systemctl restart biomate-frontend
```

### SSL Certificate Issues

```bash
# Check certificate status
sudo certbot certificates

# Force renewal
sudo certbot renew --force-renewal
```

### High Memory Usage

```bash
# Check memory
free -h

# Reduce Galaxy workers in galaxy.yml
nano /opt/biomate/backend/config/galaxy.yml
# Set workers: 1

# Restart
sudo systemctl restart biomate-galaxy
```

---

## Maintenance

### Weekly Tasks
- Check disk space: `df -h`
- Review logs: `sudo journalctl --since "1 week ago"`
- Check SSL expiry: `sudo certbot certificates`

### Monthly Tasks
- Update system: `sudo apt update && sudo apt upgrade -y`
- Review backups: `ls -lh /opt/biomate/backups`
- Check AWS billing

### Quarterly Tasks
- Security audit
- Performance optimization
- Dependency updates

---

## Security Checklist

- [ ] SSH key-based authentication only (disable password auth)
- [ ] Firewall rules configured (only 22, 80, 443 open)
- [ ] SSL/TLS enabled with A+ rating
- [ ] Regular security updates
- [ ] Backups tested and working
- [ ] Monitoring and alerts set up
- [ ] Rate limiting enabled in Nginx
- [ ] Database backups encrypted

---

## Next Steps

1. ✅ Deploy application
2. ✅ Configure domain and SSL
3. ✅ Test all features
4. Set up monitoring dashboards
5. Configure log aggregation
6. Plan scaling strategy

---

## Support

If you encounter issues:
1. Check logs: `sudo journalctl -u biomate-*`
2. Review Nginx logs: `/var/log/nginx/error.log`
3. Test services individually
4. Check AWS service health dashboard

---

**Estimated Monthly Cost Breakdown:**
- EC2 t3.medium: ~$30.37/month
- EBS 30GB gp3: ~$2.40/month
- Data transfer: ~$1-2/month (minimal)
- **Total: ~$33-35/month** (slightly over budget, but minimal)

**To stay under $30:**
- Use t3.small instead (1 vCPU, 2GB RAM): ~$15.18/month
- Reduce EBS to 20GB: ~$1.60/month
- Total: ~$17-18/month ✅

Your choice: **t3.small** for budget or **t3.medium** for better performance.
