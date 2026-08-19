# BioMate 沙箱模式概览

> 面向研发团队的非技术版说明。技术细节见 `docs/20260819_SANDBOX_MODE_COMPLETE.md`。

---

## 沙箱是什么

BioMate 允许用户提交代码和工作流在服务器上执行。沙箱模式的作用是：**把这些执行关在一个一次性的隔离容器里，防止恶意代码攻击服务器**。

代码跑完，容器销毁，什么都带不走。

---

## 为什么需要沙箱

没有沙箱时，用户提交的代码可以：

- 读取服务器上的数据库密码、AWS 密钥、LLM API Key
- 通过 Docker socket 操控宿主机（等价于 root 权限）
- 访问内网其他服务、AWS 元数据接口（获取 IAM 凭证）

沙箱把这些攻击面全部关闭。

---

## 覆盖哪些执行面

| 执行面 | 触发方式 | 沙箱保护 |
|---|---|---|
| **run_code** | 用户在聊天框让 AI 执行 Python/R 代码 | ✅ |
| **个人 .nf 工作流** | 用户上传自己写的 Nextflow 文件并运行 | ✅ |
| **Jupyter / RStudio** | 用户在聊天框启动交互式笔记本 | ✅（部分，见下） |
| **AWS Batch 工作流** | ADMET、RNA-seq、WGS、CryoEM 等标准流程 | — 不需要（云端 worker 天然隔离） |

---

## 沙箱具体做了什么

每次执行，代码被关在一个容器里，该容器：

- **断网**（`--network none`）：访问不了任何外部地址
- **非 root 用户**（uid=1000）：没有系统级权限
- **只读文件系统**：不能修改容器内系统文件
- **gVisor 内核隔离**：用虚拟内核（4.19.0-gvisor）替代真实内核，系统调用被拦截
- **资源上限**：CPU、内存、进程数均有限制
- **凭证过滤**：AWS Key、数据库密码等 env var 不传入容器

Jupyter 容器因技术原因不使用 gVisor，但有镜像白名单和挂载路径验证。

---

## 架构：窄通道（Narrow Launcher）

沙箱的核心设计是一个叫 **sandbox-launcher** 的小服务，它是**唯一能和 Docker daemon 对话的应用层组件**。

```
用户代码
  ↓
BioMate 前端 / 后端（无 Docker 权限）
  ↓  HTTP 请求
sandbox-launcher（验证请求是否合法，然后启动容器）
  ↓
docker-socket-proxy（只允许必要的 Docker 操作）
  ↓
Docker daemon → gVisor 隔离容器
```

前端和后端容器本身没有 Docker socket，所以即使它们被攻破，也无法直接操控容器。

---

## 当前部署状态

| 环境 | 沙箱状态 |
|---|---|
| **测试环境**（test.stage-public.biomate.ai） | ✅ 已开启，三个执行面全部验证通过 |
| **开发环境**（dev-public.biomate.ai） | ❌ 未开启（env vars 未设置） |
| **生产环境** | ❌ 未开启 |

沙箱所有功能都通过 **env var 开关控制，默认关闭**。不设置 env var 就跟没有沙箱代码完全一样，不影响现有功能。

---

## 现阶段重要吗

**现阶段不紧急**。目前 BioMate 的用户都是内部测试或合作研究机构，不存在随机恶意用户。

沙箱是为**将来公开上线**做的技术储备。等真正开放给不特定用户时，这套机制可以直接开启，不需要重新开发。

---

## 如何开启沙箱（运维参考）

在部署时叠加沙箱 overlay 文件：

```bash
docker compose \
  -f deploy/docker-compose.deploy.yml \
  -f deploy/docker-compose.sandbox.yml \
  up -d
```

沙箱 overlay 会自动启动 `sandbox-launcher` 和 `docker-socket-proxy` 两个服务，并为前端/后端注入必要的 env vars。

前置条件：宿主机需安装 gVisor（`runsc`）。详见 `docs/20260819_SANDBOX_MODE_COMPLETE.md` 第 6 节。

---

## 相关文件

| 文件 | 内容 |
|---|---|
| `deploy/docker-compose.sandbox.yml` | 沙箱部署 overlay（所有配置的 source of truth） |
| `deploy/sandbox-launcher/launcher.py` | 窄通道服务源码 |
| `backend/lib/galaxy/ai/compute/sandbox/` | 后端沙箱配置和命令构建逻辑 |
| `frontend/server/code-runner.ts` | run_code 执行路径 |
| `docs/20260819_SANDBOX_MODE_COMPLETE.md` | 完整技术文档（env var 参考、ECR 镜像、安全边界） |
