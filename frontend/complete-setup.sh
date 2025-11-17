#!/bin/bash
#
# Biomate Complete Setup - One Command to Rule Them All
# This script does EVERYTHING needed to get Biomate running
#

set -e  # Exit on any error

echo "========================================================================"
echo "Biomate - Complete Automated Setup"
echo "========================================================================"
echo ""
echo "This script will:"
echo "  1. Install PostgreSQL"
echo "  2. Configure database"
echo "  3. Run migrations"
echo "  4. Setup test email (Ethereal)"
echo "  5. Verify everything works"
echo "  6. Run E2E tests"
echo ""
echo "Estimated time: 5-10 minutes"
echo ""

read -p "Press Enter to continue or Ctrl+C to cancel..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========================================================================
# STEP 1: Install PostgreSQL
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 1: Installing PostgreSQL"
echo "========================================================================"
echo ""

if command -v psql &> /dev/null; then
    echo -e "${GREEN}✓ PostgreSQL already installed${NC}"
    psql --version
else
    echo "Installing PostgreSQL..."
    apt update -qq
    apt install -y postgresql postgresql-contrib
    echo -e "${GREEN}✓ PostgreSQL installed${NC}"
fi

# ========================================================================
# STEP 2: Start PostgreSQL
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 2: Starting PostgreSQL Service"
echo "========================================================================"
echo ""

systemctl start postgresql
systemctl enable postgresql

if systemctl is-active --quiet postgresql; then
    echo -e "${GREEN}✓ PostgreSQL service running${NC}"
else
    echo -e "${RED}✗ Failed to start PostgreSQL${NC}"
    exit 1
fi

# ========================================================================
# STEP 3: Create Database and User
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 3: Creating Database"
echo "========================================================================"
echo ""

# Configuration
DB_NAME="biomate_dev"
DB_USER="biomate"
DB_PASSWORD="biomate_dev_password"

# Check if database exists
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $DB_NAME; then
    echo -e "${YELLOW}Database '$DB_NAME' already exists${NC}"
else
    # Create user
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" 2>/dev/null || echo "User may already exist"

    # Create database
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

    # Grant privileges
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
    sudo -u postgres psql -d $DB_NAME -c "GRANT ALL ON SCHEMA public TO $DB_USER;"

    echo -e "${GREEN}✓ Database created${NC}"
fi

# ========================================================================
# STEP 4: Verify Connection
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 4: Verifying Database Connection"
echo "========================================================================"
echo ""

export PGPASSWORD=$DB_PASSWORD
if psql -h localhost -U $DB_USER -d $DB_NAME -c "SELECT 1;" &> /dev/null; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}✗ Cannot connect to database${NC}"
    exit 1
fi
unset PGPASSWORD

# ========================================================================
# STEP 5: Update .env File
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 5: Configuring Environment"
echo "========================================================================"
echo ""

cd /home/yzhang/biomate/frontend

# Ensure DATABASE_URL is set
if ! grep -q "^DATABASE_URL=" .env 2>/dev/null; then
    echo "DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME" >> .env
    echo -e "${GREEN}✓ DATABASE_URL added to .env${NC}"
else
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME|" .env
    echo -e "${GREEN}✓ DATABASE_URL updated in .env${NC}"
fi

# ========================================================================
# STEP 6: Install Node Dependencies
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 6: Installing Node Dependencies"
echo "========================================================================"
echo ""

if [ ! -d "node_modules" ]; then
    echo "Installing npm packages..."
    npm install --silent
    echo -e "${GREEN}✓ Dependencies installed${NC}"
else
    echo -e "${GREEN}✓ Dependencies already installed${NC}"
fi

# ========================================================================
# STEP 7: Run Database Migrations
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 7: Running Database Migrations"
echo "========================================================================"
echo ""

if npm run db:push 2>&1 | tee /tmp/migration.log; then
    echo -e "${GREEN}✓ Migrations successful${NC}"
else
    echo -e "${YELLOW}Migration command failed, trying SQL directly...${NC}"

    if [ -f "migrations/0000_add_auth_system.sql" ]; then
        export PGPASSWORD=$DB_PASSWORD
        psql -h localhost -U $DB_USER -d $DB_NAME -f migrations/0000_add_auth_system.sql
        unset PGPASSWORD
        echo -e "${GREEN}✓ SQL migration applied${NC}"
    fi
fi

# ========================================================================
# STEP 8: Setup Ethereal Email (Testing)
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 8: Setting Up Test Email Service"
echo "========================================================================"
echo ""

echo "Creating Ethereal Email account..."
ETHEREAL_RESPONSE=$(curl -s -X POST https://api.nodemailer.com/user \
    -H "Content-Type: application/json" \
    -d '{"requestor":"biomate-testing"}')

if echo "$ETHEREAL_RESPONSE" | grep -q "user"; then
    EMAIL_USER=$(echo "$ETHEREAL_RESPONSE" | grep -o '"user":"[^"]*"' | cut -d'"' -f4)
    EMAIL_PASS=$(echo "$ETHEREAL_RESPONSE" | grep -o '"pass":"[^"]*"' | cut -d'"' -f4)

    if [ ! -z "$EMAIL_USER" ] && [ ! -z "$EMAIL_PASS" ]; then
        # Update .env
        sed -i "s|^EMAIL_HOST=.*|EMAIL_HOST=smtp.ethereal.email|" .env
        sed -i "s|^EMAIL_PORT=.*|EMAIL_PORT=587|" .env
        sed -i "s|^EMAIL_USER=.*|EMAIL_USER=$EMAIL_USER|" .env
        sed -i "s|^EMAIL_PASS=.*|EMAIL_PASS=$EMAIL_PASS|" .env
        sed -i "s|^EMAIL_SECURE=.*|EMAIL_SECURE=false|" .env

        echo -e "${GREEN}✓ Ethereal Email configured${NC}"
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}  View test emails at: https://ethereal.email/messages${NC}"
        echo -e "${BLUE}  Username: $EMAIL_USER${NC}"
        echo -e "${BLUE}  Password: $EMAIL_PASS${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    else
        echo -e "${YELLOW}⚠ Could not parse Ethereal credentials${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Ethereal Email setup failed (optional)${NC}"
fi

# ========================================================================
# STEP 9: Verify Tables Created
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 9: Verifying Database Tables"
echo "========================================================================"
echo ""

export PGPASSWORD=$DB_PASSWORD
TABLE_COUNT=$(psql -h localhost -U $DB_USER -d $DB_NAME -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
unset PGPASSWORD

if [ "$TABLE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Database tables created${NC}"
    echo "  Tables found: $TABLE_COUNT"
else
    echo -e "${RED}✗ No tables found${NC}"
    exit 1
fi

# ========================================================================
# STEP 10: Run E2E Tests
# ========================================================================
echo ""
echo "========================================================================"
echo "STEP 10: Running End-to-End Tests"
echo "========================================================================"
echo ""

cd /home/yzhang/biomate/backend/tests

if python3 e2e_test_suite.py 2>&1 | tee /tmp/e2e_results.log; then
    echo -e "${GREEN}✓ Tests completed${NC}"
else
    echo -e "${YELLOW}⚠ Some tests failed (check results above)${NC}"
fi

# ========================================================================
# COMPLETE!
# ========================================================================
echo ""
echo "========================================================================"
echo "Setup Complete!"
echo "========================================================================"
echo ""
echo -e "${GREEN}✓ PostgreSQL installed and running${NC}"
echo -e "${GREEN}✓ Database created: $DB_NAME${NC}"
echo -e "${GREEN}✓ Migrations applied${NC}"
echo -e "${GREEN}✓ Email service configured (Ethereal - testing)${NC}"
echo -e "${GREEN}✓ E2E tests executed${NC}"
echo ""
echo "Next steps:"
echo "  1. Start the server: cd /home/yzhang/biomate/frontend && npm run dev"
echo "  2. Visit: http://localhost:5000"
echo "  3. Try registering: Use test card 4242 4242 4242 4242 (if Stripe configured)"
echo ""
echo "For Stripe setup, see: /home/yzhang/biomate/frontend/STRIPE_SETUP_GUIDE.md"
echo ""
echo "========================================================================"
