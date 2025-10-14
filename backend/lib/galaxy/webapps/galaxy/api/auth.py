"""
API operations for user authentication with email verification.

This module provides:
- User registration with email verification
- Login with JWT token generation
- Email verification flow
- Session management
- Password reset functionality
"""

import logging
import secrets
import sqlite3
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

import bcrypt
import jwt
from fastapi import (
    Body,
    HTTPException,
    Request,
    Response,
    status,
)
from pydantic import BaseModel, EmailStr, Field

from galaxy.exceptions import (
    ActionInputError,
    AuthenticationFailed,
    ObjectNotFound,
)
from galaxy.security.validate_user_input import (
    validate_email,
    validate_password,
)
from . import (
    depends,
    Router,
)

log = logging.getLogger(__name__)

router = Router(tags=["auth"])

# ============================================================================
# REQUEST/RESPONSE MODELS
# ============================================================================

class RegisterRequest(BaseModel):
    """User registration request"""
    email: EmailStr = Field(..., description="User email address")
    username: str = Field(..., min_length=3, max_length=50, description="Username")
    password: str = Field(..., min_length=8, description="Password (min 8 characters)")


class LoginRequest(BaseModel):
    """User login request"""
    email: EmailStr = Field(..., description="User email address")
    password: str = Field(..., description="User password")


class LoginResponse(BaseModel):
    """Login response with JWT token"""
    token: str = Field(..., description="JWT authentication token")
    user_id: int = Field(..., description="User ID")
    email: str = Field(..., description="User email")
    username: str = Field(..., description="Username")
    email_verified: bool = Field(..., description="Whether email is verified")
    subscription_status: str = Field(..., description="Subscription status (trial/active/expired)")
    trial_ends_at: Optional[str] = Field(None, description="Trial end date (ISO 8601)")


class VerifyEmailRequest(BaseModel):
    """Email verification request"""
    token: str = Field(..., description="Email verification token")


class ResendVerificationRequest(BaseModel):
    """Resend verification email request"""
    email: EmailStr = Field(..., description="User email address")


class MessageResponse(BaseModel):
    """Generic message response"""
    message: str


# ============================================================================
# AUTHENTICATION SERVICE
# ============================================================================

class AuthService:
    """Service for authentication operations"""

    def __init__(self, db_path: str = "galaxy_ai_tools.db", config: Dict[str, Any] = None):
        self.db_path = db_path
        self.config = config or {}

        # JWT configuration
        self.jwt_secret = self.config.get('jwt_secret_key', 'CHANGE_ME_IN_PRODUCTION')
        self.jwt_algorithm = self.config.get('jwt_algorithm', 'HS256')
        self.jwt_expiry_days = self.config.get('jwt_expiry_days', 30)

        # Trial configuration
        self.trial_duration_days = self.config.get('trial_duration_days', 10)

        # Rate limiting configuration
        self.email_resend_interval = self.config.get('email_resend_min_interval_minutes', 20)

    def _get_db(self) -> sqlite3.Connection:
        """Get database connection"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _hash_password(self, password: str) -> str:
        """Hash password using bcrypt"""
        return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    def _verify_password(self, password: str, hashed: str) -> bool:
        """Verify password against hash"""
        return bcrypt.checkpw(password.encode('utf-8'), hashed.encode('utf-8'))

    def _generate_token(self, length: int = 32) -> str:
        """Generate random token"""
        return secrets.token_urlsafe(length)

    def _create_jwt_token(self, user_id: int, email: str) -> str:
        """Create JWT token"""
        expiry = datetime.utcnow() + timedelta(days=self.jwt_expiry_days)
        payload = {
            'user_id': user_id,
            'email': email,
            'exp': expiry,
            'iat': datetime.utcnow(),
        }
        return jwt.encode(payload, self.jwt_secret, algorithm=self.jwt_algorithm)

    def register_user(self, email: str, username: str, password: str) -> Dict[str, Any]:
        """
        Register new user with email verification

        Args:
            email: User email
            username: Username
            password: Plain text password

        Returns:
            Dict with user info and verification token

        Raises:
            ActionInputError: If validation fails or user exists
        """
        # Validate inputs
        validate_email(email)
        validate_password(password, confirm=password)

        if len(username) < 3 or len(username) > 50:
            raise ActionInputError("Username must be between 3 and 50 characters")

        # Hash password
        password_hash = self._hash_password(password)

        # Generate verification token
        verification_token = self._generate_token()

        # Calculate trial dates
        now = datetime.utcnow()
        trial_starts_at = now.isoformat()
        trial_ends_at = (now + timedelta(days=self.trial_duration_days)).isoformat()

        conn = self._get_db()
        try:
            # Check if user already exists
            existing = conn.execute(
                "SELECT id, email FROM galaxy_user WHERE email = ? OR username = ?",
                (email, username)
            ).fetchone()

            if existing:
                raise ActionInputError("User with this email or username already exists")

            # Insert user
            cursor = conn.execute("""
                INSERT INTO galaxy_user (
                    email, username, password, create_time,
                    email_verified, verification_token, verification_sent_at,
                    trial_starts_at, trial_ends_at, subscription_status
                )
                VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, 'trial')
            """, (
                email, username, password_hash, now.isoformat(),
                verification_token, now.isoformat(),
                trial_starts_at, trial_ends_at
            ))

            user_id = cursor.lastrowid

            # Create subscription record
            conn.execute("""
                INSERT INTO user_subscriptions (
                    user_id, status, trial_start, trial_end, created_at, updated_at
                )
                VALUES (?, 'trial', ?, ?, ?, ?)
            """, (user_id, trial_starts_at, trial_ends_at, now.isoformat(), now.isoformat()))

            conn.commit()

            log.info(f"User registered: {email} (ID: {user_id})")

            return {
                'user_id': user_id,
                'email': email,
                'username': username,
                'verification_token': verification_token,
                'trial_ends_at': trial_ends_at,
            }

        except sqlite3.IntegrityError as e:
            raise ActionInputError(f"Registration failed: {str(e)}")
        finally:
            conn.close()

    def login_user(self, email: str, password: str, ip_address: str = None,
                   user_agent: str = None) -> LoginResponse:
        """
        Authenticate user and create session

        Args:
            email: User email
            password: Plain text password
            ip_address: Client IP address
            user_agent: Client user agent

        Returns:
            LoginResponse with JWT token and user info

        Raises:
            AuthenticationFailed: If credentials are invalid
        """
        conn = self._get_db()
        try:
            # Get user
            user = conn.execute("""
                SELECT id, email, username, password, email_verified,
                       subscription_status, trial_ends_at
                FROM galaxy_user
                WHERE email = ?
            """, (email,)).fetchone()

            if not user:
                raise AuthenticationFailed("Invalid email or password")

            # Verify password
            if not self._verify_password(password, user['password']):
                raise AuthenticationFailed("Invalid email or password")

            # Generate JWT token
            token = self._create_jwt_token(user['id'], user['email'])

            # Create session
            now = datetime.utcnow()
            expires_at = (now + timedelta(days=self.jwt_expiry_days)).isoformat()

            conn.execute("""
                INSERT INTO user_sessions (
                    user_id, session_id, token, expires_at,
                    last_activity, ip_address, user_agent, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                user['id'], self._generate_token(16), token, expires_at,
                now.isoformat(), ip_address or '', user_agent or '', now.isoformat()
            ))

            # Update last login
            conn.execute("""
                UPDATE galaxy_user
                SET last_login_at = ?
                WHERE id = ?
            """, (now.isoformat(), user['id']))

            conn.commit()

            log.info(f"User logged in: {email} (ID: {user['id']})")

            return LoginResponse(
                token=token,
                user_id=user['id'],
                email=user['email'],
                username=user['username'],
                email_verified=bool(user['email_verified']),
                subscription_status=user['subscription_status'] or 'trial',
                trial_ends_at=user['trial_ends_at'],
            )

        finally:
            conn.close()

    def verify_email(self, token: str) -> Dict[str, Any]:
        """
        Verify user email with token

        Args:
            token: Email verification token

        Returns:
            Dict with user info

        Raises:
            ObjectNotFound: If token is invalid
            ActionInputError: If token is expired
        """
        conn = self._get_db()
        try:
            # Find user by token
            user = conn.execute("""
                SELECT id, email, username, verification_sent_at, email_verified
                FROM galaxy_user
                WHERE verification_token = ?
            """, (token,)).fetchone()

            if not user:
                raise ObjectNotFound("Invalid verification token")

            if user['email_verified']:
                return {
                    'user_id': user['id'],
                    'email': user['email'],
                    'message': 'Email already verified'
                }

            # Check token expiry (24 hours)
            sent_at = datetime.fromisoformat(user['verification_sent_at'])
            if datetime.utcnow() - sent_at > timedelta(hours=24):
                raise ActionInputError("Verification token has expired. Please request a new one.")

            # Mark email as verified
            conn.execute("""
                UPDATE galaxy_user
                SET email_verified = 1, verification_token = NULL
                WHERE id = ?
            """, (user['id'],))

            conn.commit()

            log.info(f"Email verified: {user['email']} (ID: {user['id']})")

            return {
                'user_id': user['id'],
                'email': user['email'],
                'username': user['username'],
                'message': 'Email verified successfully'
            }

        finally:
            conn.close()

    def resend_verification_email(self, email: str) -> Dict[str, Any]:
        """
        Resend verification email

        Args:
            email: User email

        Returns:
            Dict with new verification token

        Raises:
            ObjectNotFound: If user not found
            ActionInputError: If rate limited or already verified
        """
        conn = self._get_db()
        try:
            # Get user
            user = conn.execute("""
                SELECT id, email, email_verified, verification_sent_at
                FROM galaxy_user
                WHERE email = ?
            """, (email,)).fetchone()

            if not user:
                raise ObjectNotFound("User not found")

            if user['email_verified']:
                raise ActionInputError("Email is already verified")

            # Check rate limit
            if user['verification_sent_at']:
                sent_at = datetime.fromisoformat(user['verification_sent_at'])
                time_since = datetime.utcnow() - sent_at
                if time_since < timedelta(minutes=self.email_resend_interval):
                    minutes_left = self.email_resend_interval - (time_since.seconds // 60)
                    raise ActionInputError(
                        f"Please wait {minutes_left} minutes before requesting another verification email"
                    )

            # Generate new token
            new_token = self._generate_token()
            now = datetime.utcnow()

            conn.execute("""
                UPDATE galaxy_user
                SET verification_token = ?, verification_sent_at = ?
                WHERE id = ?
            """, (new_token, now.isoformat(), user['id']))

            conn.commit()

            log.info(f"Verification email resent: {email}")

            return {
                'email': email,
                'verification_token': new_token,
                'message': 'Verification email sent'
            }

        finally:
            conn.close()

    def verify_jwt_token(self, token: str) -> Dict[str, Any]:
        """
        Verify and decode JWT token

        Args:
            token: JWT token

        Returns:
            Dict with decoded token payload

        Raises:
            AuthenticationFailed: If token is invalid or expired
        """
        try:
            payload = jwt.decode(token, self.jwt_secret, algorithms=[self.jwt_algorithm])
            return payload
        except jwt.ExpiredSignatureError:
            raise AuthenticationFailed("Token has expired")
        except jwt.InvalidTokenError:
            raise AuthenticationFailed("Invalid token")


# ============================================================================
# API ENDPOINTS
# ============================================================================

# Global service instance (will be initialized by app)
auth_service: Optional[AuthService] = None


def get_auth_service() -> AuthService:
    """Dependency to get auth service"""
    global auth_service
    if auth_service is None:
        # TODO: Load config from Galaxy configuration
        auth_service = AuthService()
    return auth_service


@router.post(
    "/api/auth/register",
    summary="Register new user with email verification",
    response_model=MessageResponse,
    status_code=status.HTTP_201_CREATED,
)
def register(
    request: RegisterRequest = Body(...),
    service: AuthService = depends(get_auth_service)
) -> MessageResponse:
    """
    Register a new user account.

    - **email**: Valid email address (will need verification)
    - **username**: Unique username (3-50 characters)
    - **password**: Password (minimum 8 characters)

    Returns success message. User must verify email before full access.
    Starts 10-day free trial automatically.
    """
    try:
        result = service.register_user(
            email=request.email,
            username=request.username,
            password=request.password
        )

        # TODO: Send verification email using email service
        # email_service.send_verification_email(
        #     to=result['email'],
        #     token=result['verification_token']
        # )

        log.info(f"Registration successful: {request.email}")

        return MessageResponse(
            message=f"Registration successful! Please check {request.email} for verification link. "
                   f"Your {service.trial_duration_days}-day free trial has started."
        )

    except (ActionInputError, AuthenticationFailed) as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        log.error(f"Registration failed: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                          detail="Registration failed")


@router.post(
    "/api/auth/login",
    summary="Login with email and password",
    response_model=LoginResponse,
)
def login(
    request: LoginRequest = Body(...),
    http_request: Request = None,
    service: AuthService = depends(get_auth_service)
) -> LoginResponse:
    """
    Authenticate user and receive JWT token.

    - **email**: User email address
    - **password**: User password

    Returns JWT token and user information.
    Use the token in Authorization header: `Bearer <token>`
    """
    try:
        # Get client info
        ip_address = http_request.client.host if http_request else None
        user_agent = http_request.headers.get('user-agent', '') if http_request else None

        response = service.login_user(
            email=request.email,
            password=request.password,
            ip_address=ip_address,
            user_agent=user_agent
        )

        return response

    except AuthenticationFailed as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))
    except Exception as e:
        log.error(f"Login failed: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                          detail="Login failed")


@router.post(
    "/api/auth/verify-email",
    summary="Verify email address with token",
    response_model=MessageResponse,
)
def verify_email(
    request: VerifyEmailRequest = Body(...),
    service: AuthService = depends(get_auth_service)
) -> MessageResponse:
    """
    Verify user email address using verification token.

    - **token**: Verification token from email

    Returns success message if verification succeeds.
    """
    try:
        result = service.verify_email(token=request.token)
        return MessageResponse(message=result['message'])

    except ObjectNotFound as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except ActionInputError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        log.error(f"Email verification failed: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                          detail="Verification failed")


@router.post(
    "/api/auth/resend-verification",
    summary="Resend verification email",
    response_model=MessageResponse,
)
def resend_verification(
    request: ResendVerificationRequest = Body(...),
    service: AuthService = depends(get_auth_service)
) -> MessageResponse:
    """
    Resend email verification link.

    - **email**: User email address

    Rate limited to prevent abuse (default: 1 email per 20 minutes).
    """
    try:
        result = service.resend_verification_email(email=request.email)

        # TODO: Send verification email using email service
        # email_service.send_verification_email(
        #     to=result['email'],
        #     token=result['verification_token']
        # )

        return MessageResponse(message=result['message'])

    except ObjectNotFound as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except ActionInputError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        log.error(f"Resend verification failed: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                          detail="Failed to resend verification email")


@router.get(
    "/api/auth/verify-token",
    summary="Verify JWT token is valid",
    response_model=Dict[str, Any],
)
def verify_token(
    http_request: Request,
    service: AuthService = depends(get_auth_service)
) -> Dict[str, Any]:
    """
    Verify that a JWT token is valid and not expired.

    Requires Authorization header: `Bearer <token>`

    Returns decoded token payload if valid.
    """
    try:
        # Get token from Authorization header
        auth_header = http_request.headers.get('authorization', '')
        if not auth_header.startswith('Bearer '):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing or invalid Authorization header"
            )

        token = auth_header[7:]  # Remove 'Bearer ' prefix
        payload = service.verify_jwt_token(token)

        return {
            'valid': True,
            'user_id': payload['user_id'],
            'email': payload['email'],
            'expires_at': datetime.fromtimestamp(payload['exp']).isoformat()
        }

    except AuthenticationFailed as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))
    except Exception as e:
        log.error(f"Token verification failed: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                          detail="Token verification failed")
