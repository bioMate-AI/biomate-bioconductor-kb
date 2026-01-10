#!/bin/bash
# 配置 AWS Batch 支持 Docker-in-Docker

REGION="us-west-2"
LAUNCH_TEMPLATE_NAME="galaxy-batch-dind-template"
COMPUTE_ENV_NAME="galaxy-cloud-compute"

echo "=========================================="
echo "配置 AWS Batch 支持 Docker-in-Docker"
echo "=========================================="

# 1. 创建用户数据脚本（配置 Docker socket 权限）
cat > /tmp/userdata.sh <<'EOF'
Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
# 确保 Docker socket 对所有用户可访问（用于 Docker-in-Docker）
chmod 666 /var/run/docker.sock

# 创建 docker 组（如果不存在）
groupadd -f docker

# 允许容器访问 Docker socket
echo "Docker socket permissions configured for DinD"

--==BOUNDARY==--
EOF

# 2. 创建 Launch Template
echo ""
echo "[1/3] 创建 EC2 Launch Template..."

# 检查 Launch Template 是否已存在
EXISTING_TEMPLATE=$(aws ec2 describe-launch-templates \
    --region "$REGION" \
    --filters "Name=launch-template-name,Values=$LAUNCH_TEMPLATE_NAME" \
    --query 'LaunchTemplates[0].LaunchTemplateId' \
    --output text 2>/dev/null)

if [ "$EXISTING_TEMPLATE" != "None" ] && [ -n "$EXISTING_TEMPLATE" ]; then
    echo "Launch Template已存在: $EXISTING_TEMPLATE"
    echo "删除旧的 Launch Template..."
    aws ec2 delete-launch-template \
        --launch-template-id "$EXISTING_TEMPLATE" \
        --region "$REGION"
fi

# 创建新的 Launch Template
TEMPLATE_ID=$(aws ec2 create-launch-template \
    --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
    --region "$REGION" \
    --launch-template-data "{
        \"UserData\": \"$(base64 < /tmp/userdata.sh | tr -d '\n')\",
        \"TagSpecifications\": [{
            \"ResourceType\": \"instance\",
            \"Tags\": [{
                \"Key\": \"Name\",
                \"Value\": \"galaxy-batch-dind-instance\"
            }]
        }]
    }" \
    --query 'LaunchTemplate.LaunchTemplateId' \
    --output text)

echo "✓ Launch Template 创建成功: $TEMPLATE_ID"

# 3. 更新 Batch 计算环境使用 Launch Template
echo ""
echo "[2/3] 更新 AWS Batch 计算环境..."

# 注意：AWS Batch 不支持直接修改正在使用的计算环境的 Launch Template
# 需要创建新的计算环境或禁用->修改->启用

echo "注意：需要手动更新计算环境，因为 AWS Batch 限制"
echo ""
echo "请执行以下步骤："
echo "1. 在 AWS Console 中打开 AWS Batch"
echo "2. 找到计算环境: $COMPUTE_ENV_NAME"
echo "3. 点击 '编辑'"
echo "4. 在 'Launch template' 部分，选择: $LAUNCH_TEMPLATE_NAME"
echo "5. 保存更改"
echo ""
echo "或者运行以下命令（如果计算环境支持更新）："
echo ""
echo "aws batch update-compute-environment \\"
echo "    --compute-environment $COMPUTE_ENV_NAME \\"
echo "    --region $REGION \\"
echo "    --compute-resources launchTemplate={launchTemplateName=$LAUNCH_TEMPLATE_NAME}"

# 4. 更新 job_conf_cloud.yml 重新启用 fetch-and-run
echo ""
echo "[3/3] 更新配置文件..."
echo "请在 config/job_conf_cloud.yml 中设置："
echo '  use_fetch_and_run: "true"'

echo ""
echo "=========================================="
echo "配置完成！"
echo "=========================================="
echo "Launch Template ID: $TEMPLATE_ID"
echo "Launch Template Name: $LAUNCH_TEMPLATE_NAME"
echo ""
echo "下一步："
echo "1. 手动更新 AWS Batch 计算环境（见上面说明）"
echo "2. 在 config/job_conf_cloud.yml 中设置 use_fetch_and_run: \"true\""
echo "3. 重启 Galaxy"
echo "4. 测试 Docker-in-Docker 功能"

# 清理
rm /tmp/userdata.sh
