# User Authentication & Payment System Implementation Plan

**Date:** 2025-10-14
**Branch:** frontend_stronger
**Project:** BioMate - User Login, State Persistence, and Payment Integration

---

## Executive Summary

This plan outlines the implementation of:
1. **User Authentication** - Login interface with email validation
2. **State Persistence** - Save user's UI state, workflows, datasets, and history
3. **Payment System** - 10-day free trial, then subscription-based charging

**Estimated Timeline:** 3-4 weeks
**Complexity:** Medium-High
**Dependencies:** Existing Galaxy user management system, payment gateway (Stripe recommended)

---

## Part 1: User Authentication System

### 1.1 Frontend - Login Interface

#### Components to Create/Modify

**New Component: `client/src/components/Login/EmailValidatedLogin.vue`**
```vue
<template>
  <div class="login-container">
    <!-- Email/Password Login Form -->
    <form @submit.prevent="handleLogin">
      <input v-model="email" type="email" required
             placeholder="Email" @blur="validateEmail" />
      <span v-if="emailError" class="error">{{ emailError }}</span>

      <input v-model="password" type="password" required
             placeholder="Password" />

      <button type="submit" :disabled="!isFormValid">Login</button>
    </form>

    <!-- Email Verification Status -->
    <div v-if="requiresVerification" class="verification-notice">
      Please verify your email. <a @click="resendVerification">Resend</a>
    </div>

    <!-- Registration Link -->
    <router-link to="/register">Create Account</router-link>
  </div>
</template>

<script>
export default {
  data() {
    return {
      email: '',
      password: '',
      emailError: null,
      requiresVerification: false
    }
  },
  methods: {
    validateEmail() {
      // Real-time email validation
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
      if (!emailRegex.test(this.email)) {
        this.emailError = 'Invalid email format'
        return false
      }
      this.emailError = null
      return true
    },
    async handleLogin() {
      // POST /api/auth/login
      // On success: save token, redirect to dashboard
      // On email not verified: show verification notice
    },
    async resendVerification() {
      // POST /api/auth/resend-verification
    }
  }
}
</script>
```

**New Component: `client/src/components/Registration/RegisterForm.vue`**
- Email input with real-time validation
- Password with strength meter
- Terms of service checkbox
- Submit → Send verification email

**Modify: `client/src/components/Login/LoginIndex.vue`**
- Route to new `EmailValidatedLogin.vue`
- Add social login options (optional, future)

#### Routing Updates

**`client/src/router/index.js`** - Add routes:
```javascript
{
  path: '/login',
  component: () => import('@/components/Login/EmailValidatedLogin.vue')
},
{
  path: '/register',
  component: () => import('@/components/Registration/RegisterForm.vue')
},
{
  path: '/verify-email/:token',
  component: () => import('@/components/Registration/EmailVerification.vue')
}
```

#### State Management

**`client/src/store/modules/auth.js`** - New Vuex module:
```javascript
export default {
  state: {
    user: null,
    token: null,
    isAuthenticated: false,
    emailVerified: false,
    trialEndsAt: null
  },
  mutations: {
    SET_USER(state, user) {
      state.user = user
      state.isAuthenticated = true
      state.emailVerified = user.email_verified
      state.trialEndsAt = user.trial_ends_at
    },
    LOGOUT(state) {
      state.user = null
      state.token = null
      state.isAuthenticated = false
    }
  },
  actions: {
    async login({ commit }, { email, password }) {
      const response = await axios.post('/api/auth/login', { email, password })
      commit('SET_USER', response.data.user)
      localStorage.setItem('auth_token', response.data.token)
    },
    async logout({ commit }) {
      await axios.post('/api/auth/logout')
      localStorage.removeItem('auth_token')
      commit('LOGOUT')
    }
  }
}
```

### 1.2 Backend - Authentication API

#### Database Schema Updates

**New Table: `user_sessions`**
```sql
CREATE TABLE user_sessions (
    session_id TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    token TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    last_activity TIMESTAMP,
    ip_address TEXT,
    user_agent TEXT,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_user_sessions_token ON user_sessions(token);
```

**Update Table: `galaxy_user`**
```sql
ALTER TABLE galaxy_user ADD COLUMN email_verified INTEGER DEFAULT 0;
ALTER TABLE galaxy_user ADD COLUMN verification_token TEXT;
ALTER TABLE galaxy_user ADD COLUMN verification_sent_at TIMESTAMP;
ALTER TABLE galaxy_user ADD COLUMN trial_starts_at TIMESTAMP;
ALTER TABLE galaxy_user ADD COLUMN trial_ends_at TIMESTAMP;
ALTER TABLE galaxy_user ADD COLUMN subscription_status TEXT DEFAULT 'trial';
-- subscription_status: 'trial', 'active', 'past_due', 'canceled'
```

#### API Endpoints

**`lib/galaxy/webapps/galaxy/api/auth.py`** - New controller:

```python
class AuthController(BaseGalaxyAPIController):

    @expose_api
    def login(self, trans, payload, **kwargs):
        """
        POST /api/auth/login
        {
            "email": "user@example.com",
            "password": "password123"
        }

        Returns:
        {
            "token": "jwt_token_here",
            "user": { id, email, username, email_verified, trial_ends_at },
            "requires_verification": false
        }
        """
        email = payload.get('email')
        password = payload.get('password')

        user = trans.sa_session.query(trans.app.model.User)\
            .filter_by(email=email).first()

        if not user or not user.check_password(password):
            raise exceptions.AuthenticationFailed("Invalid credentials")

        if not user.email_verified:
            return {
                "requires_verification": True,
                "email": email
            }

        # Create session token
        token = self._create_session_token(trans, user)

        return {
            "token": token,
            "user": self._user_to_dict(user),
            "requires_verification": False
        }

    @expose_api
    def register(self, trans, payload, **kwargs):
        """
        POST /api/auth/register
        {
            "email": "user@example.com",
            "username": "username",
            "password": "password123"
        }

        Returns:
        {
            "success": true,
            "message": "Verification email sent to user@example.com"
        }
        """
        email = payload.get('email')
        username = payload.get('username')
        password = payload.get('password')

        # Validate email format
        if not self._validate_email_format(email):
            raise exceptions.RequestParameterInvalidException("Invalid email format")

        # Check if user exists
        existing = trans.sa_session.query(trans.app.model.User)\
            .filter((trans.app.model.User.email == email) |
                    (trans.app.model.User.username == username)).first()

        if existing:
            raise exceptions.DuplicatedIdentifierException("User already exists")

        # Create user
        user = trans.app.model.User(
            email=email,
            username=username,
            password=password,
            email_verified=0,
            verification_token=self._generate_verification_token(),
            verification_sent_at=datetime.now(),
            trial_starts_at=datetime.now(),
            trial_ends_at=datetime.now() + timedelta(days=10),
            subscription_status='trial'
        )
        trans.sa_session.add(user)
        trans.sa_session.flush()

        # Send verification email
        self._send_verification_email(trans, user)

        return {
            "success": True,
            "message": f"Verification email sent to {email}"
        }

    @expose_api
    def verify_email(self, trans, payload, **kwargs):
        """
        POST /api/auth/verify-email
        {
            "token": "verification_token_here"
        }

        Returns:
        {
            "success": true,
            "token": "session_token",
            "user": {...}
        }
        """
        token = payload.get('token')

        user = trans.sa_session.query(trans.app.model.User)\
            .filter_by(verification_token=token).first()

        if not user:
            raise exceptions.ObjectNotFound("Invalid verification token")

        # Check token expiry (24 hours)
        if datetime.now() - user.verification_sent_at > timedelta(hours=24):
            raise exceptions.RequestParameterInvalidException("Verification token expired")

        user.email_verified = 1
        user.verification_token = None
        trans.sa_session.flush()

        # Auto-login after verification
        session_token = self._create_session_token(trans, user)

        return {
            "success": True,
            "token": session_token,
            "user": self._user_to_dict(user)
        }

    @expose_api
    def resend_verification(self, trans, payload, **kwargs):
        """
        POST /api/auth/resend-verification
        {
            "email": "user@example.com"
        }
        """
        email = payload.get('email')
        user = trans.sa_session.query(trans.app.model.User)\
            .filter_by(email=email).first()

        if not user:
            # Don't reveal if user exists
            return {"success": True}

        if user.email_verified:
            raise exceptions.RequestParameterInvalidException("Email already verified")

        # Rate limit: max 3 emails per hour
        if user.verification_sent_at and \
           datetime.now() - user.verification_sent_at < timedelta(minutes=20):
            raise exceptions.RequestParameterInvalidException(
                "Please wait before requesting another verification email"
            )

        user.verification_token = self._generate_verification_token()
        user.verification_sent_at = datetime.now()
        trans.sa_session.flush()

        self._send_verification_email(trans, user)

        return {"success": True}

    def _create_session_token(self, trans, user):
        """Create JWT or session token"""
        import jwt
        from datetime import datetime, timedelta

        payload = {
            'user_id': user.id,
            'exp': datetime.utcnow() + timedelta(days=30),
            'iat': datetime.utcnow()
        }

        token = jwt.encode(payload, trans.app.config.secret_key, algorithm='HS256')

        # Store session in database
        session = trans.app.model.UserSession(
            user_id=user.id,
            token=token,
            expires_at=datetime.now() + timedelta(days=30),
            ip_address=trans.request.remote_addr,
            user_agent=trans.request.headers.get('User-Agent')
        )
        trans.sa_session.add(session)
        trans.sa_session.flush()

        return token

    def _send_verification_email(self, trans, user):
        """Send verification email using existing email system"""
        from galaxy.util.mail import send_mail

        verification_url = f"{trans.app.config.get('base_url', '')}/verify-email/{user.verification_token}"

        body = f"""
        Welcome to BioMate!

        Please verify your email address by clicking the link below:
        {verification_url}

        This link will expire in 24 hours.

        If you didn't create this account, please ignore this email.
        """

        send_mail(
            trans.app.config,
            to=user.email,
            subject="Verify Your BioMate Account",
            body=body
        )
```

#### Middleware for Authentication

**`lib/galaxy/web/framework/middleware/auth_middleware.py`** - New file:

```python
class AuthenticationMiddleware:
    """Middleware to validate JWT tokens and attach user to request"""

    def __init__(self, app, config):
        self.app = app
        self.config = config

    def __call__(self, environ, start_response):
        request = Request(environ)

        # Extract token from Authorization header
        auth_header = request.headers.get('Authorization')
        if auth_header and auth_header.startswith('Bearer '):
            token = auth_header[7:]
            user = self._validate_token(token)
            if user:
                environ['galaxy.user'] = user

        return self.app(environ, start_response)

    def _validate_token(self, token):
        """Validate JWT token and return user"""
        import jwt
        try:
            payload = jwt.decode(token, self.config.secret_key, algorithms=['HS256'])
            user_id = payload.get('user_id')

            # Check if session exists and is not expired
            session = self.app.model.context.query(self.app.model.UserSession)\
                .filter_by(token=token).first()

            if session and session.expires_at > datetime.now():
                # Update last activity
                session.last_activity = datetime.now()
                self.app.model.context.flush()

                return self.app.model.context.query(self.app.model.User)\
                    .filter_by(id=user_id).first()
        except jwt.ExpiredSignatureError:
            pass
        except jwt.InvalidTokenError:
            pass

        return None
```

---

## Part 2: User State Persistence

**IMPORTANT:** See `COMPREHENSIVE_USER_STATE_ANALYSIS.md` for complete details on 15 categories of user state.

### 2.1 Current State Management (Findings from Code Analysis)

**Frontend Architecture:**
- Uses **Pinia** for state management (70+ stores)
- Extensively uses **`useUserLocalStorage()`** composable (auto-scoped per user via hashed ID)
- Storage pattern: `galaxy:{hashedUserId}:{key}`
- **Already isolated per-user in localStorage** ✅
- Uses **IndexedDB (Dexie)** for tags storage

**Critical Finding:** Much of the state is ALREADY persisted in localStorage, BUT:
- ❌ Not synced across devices
- ❌ Lost if browser cache cleared
- ❌ No backup/recovery

### 2.2 What to Track (15 Categories Identified)

**Tier 1: Critical State (Must sync to backend immediately)**
1. **User Profile & Auth** - email verification, last login, profile picture
2. **Subscription Status** - trial/active status, payment info
3. **Workflow Drafts** - unsaved workflows, editor state (zoom, position, active nodes)
4. **AI Conversation History** - chat messages, generated workflows, suggestions
5. **Favorite Tools & Datasets** - marked favorites with custom order

**Tier 2: Important State (Sync periodically, debounced)**
6. **Tool Usage History** - recently used (50), frequency, context (which workflows/datasets)
7. **Dataset Usage** - recently accessed, usage count, tool combinations
8. **History State** - pinned histories, filter texts, custom metadata
9. **Workflow Executions** - invocation history, status, inputs/outputs, errors
10. **Activity Bar & Layout** - panel widths, sidebar state, custom activities
11. **Search History** - tool/workflow/dataset searches, filter presets
12. **Tags & Annotations** - user-defined tags, usage frequency

**Tier 3: Cache-Only (Keep in localStorage, optional sync)**
13. **UI Component States** - list view mode, collapsed sections, "has seen help" flags
14. **Interactive Tool Sessions** - active sessions, saved states
15. **Quotas & Usage Stats** - storage/compute usage, API rate limits

**Detailed Breakdown:** Each category documented with database schemas and frontend state structures in `COMPREHENSIVE_USER_STATE_ANALYSIS.md`

### 2.2 Database Schema

#### New Table: `user_ui_state`

```sql
CREATE TABLE user_ui_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    state_key TEXT NOT NULL,  -- e.g., 'workflow_editor', 'tool_panel', 'history_panel'
    state_data TEXT NOT NULL,  -- JSON blob
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, state_key)
);

CREATE INDEX idx_user_ui_state_user ON user_ui_state(user_id);
```

#### New Table: `user_workflow_history`

```sql
CREATE TABLE user_workflow_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    workflow_id TEXT,  -- UUID of workflow
    workflow_name TEXT,
    workflow_data TEXT,  -- JSON workflow definition
    execution_status TEXT,  -- 'draft', 'running', 'completed', 'failed'
    execution_results TEXT,  -- JSON results
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX idx_workflow_history_user ON user_workflow_history(user_id);
CREATE INDEX idx_workflow_history_status ON user_workflow_history(execution_status);
```

#### New Table: `user_dataset_usage`

```sql
CREATE TABLE user_dataset_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    dataset_id TEXT NOT NULL,  -- e.g., 'biomate_dataset_bindingdb'
    usage_count INTEGER DEFAULT 1,
    last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    usage_context TEXT,  -- JSON: which workflows/tools used with
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, dataset_id)
);

CREATE INDEX idx_dataset_usage_user ON user_dataset_usage(user_id);
```

#### New Table: `user_tool_favorites`

```sql
CREATE TABLE user_tool_favorites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    tool_id TEXT NOT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, tool_id)
);

CREATE INDEX idx_tool_favorites_user ON user_tool_favorites(user_id);
```

### 2.3 Frontend - State Management

#### Vuex Store: `client/src/store/modules/userState.js`

```javascript
export default {
  namespaced: true,

  state: {
    uiState: {
      workflowEditor: {},
      toolPanel: { expanded: true, activeCategory: null },
      historyPanel: { expanded: true, filter: '' },
      recentTools: [],
      favoriteTools: []
    },
    workflowHistory: [],
    datasetUsage: [],
    unsavedChanges: false
  },

  mutations: {
    SET_UI_STATE(state, { key, data }) {
      state.uiState[key] = data
      state.unsavedChanges = true
    },

    SET_WORKFLOW_HISTORY(state, history) {
      state.workflowHistory = history
    },

    ADD_RECENT_TOOL(state, toolId) {
      state.uiState.recentTools = [
        toolId,
        ...state.uiState.recentTools.filter(id => id !== toolId)
      ].slice(0, 10)
      state.unsavedChanges = true
    },

    MARK_SAVED(state) {
      state.unsavedChanges = false
    }
  },

  actions: {
    async loadUserState({ commit, rootState }) {
      const userId = rootState.auth.user.id
      const response = await axios.get(`/api/users/${userId}/state`)

      commit('SET_UI_STATE', { key: 'workflowEditor', data: response.data.workflowEditor })
      commit('SET_UI_STATE', { key: 'toolPanel', data: response.data.toolPanel })
      commit('SET_WORKFLOW_HISTORY', response.data.workflowHistory)
    },

    async saveUIState({ state, rootState }, { key, data }) {
      const userId = rootState.auth.user.id
      await axios.post(`/api/users/${userId}/state/${key}`, data)
      commit('SET_UI_STATE', { key, data })
      commit('MARK_SAVED')
    },

    async trackToolUsage({ commit, rootState }, toolId) {
      const userId = rootState.auth.user.id
      await axios.post(`/api/users/${userId}/tools/usage`, { toolId })
      commit('ADD_RECENT_TOOL', toolId)
    },

    async saveWorkflowDraft({ rootState }, { workflowId, workflowData }) {
      const userId = rootState.auth.user.id
      await axios.post(`/api/users/${userId}/workflows/save`, {
        workflowId,
        workflowData,
        status: 'draft'
      })
    }
  }
}
```

#### Auto-Save Strategy

**`client/src/plugins/autoSave.js`** - Vue plugin:

```javascript
export default {
  install(app, options) {
    let saveTimeout = null

    // Watch for state changes and debounce saves
    app.config.globalProperties.$autoSave = function(key, data) {
      clearTimeout(saveTimeout)
      saveTimeout = setTimeout(() => {
        this.$store.dispatch('userState/saveUIState', { key, data })
      }, 2000)  // Save 2 seconds after last change
    }

    // Save on window unload
    window.addEventListener('beforeunload', (e) => {
      const store = app.config.globalProperties.$store
      if (store.state.userState.unsavedChanges) {
        e.preventDefault()
        e.returnValue = 'You have unsaved changes. Are you sure you want to leave?'
      }
    })
  }
}
```

### 2.4 Backend - State Persistence API

**`lib/galaxy/webapps/galaxy/api/user_state.py`** - New controller:

```python
class UserStateController(BaseGalaxyAPIController):

    @expose_api
    @require_login
    def get_state(self, trans, **kwargs):
        """
        GET /api/users/{user_id}/state

        Returns all saved UI state for the user
        """
        user_id = trans.user.id

        states = trans.sa_session.query(trans.app.model.UserUIState)\
            .filter_by(user_id=user_id).all()

        ui_state = {state.state_key: json.loads(state.state_data)
                    for state in states}

        # Load workflow history
        workflows = trans.sa_session.query(trans.app.model.UserWorkflowHistory)\
            .filter_by(user_id=user_id)\
            .order_by(trans.app.model.UserWorkflowHistory.updated_at.desc())\
            .limit(50).all()

        workflow_history = [self._workflow_to_dict(w) for w in workflows]

        # Load recent datasets
        datasets = trans.sa_session.query(trans.app.model.UserDatasetUsage)\
            .filter_by(user_id=user_id)\
            .order_by(trans.app.model.UserDatasetUsage.last_used_at.desc())\
            .limit(20).all()

        dataset_usage = [self._dataset_usage_to_dict(d) for d in datasets]

        # Load favorite tools
        favorites = trans.sa_session.query(trans.app.model.UserToolFavorites)\
            .filter_by(user_id=user_id).all()

        favorite_tools = [f.tool_id for f in favorites]

        return {
            **ui_state,
            'workflowHistory': workflow_history,
            'datasetUsage': dataset_usage,
            'favoriteTools': favorite_tools
        }

    @expose_api
    @require_login
    def save_ui_state(self, trans, state_key, payload, **kwargs):
        """
        POST /api/users/{user_id}/state/{state_key}

        Save UI state for a specific component
        """
        user_id = trans.user.id
        state_data = json.dumps(payload)

        existing = trans.sa_session.query(trans.app.model.UserUIState)\
            .filter_by(user_id=user_id, state_key=state_key).first()

        if existing:
            existing.state_data = state_data
            existing.updated_at = datetime.now()
        else:
            new_state = trans.app.model.UserUIState(
                user_id=user_id,
                state_key=state_key,
                state_data=state_data
            )
            trans.sa_session.add(new_state)

        trans.sa_session.flush()

        return {"success": True}

    @expose_api
    @require_login
    def save_workflow(self, trans, payload, **kwargs):
        """
        POST /api/users/{user_id}/workflows/save

        Save workflow (draft or execution)
        """
        user_id = trans.user.id
        workflow_id = payload.get('workflowId')
        workflow_data = payload.get('workflowData')
        status = payload.get('status', 'draft')

        existing = trans.sa_session.query(trans.app.model.UserWorkflowHistory)\
            .filter_by(user_id=user_id, workflow_id=workflow_id).first()

        if existing:
            existing.workflow_data = json.dumps(workflow_data)
            existing.execution_status = status
            existing.updated_at = datetime.now()
        else:
            new_workflow = trans.app.model.UserWorkflowHistory(
                user_id=user_id,
                workflow_id=workflow_id,
                workflow_name=workflow_data.get('name', 'Untitled'),
                workflow_data=json.dumps(workflow_data),
                execution_status=status
            )
            trans.sa_session.add(new_workflow)

        trans.sa_session.flush()

        return {"success": True, "workflowId": workflow_id}

    @expose_api
    @require_login
    def track_tool_usage(self, trans, payload, **kwargs):
        """
        POST /api/users/{user_id}/tools/usage

        Track tool usage for recommendations
        """
        user_id = trans.user.id
        tool_id = payload.get('toolId')

        # Simple tracking - increment usage count
        # Could be expanded for analytics

        return {"success": True}
```

---

## Part 3: Payment System with 10-Day Trial

### 3.1 Payment Gateway Selection

**Recommended: Stripe**
- Industry standard
- Strong API
- Support for subscriptions, trials, webhooks
- PCI compliance handled by Stripe

**Alternative: PayPal**
- More regions supported
- Easier for some users

### 3.2 Database Schema

#### New Table: `user_subscriptions`

```sql
CREATE TABLE user_subscriptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL UNIQUE,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    plan_type TEXT DEFAULT 'monthly',  -- 'monthly', 'annual'
    status TEXT DEFAULT 'trial',  -- 'trial', 'active', 'past_due', 'canceled'
    trial_start TIMESTAMP,
    trial_end TIMESTAMP,
    current_period_start TIMESTAMP,
    current_period_end TIMESTAMP,
    cancel_at_period_end INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX idx_subscriptions_user ON user_subscriptions(user_id);
CREATE INDEX idx_subscriptions_stripe_customer ON user_subscriptions(stripe_customer_id);
```

#### New Table: `payment_transactions`

```sql
CREATE TABLE payment_transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    stripe_payment_intent_id TEXT,
    amount REAL NOT NULL,
    currency TEXT DEFAULT 'USD',
    status TEXT,  -- 'pending', 'succeeded', 'failed', 'refunded'
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX idx_transactions_user ON payment_transactions(user_id);
CREATE INDEX idx_transactions_stripe ON payment_transactions(stripe_payment_intent_id);
```

### 3.3 Frontend - Payment Interface

#### Component: `client/src/components/Payment/SubscriptionManager.vue`

```vue
<template>
  <div class="subscription-manager">
    <!-- Trial Status Banner -->
    <div v-if="isTrial" class="trial-banner">
      <h3>Free Trial Active</h3>
      <p>{{ daysRemaining }} days remaining in your trial</p>
      <button @click="showPaymentForm = true">Subscribe Now</button>
    </div>

    <!-- Current Subscription Info -->
    <div v-else-if="hasActiveSubscription" class="subscription-info">
      <h3>Active Subscription</h3>
      <p>Plan: {{ subscription.plan_type }}</p>
      <p>Next billing: {{ subscription.current_period_end }}</p>
      <button @click="manageSubscription">Manage Subscription</button>
    </div>

    <!-- Payment Form -->
    <div v-if="showPaymentForm" class="payment-form">
      <h3>Subscribe to BioMate</h3>

      <!-- Plan Selection -->
      <div class="plan-selection">
        <label>
          <input type="radio" v-model="selectedPlan" value="monthly" />
          Monthly - $29/month
        </label>
        <label>
          <input type="radio" v-model="selectedPlan" value="annual" />
          Annual - $290/year (save $58)
        </label>
      </div>

      <!-- Stripe Card Element -->
      <div id="card-element" class="stripe-card"></div>
      <div v-if="cardError" class="error">{{ cardError }}</div>

      <button @click="handleSubscribe" :disabled="processing">
        {{ processing ? 'Processing...' : 'Subscribe' }}
      </button>
    </div>

    <!-- Expiration Warning -->
    <div v-if="isExpiringSoon" class="expiration-warning">
      <h3>Trial Ending Soon</h3>
      <p>Your trial ends in {{ daysRemaining }} days. Subscribe to continue using BioMate.</p>
      <button @click="showPaymentForm = true">Subscribe Now</button>
    </div>
  </div>
</template>

<script>
export default {
  data() {
    return {
      subscription: null,
      selectedPlan: 'monthly',
      showPaymentForm: false,
      cardElement: null,
      stripe: null,
      processing: false,
      cardError: null
    }
  },

  computed: {
    isTrial() {
      return this.subscription?.status === 'trial'
    },
    hasActiveSubscription() {
      return ['active', 'past_due'].includes(this.subscription?.status)
    },
    daysRemaining() {
      if (!this.subscription?.trial_end) return 0
      const end = new Date(this.subscription.trial_end)
      const now = new Date()
      return Math.max(0, Math.ceil((end - now) / (1000 * 60 * 60 * 24)))
    },
    isExpiringSoon() {
      return this.isTrial && this.daysRemaining <= 3
    }
  },

  async mounted() {
    await this.loadSubscription()
    await this.initializeStripe()
  },

  methods: {
    async loadSubscription() {
      const response = await axios.get('/api/subscription/status')
      this.subscription = response.data
    },

    async initializeStripe() {
      // Load Stripe.js
      const stripe = await loadStripe(process.env.VUE_APP_STRIPE_PUBLIC_KEY)
      this.stripe = stripe

      // Create card element
      const elements = stripe.elements()
      this.cardElement = elements.create('card')
      this.cardElement.mount('#card-element')

      this.cardElement.on('change', (event) => {
        this.cardError = event.error ? event.error.message : null
      })
    },

    async handleSubscribe() {
      this.processing = true

      try {
        // Create payment method
        const { paymentMethod, error } = await this.stripe.createPaymentMethod({
          type: 'card',
          card: this.cardElement
        })

        if (error) {
          this.cardError = error.message
          return
        }

        // Create subscription on backend
        const response = await axios.post('/api/subscription/create', {
          paymentMethodId: paymentMethod.id,
          planType: this.selectedPlan
        })

        if (response.data.requiresAction) {
          // Handle 3D Secure
          const { error: confirmError } = await this.stripe.confirmCardPayment(
            response.data.clientSecret
          )

          if (confirmError) {
            this.cardError = confirmError.message
            return
          }
        }

        // Success!
        await this.loadSubscription()
        this.showPaymentForm = false
        this.$notify({
          type: 'success',
          message: 'Subscription activated successfully!'
        })

      } catch (error) {
        this.cardError = error.response?.data?.message || 'Payment failed'
      } finally {
        this.processing = false
      }
    },

    async manageSubscription() {
      // Redirect to Stripe customer portal
      const response = await axios.post('/api/subscription/portal')
      window.location.href = response.data.url
    }
  }
}
</script>
```

#### Component: `client/src/components/Payment/TrialExpirationModal.vue`

```vue
<template>
  <modal v-if="showModal" @close="handleClose">
    <div class="trial-expiration">
      <h2>Your Trial Has Ended</h2>
      <p>Subscribe to BioMate to continue accessing your workflows and data.</p>

      <div class="features">
        <ul>
          <li>✓ Unlimited workflow generation</li>
          <li>✓ Access to 9,000+ bioinformatics tools</li>
          <li>✓ 122 curated datasets</li>
          <li>✓ Persistent workspace</li>
        </ul>
      </div>

      <SubscriptionManager />
    </div>
  </modal>
</template>

<script>
export default {
  computed: {
    showModal() {
      const subscription = this.$store.state.auth.user?.subscription
      return subscription?.status === 'trial' &&
             new Date(subscription.trial_end) < new Date()
    }
  },

  methods: {
    handleClose() {
      // Can't close - must subscribe or logout
      this.$confirm('You must subscribe to continue using BioMate.')
    }
  }
}
</script>
```

### 3.4 Backend - Payment API

**`lib/galaxy/webapps/galaxy/api/subscription.py`** - New controller:

```python
import stripe
from datetime import datetime, timedelta

class SubscriptionController(BaseGalaxyAPIController):

    def __init__(self, app):
        super().__init__(app)
        stripe.api_key = app.config.stripe_secret_key

    @expose_api
    @require_login
    def get_status(self, trans, **kwargs):
        """
        GET /api/subscription/status

        Returns subscription status for logged-in user
        """
        user_id = trans.user.id

        subscription = trans.sa_session.query(trans.app.model.UserSubscription)\
            .filter_by(user_id=user_id).first()

        if not subscription:
            return {
                "status": "none",
                "message": "No subscription found"
            }

        return self._subscription_to_dict(subscription)

    @expose_api
    @require_login
    def create_subscription(self, trans, payload, **kwargs):
        """
        POST /api/subscription/create
        {
            "paymentMethodId": "pm_xxx",
            "planType": "monthly"
        }

        Creates a Stripe subscription
        """
        user_id = trans.user.id
        payment_method_id = payload.get('paymentMethodId')
        plan_type = payload.get('planType', 'monthly')

        user_subscription = trans.sa_session.query(trans.app.model.UserSubscription)\
            .filter_by(user_id=user_id).first()

        # Create or retrieve Stripe customer
        if user_subscription and user_subscription.stripe_customer_id:
            customer_id = user_subscription.stripe_customer_id
        else:
            customer = stripe.Customer.create(
                email=trans.user.email,
                payment_method=payment_method_id,
                invoice_settings={
                    'default_payment_method': payment_method_id
                }
            )
            customer_id = customer.id

        # Determine price ID based on plan
        price_id = trans.app.config.stripe_monthly_price_id if plan_type == 'monthly' \
                   else trans.app.config.stripe_annual_price_id

        # Create subscription
        try:
            stripe_subscription = stripe.Subscription.create(
                customer=customer_id,
                items=[{'price': price_id}],
                payment_behavior='default_incomplete',
                expand=['latest_invoice.payment_intent']
            )

            # Update local subscription record
            if user_subscription:
                user_subscription.stripe_customer_id = customer_id
                user_subscription.stripe_subscription_id = stripe_subscription.id
                user_subscription.status = 'active'
                user_subscription.plan_type = plan_type
                user_subscription.current_period_start = datetime.fromtimestamp(
                    stripe_subscription.current_period_start
                )
                user_subscription.current_period_end = datetime.fromtimestamp(
                    stripe_subscription.current_period_end
                )
                user_subscription.updated_at = datetime.now()
            else:
                user_subscription = trans.app.model.UserSubscription(
                    user_id=user_id,
                    stripe_customer_id=customer_id,
                    stripe_subscription_id=stripe_subscription.id,
                    status='active',
                    plan_type=plan_type,
                    current_period_start=datetime.fromtimestamp(
                        stripe_subscription.current_period_start
                    ),
                    current_period_end=datetime.fromtimestamp(
                        stripe_subscription.current_period_end
                    )
                )
                trans.sa_session.add(user_subscription)

            trans.sa_session.flush()

            # Check if requires action (3D Secure)
            latest_invoice = stripe_subscription.latest_invoice
            payment_intent = latest_invoice.payment_intent

            if payment_intent.status == 'requires_action':
                return {
                    "requiresAction": True,
                    "clientSecret": payment_intent.client_secret
                }

            return {
                "success": True,
                "subscription": self._subscription_to_dict(user_subscription)
            }

        except stripe.error.CardError as e:
            raise exceptions.MessageException(f"Payment failed: {e.user_message}")

    @expose_api
    @require_login
    def create_portal_session(self, trans, **kwargs):
        """
        POST /api/subscription/portal

        Creates Stripe customer portal session for managing subscription
        """
        user_id = trans.user.id

        subscription = trans.sa_session.query(trans.app.model.UserSubscription)\
            .filter_by(user_id=user_id).first()

        if not subscription or not subscription.stripe_customer_id:
            raise exceptions.ObjectNotFound("No subscription found")

        session = stripe.billing_portal.Session.create(
            customer=subscription.stripe_customer_id,
            return_url=f"{trans.app.config.base_url}/subscription"
        )

        return {"url": session.url}

    @expose_api
    def webhook(self, trans, payload, **kwargs):
        """
        POST /api/subscription/webhook

        Stripe webhook handler for subscription events
        """
        sig_header = trans.request.headers.get('Stripe-Signature')
        endpoint_secret = trans.app.config.stripe_webhook_secret

        try:
            event = stripe.Webhook.construct_event(
                trans.request.body, sig_header, endpoint_secret
            )
        except ValueError:
            raise exceptions.RequestParameterInvalidException("Invalid payload")
        except stripe.error.SignatureVerificationError:
            raise exceptions.AuthenticationFailed("Invalid signature")

        # Handle different event types
        if event.type == 'customer.subscription.updated':
            self._handle_subscription_updated(trans, event.data.object)
        elif event.type == 'customer.subscription.deleted':
            self._handle_subscription_deleted(trans, event.data.object)
        elif event.type == 'invoice.payment_succeeded':
            self._handle_payment_succeeded(trans, event.data.object)
        elif event.type == 'invoice.payment_failed':
            self._handle_payment_failed(trans, event.data.object)

        return {"received": True}

    def _handle_subscription_updated(self, trans, stripe_subscription):
        """Update local subscription when Stripe subscription changes"""
        subscription = trans.sa_session.query(trans.app.model.UserSubscription)\
            .filter_by(stripe_subscription_id=stripe_subscription.id).first()

        if subscription:
            subscription.status = stripe_subscription.status
            subscription.current_period_start = datetime.fromtimestamp(
                stripe_subscription.current_period_start
            )
            subscription.current_period_end = datetime.fromtimestamp(
                stripe_subscription.current_period_end
            )
            subscription.cancel_at_period_end = 1 if stripe_subscription.cancel_at_period_end else 0
            subscription.updated_at = datetime.now()
            trans.sa_session.flush()

    def _handle_subscription_deleted(self, trans, stripe_subscription):
        """Handle subscription cancellation"""
        subscription = trans.sa_session.query(trans.app.model.UserSubscription)\
            .filter_by(stripe_subscription_id=stripe_subscription.id).first()

        if subscription:
            subscription.status = 'canceled'
            subscription.updated_at = datetime.now()
            trans.sa_session.flush()

    def _handle_payment_succeeded(self, trans, invoice):
        """Record successful payment"""
        subscription = trans.sa_session.query(trans.app.model.UserSubscription)\
            .filter_by(stripe_customer_id=invoice.customer).first()

        if subscription:
            transaction = trans.app.model.PaymentTransaction(
                user_id=subscription.user_id,
                stripe_payment_intent_id=invoice.payment_intent,
                amount=invoice.amount_paid / 100.0,  # Convert cents to dollars
                currency=invoice.currency.upper(),
                status='succeeded',
                description=f"Subscription payment - {subscription.plan_type}"
            )
            trans.sa_session.add(transaction)
            trans.sa_session.flush()

    def _handle_payment_failed(self, trans, invoice):
        """Handle failed payment"""
        subscription = trans.sa_session.query(trans.app.model.UserSubscription)\
            .filter_by(stripe_customer_id=invoice.customer).first()

        if subscription:
            subscription.status = 'past_due'
            subscription.updated_at = datetime.now()

            transaction = trans.app.model.PaymentTransaction(
                user_id=subscription.user_id,
                stripe_payment_intent_id=invoice.payment_intent,
                amount=invoice.amount_due / 100.0,
                currency=invoice.currency.upper(),
                status='failed',
                description=f"Failed subscription payment - {subscription.plan_type}"
            )
            trans.sa_session.add(transaction)
            trans.sa_session.flush()

            # TODO: Send email notification to user
```

### 3.5 Trial Management

#### Automatic Trial Creation

**Update Registration Handler:**

```python
# In lib/galaxy/webapps/galaxy/api/auth.py
def register(self, trans, payload, **kwargs):
    # ... existing code ...

    user = trans.app.model.User(
        email=email,
        username=username,
        password=password,
        # ... existing fields ...
    )
    trans.sa_session.add(user)
    trans.sa_session.flush()

    # Create trial subscription
    trial_subscription = trans.app.model.UserSubscription(
        user_id=user.id,
        status='trial',
        trial_start=datetime.now(),
        trial_end=datetime.now() + timedelta(days=10),
        plan_type='monthly'
    )
    trans.sa_session.add(trial_subscription)
    trans.sa_session.flush()

    # ... rest of registration ...
```

#### Access Control Middleware

**`lib/galaxy/web/framework/middleware/subscription_middleware.py`:**

```python
class SubscriptionMiddleware:
    """Middleware to check subscription status and block access if expired"""

    def __init__(self, app, config):
        self.app = app
        self.config = config
        self.exempt_paths = ['/api/auth/', '/api/subscription/', '/login', '/register']

    def __call__(self, environ, start_response):
        request = Request(environ)

        # Check if path is exempt
        if any(request.path.startswith(path) for path in self.exempt_paths):
            return self.app(environ, start_response)

        # Check user subscription
        user = environ.get('galaxy.user')
        if user:
            subscription = self._get_subscription(user.id)

            if subscription:
                # Check if trial expired
                if subscription.status == 'trial' and \
                   datetime.now() > subscription.trial_end:
                    return self._subscription_required_response(start_response)

                # Check if subscription inactive
                if subscription.status in ['canceled', 'past_due']:
                    return self._subscription_required_response(start_response)

        return self.app(environ, start_response)

    def _subscription_required_response(self, start_response):
        """Return 402 Payment Required response"""
        status = '402 Payment Required'
        response_headers = [('Content-Type', 'application/json')]
        start_response(status, response_headers)

        return [json.dumps({
            "error": "Subscription required",
            "message": "Your trial has expired. Please subscribe to continue."
        }).encode()]
```

---

## Implementation Phases

### Phase 1: Authentication (Week 1)

**Tasks:**
1. Create database tables (`user_sessions`, update `galaxy_user`)
2. Implement backend auth API (`/api/auth/login`, `/register`, `/verify-email`)
3. Create frontend login components (`EmailValidatedLogin.vue`, `RegisterForm.vue`)
4. Implement JWT token system
5. Add email verification flow
6. Test registration and login

**Deliverables:**
- Users can register with email validation
- Users can login and get session token
- Email verification working
- Session management in place

### Phase 2: State Persistence (Week 2)

**Tasks:**
1. Create state tables (`user_ui_state`, `user_workflow_history`, etc.)
2. Implement backend state API (`/api/users/{id}/state`)
3. Create Vuex state management module
4. Implement auto-save plugin
5. Add state restoration on login
6. Test state persistence across sessions

**Deliverables:**
- UI state persists across sessions
- Workflow drafts auto-saved
- Recent tools/datasets tracked
- User sees previous state on login

### Phase 3: Payment Integration (Week 3)

**Tasks:**
1. Set up Stripe account and get API keys
2. Create subscription tables
3. Implement subscription API
4. Create payment frontend components
5. Implement trial logic (10 days)
6. Set up Stripe webhooks
7. Test subscription flow end-to-end

**Deliverables:**
- Trial starts automatically on registration
- Users can subscribe before/after trial
- Payment processing working
- Subscription status tracked

### Phase 4: Testing & Polish (Week 4)

**Tasks:**
1. Integration testing (auth + state + payment)
2. Edge case testing (expired trials, failed payments, etc.)
3. UI/UX refinements
4. Email templates polish
5. Documentation
6. Security audit

**Deliverables:**
- All flows tested
- Edge cases handled
- User documentation
- Deployment ready

---

## Configuration Requirements

### Environment Variables

**Add to `config/galaxy.yml`:**

```yaml
# Authentication
secret_key: "your-secret-key-here-min-32-chars"
jwt_expiry_days: 30
email_verification_expiry_hours: 24

# Email Configuration
smtp_server: "smtp.sendgrid.net"
smtp_port: 587
smtp_username: "apikey"
smtp_password: "your-sendgrid-api-key"
email_from: "noreply@biomate.com"

# Stripe Configuration
stripe_public_key: "pk_live_xxx"
stripe_secret_key: "sk_live_xxx"
stripe_webhook_secret: "whsec_xxx"
stripe_monthly_price_id: "price_monthly_xxx"
stripe_annual_price_id: "price_annual_xxx"

# Trial Configuration
trial_duration_days: 10
```

### Frontend Environment Variables

**`.env.production`:**
```
VUE_APP_API_URL=https://api.biomate.com
VUE_APP_STRIPE_PUBLIC_KEY=pk_live_xxx
```

---

## Security Considerations

### Authentication
1. **Password Security:**
   - Minimum 8 characters
   - Use bcrypt with salt rounds >= 12
   - Rate limit login attempts (max 5 per 15 min)

2. **JWT Tokens:**
   - Short expiry (30 days max)
   - Store in httpOnly cookies (not localStorage)
   - Refresh token rotation

3. **Email Verification:**
   - Tokens expire after 24 hours
   - Rate limit resend requests (max 3 per hour)

### Payment Security
1. **PCI Compliance:**
   - Never store card numbers
   - Use Stripe Elements (card data never touches server)
   - HTTPS only

2. **Webhook Verification:**
   - Always verify Stripe signature
   - Use webhook secrets

### Data Protection
1. **User Data:**
   - Encrypt sensitive state data
   - Anonymize analytics
   - GDPR compliance (export/delete user data)

---

## Success Metrics

### Authentication
- Registration completion rate > 80%
- Email verification rate > 70%
- Login success rate > 95%

### State Persistence
- State restoration success rate > 99%
- Auto-save failures < 0.1%
- User satisfaction (survey) > 4/5

### Payment
- Trial-to-paid conversion rate > 20%
- Payment success rate > 98%
- Churn rate < 10%/month

---

## Risk Mitigation

### Technical Risks
1. **Email Deliverability:**
   - Risk: Verification emails go to spam
   - Mitigation: Use SendGrid/AWS SES, set up SPF/DKIM

2. **Payment Failures:**
   - Risk: Stripe downtime or payment failures
   - Mitigation: Retry logic, grace period, multiple payment methods

3. **State Loss:**
   - Risk: Database corruption or sync failures
   - Mitigation: Regular backups, transaction logging, rollback capability

### Business Risks
1. **Low Conversion:**
   - Risk: Users don't convert after trial
   - Mitigation: Onboarding flow, usage nudges, value demonstration

2. **Support Load:**
   - Risk: Payment issues create support tickets
   - Mitigation: Clear error messages, self-service portal, FAQ

---

## Next Steps

1. **Review this plan** with team and stakeholders
2. **Set up development environment** (Stripe test mode, email sandbox)
3. **Create project board** with tasks from Phase 1
4. **Begin Phase 1 implementation** (Authentication)
5. **Schedule weekly check-ins** to track progress

---

**Questions to Resolve Before Starting:**

1. Pricing: What are the actual subscription prices (monthly/annual)?
2. Payment gateway: Confirm Stripe or alternative?
3. Email service: SendGrid, AWS SES, or other?
4. Deployment: Where will this be hosted? (affects HTTPS, domain setup)
5. Testing: Staging environment available?

---

**End of Implementation Plan**
