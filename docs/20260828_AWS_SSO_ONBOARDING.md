# AWS SSO 访问配置指南

**适用人员：** yaoyun.zhang@biomate.ai / soda.lj@gmail.com  
**配置时间：** 约 10 分钟  
**目的：** 通过 AWS SSO 获取 AWS 访问权限，无需管理静态 Access Key

---

## 第一步：激活账号（仅首次需要）

1. 打开 AWS 访问入口：
   **https://d-9267ff1d26.awsapps.com/start**

2. 点击页面下方 **"Forgot password"（忘记密码）**，输入你的邮箱地址

3. 检查邮箱，收到激活邮件后点击链接，按提示设置密码

4. 返回入口页面，用邮箱 + 密码登录，确认能看到账号列表（显示 `399683337364`）

> **注意：** 如果没有收到邮件，检查垃圾邮件文件夹；或联系 Yuankai 重新发送激活链接。

---

## 第二步：安装 AWS CLI（如果尚未安装）

检查是否已安装：
```bash
aws --version
```

如果未安装或版本低于 v2，前往官方下载：
- Mac：https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-mac.html
- Windows：https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-windows.html
- Linux：https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html

---

## 第三步：配置本地 AWS CLI

在终端运行：
```bash
aws configure sso --profile biomate
```

按提示依次填写（其余直接回车使用默认值）：

```
SSO start URL [None]:    https://d-9267ff1d26.awsapps.com/start
SSO Region [None]:       us-west-2
CLI default client Region [None]:   us-west-2
CLI default output format [None]:   json
Profile name [...]:      biomate
```

填写 URL 和 Region 后，浏览器会自动弹出授权页面：
1. 用你的邮箱 + 密码登录
2. 页面显示一串验证码，确认与终端中显示的一致
3. 点击 **"Allow"（允许）**
4. 浏览器显示"请求已批准"后，回到终端继续填写剩余配置

---

## 第四步：验证配置成功

```bash
aws sts get-caller-identity --profile biomate
```

成功输出示例：
```json
{
    "UserId": "AROA...:你的名字",
    "Account": "399683337364",
    "Arn": "arn:aws:sts::399683337364:assumed-role/AWSReservedSSO_BioMateAdmin_.../你的名字"
}
```

看到 `assumed-role/AWSReservedSSO_BioMateAdmin` 即表示配置成功。

---

## 日常使用

### 执行 AWS 命令
所有 aws 命令加上 `--profile biomate`：
```bash
aws s3 ls --profile biomate
aws ec2 describe-instances --profile biomate
```

### 设为默认（可选，避免每次加 --profile）
```bash
export AWS_PROFILE=biomate
```
加入 `~/.zshrc` 或 `~/.bashrc` 后永久生效：
```bash
echo 'export AWS_PROFILE=biomate' >> ~/.zshrc
source ~/.zshrc
```

### 凭证过期后刷新（每 8 小时需刷新一次）
```bash
aws sso login --profile biomate
```
运行后浏览器弹出登录页，点允许即可，整个过程 30 秒。

---

## 常见问题

**Q：提示 `Error loading SSO Token` 怎么办？**
A：凭证已过期，运行 `aws sso login --profile biomate` 重新授权。

**Q：浏览器没有自动打开怎么办？**
A：终端会显示一个 URL 和验证码，手动复制 URL 到浏览器打开，输入验证码后点允许。

**Q：能不能用 VS Code / PyCharm 等 IDE 的 AWS 插件？**
A：可以，在 IDE 的 AWS 配置里选择 profile `biomate` 即可。

---

*如有问题联系 Yuankai（zheganjue519@gmail.com）*
