#!/bin/bash

echo "========================================================================"
echo "Biomate - Quick Setup for End-to-End Testing"
echo "========================================================================"
echo ""

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "Error: .env file not found!"
    exit 1
fi

echo "This script will help you set up Stripe and Email for testing."
echo ""

# ========================================================================
# STRIPE SETUP
# ========================================================================
echo "========================================================================"
echo "STEP 1: Stripe Test Mode Setup"
echo "========================================================================"
echo ""

# Check if Stripe is already configured
if grep -q "^STRIPE_SECRET_KEY=sk_test_" .env 2>/dev/null; then
    echo "✓ Stripe test key already configured"
else
    echo "Stripe is NOT configured. You need Stripe test credentials."
    echo ""
    echo "Quick Setup Instructions:"
    echo "1. Go to: https://dashboard.stripe.com/test/apikeys"
    echo "2. Copy your 'Secret key' (starts with sk_test_...)"
    echo "3. Paste it below"
    echo ""
    read -p "Enter your Stripe test secret key (or press Enter to skip): " stripe_key

    if [ ! -z "$stripe_key" ]; then
        # Update .env file
        sed -i "s|^STRIPE_SECRET_KEY=.*|STRIPE_SECRET_KEY=$stripe_key|" .env
        echo "✓ Stripe secret key configured"
    else
        echo "⚠ Skipping Stripe setup - payment features will not work"
    fi
fi

echo ""
echo "For full Stripe testing, you also need Price IDs."
echo "You can create test prices at: https://dashboard.stripe.com/test/products"
echo ""
read -p "Do you want to set up Price IDs now? (y/N): " setup_prices

if [[ "$setup_prices" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Create 6 prices in Stripe Dashboard (Test Mode):"
    echo "1. Academic Monthly: $29/month"
    echo "2. Academic Yearly: $290/year"
    echo "3. Professional Monthly: $99/month"
    echo "4. Professional Yearly: $990/year"
    echo "5. Enterprise Monthly: $299/month"
    echo "6. Enterprise Yearly: $2990/year"
    echo ""

    read -p "Academic Monthly Price ID: " price_acad_m
    read -p "Academic Yearly Price ID: " price_acad_y
    read -p "Professional Monthly Price ID: " price_prof_m
    read -p "Professional Yearly Price ID: " price_prof_y
    read -p "Enterprise Monthly Price ID: " price_ent_m
    read -p "Enterprise Yearly Price ID: " price_ent_y

    # Update .env
    [ ! -z "$price_acad_m" ] && sed -i "s|^STRIPE_PRICE_ACADEMIC_MONTHLY=.*|STRIPE_PRICE_ACADEMIC_MONTHLY=$price_acad_m|" .env
    [ ! -z "$price_acad_y" ] && sed -i "s|^STRIPE_PRICE_ACADEMIC_YEARLY=.*|STRIPE_PRICE_ACADEMIC_YEARLY=$price_acad_y|" .env
    [ ! -z "$price_prof_m" ] && sed -i "s|^STRIPE_PRICE_PROFESSIONAL_MONTHLY=.*|STRIPE_PRICE_PROFESSIONAL_MONTHLY=$price_prof_m|" .env
    [ ! -z "$price_prof_y" ] && sed -i "s|^STRIPE_PRICE_PROFESSIONAL_YEARLY=.*|STRIPE_PRICE_PROFESSIONAL_YEARLY=$price_prof_y|" .env
    [ ! -z "$price_ent_m" ] && sed -i "s|^STRIPE_PRICE_ENTERPRISE_MONTHLY=.*|STRIPE_PRICE_ENTERPRISE_MONTHLY=$price_ent_m|" .env
    [ ! -z "$price_ent_y" ] && sed -i "s|^STRIPE_PRICE_ENTERPRISE_YEARLY=.*|STRIPE_PRICE_ENTERPRISE_YEARLY=$price_ent_y|" .env

    echo "✓ Price IDs configured"
fi

# ========================================================================
# EMAIL SETUP - Use Ethereal (Fake SMTP for testing)
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 2: Email Service Setup"
echo "========================================================================"
echo ""

# Check if Email is already configured
if grep -q "^EMAIL_HOST=..*" .env 2>/dev/null && ! grep -q "^EMAIL_HOST=$" .env; then
    echo "✓ Email already configured"
    grep "^EMAIL_HOST=" .env
else
    echo "Setting up Ethereal Email (fake SMTP for testing)..."
    echo ""
    echo "Ethereal Email is a fake SMTP service that captures emails for testing."
    echo "All emails will be viewable at: https://ethereal.email"
    echo ""

    read -p "Set up Ethereal Email? (Y/n): " setup_email

    if [[ ! "$setup_email" =~ ^[Nn]$ ]]; then
        # Create Ethereal account via API
        echo "Creating Ethereal test account..."

        ethereal_response=$(curl -s -X POST https://api.nodemailer.com/user \
            -H "Content-Type: application/json" \
            -d '{"requestor":"biomate-testing"}')

        if [ $? -eq 0 ]; then
            email_user=$(echo "$ethereal_response" | grep -o '"user":"[^"]*"' | cut -d'"' -f4)
            email_pass=$(echo "$ethereal_response" | grep -o '"pass":"[^"]*"' | cut -d'"' -f4)

            if [ ! -z "$email_user" ] && [ ! -z "$email_pass" ]; then
                # Update .env
                sed -i "s|^EMAIL_HOST=.*|EMAIL_HOST=smtp.ethereal.email|" .env
                sed -i "s|^EMAIL_PORT=.*|EMAIL_PORT=587|" .env
                sed -i "s|^EMAIL_USER=.*|EMAIL_USER=$email_user|" .env
                sed -i "s|^EMAIL_PASS=.*|EMAIL_PASS=$email_pass|" .env
                sed -i "s|^EMAIL_SECURE=.*|EMAIL_SECURE=false|" .env

                echo "✓ Ethereal Email configured!"
                echo ""
                echo "═══════════════════════════════════════════════════════════"
                echo "  IMPORTANT: View test emails at:"
                echo "  https://ethereal.email/messages"
                echo "  Username: $email_user"
                echo "  Password: $email_pass"
                echo "═══════════════════════════════════════════════════════════"
                echo ""
            else
                echo "⚠ Failed to parse Ethereal credentials"
                echo "You can manually create an account at: https://ethereal.email"
            fi
        else
            echo "⚠ Failed to create Ethereal account"
            echo "You can manually create an account at: https://ethereal.email"
        fi
    else
        echo "⚠ Skipping email setup - email features will not work"
    fi
fi

# ========================================================================
# SUMMARY
# ========================================================================
echo ""
echo "========================================================================"
echo "Setup Complete!"
echo "========================================================================"
echo ""

# Check what's configured
stripe_configured=false
email_configured=false

if grep -q "^STRIPE_SECRET_KEY=sk_test_" .env 2>/dev/null; then
    stripe_configured=true
fi

if grep -q "^EMAIL_HOST=..*" .env 2>/dev/null && ! grep -q "^EMAIL_HOST=$" .env; then
    email_configured=true
fi

echo "Configuration Status:"
echo ""

if [ "$stripe_configured" = true ]; then
    echo "✓ Stripe: Configured (Test Mode)"
else
    echo "✗ Stripe: NOT configured (payment features disabled)"
fi

if [ "$email_configured" = true ]; then
    echo "✓ Email: Configured"
else
    echo "✗ Email: NOT configured (email features disabled)"
fi

echo ""
echo "========================================================================"
echo "Next Steps:"
echo "========================================================================"
echo ""
echo "1. Restart the server:"
echo "   npm run dev"
echo ""
echo "2. Run end-to-end tests:"
echo "   cd /home/yzhang/biomate/backend/tests"
echo "   python3 e2e_test_suite.py"
echo ""
echo "3. Manual testing:"
echo "   - Visit: http://localhost:5000"
echo "   - Try registration with Stripe test card: 4242 4242 4242 4242"
echo "   - Check emails at: https://ethereal.email/messages"
echo ""
echo "========================================================================"
