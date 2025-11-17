# Stripe Payment Integration Setup Guide

## Current Status
- ❌ STRIPE_SECRET_KEY: NOT SET
- ❌ STRIPE_WEBHOOK_SECRET: NOT SET
- ❌ All STRIPE_PRICE_* variables: NOT SET

## Steps to Configure Stripe

### 1. Create/Access Stripe Account
```bash
# Visit: https://dashboard.stripe.com/register
# Or login: https://dashboard.stripe.com/login
```

### 2. Get API Keys
1. Go to Developers → API keys
2. Copy:
   - **Publishable key**: `pk_test_...` (for frontend)
   - **Secret key**: `sk_test_...` (for backend)

### 3. Create Products & Prices

#### Academic Tier
```bash
# In Stripe Dashboard → Products → Add Product:
Name: Biomate Academic
Description: For individual researchers and students

# Add Prices:
Monthly: $29/month (save price ID: price_academic_monthly_xxx)
Yearly: $290/year (save price ID: price_academic_yearly_xxx)
```

#### Professional Tier
```bash
Name: Biomate Professional
Description: For research teams and labs

Monthly: $99/month (save price ID: price_pro_monthly_xxx)
Yearly: $990/year (save price ID: price_pro_yearly_xxx)
```

#### Enterprise Tier
```bash
Name: Biomate Enterprise
Description: For institutions and large organizations

Monthly: $299/month (save price ID: price_ent_monthly_xxx)
Yearly: $2990/year (save price ID: price_ent_yearly_xxx)
```

### 4. Configure Webhooks
```bash
# In Stripe Dashboard → Developers → Webhooks → Add endpoint

Endpoint URL: https://yourdomain.com/api/payments/webhook
# For testing: Use ngrok to expose localhost
# ngrok http 5000
# Then use: https://your-ngrok-url.ngrok.io/api/payments/webhook

Events to listen for:
✓ checkout.session.completed
✓ customer.subscription.created
✓ customer.subscription.updated
✓ customer.subscription.deleted
✓ invoice.payment_succeeded
✓ invoice.payment_failed
✓ customer.created
✓ customer.updated

# Copy webhook signing secret: whsec_...
```

### 5. Update Environment Variables

```bash
# Edit: /home/yzhang/biomate/frontend/.env

# Stripe Keys
STRIPE_SECRET_KEY=sk_test_your_secret_key_here
STRIPE_PUBLISHABLE_KEY=pk_test_your_publishable_key_here
STRIPE_WEBHOOK_SECRET=whsec_your_webhook_secret_here

# Price IDs (from step 3)
STRIPE_PRICE_ACADEMIC_MONTHLY=price_xxx
STRIPE_PRICE_ACADEMIC_YEARLY=price_xxx
STRIPE_PRICE_PROFESSIONAL_MONTHLY=price_xxx
STRIPE_PRICE_PROFESSIONAL_YEARLY=price_xxx
STRIPE_PRICE_ENTERPRISE_MONTHLY=price_xxx
STRIPE_PRICE_ENTERPRISE_YEARLY=price_xxx
```

### 6. Restart Server
```bash
cd /home/yzhang/biomate/frontend
npm run dev
```

### 7. Test Payment Flow

#### Test Cards (Stripe Test Mode):
```
Success: 4242 4242 4242 4242
Decline: 4000 0000 0000 0002
3D Secure: 4000 0025 0000 3155
```

#### Test Registration with Payment:
1. Go to: http://localhost:5000/register
2. Fill form
3. Should redirect to Stripe Checkout
4. Use test card: 4242 4242 4242 4242
5. Complete payment
6. Should redirect back with subscription active

### 8. Verify in Stripe Dashboard
- Check Customers → Should see new customer
- Check Subscriptions → Should see trial subscription
- Check Webhooks → Should see events received

## Implementation Files

- **Stripe Service**: `frontend/server/stripe-service.ts`
- **Payment Routes**: `frontend/server/routes.ts` (lines ~400-500)
- **Checkout UI**: `frontend/client/src/pages/checkout.tsx`

## Testing Checklist

- [ ] Can create checkout session
- [ ] Checkout redirects to Stripe
- [ ] Can complete payment with test card
- [ ] Webhook receives events
- [ ] Customer created in database
- [ ] Subscription status updated
- [ ] Trial period starts correctly
- [ ] Card declined handled gracefully
- [ ] 3D Secure authentication works

## Troubleshooting

**Webhook not receiving events?**
```bash
# Use Stripe CLI to forward webhooks locally:
stripe listen --forward-to localhost:5000/api/payments/webhook

# Test webhook:
stripe trigger checkout.session.completed
```

**"Stripe not configured" error?**
- Check all STRIPE_* env variables are set
- Restart server after updating .env
- Check server logs for Stripe initialization

**Payment succeeds but subscription not created?**
- Check webhook events in Stripe Dashboard
- Check server logs for webhook processing
- Verify webhook secret matches

## Security Notes

- **NEVER commit** Stripe secret keys to git
- Use `.env` file (already in .gitignore)
- In production, use live keys (pk_live_..., sk_live_...)
- Rotate keys if exposed

## Next Steps After Setup

1. Test complete registration → payment → trial flow
2. Test subscription cancellation
3. Test payment method update
4. Set up billing portal for users
5. Configure tax calculation (Stripe Tax) if needed
6. Test webhook failure scenarios
7. Implement payment retry logic
