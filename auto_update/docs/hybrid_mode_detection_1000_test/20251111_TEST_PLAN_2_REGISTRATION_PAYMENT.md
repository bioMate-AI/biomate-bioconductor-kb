# Test Plan 2: Registration & Payment Integration

**Date:** 2025-11-11
**Version:** 1.0
**Owner:** Launch Preparation Team
**Priority:** CRITICAL (LAUNCH BLOCKER)
**Estimated Effort:** 3-4 weeks

---

## Executive Summary

This document outlines comprehensive testing procedures for user registration and payment integration. **This is a CRITICAL launch blocker** because:

1. **MISSING FEATURE**: Registration does NOT collect financial credentials (user requirement)
2. **SECURITY RISKS**: Multiple vulnerabilities found in current implementation
3. **COMPLIANCE**: PCI DSS requirements not met

**Current Status:**
- ✓ Registration form exists (`frontend/client/src/pages/auth/register.tsx`)
- ✓ Backend API endpoint functional (`/api/auth/register`)
- ✓ Database schema supports billing (`stripeCustomerId`, `subscriptionStatus`)
- 🔴 **CRITICAL: NO payment method collection**
- 🔴 **CRITICAL: Stripe not configured**
- 🔴 **CRITICAL: No email verification enforcement**
- 🔴 **CRITICAL: No backend password validation**
- ⚠️ No CSRF protection
- ⚠️ No CAPTCHA

---

## CRITICAL ISSUES TO FIX BEFORE LAUNCH

### Issue #1: No Financial Credential Collection
**Severity:** P0 - LAUNCH BLOCKER
**Current Behavior:** Users can register and start 7-day trial without payment method
**Risk:** Financial loss, free riders, billing issues at trial end

**Required Implementation:**
1. Add Stripe Checkout during registration flow
2. Collect payment method (card/ACH)
3. Store Stripe Customer ID
4. Set up trial subscription with payment method on file
5. Automatic charge when trial ends

**Implementation Options:**

**Option A: Payment During Registration (Recommended)**
```typescript
// Modified registration flow:
// 1. User fills registration form
// 2. On submit -> Create Stripe Checkout Session
// 3. Redirect to Stripe hosted page
// 4. User enters payment info
// 5. Stripe redirects back with session ID
// 6. Complete registration with Stripe Customer ID
// 7. Start 7-day trial (no charge yet)
// 8. Automatic charge after trial ends
```

**Option B: Payment Before Trial Ends**
```typescript
// Keep current registration
// Send email 2 days before trial ends
// Require payment method to continue
// Suspend access if no payment added
```

**Recommendation:** Option A prevents trial abuse and ensures billing continuity

---

### Issue #2: Stripe Not Configured
**Severity:** P0 - LAUNCH BLOCKER
**Current Status:** All Stripe env variables empty

**Required Setup:**
1. Create Stripe account (or use existing)
2. Complete business verification
3. Create products and prices in Stripe Dashboard
4. Configure webhook endpoint
5. Set environment variables

**Stripe Dashboard Setup Steps:**
```bash
# 1. Create Products
Academic Tier:
  - Name: "Biomate Academic"
  - Monthly Price: $29/month (ID: price_xxxx_monthly)
  - Yearly Price: $290/year (ID: price_xxxx_yearly)

Professional Tier:
  - Name: "Biomate Professional"
  - Monthly Price: $99/month
  - Yearly Price: $990/year

Enterprise Tier:
  - Name: "Biomate Enterprise"
  - Monthly Price: $299/month
  - Yearly Price: $2990/year

# 2. Configure Webhooks
Endpoint URL: https://biomate.com/api/payments/webhook
Events to listen for:
  - checkout.session.completed
  - customer.subscription.created
  - customer.subscription.updated
  - customer.subscription.deleted
  - invoice.payment_succeeded
  - invoice.payment_failed
  - customer.created
  - customer.updated

# 3. Get Keys
Test Mode:
  - Publishable Key: pk_test_xxxx
  - Secret Key: sk_test_xxxx
  - Webhook Secret: whsec_xxxx

Production Mode:
  - Publishable Key: pk_live_xxxx
  - Secret Key: sk_live_xxxx
  - Webhook Secret: whsec_xxxx
```

**Environment Variables to Set:**
```bash
# Stripe Keys
STRIPE_SECRET_KEY=sk_live_xxxx
STRIPE_PUBLISHABLE_KEY=pk_live_xxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxx

# Price IDs
STRIPE_PRICE_ACADEMIC_MONTHLY=price_academic_monthly_id
STRIPE_PRICE_ACADEMIC_YEARLY=price_academic_yearly_id
STRIPE_PRICE_PROFESSIONAL_MONTHLY=price_pro_monthly_id
STRIPE_PRICE_PROFESSIONAL_YEARLY=price_pro_yearly_id
STRIPE_PRICE_ENTERPRISE_MONTHLY=price_ent_monthly_id
STRIPE_PRICE_ENTERPRISE_YEARLY=price_ent_yearly_id
```

---

### Issue #3: No Email Verification Enforcement
**Severity:** P1 - HIGH
**Current Behavior:** Users can access platform without verifying email
**Risk:** Fake accounts, spam, poor data quality

**Required Fix:**
```typescript
// Middleware to block unverified users
export const requireEmailVerification = (req, res, next) => {
  const user = req.user;

  if (!user.emailVerified) {
    return res.status(403).json({
      error: 'EmailNotVerified',
      message: 'Please verify your email address to continue.',
      verificationEmailSent: true
    });
  }

  next();
};

// Apply to all authenticated routes
app.use('/api/platform/*', requireEmailVerification);
app.use('/api/workflows/*', requireEmailVerification);
```

---

### Issue #4: No Backend Password Validation
**Severity:** P1 - HIGH
**Current Behavior:** Password rules only enforced in React frontend
**Risk:** Weak passwords if API called directly

**Required Fix:**
```typescript
// server/validation/password-rules.ts
import { z } from 'zod';

export const passwordSchema = z.string()
  .min(8, 'Password must be at least 8 characters')
  .max(128, 'Password too long')
  .regex(/[a-z]/, 'Password must contain lowercase letter')
  .regex(/[A-Z]/, 'Password must contain uppercase letter')
  .regex(/[0-9]/, 'Password must contain number')
  .regex(/[^a-zA-Z0-9]/, 'Password must contain special character')
  .refine(
    (password) => !commonPasswords.includes(password.toLowerCase()),
    'Password too common'
  );

// Apply in registration endpoint
app.post('/api/auth/register', async (req, res) => {
  try {
    passwordSchema.parse(req.body.password);
    // Continue with registration
  } catch (error) {
    return res.status(400).json({ error: error.errors });
  }
});
```

---

### Issue #5: No CSRF Protection
**Severity:** P1 - HIGH
**Risk:** Account takeover, unauthorized actions

**Required Fix:**
```typescript
import csrf from 'csurf';

const csrfProtection = csrf({
  cookie: {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict'
  }
});

// Apply to all state-changing routes
app.post('/api/auth/register', csrfProtection, registerHandler);
app.post('/api/auth/login', csrfProtection, loginHandler);

// Endpoint to get CSRF token
app.get('/api/csrf-token', csrfProtection, (req, res) => {
  res.json({ csrfToken: req.csrfToken() });
});
```

---

### Issue #6: No CAPTCHA
**Severity:** P2 - MEDIUM
**Risk:** Bot registrations, spam

**Required Fix:**
```typescript
// Use hCaptcha or Google reCAPTCHA
import fetch from 'node-fetch';

async function verifyCaptcha(token: string): Promise<boolean> {
  const response = await fetch('https://hcaptcha.com/siteverify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `response=${token}&secret=${process.env.HCAPTCHA_SECRET}`
  });

  const data = await response.json();
  return data.success;
}

app.post('/api/auth/register', async (req, res) => {
  const { captchaToken } = req.body;

  if (!await verifyCaptcha(captchaToken)) {
    return res.status(400).json({ error: 'Invalid CAPTCHA' });
  }

  // Continue with registration
});
```

---

## TEST PLAN

### 1. Registration Flow Testing

#### TC-REG-001: Basic Registration Flow
**Objective:** Verify user can register successfully

**Preconditions:**
- Stripe configured
- Email service configured
- Database running

**Test Steps:**
1. Navigate to /register
2. Fill form:
   - Email: test@example.com
   - Password: SecurePass123!
   - Full Name: Test User
   - Organization: Test Org
   - Phone: +1-555-0123
3. Check "I accept Terms of Service"
4. Click "Create Account"
5. Verify redirect to Stripe Checkout
6. Enter test card: 4242 4242 4242 4242
7. Complete payment form
8. Verify redirect back to platform
9. Check email for verification link

**Expected Results:**
- ✓ User created in database
- ✓ Email sent with verification link
- ✓ Stripe Customer ID stored
- ✓ Trial period started (7 days)
- ✓ Subscription status: 'trialing'
- ✓ No charge yet (trial period)

**Automated Test:**
```javascript
// tests/registration/basic-flow.spec.js
test('User can register with payment method', async ({ page }) => {
  await page.goto('http://localhost:5000/register');

  // Fill registration form
  await page.fill('[name="email"]', 'test@example.com');
  await page.fill('[name="password"]', 'SecurePass123!');
  await page.fill('[name="fullName"]', 'Test User');
  await page.fill('[name="organization"]', 'Test Org');
  await page.fill('[name="phone"]', '+1-555-0123');
  await page.check('[name="acceptedTerms"]');

  // Submit form
  await page.click('button[type="submit"]');

  // Should redirect to Stripe Checkout
  await page.waitForURL(/checkout\.stripe\.com/);

  // Fill Stripe test card
  const stripeFrame = page.frameLocator('iframe[name^="__privateStripeFrame"]');
  await stripeFrame.locator('[name="cardnumber"]').fill('4242424242424242');
  await stripeFrame.locator('[name="exp-date"]').fill('12/34');
  await stripeFrame.locator('[name="cvc"]').fill('123');
  await stripeFrame.locator('[name="postal"]').fill('12345');

  // Submit payment
  await page.click('button[type="submit"]');

  // Should redirect back to platform
  await page.waitForURL(/localhost:5000/);

  // Verify user is logged in
  const userName = await page.locator('[data-testid="user-name"]').textContent();
  expect(userName).toBe('Test User');
});
```

---

#### TC-REG-002: Email Validation
**Objective:** Verify invalid emails are rejected

**Test Cases:**
| Email | Expected Result |
|-------|----------------|
| `invalid` | Error: Invalid email format |
| `test@` | Error: Invalid email format |
| `@example.com` | Error: Invalid email format |
| `test@example` | Error: Invalid domain |
| `existing@user.com` | Error: Email already registered |

**Automated Test:**
```javascript
const invalidEmails = [
  'invalid',
  'test@',
  '@example.com',
  'test@example'
];

for (const email of invalidEmails) {
  test(`Rejects invalid email: ${email}`, async ({ page }) => {
    await page.goto('http://localhost:5000/register');
    await page.fill('[name="email"]', email);
    await page.fill('[name="password"]', 'SecurePass123!');
    await page.click('button[type="submit"]');

    const error = await page.locator('[data-testid="email-error"]').textContent();
    expect(error).toContain('Invalid email');
  });
}
```

---

#### TC-REG-003: Password Strength Validation
**Objective:** Verify password requirements are enforced

**Test Cases:**
| Password | Expected Result |
|----------|----------------|
| `short` | Error: Min 8 characters |
| `nouppercase1!` | Error: Must contain uppercase |
| `NOLOWERCASE1!` | Error: Must contain lowercase |
| `NoNumbers!` | Error: Must contain number |
| `NoSpecial1` | Error: Must contain special char |
| `password123!` | Error: Too common |
| `SecurePass123!` | ✓ Accepted |

**Automated Test:**
```javascript
const weakPasswords = [
  { password: 'short', error: '8 characters' },
  { password: 'nouppercase1!', error: 'uppercase' },
  { password: 'NOLOWERCASE1!', error: 'lowercase' },
  { password: 'NoNumbers!', error: 'number' },
  { password: 'NoSpecial1', error: 'special' },
  { password: 'password123!', error: 'common' }
];

for (const test of weakPasswords) {
  test(`Rejects weak password: ${test.password}`, async ({ page }) => {
    await page.goto('http://localhost:5000/register');
    await page.fill('[name="email"]', 'test@example.com');
    await page.fill('[name="password"]', test.password);
    await page.click('button[type="submit"]');

    const error = await page.locator('[data-testid="password-error"]').textContent();
    expect(error.toLowerCase()).toContain(test.error);
  });
}
```

---

#### TC-REG-004: Duplicate Email Prevention
**Objective:** Verify users cannot register with existing email

**Test Steps:**
1. Register user with test@example.com
2. Attempt to register again with same email
3. Verify error message

**Expected Result:** "Email already registered. Please log in."

**Automated Test:**
```javascript
test('Prevents duplicate email registration', async ({ page }) => {
  // First registration
  await registerUser(page, 'test@example.com', 'SecurePass123!');

  // Attempt duplicate
  await page.goto('http://localhost:5000/register');
  await page.fill('[name="email"]', 'test@example.com');
  await page.fill('[name="password"]', 'SecurePass123!');
  await page.click('button[type="submit"]');

  const error = await page.locator('[data-testid="error-message"]').textContent();
  expect(error).toContain('already registered');
});
```

---

#### TC-REG-005: Terms Acceptance Required
**Objective:** Verify terms must be accepted

**Test Steps:**
1. Fill registration form
2. Leave "Accept Terms" unchecked
3. Click submit
4. Verify error

**Expected Result:** "You must accept the Terms of Service"

---

#### TC-REG-006: CAPTCHA Verification
**Objective:** Verify CAPTCHA prevents bot registrations

**Test Steps:**
1. Fill registration form
2. Skip CAPTCHA (or fail it)
3. Click submit

**Expected Result:** "Please complete the CAPTCHA verification"

**Automated Test:**
```javascript
test('Requires CAPTCHA verification', async ({ page }) => {
  await page.goto('http://localhost:5000/register');
  await page.fill('[name="email"]', 'test@example.com');
  await page.fill('[name="password"]', 'SecurePass123!');
  // Don't complete CAPTCHA
  await page.click('button[type="submit"]');

  const error = await page.locator('[data-testid="captcha-error"]').textContent();
  expect(error).toContain('CAPTCHA');
});
```

---

### 2. Stripe Payment Integration Testing

#### TC-PAY-001: Stripe Checkout Session Creation
**Objective:** Verify Stripe Checkout session is created correctly

**Test Steps:**
1. Register user
2. Intercept API call to `/api/payments/create-checkout-session`
3. Verify session created with correct parameters

**Expected Request:**
```json
{
  "priceId": "price_academic_monthly_id",
  "email": "test@example.com",
  "trialPeriodDays": 7,
  "successUrl": "https://biomate.com/register/success?session_id={CHECKOUT_SESSION_ID}",
  "cancelUrl": "https://biomate.com/register"
}
```

**Expected Response:**
```json
{
  "sessionId": "cs_test_xxxx",
  "url": "https://checkout.stripe.com/pay/cs_test_xxxx"
}
```

**Automated Test:**
```javascript
test('Creates Stripe Checkout session', async ({ request }) => {
  const response = await request.post('/api/payments/create-checkout-session', {
    data: {
      priceId: 'price_academic_monthly_id',
      email: 'test@example.com'
    }
  });

  expect(response.status()).toBe(200);

  const data = await response.json();
  expect(data.sessionId).toBeTruthy();
  expect(data.url).toContain('checkout.stripe.com');
});
```

---

#### TC-PAY-002: Stripe Customer Creation
**Objective:** Verify Stripe Customer is created and stored

**Test Steps:**
1. Complete registration with payment
2. Check database for `stripeCustomerId`
3. Verify customer exists in Stripe Dashboard

**Database Check:**
```sql
SELECT id, email, stripeCustomerId, subscriptionStatus
FROM users
WHERE email = 'test@example.com';
```

**Expected:**
- `stripeCustomerId`: `cus_xxxx`
- `subscriptionStatus`: `trialing`

---

#### TC-PAY-003: Trial Subscription Setup
**Objective:** Verify trial subscription is created correctly

**Test Steps:**
1. Complete registration
2. Check Stripe subscription
3. Verify trial period

**Expected Subscription:**
```json
{
  "id": "sub_xxxx",
  "customer": "cus_xxxx",
  "status": "trialing",
  "trial_end": 1699999999,  // 7 days from now
  "items": [{
    "price": "price_academic_monthly_id",
    "quantity": 1
  }],
  "default_payment_method": "pm_xxxx"  // Card on file
}
```

---

#### TC-PAY-004: Test Card Numbers
**Objective:** Verify all Stripe test cards work

**Test Cards:**
| Card Number | Description |
|-------------|-------------|
| 4242 4242 4242 4242 | Successful payment |
| 4000 0025 0000 3155 | Requires 3D Secure |
| 4000 0000 0000 9995 | Declined (insufficient funds) |
| 4000 0000 0000 9979 | Declined (stolen card) |
| 4000 0000 0000 0069 | Expired card |

**Test Procedure:**
For each card:
1. Start registration
2. Enter test card
3. Verify appropriate handling

---

#### TC-PAY-005: 3D Secure (SCA) Handling
**Objective:** Verify Strong Customer Authentication works

**Test Steps:**
1. Register with card: 4000 0025 0000 3155
2. Complete 3D Secure challenge
3. Verify payment succeeds

**Expected:**
- Modal appears for 3D Secure
- User completes authentication
- Payment proceeds
- User redirected to platform

---

#### TC-PAY-006: Payment Failure Handling
**Objective:** Verify graceful handling of failed payments

**Test Steps:**
1. Register with declined card: 4000 0000 0000 9995
2. Verify error message
3. Allow retry

**Expected:**
- Clear error message: "Your card was declined. Please try another card."
- User can retry without losing form data
- No user account created if payment fails

---

#### TC-PAY-007: Webhook Processing
**Objective:** Verify webhook events are handled correctly

**Test Events:**

**`checkout.session.completed`:**
```json
{
  "type": "checkout.session.completed",
  "data": {
    "object": {
      "id": "cs_test_xxxx",
      "customer": "cus_xxxx",
      "subscription": "sub_xxxx",
      "payment_status": "paid",
      "metadata": {
        "userId": "user_uuid"
      }
    }
  }
}
```

**Expected Handling:**
1. Find user by metadata.userId
2. Update stripeCustomerId
3. Update subscriptionId
4. Update subscriptionStatus to 'trialing'
5. Return 200 OK

**Test Procedure:**
```bash
# Use Stripe CLI to forward webhooks
stripe listen --forward-to localhost:5000/api/payments/webhook

# Trigger test event
stripe trigger checkout.session.completed
```

**Automated Test:**
```javascript
test('Processes checkout.session.completed webhook', async ({ request }) => {
  const webhookPayload = {
    type: 'checkout.session.completed',
    data: {
      object: {
        id: 'cs_test_xxxx',
        customer: 'cus_test_xxxx',
        subscription: 'sub_test_xxxx',
        metadata: { userId: 'test-user-id' }
      }
    }
  };

  // Sign webhook (requires Stripe library)
  const signature = stripe.webhooks.generateTestHeaderString({
    payload: JSON.stringify(webhookPayload),
    secret: process.env.STRIPE_WEBHOOK_SECRET
  });

  const response = await request.post('/api/payments/webhook', {
    data: webhookPayload,
    headers: {
      'stripe-signature': signature
    }
  });

  expect(response.status()).toBe(200);

  // Verify database updated
  const user = await db.query('SELECT * FROM users WHERE id = $1', ['test-user-id']);
  expect(user.stripeCustomerId).toBe('cus_test_xxxx');
  expect(user.subscriptionStatus).toBe('trialing');
});
```

---

### 3. Email Verification Testing

#### TC-EMAIL-001: Verification Email Sent
**Objective:** Verify verification email is sent after registration

**Test Steps:**
1. Complete registration
2. Check email inbox (use mailtrap.io for testing)
3. Verify email received

**Expected Email:**
- From: noreply@biomate.com
- Subject: "Verify your Biomate account"
- Contains verification link
- Link format: `https://biomate.com/verify-email?token=xxxx`

**Automated Test:**
```javascript
test('Sends verification email after registration', async ({ page, request }) => {
  // Register user
  await registerUser(page, 'test@example.com', 'SecurePass123!');

  // Check email via Mailtrap API
  const emails = await request.get(
    'https://mailtrap.io/api/v1/inboxes/YOUR_INBOX_ID/messages',
    {
      headers: { 'Api-Token': process.env.MAILTRAP_API_TOKEN }
    }
  );

  const emailList = await emails.json();
  const verificationEmail = emailList.find(e =>
    e.to_email === 'test@example.com' &&
    e.subject.includes('Verify')
  );

  expect(verificationEmail).toBeTruthy();
});
```

---

#### TC-EMAIL-002: Email Verification Link Works
**Objective:** Verify clicking verification link activates account

**Test Steps:**
1. Register user
2. Extract verification token from email
3. Visit verification link
4. Verify account activated

**Expected:**
- User redirected to login or dashboard
- `emailVerified` set to `true` in database
- Success message displayed

---

#### TC-EMAIL-003: Expired Verification Token
**Objective:** Verify expired tokens are rejected

**Test Steps:**
1. Register user
2. Wait for token expiration (or manipulate DB)
3. Try to verify with expired token

**Expected:**
- Error: "Verification link expired. Request a new one."
- Option to resend verification email

---

#### TC-EMAIL-004: Unverified User Access Blocked
**Objective:** Verify unverified users cannot access platform

**Test Steps:**
1. Register user (verified = false)
2. Try to access `/dashboard`
3. Try to access `/workflows`

**Expected:**
- 403 Forbidden
- Message: "Please verify your email address"
- Option to resend verification email

---

### 4. Security Testing

#### TC-SEC-001: SQL Injection Prevention
**Objective:** Verify SQL injection is blocked

**Test Inputs:**
```javascript
const sqlInjectionPayloads = [
  "admin'--",
  "admin' OR '1'='1",
  "'; DROP TABLE users; --",
  "admin' UNION SELECT * FROM users--",
  "1' AND 1=1--"
];
```

**Test Procedure:**
For each payload:
1. Enter in email field
2. Submit registration
3. Verify rejected or safely escaped

**Expected:** No SQL execution, error message or safe handling

---

#### TC-SEC-002: XSS Prevention
**Objective:** Verify cross-site scripting is blocked

**Test Inputs:**
```javascript
const xssPayloads = [
  "<script>alert('XSS')</script>",
  "<img src=x onerror=alert('XSS')>",
  "<svg onload=alert('XSS')>",
  "javascript:alert('XSS')",
  "<iframe src='javascript:alert(\"XSS\")'>"
];
```

**Test Procedure:**
1. Enter payload in name field
2. Submit registration
3. View user profile
4. Verify payload is escaped (displayed as text, not executed)

---

#### TC-SEC-003: CSRF Protection
**Objective:** Verify CSRF attacks are blocked

**Test Procedure:**
```html
<!-- Malicious site tries to submit registration form -->
<form action="https://biomate.com/api/auth/register" method="POST">
  <input name="email" value="attacker@evil.com">
  <input name="password" value="Hacked123!">
</form>
<script>document.forms[0].submit();</script>
```

**Expected:** Request rejected with "Invalid CSRF token"

---

#### TC-SEC-004: Rate Limiting
**Objective:** Verify rate limiting prevents brute force

**Test Procedure:**
1. Attempt 20 registrations from same IP
2. Verify rate limit kicks in

**Expected:**
- After 5 attempts: 429 Too Many Requests
- Error: "Too many registration attempts. Try again in 15 minutes."
- Exponential backoff

**Automated Test:**
```javascript
test('Rate limits registration attempts', async ({ request }) => {
  const attempts = [];

  for (let i = 0; i < 10; i++) {
    attempts.push(
      request.post('/api/auth/register', {
        data: {
          email: `test${i}@example.com`,
          password: 'SecurePass123!'
        }
      })
    );
  }

  const responses = await Promise.all(attempts);
  const rateLimited = responses.filter(r => r.status() === 429);

  expect(rateLimited.length).toBeGreaterThan(0);
});
```

---

#### TC-SEC-005: Password Hashing
**Objective:** Verify passwords are hashed, not stored in plaintext

**Test Procedure:**
1. Register user with password "MyPassword123!"
2. Query database directly
3. Verify password is bcrypt hashed

**Database Check:**
```sql
SELECT password FROM users WHERE email = 'test@example.com';
```

**Expected:**
- Password starts with `$2b$12$` (bcrypt with 12 rounds)
- NOT plaintext
- Hash is 60 characters

---

#### TC-SEC-006: Session Security
**Objective:** Verify JWT tokens are secure

**Test Procedure:**
1. Register and login
2. Inspect cookies
3. Verify JWT properties

**Expected Cookie Properties:**
```javascript
{
  name: 'auth_token',
  httpOnly: true,  // Cannot access via JavaScript
  secure: true,    // HTTPS only (in production)
  sameSite: 'Strict',  // CSRF protection
  maxAge: 604800000  // 7 days
}
```

---

#### TC-SEC-007: Information Disclosure
**Objective:** Verify error messages don't leak sensitive info

**Test Cases:**
| Action | Bad Error | Good Error |
|--------|-----------|-----------|
| Login with unregistered email | "Email not found in database" | "Invalid email or password" |
| SQL error | "PostgreSQL error: syntax error at..." | "Registration failed. Please try again." |
| Stripe error | "Stripe API error: Customer cus_xxx not found" | "Payment processing error" |

---

### 5. Edge Cases & Error Handling

#### TC-EDGE-001: Simultaneous Registrations
**Objective:** Handle race condition on duplicate email

**Test Procedure:**
1. Open 2 browser tabs
2. Fill same email in both
3. Submit both simultaneously

**Expected:** Only one succeeds, other gets "Email already registered"

---

#### TC-EDGE-002: Network Failure During Payment
**Objective:** Handle network interruption gracefully

**Test Procedure:**
1. Start registration
2. Reach Stripe Checkout
3. Disconnect internet
4. Try to submit payment

**Expected:**
- User-friendly error
- Can retry when connection restored
- No orphaned records

---

#### TC-EDGE-003: Stripe Webhook Delay
**Objective:** Handle delayed webhook delivery

**Test Scenario:** Webhook arrives 5 minutes after checkout

**Expected:**
- Webhook still processed
- Idempotency prevents duplicate processing
- User account updated correctly

---

#### TC-EDGE-004: Browser Back Button
**Objective:** Handle back button during registration

**Test Steps:**
1. Fill registration form
2. Submit
3. While on Stripe Checkout, click back
4. Verify form state preserved

---

#### TC-EDGE-005: Multiple Tabs Registration
**Objective:** Prevent duplicate registrations from multiple tabs

**Test Procedure:**
1. Open registration in 2 tabs
2. Complete form in both
3. Submit both

**Expected:** First submission succeeds, second gets duplicate error

---

### 6. Trial Period & Billing Testing

#### TC-TRIAL-001: Trial Period Starts Correctly
**Objective:** Verify 7-day trial begins after registration

**Test Steps:**
1. Register user
2. Check database `trialStartedAt` and `trialEndsAt`
3. Verify 7-day difference

**Expected:**
```sql
trialStartedAt: 2025-11-11 10:00:00
trialEndsAt: 2025-11-18 10:00:00
```

---

#### TC-TRIAL-002: No Charge During Trial
**Objective:** Verify no charge occurs during trial period

**Test Steps:**
1. Complete registration with card on file
2. Check Stripe charges immediately
3. Check daily for 7 days

**Expected:** Zero charges until trial ends

---

#### TC-TRIAL-003: Auto-Charge After Trial
**Objective:** Verify automatic billing when trial ends

**Test Steps:**
1. Create backdated trial (ends today)
2. Wait for billing cycle
3. Verify charge created

**Expected:**
- Stripe invoice created
- Payment attempted on default payment method
- If successful: subscriptionStatus = 'active'
- If failed: subscriptionStatus = 'past_due'

---

#### TC-TRIAL-004: Trial Expiration Warning
**Objective:** Verify email sent 2 days before trial ends

**Test Steps:**
1. Create user with trial ending in 2 days
2. Run cron job / scheduled task
3. Check email sent

**Expected Email:**
- Subject: "Your Biomate trial ends in 2 days"
- Contains: Current plan, price, trial end date
- CTA: Update payment method (if needed)

---

#### TC-TRIAL-005: One Trial Per User
**Objective:** Verify users cannot create multiple trials

**Test Steps:**
1. Register user, start trial
2. Cancel account
3. Try to register again with same email

**Expected:** Error or no trial period (immediate billing)

**Database Check:**
```sql
SELECT trialUsed FROM users WHERE email = 'test@example.com';
-- Should be TRUE
```

---

### 7. Subscription Tier Testing

#### TC-TIER-001: Tier Selection During Registration
**Objective:** Verify user can choose tier

**Test Steps:**
1. On registration form, select "Professional" tier
2. Complete registration
3. Verify correct Stripe price used

**Expected:**
- Checkout session uses `price_professional_monthly_id`
- Database: `subscriptionTier = 'professional'`

---

#### TC-TIER-002: All Tiers Available
**Objective:** Verify all 3 tiers can be selected

**Test Cases:**
- Academic: $29/month or $290/year
- Professional: $99/month or $990/year
- Enterprise: $299/month or $2990/year

For each tier:
1. Select tier
2. Complete registration
3. Verify correct price applied

---

#### TC-TIER-003: Monthly vs Yearly Billing
**Objective:** Verify billing interval selection

**Test Steps:**
1. Select "Professional" tier
2. Choose "Yearly" billing
3. Complete registration

**Expected:**
- Checkout session uses yearly price ID
- Shows annual savings: "Save $198/year"
- First charge: $990 (not $99)

---

### 8. Performance Testing

#### TC-PERF-001: Registration Load Test
**Objective:** Verify system handles concurrent registrations

**Test Procedure:**
```bash
# Use k6 or artillery for load testing
k6 run registration-load-test.js

export VUS=100  # Virtual users
export DURATION=60s  # Test duration
```

**Load Test Script:**
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  vus: 100,
  duration: '60s',
};

export default function () {
  const email = `user${Date.now()}@example.com`;
  const payload = JSON.stringify({
    email: email,
    password: 'SecurePass123!',
    fullName: 'Load Test User',
    organization: 'Test Org',
    acceptedTerms: true
  });

  const params = {
    headers: { 'Content-Type': 'application/json' },
  };

  let response = http.post('http://localhost:5000/api/auth/register', payload, params);

  check(response, {
    'is status 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(1);
}
```

**Success Criteria:**
- 100 concurrent users
- 95% requests complete in < 500ms
- 0% error rate
- Database handles load

---

### 9. Compliance Testing

#### TC-COMP-001: PCI DSS Compliance
**Objective:** Verify no card data stored on servers

**Test Steps:**
1. Complete registration with card
2. Search database for card numbers
3. Search logs for card data

**Expected:**
- NO card numbers in database
- NO CVV stored anywhere
- Only Stripe Customer ID and Payment Method ID
- Stripe handles all card data

---

#### TC-COMP-002: GDPR Compliance
**Objective:** Verify GDPR requirements met

**Checklist:**
- [ ] Privacy policy link visible
- [ ] Cookie consent displayed (if using cookies)
- [ ] Data processing disclosed
- [ ] User can export data (implement endpoint)
- [ ] User can delete account (implement endpoint)
- [ ] Legitimate interest documented

---

#### TC-COMP-003: Terms of Service Acceptance
**Objective:** Verify terms acceptance is tracked

**Test Steps:**
1. Register user
2. Check database `termsAcceptedAt` timestamp
3. Verify terms version stored (if applicable)

**Expected:**
```sql
SELECT termsAcceptedAt, termsVersion FROM users WHERE email = 'test@example.com';
-- termsAcceptedAt: 2025-11-11 10:00:00
-- termsVersion: 1.0 (or current version)
```

---

### 10. Test Execution Plan

**Phase 1: Setup (Week 1)**
- [ ] Configure Stripe account
- [ ] Set environment variables
- [ ] Implement financial credential collection
- [ ] Add backend password validation
- [ ] Implement CSRF protection
- [ ] Add CAPTCHA
- [ ] Configure email service

**Phase 2: Security Testing (Week 2)**
- [ ] Run SQL injection tests
- [ ] Run XSS tests
- [ ] Test CSRF protection
- [ ] Test rate limiting
- [ ] Verify password hashing
- [ ] Test session security
- [ ] Penetration testing

**Phase 3: Integration Testing (Week 3)**
- [ ] Test Stripe payment flow end-to-end
- [ ] Test all webhook events
- [ ] Test email verification
- [ ] Test trial period logic
- [ ] Test subscription tiers

**Phase 4: Load & Edge Cases (Week 4)**
- [ ] Load testing (100+ concurrent users)
- [ ] Edge case testing
- [ ] Error handling verification
- [ ] Browser compatibility
- [ ] Mobile testing

---

## Test Environment Setup

**Local Development:**
```bash
# Set Stripe test keys
export STRIPE_SECRET_KEY=sk_test_xxxx
export STRIPE_PUBLISHABLE_KEY=pk_test_xxxx
export STRIPE_WEBHOOK_SECRET=whsec_test_xxxx

# Forward webhooks from Stripe
stripe listen --forward-to localhost:5000/api/payments/webhook

# Start app
cd /home/yzhang/biomate/frontend
npm run dev
```

**Staging Environment:**
- Use Stripe test mode
- Use Mailtrap.io for emails
- PostgreSQL staging database
- Full monitoring enabled

**Production Environment:**
- Stripe live mode
- Real email service (AWS SES)
- Production database with backups
- All security measures active

---

## Success Criteria Summary

**MUST PASS (Launch Blockers):**
- [ ] Payment method collected during registration
- [ ] Stripe fully configured and tested
- [ ] Email verification enforced
- [ ] Backend password validation implemented
- [ ] CSRF protection active
- [ ] All P0 security tests pass
- [ ] Zero SQL injection vulnerabilities
- [ ] Zero XSS vulnerabilities

**SHOULD PASS (High Priority):**
- [ ] CAPTCHA implemented
- [ ] Rate limiting functional
- [ ] Load test: 100 concurrent users
- [ ] All webhook events handled
- [ ] Trial billing logic correct
- [ ] All tier options working

**NICE TO HAVE:**
- [ ] Social OAuth registration (Google/GitHub)
- [ ] Phone verification
- [ ] Two-factor authentication
- [ ] Advanced fraud detection

---

## Rollback Plan

If critical issues found in production:
1. Disable new registrations (maintenance mode)
2. Roll back code to previous version
3. Fix issues in staging
4. Re-test completely
5. Deploy with phased rollout

---

**Document Version:** 1.0
**Last Updated:** 2025-11-11
**Next Review:** After implementation, before launch
