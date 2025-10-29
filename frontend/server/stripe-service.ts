import Stripe from 'stripe';
import { db } from './db';
import { users } from '../shared/schema';
import { eq } from 'drizzle-orm';

const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY;
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET;
const APP_URL = process.env.APP_URL || 'http://localhost:5000';

// Subscription tier price IDs (set these in Stripe dashboard)
const PRICE_IDS = {
  academic_monthly: process.env.STRIPE_PRICE_ACADEMIC_MONTHLY,
  academic_yearly: process.env.STRIPE_PRICE_ACADEMIC_YEARLY,
  professional_monthly: process.env.STRIPE_PRICE_PROFESSIONAL_MONTHLY,
  professional_yearly: process.env.STRIPE_PRICE_PROFESSIONAL_YEARLY,
  enterprise_monthly: process.env.STRIPE_PRICE_ENTERPRISE_MONTHLY,
  enterprise_yearly: process.env.STRIPE_PRICE_ENTERPRISE_YEARLY,
};

/**
 * Stripe Payment Service
 * Handles subscription management, checkout, and webhooks
 */
export class StripeService {
  private stripe: Stripe | null = null;
  private initialized = false;

  constructor() {
    if (STRIPE_SECRET_KEY) {
      this.stripe = new Stripe(STRIPE_SECRET_KEY, {
        apiVersion: '2024-11-20.acacia',
      });
      this.initialized = true;
      console.log('[Stripe] Service initialized');
    } else {
      console.warn('[Stripe] Not configured - set STRIPE_SECRET_KEY in .env');
    }
  }

  /**
   * Check if Stripe is configured
   */
  isConfigured(): boolean {
    return this.initialized && !!this.stripe;
  }

  /**
   * Create Stripe checkout session for subscription
   */
  async createCheckoutSession(
    userId: string,
    priceId: string,
    successUrl?: string,
    cancelUrl?: string
  ): Promise<Stripe.Checkout.Session> {
    if (!this.stripe) {
      throw new Error('Stripe not configured');
    }

    // Get user
    const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
    if (!user) {
      throw new Error('User not found');
    }

    // Create or get Stripe customer
    let customerId = user.stripeCustomerId;
    if (!customerId) {
      const customer = await this.stripe.customers.create({
        email: user.email,
        name: user.fullName,
        metadata: {
          userId: user.id,
        },
      });
      customerId = customer.id;

      // Save customer ID
      await db
        .update(users)
        .set({ stripeCustomerId: customerId, updatedAt: new Date() })
        .where(eq(users.id, userId));
    }

    // Create checkout session
    const session = await this.stripe.checkout.sessions.create({
      customer: customerId,
      mode: 'subscription',
      payment_method_types: ['card'],
      line_items: [
        {
          price: priceId,
          quantity: 1,
        },
      ],
      success_url: successUrl || `${APP_URL}/dashboard?payment=success`,
      cancel_url: cancelUrl || `${APP_URL}/pricing?payment=canceled`,
      metadata: {
        userId: user.id,
      },
      subscription_data: {
        metadata: {
          userId: user.id,
        },
      },
    });

    console.log(`[Stripe] Checkout session created for user ${userId}`);
    return session;
  }

  /**
   * Create customer portal session (for managing subscription)
   */
  async createPortalSession(userId: string, returnUrl?: string): Promise<Stripe.BillingPortal.Session> {
    if (!this.stripe) {
      throw new Error('Stripe not configured');
    }

    const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
    if (!user || !user.stripeCustomerId) {
      throw new Error('User has no Stripe customer');
    }

    const session = await this.stripe.billingPortal.sessions.create({
      customer: user.stripeCustomerId,
      return_url: returnUrl || `${APP_URL}/dashboard`,
    });

    console.log(`[Stripe] Portal session created for user ${userId}`);
    return session;
  }

  /**
   * Handle Stripe webhook events
   */
  async handleWebhook(payload: string | Buffer, signature: string): Promise<void> {
    if (!this.stripe || !STRIPE_WEBHOOK_SECRET) {
      throw new Error('Stripe or webhook secret not configured');
    }

    let event: Stripe.Event;

    try {
      event = this.stripe.webhooks.constructEvent(payload, signature, STRIPE_WEBHOOK_SECRET);
    } catch (err: any) {
      console.error('[Stripe] Webhook signature verification failed:', err.message);
      throw new Error('Webhook signature verification failed');
    }

    console.log(`[Stripe] Webhook event received: ${event.type}`);

    // Handle different event types
    switch (event.type) {
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
        await this.handleSubscriptionUpdate(event.data.object as Stripe.Subscription);
        break;

      case 'customer.subscription.deleted':
        await this.handleSubscriptionDeleted(event.data.object as Stripe.Subscription);
        break;

      case 'invoice.payment_succeeded':
        await this.handlePaymentSucceeded(event.data.object as Stripe.Invoice);
        break;

      case 'invoice.payment_failed':
        await this.handlePaymentFailed(event.data.object as Stripe.Invoice);
        break;

      case 'checkout.session.completed':
        await this.handleCheckoutCompleted(event.data.object as Stripe.Checkout.Session);
        break;

      default:
        console.log(`[Stripe] Unhandled event type: ${event.type}`);
    }
  }

  /**
   * Handle subscription created/updated
   */
  private async handleSubscriptionUpdate(subscription: Stripe.Subscription): Promise<void> {
    const userId = subscription.metadata.userId;
    if (!userId) {
      console.error('[Stripe] No userId in subscription metadata');
      return;
    }

    // Determine tier from price ID
    const priceId = subscription.items.data[0]?.price.id;
    let tier = 'academic';

    if (priceId?.includes('professional')) {
      tier = 'professional';
    } else if (priceId?.includes('enterprise')) {
      tier = 'enterprise';
    }

    // Update user subscription
    await db
      .update(users)
      .set({
        subscriptionStatus: subscription.status,
        subscriptionTier: tier,
        subscriptionId: subscription.id,
        currentPeriodEnd: new Date(subscription.current_period_end * 1000),
        trialUsed: true,
        updatedAt: new Date(),
      })
      .where(eq(users.id, userId));

    console.log(`[Stripe] Updated subscription for user ${userId}: ${subscription.status}`);
  }

  /**
   * Handle subscription deleted
   */
  private async handleSubscriptionDeleted(subscription: Stripe.Subscription): Promise<void> {
    const userId = subscription.metadata.userId;
    if (!userId) {
      console.error('[Stripe] No userId in subscription metadata');
      return;
    }

    await db
      .update(users)
      .set({
        subscriptionStatus: 'canceled',
        subscriptionId: null,
        currentPeriodEnd: null,
        updatedAt: new Date(),
      })
      .where(eq(users.id, userId));

    console.log(`[Stripe] Subscription canceled for user ${userId}`);
  }

  /**
   * Handle successful payment
   */
  private async handlePaymentSucceeded(invoice: Stripe.Invoice): Promise<void> {
    if (!invoice.customer || !invoice.subscription) {
      return;
    }

    console.log(`[Stripe] Payment succeeded for invoice ${invoice.id}`);
    // Additional logic if needed (e.g., send receipt email)
  }

  /**
   * Handle failed payment
   */
  private async handlePaymentFailed(invoice: Stripe.Invoice): Promise<void> {
    if (!invoice.customer || !invoice.subscription) {
      return;
    }

    console.log(`[Stripe] Payment failed for invoice ${invoice.id}`);

    // Update subscription status to past_due
    const subscription = await this.stripe?.subscriptions.retrieve(invoice.subscription as string);
    if (subscription?.metadata.userId) {
      await db
        .update(users)
        .set({
          subscriptionStatus: 'past_due',
          updatedAt: new Date(),
        })
        .where(eq(users.id, subscription.metadata.userId));
    }

    // TODO: Send payment failed email to user
  }

  /**
   * Handle checkout session completed
   */
  private async handleCheckoutCompleted(session: Stripe.Checkout.Session): Promise<void> {
    const userId = session.metadata?.userId;
    if (!userId) {
      console.error('[Stripe] No userId in checkout session metadata');
      return;
    }

    console.log(`[Stripe] Checkout completed for user ${userId}`);
    // Subscription will be updated via subscription.created webhook
  }

  /**
   * Cancel subscription
   */
  async cancelSubscription(userId: string): Promise<void> {
    if (!this.stripe) {
      throw new Error('Stripe not configured');
    }

    const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
    if (!user || !user.subscriptionId) {
      throw new Error('User has no active subscription');
    }

    await this.stripe.subscriptions.cancel(user.subscriptionId);
    console.log(`[Stripe] Subscription canceled for user ${userId}`);
  }

  /**
   * Get subscription details
   */
  async getSubscription(userId: string): Promise<Stripe.Subscription | null> {
    if (!this.stripe) {
      throw new Error('Stripe not configured');
    }

    const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
    if (!user || !user.subscriptionId) {
      return null;
    }

    try {
      return await this.stripe.subscriptions.retrieve(user.subscriptionId);
    } catch (error) {
      console.error('[Stripe] Failed to retrieve subscription:', error);
      return null;
    }
  }

  /**
   * Get available pricing tiers
   */
  getPricingTiers() {
    return {
      academic: {
        monthly: PRICE_IDS.academic_monthly,
        yearly: PRICE_IDS.academic_yearly,
      },
      professional: {
        monthly: PRICE_IDS.professional_monthly,
        yearly: PRICE_IDS.professional_yearly,
      },
      enterprise: {
        monthly: PRICE_IDS.enterprise_monthly,
        yearly: PRICE_IDS.enterprise_yearly,
      },
    };
  }
}

// Export singleton instance
export const stripeService = new StripeService();
