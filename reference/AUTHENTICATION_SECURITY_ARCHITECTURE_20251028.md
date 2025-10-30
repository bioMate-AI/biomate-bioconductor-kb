# BioMate Authentication & Security Architecture

**Document Created:** 2025-10-28
**Status:** Implementation Ready
**Target:** 2-Week Launch (P0)

---

## Executive Summary

This document defines the authentication and security architecture for BioMate's 2-week production launch, connecting the existing website to user registration/login, payment integration, and the chat+workflow interface.

**Tech Stack Decision:**
- **Primary Auth:** Custom JWT-based authentication (already have user management in Galaxy)
- **Session Management:** Redis for session storage
- **Password Security:** bcrypt with salt rounds = 12
- **MFA (Future):** TOTP-based (Google Authenticator) - Phase 2
- **OAuth (Future):** Google/GitHub SSO - Phase 2

**Why NOT Auth0/AWS Cognito for P0:**
- You already have Galaxy user management
- Faster to integrate with existing backend
- More control over user data
- Can add OAuth later without breaking changes

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    BioMate Website                               │
│  ┌────────────┐  ┌─────────────┐  ┌──────────────────────┐     │
│  │  Landing   │  │  Pricing    │  │  Documentation       │     │
│  │  Page      │  │  Page       │  │  /FAQ                │     │
│  └────────────┘  └─────────────┘  └──────────────────────┘     │
│         │                │                                       │
│         └────────────────┴───────────────┐                      │
│                                           ↓                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │         Auth Gateway                                     │   │
│  │  /register  /login  /logout  /forgot-password           │   │
│  └──────────────────────────────────────────────────────────┘   │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│              Express/Node.js Middleware (Port 3000)              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Auth Service                                            │   │
│  │  - JWT generation/validation                             │   │
│  │  - Session management (Redis)                            │   │
│  │  - Password hashing (bcrypt)                             │   │
│  │  - Trial period tracking                                 │   │
│  └──────────────────────────────────────────────────────────┘   │
│                             │                                    │
│                             ↓                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Payment Integration (Stripe)                            │   │
│  │  - Subscription management                               │   │
│  │  - Trial period enforcement                              │   │
│  │  - Webhook handling                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│              Galaxy Backend (Port 8080)                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  User Management                                         │   │
│  │  - User profiles                                         │   │
│  │  - Project management                                    │   │
│  │  - Workflow history                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│         Chat + Workflow Interface (React Frontend)               │
│  Accessible only with valid JWT token                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## User Journey Flow

### 1. New User Registration

```
Website Landing Page
    ↓
Click "Get Started" / "Sign Up"
    ↓
Registration Form
├── Email (required, validated)
├── Password (min 8 chars, 1 uppercase, 1 number, 1 special)
├── Full Name (required)
├── Organization (optional)
├── Phone (optional, for MFA future)
└── Accept Terms of Service (required checkbox)
    ↓
Submit Registration
    ↓
Backend Validation
├── Check email uniqueness
├── Hash password (bcrypt, salt=12)
├── Create user record in database
├── Generate JWT token (7-day trial)
└── Create Stripe customer (no payment yet)
    ↓
Send Welcome Email
├── Verification link (optional for P0)
└── Trial period info (7 days free)
    ↓
Auto-login (JWT token in cookie)
    ↓
Redirect to Chat + Workflow Page
```

**API Endpoint:**
```
POST /api/auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "SecurePass123!",
  "full_name": "John Doe",
  "organization": "Research Lab",
  "terms_accepted": true
}

Response (200):
{
  "success": true,
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "full_name": "John Doe",
    "trial_ends_at": "2025-11-04T12:00:00Z",
    "subscription_status": "trialing"
  },
  "token": "jwt_token_here",
  "expires_in": 604800  // 7 days in seconds
}
```

---

### 2. Existing User Login

```
Website
    ↓
Click "Login"
    ↓
Login Form
├── Email
└── Password
    ↓
Submit Login
    ↓
Backend Validation
├── Find user by email
├── Verify password (bcrypt compare)
├── Check subscription status
│   ├── Trial active? → Allow access
│   ├── Trial expired + no payment? → Prompt payment
│   └── Paid subscription? → Allow access
├── Generate new JWT token
└── Update last_login timestamp
    ↓
Return JWT + User Info
    ↓
Set JWT in HTTP-only cookie
    ↓
Redirect to Chat + Workflow Page
```

**API Endpoint:**
```
POST /api/auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "SecurePass123!"
}

Response (200):
{
  "success": true,
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "full_name": "John Doe",
    "trial_ends_at": "2025-11-04T12:00:00Z",
    "subscription_status": "active",  // or "trialing", "past_due", "canceled"
    "subscription_tier": "professional"  // or "academic", "enterprise"
  },
  "token": "jwt_token_here",
  "expires_in": 604800
}

Response (401) - Trial Expired:
{
  "success": false,
  "error": "trial_expired",
  "message": "Your 7-day trial has expired. Please subscribe to continue.",
  "redirect_to": "/pricing?upgrade=true"
}
```

---

### 3. Accessing Chat + Workflow Page

```
User Navigates to /chat or /workflows
    ↓
Frontend Checks JWT Token
├── Token in cookie?
│   ├── Yes → Continue
│   └── No → Redirect to /login
    ↓
Validate JWT on Backend
├── Token signature valid?
├── Token not expired?
├── User exists in database?
└── Subscription status active/trialing?
    ↓
If ALL checks pass:
├── Allow access to chat/workflow
└── Load user data and history
    ↓
If ANY check fails:
├── Clear invalid token
├── Redirect to /login
└── Show error message
```

**API Middleware:**
```javascript
// frontend/server/middleware/auth.ts

export async function authenticateRequest(req, res, next) {
  const token = req.cookies.biomate_token;

  if (!token) {
    return res.status(401).json({ error: 'No token provided' });
  }

  try {
    // Verify JWT
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // Check user exists and subscription status
    const user = await getUserById(decoded.userId);

    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }

    // Check subscription status
    const subscriptionStatus = await checkSubscriptionStatus(user.id);

    if (!subscriptionStatus.active) {
      return res.status(403).json({
        error: 'subscription_required',
        trial_expired: subscriptionStatus.trial_expired,
        message: 'Please subscribe to continue using BioMate'
      });
    }

    // Attach user to request
    req.user = user;
    req.subscription = subscriptionStatus;

    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}
```

---

## Database Schema

### Users Table

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    organization VARCHAR(255),
    phone VARCHAR(50),

    -- Trial management
    trial_started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    trial_ends_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '7 days'),
    trial_used BOOLEAN DEFAULT false,

    -- Subscription
    stripe_customer_id VARCHAR(255),
    subscription_status VARCHAR(50) DEFAULT 'trialing',
        -- Values: 'trialing', 'active', 'past_due', 'canceled', 'paused'
    subscription_tier VARCHAR(50) DEFAULT 'academic',
        -- Values: 'academic', 'professional', 'enterprise'
    subscription_id VARCHAR(255),  -- Stripe subscription ID
    current_period_end TIMESTAMP,

    -- Security
    email_verified BOOLEAN DEFAULT false,
    verification_token VARCHAR(255),
    reset_password_token VARCHAR(255),
    reset_password_expires TIMESTAMP,

    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP,

    -- Metadata
    terms_accepted_at TIMESTAMP,
    marketing_emails_opt_in BOOLEAN DEFAULT false,

    CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT valid_subscription_status CHECK (
        subscription_status IN ('trialing', 'active', 'past_due', 'canceled', 'paused')
    ),
    CONSTRAINT valid_subscription_tier CHECK (
        subscription_tier IN ('academic', 'professional', 'enterprise')
    )
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_stripe_customer_id ON users(stripe_customer_id);
CREATE INDEX idx_users_subscription_status ON users(subscription_status);
CREATE INDEX idx_users_trial_ends_at ON users(trial_ends_at);
```

---

### Sessions Table (Redis Alternative)

If not using Redis, use PostgreSQL for sessions:

```sql
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_activity_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT session_not_expired CHECK (expires_at > CURRENT_TIMESTAMP)
);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_token_hash ON sessions(token_hash);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);

-- Automatic cleanup of expired sessions
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS void AS $$
BEGIN
    DELETE FROM sessions WHERE expires_at < CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Run cleanup daily via cron
SELECT cron.schedule('cleanup-sessions', '0 2 * * *', 'SELECT cleanup_expired_sessions()');
```

---

## JWT Token Structure

### Token Payload

```javascript
{
  // Standard JWT claims
  "iss": "biomate.com",
  "sub": "user_uuid",  // User ID
  "iat": 1698768000,   // Issued at (Unix timestamp)
  "exp": 1699372800,   // Expires at (7 days from issued)
  "nbf": 1698768000,   // Not before

  // Custom claims
  "email": "user@example.com",
  "subscription_status": "trialing",
  "subscription_tier": "academic",
  "trial_ends_at": 1699372800,

  // Permissions (for future RBAC)
  "roles": ["user"],
  "permissions": ["workflow:execute", "workflow:view"]
}
```

### Token Generation

```javascript
// frontend/server/services/auth-service.ts

import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';

const JWT_SECRET = process.env.JWT_SECRET;  // Must be 32+ chars, random
const JWT_EXPIRY = '7d';  // 7 days
const BCRYPT_ROUNDS = 12;

export class AuthService {

  async registerUser(data) {
    // Validate email uniqueness
    const existingUser = await db.users.findOne({ email: data.email });
    if (existingUser) {
      throw new Error('Email already registered');
    }

    // Hash password
    const passwordHash = await bcrypt.hash(data.password, BCRYPT_ROUNDS);

    // Calculate trial end date
    const trialEndsAt = new Date();
    trialEndsAt.setDate(trialEndsAt.getDate() + 7);

    // Create user
    const user = await db.users.create({
      email: data.email,
      password_hash: passwordHash,
      full_name: data.full_name,
      organization: data.organization,
      trial_started_at: new Date(),
      trial_ends_at: trialEndsAt,
      trial_used: false,
      subscription_status: 'trialing',
      subscription_tier: 'academic',
      terms_accepted_at: new Date()
    });

    // Create Stripe customer (no payment yet)
    const stripeCustomer = await stripe.customers.create({
      email: user.email,
      name: user.full_name,
      metadata: {
        biomate_user_id: user.id
      }
    });

    // Update user with Stripe customer ID
    await db.users.update(user.id, {
      stripe_customer_id: stripeCustomer.id
    });

    // Generate JWT
    const token = this.generateToken(user);

    // Send welcome email
    await this.sendWelcomeEmail(user);

    return { user, token };
  }

  async loginUser(email, password) {
    // Find user
    const user = await db.users.findOne({ email });
    if (!user) {
      throw new Error('Invalid credentials');
    }

    // Verify password
    const passwordValid = await bcrypt.compare(password, user.password_hash);
    if (!passwordValid) {
      throw new Error('Invalid credentials');
    }

    // Check subscription status
    const subscriptionStatus = await this.checkSubscriptionStatus(user);

    if (!subscriptionStatus.active && !subscriptionStatus.trialing) {
      throw new Error('TRIAL_EXPIRED');
    }

    // Update last login
    await db.users.update(user.id, {
      last_login_at: new Date()
    });

    // Generate JWT
    const token = this.generateToken(user);

    return { user, token, subscriptionStatus };
  }

  generateToken(user) {
    const payload = {
      iss: 'biomate.com',
      sub: user.id,
      email: user.email,
      subscription_status: user.subscription_status,
      subscription_tier: user.subscription_tier,
      trial_ends_at: Math.floor(user.trial_ends_at.getTime() / 1000),
      roles: ['user'],
      permissions: ['workflow:execute', 'workflow:view']
    };

    return jwt.sign(payload, JWT_SECRET, {
      expiresIn: JWT_EXPIRY
    });
  }

  async checkSubscriptionStatus(user) {
    const now = new Date();

    // Check if trial is active
    const trialing = user.trial_ends_at > now && !user.trial_used;

    // Check if paid subscription is active
    const subscriptionActive =
      user.subscription_status === 'active' &&
      (user.current_period_end === null || user.current_period_end > now);

    return {
      active: trialing || subscriptionActive,
      trialing: trialing,
      trial_expired: user.trial_ends_at <= now,
      days_remaining: trialing ?
        Math.ceil((user.trial_ends_at - now) / (1000 * 60 * 60 * 24)) : 0,
      subscription_tier: user.subscription_tier,
      subscription_status: user.subscription_status
    };
  }

  async sendWelcomeEmail(user) {
    // TODO: Integrate with email service (SendGrid, AWS SES, etc.)
    console.log(`Welcome email sent to ${user.email}`);
  }
}
```

---

## Security Implementation

### 1. Password Requirements

**Minimum Requirements:**
- ✅ At least 8 characters
- ✅ At least 1 uppercase letter
- ✅ At least 1 lowercase letter
- ✅ At least 1 number
- ✅ At least 1 special character (!@#$%^&*)

**Frontend Validation:**
```javascript
// frontend/client/src/utils/password-validator.ts

export function validatePassword(password: string): {
  valid: boolean;
  errors: string[]
} {
  const errors: string[] = [];

  if (password.length < 8) {
    errors.push('Password must be at least 8 characters');
  }
  if (!/[A-Z]/.test(password)) {
    errors.push('Password must contain at least one uppercase letter');
  }
  if (!/[a-z]/.test(password)) {
    errors.push('Password must contain at least one lowercase letter');
  }
  if (!/[0-9]/.test(password)) {
    errors.push('Password must contain at least one number');
  }
  if (!/[!@#$%^&*]/.test(password)) {
    errors.push('Password must contain at least one special character (!@#$%^&*)');
  }

  return {
    valid: errors.length === 0,
    errors
  };
}
```

---

### 2. HTTPS Enforcement

**Nginx Configuration:**
```nginx
# /etc/nginx/sites-available/biomate

server {
    listen 80;
    server_name biomate.com www.biomate.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name biomate.com www.biomate.com;

    # SSL certificates (Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/biomate.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/biomate.com/privkey.pem;

    # Strong SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Proxy to Node.js
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Static assets (if any)
    location /static/ {
        alias /var/www/biomate/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

---

### 3. Rate Limiting

**Prevent Brute Force Attacks:**

```javascript
// frontend/server/middleware/rate-limiter.ts

import rateLimit from 'express-rate-limit';
import RedisStore from 'rate-limit-redis';
import Redis from 'ioredis';

const redis = new Redis(process.env.REDIS_URL);

// Strict rate limit for auth endpoints
export const authRateLimiter = rateLimit({
  store: new RedisStore({
    client: redis,
    prefix: 'rl:auth:'
  }),
  windowMs: 15 * 60 * 1000,  // 15 minutes
  max: 5,  // Max 5 requests per window
  message: 'Too many login attempts. Please try again in 15 minutes.',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    res.status(429).json({
      error: 'rate_limit_exceeded',
      message: 'Too many login attempts. Please try again later.',
      retry_after: 900  // 15 minutes in seconds
    });
  }
});

// General API rate limit
export const apiRateLimiter = rateLimit({
  store: new RedisStore({
    client: redis,
    prefix: 'rl:api:'
  }),
  windowMs: 1 * 60 * 1000,  // 1 minute
  max: 100,  // Max 100 requests per minute
  message: 'Too many requests. Please slow down.'
});

// Usage in routes
app.post('/api/auth/login', authRateLimiter, loginHandler);
app.post('/api/auth/register', authRateLimiter, registerHandler);
app.use('/api/', apiRateLimiter);
```

---

### 4. CSRF Protection

**For Cookie-based JWT:**

```javascript
// frontend/server/middleware/csrf.ts

import csrf from 'csurf';
import cookieParser from 'cookie-parser';

// Initialize CSRF protection
const csrfProtection = csrf({
  cookie: {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict'
  }
});

app.use(cookieParser());
app.use(csrfProtection);

// Send CSRF token to client
app.get('/api/csrf-token', (req, res) => {
  res.json({ csrfToken: req.csrfToken() });
});

// Client must include CSRF token in requests
// Header: X-CSRF-Token: <token>
```

---

### 5. Cookie Settings

**Secure Cookie Configuration:**

```javascript
// frontend/server/utils/cookies.ts

export function setAuthCookie(res, token) {
  res.cookie('biomate_token', token, {
    httpOnly: true,  // Prevent XSS access
    secure: process.env.NODE_ENV === 'production',  // HTTPS only in production
    sameSite: 'strict',  // CSRF protection
    maxAge: 7 * 24 * 60 * 60 * 1000,  // 7 days
    path: '/',
    domain: process.env.COOKIE_DOMAIN || undefined
  });
}

export function clearAuthCookie(res) {
  res.clearCookie('biomate_token', {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: '/'
  });
}
```

---

## Environment Variables

```bash
# .env.production

# JWT Configuration
JWT_SECRET=<GENERATE_RANDOM_32_CHAR_STRING>
JWT_EXPIRY=7d

# Database
DATABASE_URL=postgresql://biomate:password@localhost:5432/biomate

# Redis (for sessions and rate limiting)
REDIS_URL=redis://localhost:6379

# Stripe
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...

# Email Service (SendGrid, AWS SES, etc.)
EMAIL_SERVICE=sendgrid
EMAIL_API_KEY=SG....
EMAIL_FROM=noreply@biomate.com

# Security
COOKIE_DOMAIN=.biomate.com
CORS_ORIGIN=https://biomate.com

# Application
NODE_ENV=production
PORT=3000
```

**Generate JWT Secret:**
```bash
# In terminal
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

---

## API Routes Summary

### Authentication Routes

```javascript
// frontend/server/routes/auth.ts

import express from 'express';
import { AuthService } from '../services/auth-service';
import { authRateLimiter } from '../middleware/rate-limiter';
import { validateRegistration, validateLogin } from '../middleware/validators';

const router = express.Router();
const authService = new AuthService();

// Register new user
router.post('/register',
  authRateLimiter,
  validateRegistration,
  async (req, res) => {
    try {
      const { user, token } = await authService.registerUser(req.body);

      // Set cookie
      setAuthCookie(res, token);

      res.status(201).json({
        success: true,
        user: sanitizeUser(user),
        token
      });
    } catch (error) {
      res.status(400).json({
        success: false,
        error: error.message
      });
    }
  }
);

// Login existing user
router.post('/login',
  authRateLimiter,
  validateLogin,
  async (req, res) => {
    try {
      const { email, password } = req.body;
      const { user, token, subscriptionStatus } =
        await authService.loginUser(email, password);

      // Set cookie
      setAuthCookie(res, token);

      res.json({
        success: true,
        user: sanitizeUser(user),
        token,
        subscription: subscriptionStatus
      });
    } catch (error) {
      if (error.message === 'TRIAL_EXPIRED') {
        return res.status(403).json({
          success: false,
          error: 'trial_expired',
          message: 'Your trial has expired. Please subscribe to continue.'
        });
      }

      res.status(401).json({
        success: false,
        error: 'Invalid credentials'
      });
    }
  }
);

// Logout
router.post('/logout',
  authenticateRequest,
  async (req, res) => {
    // Clear cookie
    clearAuthCookie(res);

    // Optionally: Invalidate token in Redis/DB

    res.json({
      success: true,
      message: 'Logged out successfully'
    });
  }
);

// Get current user
router.get('/me',
  authenticateRequest,
  async (req, res) => {
    res.json({
      success: true,
      user: sanitizeUser(req.user),
      subscription: req.subscription
    });
  }
);

// Refresh token (optional, if implementing token refresh)
router.post('/refresh',
  authenticateRequest,
  async (req, res) => {
    const newToken = authService.generateToken(req.user);
    setAuthCookie(res, newToken);

    res.json({
      success: true,
      token: newToken
    });
  }
);

export default router;
```

---

## Frontend Integration

### Login Component

```typescript
// frontend/client/src/components/auth/LoginForm.tsx

import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';

export const LoginForm: React.FC = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',  // Important for cookies
        body: JSON.stringify({ email, password })
      });

      const data = await response.json();

      if (!response.ok) {
        if (data.error === 'trial_expired') {
          // Redirect to pricing page
          navigate('/pricing?expired=true');
          return;
        }
        throw new Error(data.error || 'Login failed');
      }

      // Store token in localStorage as backup (optional)
      localStorage.setItem('biomate_token', data.token);

      // Redirect to chat/workflow page
      navigate('/chat');

    } catch (error) {
      setError(error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="login-form">
      <h2>Login to BioMate</h2>

      {error && <div className="error-message">{error}</div>}

      <div className="form-group">
        <label htmlFor="email">Email</label>
        <input
          type="email"
          id="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          disabled={loading}
        />
      </div>

      <div className="form-group">
        <label htmlFor="password">Password</label>
        <input
          type="password"
          id="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          disabled={loading}
        />
      </div>

      <button type="submit" disabled={loading}>
        {loading ? 'Logging in...' : 'Login'}
      </button>

      <div className="links">
        <a href="/forgot-password">Forgot password?</a>
        <a href="/register">Don't have an account? Sign up</a>
      </div>
    </form>
  );
};
```

---

### Protected Route Component

```typescript
// frontend/client/src/components/auth/ProtectedRoute.tsx

import React, { useEffect, useState } from 'react';
import { Navigate } from 'react-router-dom';

interface ProtectedRouteProps {
  children: React.ReactNode;
}

export const ProtectedRoute: React.FC<ProtectedRouteProps> = ({ children }) => {
  const [authenticated, setAuthenticated] = useState<boolean | null>(null);
  const [subscriptionActive, setSubscriptionActive] = useState<boolean>(true);

  useEffect(() => {
    checkAuth();
  }, []);

  const checkAuth = async () => {
    try {
      const response = await fetch('/api/auth/me', {
        credentials: 'include'
      });

      if (!response.ok) {
        setAuthenticated(false);
        return;
      }

      const data = await response.json();
      setAuthenticated(true);
      setSubscriptionActive(data.subscription.active);

    } catch (error) {
      setAuthenticated(false);
    }
  };

  if (authenticated === null) {
    return <div>Loading...</div>;
  }

  if (!authenticated) {
    return <Navigate to="/login" />;
  }

  if (!subscriptionActive) {
    return <Navigate to="/pricing?expired=true" />;
  }

  return <>{children}</>;
};
```

---

## Testing Checklist

### Manual Testing

- [ ] **Registration Flow**
  - [ ] Register with valid email/password
  - [ ] Verify email uniqueness check
  - [ ] Verify password validation
  - [ ] Verify Terms checkbox requirement
  - [ ] Verify auto-login after registration
  - [ ] Verify redirect to /chat
  - [ ] Verify welcome email sent
  - [ ] Verify Stripe customer created

- [ ] **Login Flow**
  - [ ] Login with valid credentials
  - [ ] Login with invalid email
  - [ ] Login with wrong password
  - [ ] Verify rate limiting (5 attempts)
  - [ ] Verify redirect to /chat on success
  - [ ] Verify last_login_at updated

- [ ] **Trial Period**
  - [ ] Access chat/workflow during trial (days 1-7)
  - [ ] Verify trial countdown display
  - [ ] Attempt access after trial expires
  - [ ] Verify redirect to pricing page
  - [ ] Verify cannot use trial twice

- [ ] **Session Management**
  - [ ] Token persists across page refreshes
  - [ ] Token expires after 7 days
  - [ ] Logout clears token
  - [ ] Cannot access protected routes without token

- [ ] **Security**
  - [ ] HTTPS enforced
  - [ ] Cookies are HTTP-only
  - [ ] Rate limiting works on /login
  - [ ] Password hashing (never plain text)

---

## Deployment Steps

### 1. Database Setup

```bash
# Create database
createdb biomate_production

# Run migrations
psql -U biomate -d biomate_production -f migrations/001_create_users_table.sql
psql -U biomate -d biomate_production -f migrations/002_create_sessions_table.sql
```

### 2. Redis Setup

```bash
# Install Redis
sudo apt install redis-server

# Start Redis
sudo systemctl start redis
sudo systemctl enable redis

# Test Redis
redis-cli ping  # Should return PONG
```

### 3. Environment Configuration

```bash
# Copy production environment file
cp .env.example .env.production

# Generate JWT secret
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))" >> .env.production

# Edit .env.production with actual values
nano .env.production
```

### 4. SSL Certificate (Let's Encrypt)

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d biomate.com -d www.biomate.com

# Verify auto-renewal
sudo certbot renew --dry-run
```

### 5. Application Deployment

```bash
# Build application
npm run build

# Start with PM2
pm2 start npm --name "biomate-frontend" -- run start:prod
pm2 save
pm2 startup
```

---

## Monitoring & Logging

### Authentication Metrics

**Track:**
- Registration rate (daily/weekly)
- Login success/failure rate
- Trial conversion rate
- Token expiration rate
- Rate limit hits
- Session duration

**Alerts:**
- Failed login rate > 10% (potential attack)
- Registration spike (potential bot activity)
- Rate limit frequently hit (adjust limits or investigate)

---

## Next Phase (Post-Launch)

**Phase 2 Enhancements:**
1. Email verification (send verification link on registration)
2. Password reset flow
3. OAuth integration (Google, GitHub)
4. Multi-factor authentication (TOTP)
5. Session management UI (view/revoke active sessions)
6. Security audit log (login history, IP tracking)

---

## Document Status

**Version:** 1.0
**Status:** Ready for Implementation
**Estimated Implementation Time:** 3-5 days
**Dependencies:** Database, Redis, Stripe integration
**Testing Time:** 1-2 days

