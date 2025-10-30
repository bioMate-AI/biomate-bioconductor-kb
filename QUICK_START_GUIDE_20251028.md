# BioMate P0 Quick Start Guide

**Last Updated:** 2025-10-28
**Estimated Setup Time:** 30-45 minutes

---

## Prerequisites

- ✅ Node.js 18+ installed
- ✅ npm or yarn installed
- ⚠️ PostgreSQL database (see setup options below)
- ⚠️ AWS S3 bucket and credentials

---

## Step 1: Set Up PostgreSQL Database (Choose One Option)

### Option A: Neon (Recommended - Easiest & Free)

1. Go to https://neon.tech
2. Sign up (free, no credit card required)
3. Click "Create Project"
4. Copy the connection string (looks like: `postgresql://username:password@ep-xxx.us-east-1.aws.neon.tech/neondb`)
5. Save this for Step 3

### Option B: Supabase (Alternative Cloud Option)

1. Go to https://supabase.com
2. Sign up and create a new project
3. Go to Project Settings → Database
4. Copy the "Connection string" (URI)
5. Save this for Step 3

### Option C: Local PostgreSQL

```bash
# Install PostgreSQL
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib

# Start PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Create database
sudo -u postgres psql

# In PostgreSQL prompt:
CREATE DATABASE biomate_dev;
CREATE USER biomate WITH PASSWORD 'your_secure_password_here';
GRANT ALL PRIVILEGES ON DATABASE biomate_dev TO biomate;
\q

# Your connection string will be:
# postgresql://biomate:your_secure_password_here@localhost:5432/biomate_dev
```

---

## Step 2: Configure AWS S3

### If you don't have an S3 bucket yet:

```bash
# Using AWS CLI (if installed)
aws s3 mb s3://biomate-YOUR_NAME-dev --region us-east-1

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket biomate-YOUR_NAME-dev \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

Or create via AWS Console:
1. Go to https://s3.console.aws.amazon.com/
2. Click "Create bucket"
3. Name it (e.g., `biomate-yourname-dev`)
4. Enable "Server-side encryption" (AES-256)
5. Click "Create bucket"

### Get AWS Credentials:

1. Go to https://console.aws.amazon.com/iam/
2. Click "Users" → Your username → "Security credentials"
3. Click "Create access key"
4. Save the Access Key ID and Secret Access Key

---

## Step 3: Configure Environment Variables

```bash
cd /home/yzhang/biomate/frontend

# Edit the .env file
nano .env
```

Update these values:

```bash
# Replace with your database URL from Step 1
DATABASE_URL=postgresql://YOUR_DB_CONNECTION_STRING_HERE

# Replace with your AWS credentials from Step 2
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=your-secret-key
S3_BUCKET_NAME=biomate-yourname-dev

# Optional: Generate a new JWT secret
# JWT_SECRET=$(openssl rand -hex 32)
```

**Ctrl+O** to save, **Ctrl+X** to exit

---

## Step 4: Run Database Migrations

```bash
cd /home/yzhang/biomate/frontend

# Push the schema to the database (creates the users table)
npx drizzle-kit push
```

You should see:
```
✓ Applying migrations...
✓ Migration complete
```

---

## Step 5: Install Dependencies (if not already done)

```bash
cd /home/yzhang/biomate/frontend
npm install
```

---

## Step 6: Start the Development Server

```bash
cd /home/yzhang/biomate/frontend
npm run dev
```

You should see:
```
serving on port 5000
```

The application is now running at: **http://localhost:5000**

---

## Step 7: Test Authentication

### Test 1: Register a New User

Open your browser and go to http://localhost:5000

1. Click "Sign up" or go to http://localhost:5000/register
2. Fill in:
   - **Name:** Test User
   - **Email:** test@example.com
   - **Password:** SecurePass123!
3. Click "Sign Up"

You should be redirected to the dashboard with a "Trial" badge.

### Test 2: Verify in Database

```bash
# If using Neon/Supabase, use their web SQL editor
# If using local PostgreSQL:
sudo -u postgres psql -d biomate_dev

SELECT id, email, full_name, subscription_status, trial_ends_at FROM users;
```

You should see your test user with:
- `subscription_status`: `trialing`
- `trial_ends_at`: 7 days from now

### Test 3: Logout and Login Again

1. Click your profile icon → "Logout"
2. Click "Login"
3. Use the same credentials: test@example.com / SecurePass123!
4. You should be logged in successfully

---

## Step 8: Test S3 File Upload (Optional)

### Via API (using curl):

```bash
# 1. Login and get token
TOKEN=$(curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"SecurePass123!"}' \
  -c cookies.txt \
  | jq -r '.token')

echo "Token: $TOKEN"

# 2. Initialize upload
UPLOAD_DATA=$(curl -X POST http://localhost:5000/api/s3/upload/init \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "test.txt",
    "fileSize": 1024,
    "contentType": "text/plain"
  }')

echo "Upload Data: $UPLOAD_DATA"

UPLOAD_URL=$(echo $UPLOAD_DATA | jq -r '.uploadUrl')

# 3. Upload file to S3
echo "Hello BioMate!" > test.txt
curl -X PUT "$UPLOAD_URL" \
  --upload-file test.txt \
  -H "Content-Type: text/plain"

echo "✓ File uploaded successfully!"
```

### Via Frontend UI:

The file upload UI is already integrated. When logged in:
1. Go to the workflow/data upload page
2. Select a file
3. It will automatically upload to S3 using presigned URLs

---

## Troubleshooting

### Error: "DATABASE_URL environment variable is required"

**Solution:**
- Make sure `.env` file exists in `/home/yzhang/biomate/frontend/`
- Check that `DATABASE_URL` is set and not commented out
- Verify the connection string format

### Error: "relation \"users\" does not exist"

**Solution:**
```bash
cd /home/yzhang/biomate/frontend
npx drizzle-kit push
```

### Error: "AWS credentials not configured"

**Solution:**
- Check that `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set in `.env`
- Verify credentials are valid: `aws sts get-caller-identity`

### Error: "Connection refused" to database

**Solution:**
- **If using Neon/Supabase:** Check your connection string is correct
- **If using local PostgreSQL:**
  ```bash
  sudo systemctl status postgresql
  sudo systemctl start postgresql
  ```

### Error: "Email already registered"

**Solution:** This is expected if you've already registered with that email. Either:
- Use a different email
- Or delete the user:
  ```sql
  DELETE FROM users WHERE email = 'test@example.com';
  ```

---

## What's Working Now

✅ **Authentication:**
- User registration with email/password
- Login/logout
- JWT token authentication
- 7-day trial management
- Password hashing with bcrypt
- HTTP-only cookies for security

✅ **Data Management:**
- S3 presigned URLs for upload
- Simple uploads for files < 100MB
- Multipart upload support for files > 100MB
- Presigned URLs for downloads
- User-scoped storage

✅ **Frontend:**
- Login page with real API integration
- Register page with real API integration
- Auth context with token validation
- Auto-login on page refresh
- Subscription status display

---

## Next Steps

Now that authentication and S3 are working, you can:

1. **Test workflow execution** with Galaxy backend
2. **Add more users** to test multi-user support
3. **Configure S3 lifecycle policies** to reduce costs
4. **Set up monitoring** for database and S3 usage
5. **Implement additional P1 features** (Chatboard, ToolUniverse, etc.)

---

## Need Help?

### Check Logs

```bash
# Frontend server logs
cd /home/yzhang/biomate/frontend
npm run dev
# Watch the console output

# Database logs (local PostgreSQL)
sudo tail -f /var/log/postgresql/postgresql-*.log
```

### Test Database Connection

```bash
# Test PostgreSQL connection
psql "$DATABASE_URL"

# If successful, you'll see:
# psql (XX.X)
# Type "help" for help.
```

### Verify Environment Variables

```bash
cd /home/yzhang/biomate/frontend
grep -v '^#' .env | grep -v '^$'
```

---

## Security Checklist

Before deploying to production:

- [ ] Generate a new `JWT_SECRET`: `openssl rand -hex 32`
- [ ] Use a strong database password
- [ ] Enable S3 bucket versioning
- [ ] Configure S3 CORS for your domain
- [ ] Set up S3 lifecycle policies
- [ ] Enable CloudWatch monitoring
- [ ] Use HTTPS (get SSL certificate)
- [ ] Set `NODE_ENV=production`
- [ ] Review IAM permissions for AWS credentials

---

## Architecture Diagram

```
┌──────────────┐
│   Browser    │
│  (Frontend)  │
└──────┬───────┘
       │ HTTPS
       ↓
┌──────────────────────────────┐
│   Express Server (Port 5000) │
│  ┌────────────────────────┐  │
│  │  Auth Routes           │  │
│  │  /api/auth/*          │  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │  S3 Routes             │  │
│  │  /api/s3/*            │  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │  Auth Middleware       │  │
│  │  JWT Verification      │  │
│  └────────────────────────┘  │
└───────┬───────────┬──────────┘
        │           │
        ↓           ↓
┌──────────────┐  ┌──────────────┐
│  PostgreSQL  │  │    AWS S3    │
│  (Users DB)  │  │  (Files)     │
└──────────────┘  └──────────────┘
```

---

**Setup Complete!** You now have a fully functional authentication and data management system for BioMate. 🎉
