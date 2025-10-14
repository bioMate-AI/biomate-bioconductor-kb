"""
API operations for subscription and payment management with Stripe.

Handles:
- Trial management (10-day free trial)
- Subscription creation and management
- Payment processing via Stripe
- Webhook handling for Stripe events
- Customer portal access
"""

import logging
import sqlite3
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

try:
    import stripe
    STRIPE_AVAILABLE = True
except ImportError:
    STRIPE_AVAILABLE = False

from fastapi import (
    Body,
    HTTPException,
    Header,
    Path,
    Query,
    Request,
    Response,
    status,
)
from pydantic import BaseModel, Field

from galaxy.exceptions import (
    ActionInputError,
    ObjectNotFound,
)
from . import (
    depends,
    Router,
)

log = logging.getLogger(__name__)

router = Router(tags=["subscription"])


# ============================================================================
# REQUEST/RESPONSE MODELS
# ============================================================================

class SubscriptionStatus(BaseModel):
    """User subscription status"""
    user_id: int
    status: str = Field(..., description="trial, active, past_due, canceled, expired")
    plan_type: Optional[str] = Field(None, description="monthly or annual")
    trial_start: Optional[str] = None
    trial_end: Optional[str] = None
    current_period_start: Optional[str] = None
    current_period_end: Optional[str] = None
    cancel_at_period_end: bool = False
    stripe_customer_id: Optional[str] = None
    stripe_subscription_id: Optional[str] = None


class CreateCheckoutSessionRequest(BaseModel):
    """Request to create Stripe checkout session"""
    plan_type: str = Field(..., description="monthly or annual")
    success_url: str = Field(..., description="URL to redirect on success")
    cancel_url: str = Field(..., description="URL to redirect on cancel")


class CheckoutSessionResponse(BaseModel):
    """Checkout session response"""
    session_id: str
    checkout_url: str


class PortalSessionResponse(BaseModel):
    """Customer portal session response"""
    portal_url: str


class WebhookResponse(BaseModel):
    """Webhook response"""
    received: bool
    message: str


# ============================================================================
# SUBSCRIPTION SERVICE
# ============================================================================

class SubscriptionService:
    """Service for managing subscriptions and payments"""

    def __init__(self, db_path: str = "galaxy_ai_tools.db", config: Dict[str, Any] = None):
        if not STRIPE_AVAILABLE:
            raise ImportError("Stripe library not installed. Run: pip install stripe")

        self.db_path = db_path
        self.config = config or {}

        # Stripe configuration
        stripe_config = self.config.get('stripe', {})
        stripe.api_key = stripe_config.get('secret_key', '')
        self.publishable_key = stripe_config.get('publishable_key', '')
        self.webhook_secret = stripe_config.get('webhook_secret', '')
        self.test_mode = stripe_config.get('test_mode', True)

        # Price IDs from Stripe Dashboard
        price_ids = stripe_config.get('price_ids', {})
        self.monthly_price_id = price_ids.get('monthly', '')
        self.annual_price_id = price_ids.get('annual', '')

        # App URLs
        app_config = self.config.get('app', {})
        self.base_url = app_config.get('base_url', 'http://localhost:8080')

        log.info(f"Subscription service initialized (test_mode: {self.test_mode})")

    def _get_db(self) -> sqlite3.Connection:
        """Get database connection"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def get_subscription_status(self, user_id: int) -> SubscriptionStatus:
        """Get user's subscription status"""
        conn = self._get_db()
        try:
            # Get user and subscription info
            user = conn.execute("""
                SELECT u.id, u.email, u.subscription_status,
                       u.trial_starts_at, u.trial_ends_at,
                       s.stripe_customer_id, s.stripe_subscription_id,
                       s.plan_type, s.status, s.trial_start, s.trial_end,
                       s.current_period_start, s.current_period_end,
                       s.cancel_at_period_end
                FROM galaxy_user u
                LEFT JOIN user_subscriptions s ON u.id = s.user_id
                WHERE u.id = ?
            """, (user_id,)).fetchone()

            if not user:
                raise ObjectNotFound(f"User {user_id} not found")

            # Check if trial has expired
            status = user['subscription_status'] or 'trial'
            if status == 'trial' and user['trial_ends_at']:
                trial_end = datetime.fromisoformat(user['trial_ends_at'])
                if datetime.utcnow() > trial_end:
                    status = 'expired'
                    # Update status
                    conn.execute("""
                        UPDATE galaxy_user SET subscription_status = 'expired'
                        WHERE id = ?
                    """, (user_id,))
                    conn.commit()

            return SubscriptionStatus(
                user_id=user['id'],
                status=status,
                plan_type=user['plan_type'],
                trial_start=user['trial_starts_at'] or user['trial_start'],
                trial_end=user['trial_ends_at'] or user['trial_end'],
                current_period_start=user['current_period_start'],
                current_period_end=user['current_period_end'],
                cancel_at_period_end=bool(user['cancel_at_period_end']),
                stripe_customer_id=user['stripe_customer_id'],
                stripe_subscription_id=user['stripe_subscription_id']
            )

        finally:
            conn.close()

    def create_checkout_session(
        self,
        user_id: int,
        plan_type: str,
        success_url: str,
        cancel_url: str
    ) -> CheckoutSessionResponse:
        """Create Stripe checkout session"""
        if plan_type not in ('monthly', 'annual'):
            raise ActionInputError("plan_type must be 'monthly' or 'annual'")

        conn = self._get_db()
        try:
            # Get user info
            user = conn.execute("""
                SELECT id, email, subscription_status
                FROM galaxy_user
                WHERE id = ?
            """, (user_id,)).fetchone()

            if not user:
                raise ObjectNotFound(f"User {user_id} not found")

            # Get or create Stripe customer
            subscription = conn.execute("""
                SELECT stripe_customer_id FROM user_subscriptions
                WHERE user_id = ?
            """, (user_id,)).fetchone()

            if subscription and subscription['stripe_customer_id']:
                customer_id = subscription['stripe_customer_id']
            else:
                # Create new Stripe customer
                customer = stripe.Customer.create(
                    email=user['email'],
                    metadata={'user_id': user_id}
                )
                customer_id = customer.id

                # Save customer ID
                conn.execute("""
                    UPDATE user_subscriptions
                    SET stripe_customer_id = ?, updated_at = ?
                    WHERE user_id = ?
                """, (customer_id, datetime.utcnow().isoformat(), user_id))
                conn.commit()

                log.info(f"Created Stripe customer for user {user_id}: {customer_id}")

            # Determine price ID
            price_id = self.monthly_price_id if plan_type == 'monthly' else self.annual_price_id

            if not price_id:
                raise ActionInputError(
                    f"Price ID not configured for {plan_type} plan. "
                    "Please configure Stripe price IDs in auth_payment_config.yml"
                )

            # Create checkout session
            session = stripe.checkout.Session.create(
                customer=customer_id,
                payment_method_types=['card'],
                line_items=[{
                    'price': price_id,
                    'quantity': 1,
                }],
                mode='subscription',
                success_url=success_url,
                cancel_url=cancel_url,
                metadata={
                    'user_id': user_id,
                    'plan_type': plan_type
                }
            )

            log.info(f"Created checkout session for user {user_id}: {session.id}")

            return CheckoutSessionResponse(
                session_id=session.id,
                checkout_url=session.url
            )

        except stripe.error.StripeError as e:
            log.error(f"Stripe error creating checkout session: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Payment processing error: {str(e)}"
            )
        finally:
            conn.close()

    def create_portal_session(self, user_id: int, return_url: str) -> PortalSessionResponse:
        """Create Stripe customer portal session"""
        conn = self._get_db()
        try:
            # Get Stripe customer ID
            subscription = conn.execute("""
                SELECT stripe_customer_id FROM user_subscriptions
                WHERE user_id = ?
            """, (user_id,)).fetchone()

            if not subscription or not subscription['stripe_customer_id']:
                raise ObjectNotFound("No active subscription found")

            # Create portal session
            session = stripe.billing_portal.Session.create(
                customer=subscription['stripe_customer_id'],
                return_url=return_url
            )

            log.info(f"Created portal session for user {user_id}")

            return PortalSessionResponse(portal_url=session.url)

        except stripe.error.StripeError as e:
            log.error(f"Stripe error creating portal session: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Payment portal error: {str(e)}"
            )
        finally:
            conn.close()

    def handle_webhook(self, payload: bytes, signature: str) -> Dict[str, Any]:
        """Handle Stripe webhook events"""
        try:
            # Verify webhook signature
            event = stripe.Webhook.construct_event(
                payload, signature, self.webhook_secret
            )

            log.info(f"Received Stripe webhook: {event['type']}")

            # Handle different event types
            if event['type'] == 'checkout.session.completed':
                self._handle_checkout_completed(event['data']['object'])

            elif event['type'] == 'customer.subscription.created':
                self._handle_subscription_created(event['data']['object'])

            elif event['type'] == 'customer.subscription.updated':
                self._handle_subscription_updated(event['data']['object'])

            elif event['type'] == 'customer.subscription.deleted':
                self._handle_subscription_deleted(event['data']['object'])

            elif event['type'] == 'invoice.payment_succeeded':
                self._handle_payment_succeeded(event['data']['object'])

            elif event['type'] == 'invoice.payment_failed':
                self._handle_payment_failed(event['data']['object'])

            return {'status': 'processed', 'event_type': event['type']}

        except stripe.error.SignatureVerificationError as e:
            log.error(f"Webhook signature verification failed: {e}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid signature"
            )
        except Exception as e:
            log.error(f"Webhook handling error: {e}")
            raise

    def _handle_checkout_completed(self, session: Dict[str, Any]):
        """Handle successful checkout"""
        user_id = int(session['metadata']['user_id'])
        plan_type = session['metadata']['plan_type']
        customer_id = session['customer']
        subscription_id = session['subscription']

        conn = self._get_db()
        try:
            now = datetime.utcnow().isoformat()

            # Update subscription record
            conn.execute("""
                UPDATE user_subscriptions
                SET stripe_customer_id = ?,
                    stripe_subscription_id = ?,
                    plan_type = ?,
                    status = 'active',
                    updated_at = ?
                WHERE user_id = ?
            """, (customer_id, subscription_id, plan_type, now, user_id))

            # Update user status
            conn.execute("""
                UPDATE galaxy_user
                SET subscription_status = 'active'
                WHERE id = ?
            """, (user_id,))

            conn.commit()

            log.info(f"Checkout completed for user {user_id}, subscription {subscription_id}")

        finally:
            conn.close()

    def _handle_subscription_created(self, subscription: Dict[str, Any]):
        """Handle subscription creation"""
        customer_id = subscription['customer']
        subscription_id = subscription['id']

        conn = self._get_db()
        try:
            # Find user by customer ID
            user = conn.execute("""
                SELECT user_id FROM user_subscriptions
                WHERE stripe_customer_id = ?
            """, (customer_id,)).fetchone()

            if not user:
                log.warning(f"No user found for customer {customer_id}")
                return

            user_id = user['user_id']
            now = datetime.utcnow().isoformat()
            current_period_end = datetime.fromtimestamp(
                subscription['current_period_end']
            ).isoformat()

            # Update subscription
            conn.execute("""
                UPDATE user_subscriptions
                SET stripe_subscription_id = ?,
                    current_period_start = ?,
                    current_period_end = ?,
                    status = 'active',
                    updated_at = ?
                WHERE user_id = ?
            """, (
                subscription_id,
                now,
                current_period_end,
                now,
                user_id
            ))

            conn.commit()

            log.info(f"Subscription created for user {user_id}: {subscription_id}")

        finally:
            conn.close()

    def _handle_subscription_updated(self, subscription: Dict[str, Any]):
        """Handle subscription update"""
        subscription_id = subscription['id']
        new_status = subscription['status']
        cancel_at_period_end = subscription.get('cancel_at_period_end', False)

        conn = self._get_db()
        try:
            now = datetime.utcnow().isoformat()
            current_period_end = datetime.fromtimestamp(
                subscription['current_period_end']
            ).isoformat()

            # Update subscription
            conn.execute("""
                UPDATE user_subscriptions
                SET status = ?,
                    current_period_end = ?,
                    cancel_at_period_end = ?,
                    updated_at = ?
                WHERE stripe_subscription_id = ?
            """, (
                new_status,
                current_period_end,
                1 if cancel_at_period_end else 0,
                now,
                subscription_id
            ))

            # Update user status
            conn.execute("""
                UPDATE galaxy_user
                SET subscription_status = ?
                WHERE id IN (
                    SELECT user_id FROM user_subscriptions
                    WHERE stripe_subscription_id = ?
                )
            """, (new_status, subscription_id))

            conn.commit()

            log.info(f"Subscription {subscription_id} updated to status: {new_status}")

        finally:
            conn.close()

    def _handle_subscription_deleted(self, subscription: Dict[str, Any]):
        """Handle subscription cancellation"""
        subscription_id = subscription['id']

        conn = self._get_db()
        try:
            now = datetime.utcnow().isoformat()

            # Update subscription
            conn.execute("""
                UPDATE user_subscriptions
                SET status = 'canceled',
                    updated_at = ?
                WHERE stripe_subscription_id = ?
            """, (now, subscription_id))

            # Update user status
            conn.execute("""
                UPDATE galaxy_user
                SET subscription_status = 'canceled'
                WHERE id IN (
                    SELECT user_id FROM user_subscriptions
                    WHERE stripe_subscription_id = ?
                )
            """, (subscription_id,))

            conn.commit()

            log.info(f"Subscription {subscription_id} canceled")

        finally:
            conn.close()

    def _handle_payment_succeeded(self, invoice: Dict[str, Any]):
        """Handle successful payment"""
        subscription_id = invoice.get('subscription')
        amount = invoice['amount_paid'] / 100  # Convert cents to dollars

        if not subscription_id:
            return

        conn = self._get_db()
        try:
            # Find user
            user = conn.execute("""
                SELECT user_id FROM user_subscriptions
                WHERE stripe_subscription_id = ?
            """, (subscription_id,)).fetchone()

            if not user:
                log.warning(f"No user found for subscription {subscription_id}")
                return

            user_id = user['user_id']
            now = datetime.utcnow().isoformat()

            # Record payment transaction
            conn.execute("""
                INSERT INTO payment_transactions (
                    user_id, subscription_id, stripe_payment_intent_id,
                    amount, currency, status, metadata, created_at
                )
                VALUES (?, ?, ?, ?, ?, 'succeeded', '{}', ?)
            """, (
                user_id,
                subscription_id,
                invoice.get('payment_intent', ''),
                amount,
                invoice['currency'].upper(),
                now
            ))

            # Update subscription status to active
            conn.execute("""
                UPDATE user_subscriptions
                SET status = 'active', updated_at = ?
                WHERE stripe_subscription_id = ?
            """, (now, subscription_id))

            conn.execute("""
                UPDATE galaxy_user
                SET subscription_status = 'active'
                WHERE id = ?
            """, (user_id,))

            conn.commit()

            log.info(f"Payment succeeded for user {user_id}: ${amount}")

        finally:
            conn.close()

    def _handle_payment_failed(self, invoice: Dict[str, Any]):
        """Handle failed payment"""
        subscription_id = invoice.get('subscription')

        if not subscription_id:
            return

        conn = self._get_db()
        try:
            now = datetime.utcnow().isoformat()

            # Update subscription to past_due
            conn.execute("""
                UPDATE user_subscriptions
                SET status = 'past_due', updated_at = ?
                WHERE stripe_subscription_id = ?
            """, (now, subscription_id))

            conn.execute("""
                UPDATE galaxy_user
                SET subscription_status = 'past_due'
                WHERE id IN (
                    SELECT user_id FROM user_subscriptions
                    WHERE stripe_subscription_id = ?
                )
            """, (subscription_id,))

            conn.commit()

            log.warning(f"Payment failed for subscription {subscription_id}")

            # TODO: Send email notification to user about failed payment

        finally:
            conn.close()


# ============================================================================
# API ENDPOINTS
# ============================================================================

# Global service instance
subscription_service: Optional[SubscriptionService] = None


def get_subscription_service() -> SubscriptionService:
    """Dependency to get subscription service"""
    global subscription_service
    if subscription_service is None:
        # TODO: Load config from Galaxy configuration
        subscription_service = SubscriptionService()
    return subscription_service


@router.get(
    "/api/subscription/status/{user_id}",
    summary="Get subscription status",
    response_model=SubscriptionStatus,
)
def get_status(
    user_id: int = Path(..., description="User ID"),
    service: SubscriptionService = depends(get_subscription_service)
) -> SubscriptionStatus:
    """
    Get user's subscription status.

    Returns:
    - Trial status and expiry date
    - Active subscription info
    - Payment status
    """
    try:
        return service.get_subscription_status(user_id)
    except ObjectNotFound as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except Exception as e:
        log.error(f"Failed to get subscription status: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve subscription status"
        )


@router.post(
    "/api/subscription/create-checkout/{user_id}",
    summary="Create Stripe checkout session",
    response_model=CheckoutSessionResponse,
)
def create_checkout(
    user_id: int = Path(..., description="User ID"),
    request: CreateCheckoutSessionRequest = Body(...),
    service: SubscriptionService = depends(get_subscription_service)
) -> CheckoutSessionResponse:
    """
    Create Stripe checkout session for subscription.

    - **plan_type**: 'monthly' ($20/month) or 'annual' ($200/year)
    - **success_url**: Redirect URL on successful payment
    - **cancel_url**: Redirect URL if user cancels

    Returns checkout URL to redirect user to Stripe payment page.
    """
    try:
        return service.create_checkout_session(
            user_id=user_id,
            plan_type=request.plan_type,
            success_url=request.success_url,
            cancel_url=request.cancel_url
        )
    except (ActionInputError, ObjectNotFound) as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        log.error(f"Failed to create checkout session: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create checkout session"
        )


@router.post(
    "/api/subscription/create-portal/{user_id}",
    summary="Create customer portal session",
    response_model=PortalSessionResponse,
)
def create_portal(
    user_id: int = Path(..., description="User ID"),
    return_url: str = Query(..., description="URL to return to after portal"),
    service: SubscriptionService = depends(get_subscription_service)
) -> PortalSessionResponse:
    """
    Create Stripe customer portal session.

    Allows users to:
    - Update payment method
    - View billing history
    - Cancel subscription
    - Download invoices
    """
    try:
        return service.create_portal_session(user_id, return_url)
    except ObjectNotFound as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except Exception as e:
        log.error(f"Failed to create portal session: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create portal session"
        )


@router.post(
    "/api/subscription/webhook",
    summary="Stripe webhook endpoint",
    response_model=WebhookResponse,
)
async def webhook(
    request: Request,
    stripe_signature: str = Header(None, alias="stripe-signature"),
    service: SubscriptionService = depends(get_subscription_service)
) -> WebhookResponse:
    """
    Stripe webhook endpoint for subscription events.

    Handles:
    - checkout.session.completed
    - customer.subscription.created
    - customer.subscription.updated
    - customer.subscription.deleted
    - invoice.payment_succeeded
    - invoice.payment_failed

    This endpoint must be registered in Stripe Dashboard.
    """
    try:
        payload = await request.body()

        if not stripe_signature:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Missing stripe-signature header"
            )

        result = service.handle_webhook(payload, stripe_signature)

        return WebhookResponse(
            received=True,
            message=f"Webhook processed: {result['event_type']}"
        )

    except HTTPException:
        raise
    except Exception as e:
        log.error(f"Webhook processing error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Webhook processing failed"
        )


@router.get(
    "/api/subscription/config",
    summary="Get Stripe configuration",
    response_model=Dict[str, Any],
)
def get_config(
    service: SubscriptionService = depends(get_subscription_service)
) -> Dict[str, Any]:
    """
    Get Stripe configuration for frontend.

    Returns publishable key and other non-sensitive config.
    """
    return {
        'publishable_key': service.publishable_key,
        'test_mode': service.test_mode,
        'pricing': {
            'monthly': {'amount': 20.00, 'currency': 'USD'},
            'annual': {'amount': 200.00, 'currency': 'USD', 'savings': 40.00}
        }
    }
