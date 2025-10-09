#!/bin/bash

# Galaxy AI Assistant Startup Script
# This script starts Galaxy with AI Assistant enabled

echo "🚀 Starting Galaxy with AI Assistant..."

# Check if config file exists
if [ ! -f "config/galaxy.yml" ]; then
    echo "⚠️  Creating Galaxy configuration with AI Assistant enabled..."
    cp config/galaxy_ai_example.yml config/galaxy.yml
    echo "📝 Please edit config/galaxy.yml and add your OpenAI API key:"
    echo "   ai_api_key: 'your-openai-api-key-here'"
    echo ""
fi

# Check if AI modules are importable
echo "🔍 Checking AI module dependencies..."

python3 -c "
try:
    import galaxy.ai.ai_assistant
    print('✅ AI Assistant modules found')
except ImportError as e:
    print(f'❌ AI Assistant modules missing: {e}')
    print('This is expected - modules will be available after Galaxy starts')
" 2>/dev/null

echo ""
echo "🌟 Starting Galaxy..."
echo "📍 Galaxy will be available at: http://localhost:8080"
echo "🤖 Look for the AI Assistant floating button in the bottom-right corner"
echo ""
echo "If you don't see the AI Assistant button:"
echo "1. Make sure the frontend rebuilt successfully"
echo "2. Check browser console for any JavaScript errors"
echo "3. Try refreshing the page (Ctrl+F5)"
echo ""

# Start Galaxy
exec sh run.sh