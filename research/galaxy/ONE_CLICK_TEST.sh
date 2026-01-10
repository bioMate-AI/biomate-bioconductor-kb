#!/bin/bash
#
# 一键测试Galaxy云执行
# 这个脚本会帮你完成所有步骤
#

echo "╔════════════════════════════════════════════════════════╗"
echo "║        Galaxy 云执行 - 一键测试脚本                    ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# 检查API Key
if [ -z "$GALAXY_API_KEY" ]; then
    echo "❌ 需要设置API Key"
    echo ""
    echo "请按以下步骤操作："
    echo "1. 访问 http://localhost:8080"
    echo "2. User → Preferences → Manage API Key"
    echo "3. Create New Key并复制"
    echo "4. 运行: export GALAXY_API_KEY='your-key-here'"
    echo "5. 再次运行此脚本"
    exit 1
fi

echo "✅ API Key已设置"
echo ""

# Galaxy配置
GALAXY_URL="http://localhost:8080"
WORKFLOW_FILE="test_cloud_workflow.ga"

# 测试连接
echo "🔗 测试Galaxy连接..."
VERSION=$(curl -s -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/version" | python3 -c "import sys, json; print(json.load(sys.stdin)['version_major'])" 2>/dev/null)

if [ -z "$VERSION" ]; then
    echo "❌ 无法连接到Galaxy"
    echo "   请确认Galaxy正在运行: http://localhost:8080"
    exit 1
fi

echo "✅ Galaxy v$VERSION 运行中"
echo ""

# 获取或创建历史记录
echo "📝 准备历史记录..."
HISTORY_ID=$(curl -s -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/histories" | \
    python3 -c "import sys, json; h=json.load(sys.stdin); print(h[0]['id'] if h else '')" 2>/dev/null)

if [ -z "$HISTORY_ID" ]; then
    echo "   创建新历史记录..."
    HISTORY_ID=$(curl -s -X POST -H "x-api-key: $GALAXY_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"name":"Cloud Test"}' \
        "$GALAXY_URL/api/histories" | \
        python3 -c "import sys, json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
fi

echo "✅ History ID: $HISTORY_ID"
echo ""

# 上传文件
echo "📤 上传测试文件..."
DATASET_IDS=()

for file in test_collection_data/sample*.txt; do
    if [ ! -f "$file" ]; then
        echo "   ⚠️  文件不存在: $file"
        continue
    fi

    echo "   上传: $(basename $file)..."

    # 使用tools API上传
    RESULT=$(curl -s -X POST \
        -H "x-api-key: $GALAXY_API_KEY" \
        -F "tool_id=upload1" \
        -F "history_id=$HISTORY_ID" \
        -F "file=@$file" \
        -F "file_type=txt" \
        "$GALAXY_URL/api/tools" 2>/dev/null)

    # 提取dataset ID
    DATASET_ID=$(echo "$RESULT" | python3 -c "import sys, json; r=json.load(sys.stdin); print(r['outputs'][0]['id'] if 'outputs' in r else '')" 2>/dev/null)

    if [ -n "$DATASET_ID" ]; then
        DATASET_IDS+=("$DATASET_ID")
        echo "   ✅ Dataset ID: $DATASET_ID"
    else
        echo "   ❌ 上传失败"
    fi
done

if [ ${#DATASET_IDS[@]} -eq 0 ]; then
    echo "❌ 没有文件被上传"
    exit 1
fi

echo "✅ 上传了 ${#DATASET_IDS[@]} 个文件"
echo ""

# 创建collection
echo "📁 创建Collection..."

# 构建element identifiers JSON
ELEMENTS="["
for i in "${!DATASET_IDS[@]}"; do
    if [ $i -gt 0 ]; then
        ELEMENTS="$ELEMENTS,"
    fi
    ELEMENTS="$ELEMENTS{\"name\":\"sample$((i+1))\",\"src\":\"hda\",\"id\":\"${DATASET_IDS[$i]}\"}"
done
ELEMENTS="$ELEMENTS]"

# 创建collection
COLLECTION_DATA="{\"collection_type\":\"list\",\"name\":\"test_collection\",\"element_identifiers\":$ELEMENTS,\"history_id\":\"$HISTORY_ID\"}"

COLLECTION_ID=$(curl -s -X POST \
    -H "x-api-key: $GALAXY_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$COLLECTION_DATA" \
    "$GALAXY_URL/api/dataset_collections" | \
    python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)

if [ -z "$COLLECTION_ID" ]; then
    echo "❌ Collection创建失败"
    echo "   可能需要等待文件上传完成，请稍后在UI中手动创建"
    echo ""
    echo "手动步骤："
    echo "1. 访问 $GALAXY_URL"
    echo "2. 历史记录面板 → 选中3个文件"
    echo "3. For all selected... → Build Dataset List"
    exit 1
fi

echo "✅ Collection ID: $COLLECTION_ID"
echo ""

# 导入workflow (如果还没导入)
echo "📥 检查Workflow..."
WORKFLOW_ID=$(curl -s -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/workflows" | \
    python3 -c "import sys, json; wfs=json.load(sys.stdin); print(next((w['id'] for w in wfs if 'Cloud Test' in w.get('name', '')), ''))" 2>/dev/null)

if [ -z "$WORKFLOW_ID" ]; then
    echo "   导入Workflow..."

    if [ ! -f "$WORKFLOW_FILE" ]; then
        echo "❌ Workflow文件不存在: $WORKFLOW_FILE"
        exit 1
    fi

    WORKFLOW_JSON=$(cat "$WORKFLOW_FILE" | python3 -c "import sys, json; print(json.dumps({'workflow': json.load(sys.stdin)}))")

    WORKFLOW_ID=$(curl -s -X POST \
        -H "x-api-key: $GALAXY_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$WORKFLOW_JSON" \
        "$GALAXY_URL/api/workflows" | \
        python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)

    if [ -z "$WORKFLOW_ID" ]; then
        echo "❌ Workflow导入失败"
        exit 1
    fi

    echo "   ✅ Workflow已导入"
fi

echo "✅ Workflow ID: $WORKFLOW_ID"
echo ""

# 运行workflow
echo "▶️  运行Workflow..."

RUN_DATA="{\"workflow_id\":\"$WORKFLOW_ID\",\"history\":\"hist_id=$HISTORY_ID\",\"inputs\":{\"0\":{\"id\":\"$COLLECTION_ID\",\"src\":\"hdca\"}}}"

INVOCATION=$(curl -s -X POST \
    -H "x-api-key: $GALAXY_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$RUN_DATA" \
    "$GALAXY_URL/api/workflows/$WORKFLOW_ID/invocations" 2>/dev/null)

INVOCATION_ID=$(echo "$INVOCATION" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)

if [ -z "$INVOCATION_ID" ]; then
    echo "❌ Workflow启动失败"
    echo "   错误: $INVOCATION"
    exit 1
fi

echo "✅ Workflow已启动"
echo "   Invocation ID: $INVOCATION_ID"
echo ""

# 显示结果
echo "╔════════════════════════════════════════════════════════╗"
echo "║              ✅ 测试已启动！                            ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "🎯 下一步验证："
echo ""
echo "1. 在Galaxy UI查看:"
echo "   $GALAXY_URL/histories/$HISTORY_ID"
echo ""
echo "2. 点击作业详情，查看:"
echo "   ✓ Destination: cloud_small"
echo "   ✓ Runner: galaxy_cloud"
echo ""
echo "3. 在AWS查看:"
echo "   aws batch list-jobs --job-queue galaxy-cloud-queue"
echo ""
echo "4. 查看S3:"
echo "   aws s3 ls s3://galaxy-cloud-data-1760241377/ --recursive"
echo ""
echo "5. 实时查看Galaxy日志:"
echo "   tail -f galaxy_startup.log | grep -i batch"
echo ""
