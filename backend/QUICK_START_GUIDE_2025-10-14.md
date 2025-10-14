# Quick Start Guide - Authentication & Payment System

**Last Updated:** 2025-10-14
**Estimated Setup Time:** 30-60 minutes

---

## Prerequisites

- Python 3.8+ installed
- Galaxy backend running
- SQLite database (galaxy_ai_tools.db)
- Internet connection for package installation

---

## Step 1: Install Dependencies (5 minutes)

```bash
cd /Users/jingqiwang/biomate/backend

# Install required Python packages
pip install -r requirements_auth_payment.txt

# Verify installation
python3 -c "import bcrypt, jwt, stripe; print('✓ All packages installed')"
```

---

## Step 2: Run Database Migrations (5 minutes)

```bash
# IMPORTANT: Backup your database first!
cp galaxy_ai_tools.db galaxy_ai_tools.db.backup_$(date +%Y%m%d_%H%M%S)

# Preview what will change (dry run)
python3 scripts/run_migrations.py --dry-run

# If everything looks good, apply migrations
python3 scripts/run_migrations.py

# Verify migrations were applied
python3 scripts/run_migrations.py --list
```

**Expected output:**
```
✓ [APPLIED] 001_add_user_authentication_columns.sql
✓ [APPLIED] 002_add_tier1_state_tables.sql
Applied: 2/2 migrations
```

---

## Step 3: Configure Services (15-20 minutes)

### 3.1 Create Configuration File

```bash
# Copy example config
cp config/auth_payment_config.yml.example config/auth_payment_config.yml

# Edit the file
nano config/auth_payment_config.yml  # or use your preferred editor
```

### 3.2 Generate JWT Secret Key

```bash
# Generate a secure random key
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

Copy the output and paste it into `config/auth_payment_config.yml`:
```yaml
security:
  jwt_secret_key: "PASTE_YOUR_GENERATED_KEY_HERE"
```

### 3.3 Set Up Email Service (Choose One)

#### Option A: SendGrid (Recommended for Getting Started)

1. Sign up at https://sendgrid.com (free tier: 100 emails/day)
2. Create an API key: https://app.sendgrid.com/settings/api_keys
3. Add to config:
```yaml
email:
  provider: "sendgrid"
  sendgrid:
    api_key: "YOUR_SENDGRID_API_KEY_HERE"
    from_email: "noreply@yourdomain.com"
    from_name: "BioMate"
```

#### Option B: AWS SES (Better for Scale)

1. Sign up for AWS: https://aws.amazon.com
2. Verify your sender email in SES console
3. Get access key and secret from IAM
4. Add to config:
```yaml
email:
  provider: "aws_ses"
  aws_ses:
    region: "us-east-1"
    access_key_id: "YOUR_AWS_ACCESS_KEY"
    secret_access_key: "YOUR_AWS_SECRET_KEY"
    from_email: "noreply@yourdomain.com"
```

#### Option C: Development Mode (No Real Emails)

For testing without sending real emails:
```yaml
development:
  mock_email: true  # Emails will be logged but not sent
```

### 3.4 Set Up Stripe (for Payments)

1. **Sign up for Stripe:** https://stripe.com
2. **Get Test API Keys:** https://dashboard.stripe.com/test/apikeys
3. **Create Products in Dashboard:**
   - Navigate to: Products → Add Product
   - Create two products:
     - **Monthly Plan:** $20/month, recurring
     - **Annual Plan:** $200/year, recurring
   - Copy the Price IDs (start with `price_...`)

4. **Add to config:**
```yaml
stripe:
  publishable_key: "pk_test_YOUR_PUBLISHABLE_KEY"
  secret_key: "sk_test_YOUR_SECRET_KEY"
  webhook_secret: "whsec_YOUR_WEBHOOK_SECRET"  # We'll set this up later
  price_ids:
    monthly: "price_YOUR_MONTHLY_PRICE_ID"
    annual: "price_YOUR_ANNUAL_PRICE_ID"
  test_mode: true
```

5. **Set Up Webhook (Important!):**
   - Go to: https://dashboard.stripe.com/test/webhooks
   - Click "Add endpoint"
   - Endpoint URL: `https://your-domain.com/api/subscription/webhook`
   - Select events:
     - `checkout.session.completed`
     - `customer.subscription.created`
     - `customer.subscription.updated`
     - `customer.subscription.deleted`
     - `invoice.payment_succeeded`
     - `invoice.payment_failed`
   - Copy the webhook secret and add to config

### 3.5 Update App URLs

```yaml
app:
  base_url: "http://localhost:8080"      # Your backend URL
  frontend_url: "http://localhost:8081"  # Your frontend URL
```

---

## Step 4: Test the Backend APIs (10 minutes)

### 4.1 Start Galaxy Server

```bash
# Start your Galaxy server normally
# The new APIs will be automatically available
```

### 4.2 Test Registration

```bash
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "username": "testuser",
    "password": "Test1234"
  }'
```

**Expected response:**
```json
{
  "message": "Registration successful! Please check test@example.com for verification link. Your 10-day free trial has started."
}
```

### 4.3 Check Email Logs

If using mock_email mode, check the logs:
```bash
tail -f logs/auth.log
```

You should see the verification email content.

### 4.4 Verify Email (Manual for Testing)

```bash
# Get the verification token from the database
sqlite3 galaxy_ai_tools.db "SELECT verification_token FROM galaxy_user WHERE email='test@example.com';"

# Use the token to verify
curl -X POST http://localhost:8080/api/auth/verify-email \
  -H "Content-Type: application/json" \
  -d '{
    "token": "PASTE_TOKEN_HERE"
  }'
```

**Expected response:**
```json
{
  "message": "Email verified successfully"
}
```

### 4.5 Test Login

```bash
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "Test1234"
  }'
```

**Expected response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user_id": 1,
  "email": "test@example.com",
  "username": "testuser",
  "email_verified": true,
  "subscription_status": "trial",
  "trial_ends_at": "2025-10-24T12:00:00"
}
```

### 4.6 Test State Sync

```bash
# Get user state (use the token from login)
curl -X GET http://localhost:8080/api/users/1/state/all \
  -H "Authorization: Bearer YOUR_JWT_TOKEN_HERE"
```

### 4.7 Test Subscription Status

```bash
curl -X GET http://localhost:8080/api/subscription/status/1
```

**Expected response:**
```json
{
  "user_id": 1,
  "status": "trial",
  "plan_type": null,
  "trial_start": "2025-10-14T12:00:00",
  "trial_end": "2025-10-24T12:00:00",
  "stripe_customer_id": null
}
```

---

## Step 5: Verify Everything Works ✓

Run through this checklist:

- [ ] Database migrations applied successfully
- [ ] Configuration file created and edited
- [ ] JWT secret key generated and added
- [ ] Email service configured (or mock mode enabled)
- [ ] Stripe API keys added
- [ ] User can register
- [ ] Email verification works (or mock logs show email)
- [ ] User can login and get JWT token
- [ ] User state endpoints respond
- [ ] Subscription status endpoint works

---

## Common Issues & Solutions

### Issue: "ModuleNotFoundError: No module named 'bcrypt'"
**Solution:** Install dependencies: `pip install -r requirements_auth_payment.txt`

### Issue: "Database is locked"
**Solution:** Make sure Galaxy server is stopped before running migrations

### Issue: "Invalid signature" on Stripe webhook
**Solution:**
1. Verify webhook secret is correct in config
2. Make sure you're using the test webhook secret with test keys
3. Test locally with Stripe CLI: `stripe listen --forward-to localhost:8080/api/subscription/webhook`

### Issue: Emails not sending
**Solution:**
1. Check API key is correct
2. Verify from_email is verified (for AWS SES)
3. Check logs/auth.log for error messages
4. Use mock_email mode for testing: `development.mock_email: true`

### Issue: JWT token invalid
**Solution:**
1. Verify jwt_secret_key is the same in config
2. Check token hasn't expired (default 30 days)
3. Ensure Authorization header format: `Bearer <token>`

---

## Next Steps

### For Development:
1. Create frontend Vue components
2. Integrate state sync with Pinia stores
3. Add Stripe checkout flow to UI
4. Test complete user journey

### For Production:
1. Change Stripe to live mode (use pk_live_ and sk_live_ keys)
2. Set up real email service (not mock)
3. Use strong JWT secret (32+ bytes random)
4. Enable HTTPS
5. Set up proper domain for webhook endpoint
6. Configure backup strategy for database
7. Set up monitoring and alerts

---

## Useful Commands

### Database Management
```bash
# View migration status
python3 scripts/run_migrations.py --list

# Rollback last migration (careful!)
python3 scripts/run_migrations.py --rollback 1

# Check database size
ls -lh galaxy_ai_tools.db

# Query users
sqlite3 galaxy_ai_tools.db "SELECT id, email, username, subscription_status FROM galaxy_user;"
```

### Testing & Debugging
```bash
# Watch auth logs
tail -f logs/auth.log

# Watch payment logs
tail -f logs/payment.log

# Watch state sync logs
tail -f logs/state_sync.log

# Test Stripe webhooks locally
stripe listen --forward-to localhost:8080/api/subscription/webhook
```

### API Testing with curl
```bash
# Register user
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","username":"user","password":"Pass1234"}'

# Login
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"Pass1234"}'

# Get state (replace TOKEN)
curl -X GET http://localhost:8080/api/users/1/state/all \
  -H "Authorization: Bearer TOKEN"

# Create checkout session
curl -X POST http://localhost:8080/api/subscription/create-checkout/1 \
  -H "Content-Type: application/json" \
  -d '{"plan_type":"monthly","success_url":"http://localhost:8081/success","cancel_url":"http://localhost:8081/cancel"}'
```

---

## Documentation Files

For more detailed information, see:

1. **BACKEND_IMPLEMENTATION_SUMMARY_2025-10-14.md** - Complete technical documentation
2. **AUTH_PAYMENT_IMPLEMENTATION_PLAN_2025-10-14.md** - Full implementation details with code examples
3. **USER_STATE_PERSISTENCE_ANALYSIS_2025-10-14.md** - State persistence deep dive
4. **AUTH_PAYMENT_EXECUTIVE_SUMMARY_2025-10-14.md** - High-level overview and decisions
5. **AUTH_PAYMENT_PROGRESS_LOG_2025-10-14.md** - Development progress and status

---

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review the detailed documentation files
3. Check logs in `logs/` directory
4. Verify configuration in `config/auth_payment_config.yml`

---

**Setup Complete!** 🎉

You now have a fully functional authentication and payment backend. The next step is to create the frontend components to interact with these APIs.

**Questions to Consider Before Moving Forward:**
1. Do you want to proceed with frontend implementation?
2. Do you want to run the migrations now?
3. Do you need help setting up Stripe or email services?
