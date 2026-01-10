#!/bin/bash
#
# Test Hybrid Execution Configuration
# 测试混合执行配置
#

set -e

echo "========================================="
echo "Testing Hybrid Execution Configuration"
echo "========================================="
echo ""

# Check configuration file exists
if [ ! -f "config/job_conf_cloud.yml" ]; then
    echo "❌ Error: config/job_conf_cloud.yml not found"
    exit 1
fi

echo "✅ Configuration file found"
echo ""

# Verify expression tools are configured for local execution
echo "🔍 Checking expression tool routing configuration..."
echo ""

TOOLS=("pick_value" "compose_text_param" "param_value_from_file" "filter_failed_datasets")

for tool in "${TOOLS[@]}"; do
    if grep -q "id: \"$tool\"" config/job_conf_cloud.yml && \
       grep -A1 "id: \"$tool\"" config/job_conf_cloud.yml | grep -q "environment: local"; then
        echo "  ✅ $tool → local execution"
    else
        echo "  ❌ $tool → NOT configured for local"
    fi
done

echo ""
echo "========================================="
echo "Configuration Status Summary"
echo "========================================="

# Count configured expression tools
EXPR_TOOLS=$(grep -A1 "# === Expression Tools" config/job_conf_cloud.yml | grep "id:" | wc -l | tr -d ' ')
echo "Expression tools configured: $EXPR_TOOLS"

# Check if local runner is configured
if grep -q "local:" config/job_conf_cloud.yml && \
   grep -A2 "local:" config/job_conf_cloud.yml | grep -q "LocalJobRunner"; then
    echo "✅ Local runner configured"
else
    echo "❌ Local runner NOT configured"
fi

# Check if cloud runner is configured
if grep -q "galaxy_cloud:" config/job_conf_cloud.yml && \
   grep -A2 "galaxy_cloud:" config/job_conf_cloud.yml | grep -q "GalaxyCloudJobRunner"; then
    echo "✅ Cloud runner configured"
else
    echo "❌ Cloud runner NOT configured"
fi

echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Start Galaxy with hybrid execution:"
echo "   GALAXY_CONFIG_FILE=config/galaxy.yml \\"
echo "   GALAXY_CONFIG_JOB_CONFIG_FILE=config/job_conf_cloud.yml \\"
echo "   sh run.sh"
echo ""
echo "2. Run a workflow containing expression tools"
echo ""
echo "3. Monitor execution:"
echo "   - Expression tools should complete in < 1 second"
echo "   - Compute tools should be submitted to AWS Batch"
echo ""
echo "4. Check logs:"
echo "   tail -f logs/galaxy_startup_*.log"
echo ""
echo "========================================="
