#!/bin/bash
# Simple Galaxy startup script that bypasses webpack issues

echo "Starting Galaxy with AI Assistant - Simple Mode"

# Set environment to skip client build
export SKIP_CLIENT_BUILD=1
export NODE_ENV=development

# Kill any existing processes
pkill -f "galaxy|gunicorn|webpack" 2>/dev/null || true
sleep 2

# Clean up gravity config
rm -rf database/gravity/ 2>/dev/null || true

echo "Activating virtual environment..."
source .venv/bin/activate

echo "Starting Galaxy server directly..."
# Use simple python startup instead of complex run.sh
export PYTHONPATH=lib
export GALAXY_CONFIG_FILE=config/galaxy.yml

# Start Galaxy directly with Python
python scripts/galaxy-main.py serve --host=0.0.0.0 --port=8080 --debug &

echo "Galaxy started in background. Checking status..."
sleep 10

# Check if it's running
if curl -s http://localhost:8080/ >/dev/null 2>&1; then
    echo "✅ Galaxy is running at http://localhost:8080/"
    echo "🤖 AI Assistant should be available!"
else
    echo "❌ Galaxy failed to start. Trying alternative method..."
    
    # Alternative: Use gunicorn directly
    gunicorn 'galaxy.webapps.galaxy.fast_factory:factory()' \
        --timeout 300 \
        --pythonpath lib \
        -k galaxy.webapps.galaxy.workers.Worker \
        -b 0.0.0.0:8080 \
        --workers=1 \
        --preload &
    
    sleep 15
    echo "Checking alternative startup..."
    if curl -s http://localhost:8080/ >/dev/null 2>&1; then
        echo "✅ Galaxy is now running at http://localhost:8080/"
    else
        echo "❌ Galaxy startup failed. Check logs."
    fi
fi