#!/bin/bash

echo "========================================================================"
echo "Biomate - PostgreSQL Database Setup"
echo "========================================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration from .env
DB_NAME="biomate_dev"
DB_USER="biomate"
DB_PASSWORD="biomate_dev_password"
DB_HOST="localhost"
DB_PORT="5432"

echo "This script will set up the PostgreSQL database for Biomate."
echo ""
echo "Configuration:"
echo "  Database: $DB_NAME"
echo "  User: $DB_USER"
echo "  Host: $DB_HOST:$DB_PORT"
echo ""

# ========================================================================
# STEP 1: Check if PostgreSQL is installed
# ========================================================================
echo "------------------------------------------------------------------------"
echo "STEP 1: Checking PostgreSQL Installation"
echo "------------------------------------------------------------------------"
echo ""

if ! command -v psql &> /dev/null; then
    echo -e "${RED}✗ PostgreSQL client not found${NC}"
    echo ""
    echo "PostgreSQL is not installed. Please install it first:"
    echo ""
    echo "  sudo apt update"
    echo "  sudo apt install postgresql postgresql-contrib"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ PostgreSQL client found${NC}"
PSQL_VERSION=$(psql --version)
echo "  Version: $PSQL_VERSION"
echo ""

# ========================================================================
# STEP 2: Check if PostgreSQL service is running
# ========================================================================
echo "------------------------------------------------------------------------"
echo "STEP 2: Checking PostgreSQL Service"
echo "------------------------------------------------------------------------"
echo ""

if sudo systemctl is-active --quiet postgresql; then
    echo -e "${GREEN}✓ PostgreSQL service is running${NC}"
else
    echo -e "${YELLOW}⚠ PostgreSQL service is not running${NC}"
    echo ""
    read -p "Start PostgreSQL service now? (Y/n): " start_service

    if [[ ! "$start_service" =~ ^[Nn]$ ]]; then
        echo "Starting PostgreSQL service..."
        sudo systemctl start postgresql
        sudo systemctl enable postgresql

        if sudo systemctl is-active --quiet postgresql; then
            echo -e "${GREEN}✓ PostgreSQL service started successfully${NC}"
        else
            echo -e "${RED}✗ Failed to start PostgreSQL service${NC}"
            echo "Please start it manually: sudo systemctl start postgresql"
            exit 1
        fi
    else
        echo -e "${RED}Cannot continue without PostgreSQL running${NC}"
        exit 1
    fi
fi
echo ""

# ========================================================================
# STEP 3: Create database and user
# ========================================================================
echo "------------------------------------------------------------------------"
echo "STEP 3: Creating Database and User"
echo "------------------------------------------------------------------------"
echo ""

# Check if database already exists
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $DB_NAME; then
    echo -e "${YELLOW}⚠ Database '$DB_NAME' already exists${NC}"
    echo ""
    read -p "Drop and recreate database? (y/N): " recreate_db

    if [[ "$recreate_db" =~ ^[Yy]$ ]]; then
        echo "Dropping existing database..."
        sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>&1
        echo -e "${GREEN}✓ Database dropped${NC}"
    else
        echo "Keeping existing database"
        SKIP_DB_CREATE=true
    fi
fi

if [ "$SKIP_DB_CREATE" != true ]; then
    echo "Creating database and user..."

    # Create user if not exists
    sudo -u postgres psql -c "DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN
            CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
        END IF;
    END
    \$\$;" 2>&1

    # Create database
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>&1

    # Grant privileges
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" 2>&1
    sudo -u postgres psql -d $DB_NAME -c "GRANT ALL ON SCHEMA public TO $DB_USER;" 2>&1

    echo -e "${GREEN}✓ Database and user created${NC}"
fi
echo ""

# ========================================================================
# STEP 4: Verify connection
# ========================================================================
echo "------------------------------------------------------------------------"
echo "STEP 4: Verifying Database Connection"
echo "------------------------------------------------------------------------"
echo ""

# Test connection
export PGPASSWORD=$DB_PASSWORD
if psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT 1;" &> /dev/null; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}✗ Cannot connect to database${NC}"
    echo ""
    echo "Please check:"
    echo "  1. PostgreSQL service is running: sudo systemctl status postgresql"
    echo "  2. User and database exist: sudo -u postgres psql -l"
    echo "  3. Password is correct: $DB_PASSWORD"
    echo ""
    exit 1
fi
unset PGPASSWORD
echo ""

# ========================================================================
# STEP 5: Run database migrations
# ========================================================================
echo "------------------------------------------------------------------------"
echo "STEP 5: Running Database Migrations"
echo "------------------------------------------------------------------------"
echo ""

# Check if .env file exists and has DATABASE_URL
if [ ! -f ".env" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    echo "Creating .env with DATABASE_URL..."
    echo "DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME" > .env
    echo -e "${GREEN}✓ .env file created${NC}"
elif ! grep -q "^DATABASE_URL=" .env; then
    echo -e "${YELLOW}⚠ DATABASE_URL not found in .env${NC}"
    echo "Adding DATABASE_URL to .env..."
    echo "DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME" >> .env
    echo -e "${GREEN}✓ DATABASE_URL added to .env${NC}"
else
    echo -e "${GREEN}✓ DATABASE_URL configured in .env${NC}"
fi
echo ""

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}⚠ node_modules not found${NC}"
    echo "Installing npm dependencies..."
    npm install
    echo ""
fi

# Run migrations using drizzle-kit push
echo "Running database schema push..."
echo ""

if npm run db:push; then
    echo ""
    echo -e "${GREEN}✓ Database schema created successfully${NC}"
else
    echo ""
    echo -e "${YELLOW}⚠ Migration command failed, trying manual SQL...${NC}"
    echo ""

    # Try running the SQL migration directly
    if [ -f "migrations/0000_add_auth_system.sql" ]; then
        echo "Applying migration SQL directly..."
        export PGPASSWORD=$DB_PASSWORD
        psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f migrations/0000_add_auth_system.sql
        unset PGPASSWORD
        echo -e "${GREEN}✓ Migration applied${NC}"
    else
        echo -e "${RED}✗ Migration file not found${NC}"
        exit 1
    fi
fi
echo ""

# ========================================================================
# STEP 6: Verify tables were created
# ========================================================================
echo "------------------------------------------------------------------------"
echo "STEP 6: Verifying Database Setup"
echo "------------------------------------------------------------------------"
echo ""

export PGPASSWORD=$DB_PASSWORD
TABLE_COUNT=$(psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
unset PGPASSWORD

if [ "$TABLE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Database tables created successfully${NC}"
    echo "  Tables found: $TABLE_COUNT"
    echo ""

    # List tables
    echo "Tables in database:"
    export PGPASSWORD=$DB_PASSWORD
    psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "\dt"
    unset PGPASSWORD
else
    echo -e "${RED}✗ No tables found in database${NC}"
    echo "Migration may have failed"
    exit 1
fi
echo ""

# ========================================================================
# SUMMARY
# ========================================================================
echo "========================================================================"
echo "Database Setup Complete!"
echo "========================================================================"
echo ""
echo "Configuration:"
echo "  ${GREEN}✓${NC} Database: $DB_NAME"
echo "  ${GREEN}✓${NC} User: $DB_USER"
echo "  ${GREEN}✓${NC} Host: $DB_HOST:$DB_PORT"
echo "  ${GREEN}✓${NC} Tables: $TABLE_COUNT created"
echo ""
echo "Connection string:"
echo "  postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"
echo ""
echo "========================================================================"
echo "Next Steps:"
echo "========================================================================"
echo ""
echo "1. Restart the Biomate server:"
echo "   npm run dev"
echo ""
echo "2. Run end-to-end tests:"
echo "   cd /home/yzhang/biomate/backend/tests"
echo "   python3 e2e_test_suite.py"
echo ""
echo "3. Try registering a test user:"
echo "   curl -X POST http://localhost:5000/api/auth/register \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"email\":\"test@test.com\",\"password\":\"Test123!\","
echo "         \"fullName\":\"Test User\",\"termsAccepted\":true}'"
echo ""
echo "========================================================================"
echo ""
