#!/usr/bin/env python3
"""Surgical, journaled Word edits from the approved immutable source commit.

Run with the bundled document Python runtime, then render/inspect all outputs.
Outputs are review candidates; this script does not qualify a release.
"""
from copy import deepcopy
import hashlib
import io
import json
import re
from pathlib import Path
import subprocess
import zipfile

from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, RGBColor

ROOT = Path(__file__).resolve().parents[2]
BASE = "79c0421d90ff86f5973513a0360677bd72df390c"
OUT = ROOT / "docs/qa/20261107-onprem-readiness/revised-manuals"


def same_except_comment_dates(before, after):
    """Keep unchanged candidates byte-stable across unrelated manual edits."""
    with zipfile.ZipFile(io.BytesIO(before)) as old, zipfile.ZipFile(io.BytesIO(after)) as new:
        if set(old.namelist()) != set(new.namelist()):
            return False
        for name in old.namelist():
            a, b = old.read(name), new.read(name)
            if name == "word/comments.xml":
                a = re.sub(rb' w:date="[^"]*"', b'', a)
                b = re.sub(rb' w:date="[^"]*"', b'', b)
            if a != b:
                return False
        return True


def recreate(services):
    return "docker compose --env-file /app/biomate/.env \\\n  -f /app/biomate/docker-compose.onprem.yml \\\n  up -d --no-deps --force-recreate " + services


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    journal = []
    for suffix in ("交付清单", "运维手册", "运维远程支持手册"):
        name = "BioMate本地部署" + suffix + ".docx"
        raw = subprocess.check_output(["git", "show", BASE + ":docs/" + name], cwd=ROOT)
        doc = Document(io.BytesIO(raw))
        paragraphs = list(doc.paragraphs)
        changes = []

        def edit(index, text, reason, normal=False):
            p = paragraphs[index]
            before = p.text
            if before == text:
                return
            old_style = p.style.name
            properties = deepcopy(p.runs[0]._r.rPr) if p.runs and p.runs[0]._r.rPr is not None else None
            p.clear()
            if normal:
                p.style = doc.styles["Normal"]
            run = p.add_run(text)
            if properties is not None and not normal:
                run._r.insert(0, properties)
            if text:
                doc.add_comment(run, text=reason, author="BioMate 实施团队", initials="BM")
            changes.append({"paragraph_index_in_approved_source": index, "before": before, "after": text,
                            "reason": reason, "before_style": old_style, "after_style": p.style.name})

        def update_restart(index, services=None):
            text = paragraphs[index].text
            for old, target in (("docker restart biomate-galaxy biomate-frontend", "galaxy-backend frontend"),
                                ("docker restart biomate-galaxy", "galaxy-backend"),
                                ("docker restart biomate-frontend", "frontend")):
                text = text.replace(old, recreate(services or target))
            edit(index, text, "环境变量在容器创建时注入；应用 .env 变化须重建相关服务，不能只 restart。")

        if suffix == "交付清单":
            edit(100, "A2. 工作流启动后长时间未完成\n可能涉及镜像拉取、架构、资源不足或任务自身错误。先检查实际运行状态和执行器日志，再按已确认原因处理；不能默认归因于镜像代理。", "删除与后续安全处置相矛盾的全局 Docker 代理删除指令。", True)
            edit(105, "只检查配置是否已设置，使用完整部署包的元数据诊断：\ncd /app/biomate\nbash scripts/diag-onprem.sh\n网络验证应针对所选模型服务，限制连接和响应超时；HTTP 连通不等于鉴权、模型及工具调用已通过。", "移除 grep .env 的明文密钥输出；通用 HTTP 成功不能替代模型调用验收。", True)
            edit(143, "收集问题信息（由客户审查后按批准渠道发送）：", "默认外发原始日志与诊断隐私边界不一致。", True)
            edit(144, "cd /app/biomate\nbash scripts/diag-onprem.sh\n# 默认元数据模式；仅在客户明确授权后按远程支持手册采集敏感日志。", "用配套元数据采集替代未经审查的完整 Compose 日志导出。", True)
            edit(113, "先核对文件归属、运行记录、实际工作目录和前后端共享挂载。仅在配置确实错误时由管理员修改对应变量，并重建受影响服务；禁止把扩大允许路径作为 403 的通用绕过。再次验证本人有权访问的文件可以读取，而其他账号和无关路径仍被拒绝。", "403 恢复同时验收正向访问与跨用户拒绝，不能无条件追加目录放宽权限。", True)
            edit(46, "BioMate 以经发行验收的部署包交付，不需要访问私有源码仓库。实施前核对版本清单、CPU 架构、镜像摘要和 SHA256 校验文件；未确认完整性时不得开始离线交付。", "旧版引用的标准打包脚本不在已批准源码中；不得保留不可执行的交付命令。", True)
            edit(78, "若内网 LLM 不可达，检查防火墙及 LLM_API_URL、LLM_MODEL、LLM_API_KEY，并确认 GALAXY_AI_LLM_PROVIDER=openai_compatible。只核对密钥是否已设置，不在截图、日志或聊天中输出明文。", "使用前后端实际支持的配置名，并限制密钥输出。", True)
            edit(98, "A1. 页面空白 / 白屏\n先检查浏览器网络请求、前端健康和镜像版本。若 Google CDN 请求阻塞，使用包含运行时过滤修复的配套镜像，并设置 DISABLE_GOOGLE_FONTS=true。\n" + recreate("frontend") + "\n验证根路径、index.html 和项目深链接均可加载，且不再请求 Google Fonts/Analytics。不要按行删除压缩后的 HTML；这可能删除整个页面。", "落实配套代码、Compose 透传和根路径验收要求，删除危险的压缩 HTML 按行补丁。", True)
            edit(99, "", "移除已被重建容器步骤替代的孤立 restart 命令。")
            edit(101, "先核对任务镜像名称、CPU 架构、预载状态及执行器日志，再确认是否受镜像代理影响。优先使用已验收的离线镜像和任务拉取策略；不要直接删除全局 Docker 镜像代理配置或重启 Docker，以免影响其他服务。", "故障恢复应针对已确认原因，不能默认修改全局服务配置。", True)
            edit(103, "由管理员先确认无活动任务，并核对容器数据库卷的实际挂载及锁文件位置。停止后端，保留日志及该锁文件副本，只处理已确认失效的 /app/database/dependencies/involucro.lock，再启动后端。禁止递归删除所有 *.lock。", "保留可恢复证据，限定单一失效锁，删除宽泛递归清理示例。", True)
            update_restart(108)
            edit(110, "docker exec biomate-galaxy uname -m\n# ARM64 应返回 aarch64；还须核对具体镜像的架构和工作流验收记录。", "容器 inspect 不提供文中假设的顶层 Architecture 字段；使用实际运行架构检查。")
            edit(111, "A7. MinIO 访问报签名错误\n可能涉及端点、签名区域、寻址方式或凭证不一致。先核对故障类别，不能仅凭错误信息认定密码有误。", "区分多种签名错误成因，不将凭证误配置诊断为数据损坏。", True)
            edit(112, "A8. 工作流输出预览或下载返回 403\n403 可能是权限、文件归属、路径或共享挂载问题。用有权访问该运行的账号验证；不得关闭鉴权或扩大访问根目录来绕过错误。", "区分真实访问拒绝与配置缺陷，避免将所有 403 当作可绕过的问题。", True)
            edit(115, "只核对凭证是否已设置及受控保管记录，不输出明文。先备份对象数据和配置，再由管理员按存储服务的凭证轮换流程处理。禁止删除 MinIO 数据卷，也不能用重新安装来修复已有数据的认证问题。", "删除可能造成研究数据永久丢失的恢复建议。", True)
            paragraphs[111]._p.addnext(paragraphs[115]._p)
            changes.append({"operation": "move", "paragraph_index_in_approved_source": 115, "after_original_paragraph": 111,
                            "reason": "将 MinIO 处置内容归回 A7，不再插在 A8 文件权限问题之后。"})
        elif suffix == "运维手册":
            edit(21, "部署架构应按客户硬件、任务类型和配套发行清单选择。x86-64 与 ARM64 均有实现支持，但必须逐项核对应用、基础服务、任务镜像及模型依赖的架构；不能将平台支持等同于所有工作流均已原生验收。", "去除跨 CPU 性能相同和全工作流完整支持的无条件保证。", True)
            edit(44, "任务镜像的 ARM64 可用性以配套发行清单、摘要和实际原生执行结果为准。显式指定的架构标签不会自动切换；多架构标签也须确认含有所需平台的 manifest。", "镜像架构不能仅凭 Docker 默认平台或镜像命名推断。", True)
            edit(46, "部分任务可能仅提供 x86-64 镜像。ARM64 上的模拟执行必须逐项验证功能、性能及依赖；不能承诺统一性能倍数或功能等价。未经该环境验收的工作流不得计为已通过。", "删除未经逐流程验证的模拟运行保证。", True)
            edit(48, "健康检查宽限期只决定何时开始计入失败，不是启动成功证明。Booting worker 仅表示进程启动阶段；仍需验证健康端点、目录加载及实际工作流。超过约定观察时限时保留错误并核对原生架构、内存、模型资产和初始化状态。", "不能凭一条 worker 日志判定成功，避免将真实启动故障当作正常等待。", True)
            edit(97, "平台提供对象存储配置能力。OSS、COS 或其他服务能否替换当前存储，需在配套发行版中验证所有客户端路径；核对下面的配置示例后，按前述上传、下载、预览和任务执行测试验收。环境变化须重建相关容器，不能只 restart。", "区分配置能力与所有存储路径已经验收，避免跨后端无条件兼容承诺。", True)
            edit(154, "备份应写入客户批准的受限目录，使用唯一时间标识并限制权限。PostgreSQL 使用一致性导出并验证退出状态及恢复结果；SQLite 使用受支持的在线备份接口，或停止所有写入后连同 WAL/SHM 状态一致备份，不能直接复制运行中的主文件。对象存储、模型资产和配置另作一致性备份。自动过期清理必须遵循客户保留策略与批准清单，不递归删除整个备份根目录。只有校验和恢复演练通过后才能记录备份成功。", "去除可能复制不一致 SQLite、管道失败仍报成功及递归删除备份根目录的示例。", True)
            edit(175, "方法二：由发行工程师提供配套修复镜像", "旧标题与已删除的现场 HTML 热补丁相矛盾。", True)
            edit(181, "使用客户批准的真实 Web 访问 Origin（协议、主机和端口）配置 CORS_ORIGINS；多个值按模板约定分隔。不要从云元数据推断内网访问地址，也不要覆盖仍在使用的合法 Origin。\n" + recreate("frontend") + "\n验证获准 Origin 可访问，未获准 Origin 仍被拒绝。", "避免使用公网 IP、覆盖现有 Origin 或放宽 CORS 作为通用修复。", True)
            edit(200, "镜像拉取慢时，先核对配套发行清单和已验收的离线镜像包。Docker registry-mirrors 不是任意私有 GHCR 仓库的通用代理；不要据此承诺私有仓库加速。", "区分 Docker Hub 镜像代理与私有 GHCR，纠正错误加速建议。", True)
            edit(201, "不要覆盖 /etc/docker/daemon.json。若客户基础设施管理员批准修改全局 Docker 配置，须先备份并合并现有设置，确认所有服务影响及回滚步骤，在维护窗口实施。优先使用已验收的离线交付包。", "移除覆盖客户全局 Docker 配置的命令。", True)
            edit(230, "不要通过无条件追加 NEXTFLOW_WORK_DIR 或扩大允许目录绕过权限检查。核对发行版、运行归属和共享挂载后，验证有权访问的输出可读，并验证其他用户及无关路径仍被拒绝。", "权限恢复必须包含负向隔离验收。", True)
            edit(232, "先用客户批准的管理通道检查存储健康，再由有权限的用户验证该运行的上传、预览和下载。健康端点返回成功不等于对象权限与数据读取成功。不要把存储密码放入命令行参数、截图或日志，也不要关闭桶或文件归属检查。", "去除明文存储密码命令行及将健康检查等同于访问验收的示例。", True)
            edit(34, "先确认这些变量已在配套 Compose 的 galaxy-backend.environment 中传入；修改 .env 后重建后端服务。仅向宿主机 .env 添加变量或执行 restart 不会更新容器环境。", "澄清宿主机配置与容器实际环境的区别。", True)
            for index in (72, 74, 99, 140, 159, 174, 219):
                update_restart(index)
            edit(113, "本地 GPU 任务必须单独验收", "删除没有执行器消费的环境变量启用步骤。", True)
            edit(114, "当前配套实现没有消费旧文所列的 GPU Docker 选项变量，不要依赖该设置启用 GPU。应核对 NVIDIA 驱动、任务容器设备请求和具体工作流的实际 GPU 使用。", "没有运行时消费的变量不能作为已支持配置宣传。", True)
            edit(115, "将 GPU 暴露给后端容器，不等于后端启动的任务容器获得 GPU。Slurm 和 Kubernetes 执行器已有实现，但仍须核对实际提交的资源请求及 GPU 作业结果；修改资源名称不能替代兼容性验收。", "区分后端与任务容器，以及执行器实现与真实 GPU 调度。", True)
            edit(168, "先检查当前镜像是否包含已验收的任务拉取策略，并确认本地镜像名称和架构正确。不要在客户现场通过替换容器内 Python 源码修复执行器；应使用配套发行版并保留回滚镜像。", "删除依赖字符串替换位置的现场源代码热补丁。", True)
            edit(173, "方法一 使用配套镜像的运行时 Google CDN 过滤", "过滤功能存在于配套实现，不能暗示任意旧镜像均支持。", True)
            edit(176, "不建议直接用 sed 按行修改构建后的 index.html：压缩 HTML 可能只有一行，按行删除会破坏整个页面。若配套镜像尚未包含运行时过滤修复，应回滚至已验收版本或由发行工程师提供修复镜像。", "避免紧急修复删除整份压缩页面。", True)
            edit(187, "首次初始化应使用容器可访问的受控内网资产源。已有目录更新按第 6 节执行：停止后端、备份 SQLite 目录和配置、核对新文件校验值后替换，再启动并检查索引。不要在运行中直接覆盖目录数据库。", "区分首次初始化与已有目录更新，避免在线覆盖数据库。", True)
            edit(193, "确认无活动任务，停止后端并保留日志、锁文件副本和挂载记录。只处理已确认失效的 /app/database/dependencies/involucro.lock，然后启动后端。禁止在挂载路径为空或未经核对时执行文件删除。", "对精确锁文件恢复增加路径及活动任务校验。", True)
            edit(211, "只确认密钥已设置，不输出其值：\ndocker exec biomate-galaxy python3 -c 'import os; print(\"DEEPSEEK_API_KEY=set\" if os.getenv(\"DEEPSEEK_API_KEY\") else \"DEEPSEEK_API_KEY=empty\")'\n随后在获准的网络边界内验证模型服务连通性。", "避免 printenv 将真实 API 密钥暴露到日志或支持渠道。", True)
            edit(215, "# 确认 PostgreSQL 已就绪\ndocker exec biomate-postgres pg_isready -U biomate -d biomate\n# 只确认连接字符串是否存在，不打印含密码的 URL\ndocker exec biomate-frontend node -e 'console.log(process.env.DATABASE_URL ? \"DATABASE_URL=set\" : \"DATABASE_URL=empty\")'", "数据库连接 URL 可能含密码；诊断默认只报告设置状态。")
            edit(242, "标准交付包应由已验收的发行流程生成。当前已批准仓库没有旧文引用的标准打包脚本，不得把旧命令当作可执行步骤。发行清单必须包含应用镜像、基础服务与任务镜像、目录数据库、工作流定义、模型资产、配置模板和维护工具，并逐项核对 CPU 架构、摘要及校验文件。", "删除不存在的打包命令；明确完整离线交付的实际依赖。", True)
            edit(249, "首次初始化前，由客户管理员提供 db-init 和 nfcore-init 均可访问的受控内网资产地址，并设置 BIOMATE_DB_URL、BIOMATE_NFCORE_URL。仅在显式只读挂载和读取方式均已验收时使用本地文件路径；宿主机的 file:// 路径不会自动出现在容器内。已有数据卷按第 6 节备份更新，不能通过删除数据卷强制初始化。", "去除没有容器挂载支撑的 host file:// 示例。", True)
        else:
            edit(8, "方案 C：Cloudflare 正式隧道（须独立验收）", "目录与正式隧道及 Access 验收要求一致，不宣传未验证的临时 SSH。")
            edit(9, "接入后：在批准的数据边界内排查问题", "目录不默认指示启动外部 AI。")
            edit(11, "frp 中继服务管理（获准管理员）", "服务部署权取决于客户授权，不限定为团队内部云账号。")
            edit(54, "由获准管理员部署客户批准的中继服务，参见第 8 节；位置、访问范围及流量路径须经过审批。", "与客户批准的中继位置一致，不默认使用团队的外部云账号。", True)
            for stop_index in (47, 64, 76):
                edit(stop_index, "# 同一操作者、同一状态目录，只停止已验证归属的会话\nbash scripts/remote-access.sh stop", "与部署包实际脚本路径和限定停止范围一致。")
            edit(48, "随后由获准管理员在控制台撤销或删除对应设备，并验证访问已被拒绝。停止客户端和撤销服务端授权是两项独立检查。", "不能把仅停止客户端与撤销服务端授权当作等价替代。", True)
            edit(67, "适用：客户已批准正式 Cloudflare 中继与 Access 策略，且客户端、镜像和 SSH 访问均具备独立验收条件。", "适用场景与正式隧道一致，不再宣传无需完整 SSH 的临时模式。", True)
            edit(78, "6. 接入后：在批准的数据边界内排查问题", "正文标题不默认指示启动外部 AI。")
            edit(79, "进入客户环境后，只执行本次批准范围内的诊断与变更；先验证元数据，再按授权确定是否需要敏感日志。", "SSH 权限不自动授权所有日志、数据或模型访问。", True)
            edit(80, "6.1 诊断工具及 AI 使用边界", "与后续禁止自动安装和默认外发的说明一致。")
            edit(88, "cd /app/biomate\nbash scripts/diag-onprem.sh\n# bash 调用不要求脚本执行位；如仍拒绝访问，核对目录/文件权限和操作者。\n# 配套隐私过滤程序必须同时存在，不复制单个脚本绕过检查。", "使用配套脚本真实路径，不把所有权限错误都归因于执行位。", True)
            edit(90, "客户端预装失败或版本不匹配时由管理员核对来源、校验值、CPU 架构和批准的软件清单；脚本不会切换第三方镜像源。", "删除与取消自动下载相矛盾的 ghproxy 说明。", True)
            edit(101, "8. frp 中继服务管理（获准管理员）", "与客户审批的中继归属和管理职责一致。")
            edit(102, "中继位置、容量、网络区域与运维责任由客户批准并按实际并发验收，不默认指定供应商、区域或硬件规格。", "删除未测量的固定规格与默认外部区域建议。", True)
            edit(36, "由客户 IT 批准组织账号、访问策略和认证 key。凭据通过批准的密钥渠道写入仅当前操作者可读的文件；不放入命令行、聊天或截图。客户端须由管理员预装并验证。", "新脚本拒绝明文命令行凭据，也不会接管已有主机连接。", True)
            edit(42, "# 管理员预装并启动 Tailscale，批准本次访问后准备私有凭据文件\nchmod 600 /secure/tailscale-auth\nbash scripts/remote-access.sh tailscale \\\n  --key-file /secure/tailscale-auth\n# 已有主机连接时拒绝接管；返回成功且状态确认 Running 才算接入。", "与受保护的 auth-key file 接口一致；移除自动安装及明文 key 示例。", True)
            edit(58, "# 管理员预装并校验 frpc；凭据文件归当前用户所有\nchmod 600 /secure/frp-token\nbash scripts/remote-access.sh frp \\\n  --server <客户批准的中继主机> \\\n  --token-file /secure/frp-token \\\n  --port <客户批准的端口>", "改用私有凭据文件，不把共享 token 暴露到进程参数或 shell 历史。", True)
            edit(59, "脚本不自动下载 frpc，也不使用未经校验的镜像代理。由管理员核对版本、来源校验值、CPU 架构和执行权限后预装；服务端登录成功仍须验证代理注册、SSH 账号和访问范围。", "替换未校验自动下载保证，区分登录与端到端成功。", True)
            edit(66, "5. 方案 C：Cloudflare 正式隧道（须独立验收）", "未验证的 quick SSH 模式不作为可用支持通道。")
            edit(68, "必须经客户批准 Cloudflare 中继路径、Access 策略及数据边界。脚本拒绝 --quick SSH 模式；正式隧道须预置已验收的不可变镜像，支持 token-file，并单独验证 SSH。进程运行不等于通道验收。", "与 fail-closed 实现一致，移除随机 URL 即可 SSH 的错误保证。", True)
            edit(70, "# 客户预载并验收镜像，凭据文件仅当前操作者可读\nchmod 600 /secure/cloudflare-token\nbash scripts/remote-access.sh cloudflare \\\n  --token-file /secure/cloudflare-token \\\n  --image cloudflare/cloudflared@sha256:<已验收的64位摘要>\n# 不会自动拉取镜像；实际版本须支持 token-file。", "不可变镜像、离线预载和文件凭据取代 latest 与明文 token。", True)
            edit(72, "脚本仅报告 Cloudflare 进程已启动。客户管理员随后验证服务端连接、Access 策略、SSH 访问及未授权拒绝。未完成这些验证不能记录远程支持通道通过。", "删除无实际连接验证的成功输出示例。", True)
            edit(74, "工程师使用经客户批准并校验的 cloudflared 客户端，通过批准的 Access 主机名及最小权限账号连接。软件安装、版本与来源校验由管理员管理；不要下载未固定版本的二进制后直接运行。", "不再从 latest 下载未校验客户端，不默认使用 root。", True)
            edit(89, "Q: frpc 未安装或版本未验收", "脚本已取消未经校验的自动下载，不再按下载代理故障处理。")
            edit(91, "由客户管理员按批准的软件分发流程预装 frpc，核对来源、版本、SHA256、CPU 架构及权限。再使用 --token-file 启动已批准的中继和端口。不要将可执行文件放到公共 /tmp 固定路径，也不要使用 --token 明文参数。", "删除共享临时可执行路径和旧明文接口，保持与新脚本一致。", True)
            edit(99, "# 使用创建会话的同一操作者及相同状态目录\nbash scripts/remote-access.sh stop\nbash scripts/remote-access.sh status\n# 仅停止本脚本已验证归属的会话，不停止主机其他连接。\n# 由管理员另行撤销服务端授权并验证无法再次连接。", "脚本状态不是主机所有远程通道均已撤销的证明。", True)
            edit(103, "中继服务器由客户或获准基础设施管理员部署和管理。先核对 frps 发行版本、校验值与架构，再按批准的变更流程安装。配置及共享 token 仅管理员可读；限制客户端来源、工程师来源和允许的单个端口范围，配置日志保留及服务端撤销流程。启动后分别验证认证、代理注册、SSH 正向访问与未授权拒绝。不要照抄未校验下载、固定公网端口或示例 token 的自动部署脚本。", "删除未经校验执行、默认全端口范围及示例明文服务器配置，服务器设置须独立审计。", True)
            edit(82, "6.2 客户批准范围内的元数据诊断", "不能默认授权外部 AI 读取完整日志、运行路径或健康响应正文。")
            edit(83, "cd /app/biomate\nbash scripts/diag-onprem.sh\n# 默认只采集元数据；先由客户审查结果。\n# 需要日志正文时，记录客户批准的范围、接收人和保留期限，\n# 再按第 2 节执行显式授权的敏感采集。\n# 不把实时原始日志、许可证内容或患者数据自动输入外部模型。", "去除默认原始日志/健康响应正文采集，也修复原长行超出页面边界。", True)
            edit(14, "先确认客户授权及数据边界。\n可离线排查：在客户内网生成元数据诊断包，由客户审查后按批准渠道提供。\n确需远程操作：由客户 IT 审批接入软件、账号、访问范围及会话时限，再选用已验收的 Tailscale 或 frp 方案。\n第三方中继或临时公网隧道：额外核对流量经过的位置、访问控制和客户许可；不得作为无审批的备用通道。\n支持结束：停止对应通道，撤销设备/账号授权，验证无法重新连接并保存审计记录。认证 key 到期或轮换共享 token 均不能替代会话撤销。", "决策图本身仍包含一次性 token、自动撤销及无审批接入等错误，不能只修正文而保留矛盾图示。", True)
            edit(38, "Ephemeral 设备的自动清理条件以服务配置为准；支持结束仍须主动停止通道并验证设备授权已撤销。", "临时设备清理不能等同于即时断开或会话自动到期。", True)
            edit(52, "可选择客户批准的自管中继；仍需核对中继主机、云服务商、流量经过区域、密钥管理和日志策略。自管服务不自动等于无第三方参与或满足合规要求。", "不把自管中继作为无条件合规保证。", True)
            edit(81, "不要在客户服务器自动下载并运行外部 AI 工具。优先使用客户批准的本地诊断程序；确需 AI 辅助时，先审批模型位置、数据访问与外发范围。即使工具运行在工程师电脑上，输入客户日志或命令输出仍可能产生数据外发，不能以 SSH 手动执行替代数据授权。", "联网、临时安装或工程师本机运行均不能构成默认数据处理授权。", True)
            edit(44, "# 由客户批准的账号连接，仅在授权范围内操作\nssh <获准账号>@<批准的设备地址>\n# 使用获准的本地诊断工具；AI 辅助分析须另行核对数据授权。", "不默认要求 root 或启动外部 AI。")
            edit(61, "# 连接地址、账号和端口由客户批准\nssh <获准账号>@<批准的中继地址> -p <获准端口>\n# 保留访问审计；不自动启动外部 AI。", "接入成功不构成外部模型处理客户数据的授权。")
            edit(17, "优先在客户内网收集元数据诊断。默认不包含日志正文、运行记录或环境值；即使是元数据，也应由客户审查后再按批准渠道处理。", "与默认最小化采集实现一致，不把脱敏当作自动可外发保证。", True)
            edit(18, "2.1 客户操作", "去除未经测量的固定完成时长。")
            edit(19, "# 使用完整部署包，隐私过滤程序必须与 shell 脚本一同提供\ncd /app/biomate\nbash scripts/diag-onprem.sh\n# 只有在客户明确授权后才收集敏感日志\n# bash scripts/diag-onprem.sh --include-sensitive --confirm-authorized", "替换远程下载即执行和单文件运行方式，说明额外敏感采集授权。")
            edit(20, "输出路径以脚本打印为准；每次使用唯一目录，默认目录权限仅限当前用户。", "采用唯一安全临时目录，不再假定固定秒级文件名。", True)
            edit(21, "由客户先检查诊断包，确认接收人、传输渠道和保留期限。不要上传公共文件分享服务，也不要默认将内容发送给境外 AI 服务。", "落实医院数据边界与转移授权。", True)
            edit(24, "在受控工作目录检查来源和归档内容后再解压。不要以 root 身份展开不可信归档，也不要直接在用户主目录覆盖现有文件。", "避免将客户提供的归档直接展开到共享目录。", True)
            edit(26, "SUMMARY.txt             # 状态摘要\nsystem.txt              # 系统元数据\ndocker-info.txt         # Docker 版本和空间信息\ncontainers-status.txt   # 受控容器状态\ninspect/                # 仅允许字段的状态投影，不含完整配置\napi-checks.txt          # 默认仅 HTTP 状态，不含响应正文\nenv-summary.txt         # 仅环境变量名及设置状态\n\nlogs/ 和运行记录仅在显式授权的敏感模式下采集；该模式的输出不能视为已脱敏。", "目录说明对应实际隐私边界，不再声称完整 inspect 或日志已安全脱敏。")
            edit(27, "在客户批准的数据边界内分析", "不默认推荐把支持数据输入外部 AI。", True)
            edit(28, "先查看 SUMMARY.txt 和状态元数据，再确定是否需要由客户批准更细的日志采集。若使用 AI 辅助分析，应事先确认模型部署位置、数据处理条款和授权范围；不得自动上传患者数据或凭证。", "明确模型分析的数据流和审批条件。", True)
            edit(32, "优势：接入配置较简单，可通过控制台和访问策略审计。认证 key 到期不会自动撤销已经加入的设备；支持结束后必须停止通道并在控制台撤销或删除对应设备。", "依据 Tailscale 官方 Auth keys 文档区分 auth key 到期与节点授权。", True)
            for index, paragraph in enumerate(paragraphs):
                if "Expiry: 1 hour" in paragraph.text:
                    edit(index, "认证 key 使用控制台支持的最短合适期限；支持会话另设明确结束时间。key 的有效期不是会话自动断开保证。", "官方 auth key 有效期范围与旧文一小时示例不一致；会话撤销须独立执行。", True)
            edit(55, "4.2 共享凭证的保管与会话撤销", "当前 frp 实现使用共享 token，不是一次性 token。")
            edit(56, "当前方案使用受控共享 token，由授权管理员通过批准的密钥渠道提供。不得宣称其为一次性凭证。每次支持都须记录客户授权、工程师身份、连接端口与结束时间；结束后停止对应客户端并验证无法再次连接。", "与已实现的 frp 认证方式一致，补充会话级控制。", True)
            edit(104, "Token 管理原则：共享 token 存放于批准的密钥库，按组织策略及事件需要轮换。支持结束后停止对应会话，检查客户端、服务端和审计记录；仅轮换 token 或观察日志不能替代验证通道已关闭。\n参考：https://tailscale.com/docs/features/access-control/auth-keys", "共享凭证轮换与活动会话撤销是不同控制。", True)

        # Reconcile unsupported guarantees throughout the existing manuals,
        # keeping capabilities distinct from per-release qualification.
        for index, p in enumerate(paragraphs):
            text = p.text
            if "支持的 GALAXY_AI_LLM_PROVIDER 值" in text:
                edit(index, "支持的 GALAXY_AI_LLM_PROVIDER 包括 openai_compatible、anthropic、openai、deepseek、zhipu、openrouter 和 ollama。默认以配套 .env 模板为准；只配置选用提供商所需的端点、模型名及密钥。", "补全实际模型提供商配置，与默认模板一致。", True)
            elif "性价比最佳" in text or "国内直连无延迟" in text:
                edit(index, text.replace("性价比最佳", "应按客户场景评测成本和质量").replace("国内直连无延迟", "连通性与延迟以现场实测为准"), "去除没有当前测试依据的性能和成本保证。", True)
            elif "旧版本部署使用 MinIO，新版本使用阿里云 OSS" in text:
                edit(index, "是否运行 MinIO 取决于所选存储配置，不由新旧版本决定。使用外部对象存储或已验收的纯本地模式时，不应仅因没有 MinIO 容器就判定部署故障；先核对实际端点、凭证及文件读写路径。", "存储模式可配置，不能把某个演示环境当作所有部署的默认。", True)
            elif "速度约为 x86 的 1/3" in text:
                edit(index, "工作目录需要足够容量的持久化存储。实际临时空间、启动耗时和模拟性能取决于工作流、数据量、镜像架构及服务器配置。ARM64 主机应逐项核对任务镜像是否原生；需要模拟执行的工具必须另做功能与性能验收。", "架构支持与性能必须按镜像和流程验证，不能给出统一倍速保证。", True)
            elif "要把输入/输出改存到客户已有" in text:
                edit(index, "更换对象存储时同时核对端点、区域、凭证、寻址方式及各服务的实际配置，并用上传、下载、预览和工作流分阶段验证。只有客户端路径均通过验收后，才能替换现有存储；先备份并制定回滚方案。", "不能把部分客户端配置支持等同于所有存储路径均已验证。", True)
            elif "Ollama 本地大模型需要" in text:
                edit(index, "本地模型的内存和显存需求取决于量化方式、上下文长度、批量和并发。按实际模型与服务器压测，不能只凭参数量给出统一最低内存；完全离线时还需预置模型权重及其全部依赖。", "收紧没有具体模型配置和测试依据的硬件保证。", True)
            elif "管理界面：http://<服务器IP>:9001" in text:
                edit(index, "MinIO 管理界面默认仅绑定服务器本机 127.0.0.1:9001。远程管理使用获准的 SSH 隧道或受控代理，不直接向用户网络开放管理端口。", "与实际 Compose loopback 绑定一致。", True)
            elif "mkfs.ext4 /dev/vdb" in text:
                edit(index, "数据盘初始化、格式化、挂载及开机持久化由客户基础设施管理员在核对设备标识、备份和授权后完成。不要按示例设备名格式化磁盘，也不要盲写 fstab。实施工程师仅做只读核对：\nlsblk -f\ndf -h /app", "移除对假定设备名的格式化命令，避免误删客户数据盘。", True)
            elif "docker system prune -f" in text:
                edit(index, text.replace("docker system prune -f", "# 清理前逐项核对、备份并获得授权；不要执行全局 prune"), "全局清理可能删除停止的容器及离线恢复资产，不能作为例行无风险操作。")
            elif "--netfilter-mode=off" in text:
                edit(index, "由客户网络管理员核对官方接入需求、出站策略、代理和中继可达性。不要为了接入关闭防火墙管理，也不要把修改 netfilter 设置当作强制 TCP 传输或穿透防火墙的保证。", "删除不准确的网络排障承诺及不必要的防火墙管理关闭命令。", True)
            elif "免费，支持最多 20 台设备" in text:
                edit(index, "由客户 IT 批准组织账号、访问策略和服务套餐。设备容量及许可按当前合同与官方说明确认，不在本手册承诺固定免费额度。", "移除可能变化的商业套餐和设备数承诺。", True)
            else:
                updated = text
                for old, new in (("docs/ONPREM_SETUP.md", "《BioMate 本地部署运维手册》"), ("ONPREM_SETUP.md", "《BioMate 本地部署运维手册》"), ("ONPREM_DELIVERY_CHECKLIST.md", "《BioMate 本地部署交付清单》")):
                    updated = updated.replace(old, new)
                if updated != text:
                    edit(index, updated, "交付给客户的 Word 手册引用实际文档名称，不引用未随包提供的仓库 Markdown 路径。", True)

        for index, p in enumerate(paragraphs):
            text = p.text
            updated = text.replace("滚动重启（无停机时间约 30 秒）", "在维护窗口更新服务（可能中断，先确认无活动任务和可用备份）")
            updated = re.sub(r"docker compose([^\n]*) down -v", r"# 禁止在例行维护中删除持久化卷；销毁必须另行授权并先验证备份", updated)
            if "scp biomate-deploy-" in updated:
                updated = updated.replace(".tar.gz biomate-images-", ".tar.gz \\\n  biomate-images-")
                updated = re.sub(r"\.tar\.gz root@", ".tar.gz \\\n  root@", updated)
            if updated != text:
                edit(index, updated, "补充维护中断/数据保护边界，并为长命令加入可复制的 shell 续行。")

        for table_index, table in enumerate(doc.tables):
            for row_index, row in enumerate(table.rows):
                for cell_index, cell in enumerate(row.cells):
                    before = cell.text
                    after = before.replace("✅ 完整支持", "按配套镜像逐项验收").replace("默认，效果最好", "按客户评测选择")
                    after = after.replace("docs/ONPREM_SETUP.md", "《BioMate 本地部署运维手册》")
                    if "/app/biomate/data/minio" in before:
                        after = "按实际 MinIO 数据卷或外部对象存储进行一致性备份，先核对挂载位置。"
                    if after != before:
                        cell.text = after
                        changes.append({"table_index": table_index, "row_index": row_index, "cell_index": cell_index, "before": before, "after": after, "reason": "将能力声明与实际部署配置、验收和备份位置对齐。"})

        # Approved inputs lack explicit section dimensions/table grids, and
        # their theme CJK fonts vanish in the packaged renderer. Repair the
        # document structure without changing table contents or their order.
        for index, p in enumerate(paragraphs):
            for old, new in (("v1.1 · 2026-11-06", "v1.2 审阅版 · 2026-11-07"), ("v1.0 · 2026-11-06", "v1.1 审阅版 · 2026-11-07")):
                if old in p.text:
                    before = p.text
                    for run in p.runs:
                        run.text = run.text.replace(old, new)
                    if old in p.text:
                        edit(index, p.text.replace(old, new), "更新修订日期及审阅状态。", True)
                    else:
                        changes.append({"paragraph_index_in_approved_source": index, "before": before, "after": p.text, "reason": "更新修订日期及审阅状态，保留原行内格式。"})
            if re.search(r"v1\.0\s*·\s*2026-11-06", p.text):
                edit(index, re.sub(r"v1\.0\s*·\s*2026-11-06", "v1.1 审阅版 · 2026-11-07", p.text), "更新带特殊空白符的旧版本日期及审阅状态。", True)
        for child in list(doc.element.body):
            if child.tag == qn("w:sdt") and "".join(n.text or "" for n in child.iter(qn("w:t"))).strip() == "Table of Contents":
                doc.element.body.remove(child)
                changes.append({"operation": "remove-empty-toc-placeholder", "reason": "移除没有任何条目的英文目录占位块；保留正文及标题导航。"})
        for section in doc.sections:
            if section.page_width is None:
                section.page_width = Inches(8.5)
                section.page_height = Inches(11)
            if section.left_margin is None:
                section.left_margin = Inches(0.75)
                section.right_margin = Inches(0.75)
                section.top_margin = Inches(0.75)
                section.bottom_margin = Inches(0.75)
        for fonts in doc.element.xpath(".//w:rFonts"):
            fonts.set(qn("w:eastAsia"), "Heiti SC")
            fonts.attrib.pop(qn("w:eastAsiaTheme"), None)
        for style in doc.styles:
            properties = style.element.get_or_add_rPr()
            fonts = properties.find(qn("w:rFonts"))
            if fonts is None:
                fonts = OxmlElement("w:rFonts")
                properties.insert(0, fonts)
            fonts.set(qn("w:eastAsia"), "Heiti SC")
            fonts.attrib.pop(qn("w:eastAsiaTheme"), None)
            if style.style_id.startswith(("Heading", "Title", "Subtitle")) or style.style_id.endswith("Heading"):
                style.font.color.rgb = RGBColor(0, 0, 0)
                color = properties.find(qn("w:color"))
                if color is not None:
                    for attr in ("themeColor", "themeShade", "themeTint"):
                        color.attrib.pop(qn("w:" + attr), None)
        available = int((doc.sections[0].page_width - doc.sections[0].left_margin - doc.sections[0].right_margin) / 635)
        for table in doc.tables:
            count = max(len(row.cells) for row in table.rows)
            weights = {2: [0.28, 0.72], 3: [0.28, 0.44, 0.28], 4: [0.20, 0.40, 0.25, 0.15], 5: [0.24, 0.19, 0.19, 0.19, 0.19]}.get(count, [1 / count] * count)
            headers = [cell.text for cell in table.rows[0].cells]
            if count == 3 and "预计时长" in headers:
                weights = [0.30, 0.18, 0.52]
            widths = [int(available * weight) for weight in weights]
            grid = table._tbl.find(qn("w:tblGrid"))
            if grid is None:
                grid = OxmlElement("w:tblGrid")
                table._tbl.insert(1, grid)
            for child in list(grid):
                grid.remove(child)
            for width in widths:
                column = OxmlElement("w:gridCol")
                column.set(qn("w:w"), str(width))
                grid.append(column)
            table.autofit = False
            for row in table.rows:
                row._tr.get_or_add_trPr().append(OxmlElement("w:cantSplit"))
                for index, cell in enumerate(row.cells):
                    cell.width = widths[min(index, count - 1)] * 635
            header_properties = table.rows[0]._tr.get_or_add_trPr()
            if header_properties.find(qn("w:tblHeader")) is None:
                header_properties.append(OxmlElement("w:tblHeader"))
            borders = table._tbl.tblPr.find(qn("w:tblBorders"))
            if borders is None:
                borders = OxmlElement("w:tblBorders")
                table._tbl.tblPr.append(borders)
            for side in ("top", "left", "bottom", "right", "insideH", "insideV"):
                border = borders.find(qn("w:" + side))
                if border is None:
                    border = OxmlElement("w:" + side)
                    borders.append(border)
                for attr, value in (("val", "single"), ("sz", "4"), ("color", "D9D9D9")):
                    border.set(qn("w:" + attr), value)
        changes.append({"operation": "layout-repair", "reason": "Visual QA found renderer font-resolution failure; input section/table-grid dimensions also needed explicit values. Fontconfig repair is task-local, not a customer system change.",
                        "changes": ["explicit existing Heiti SC CJK font reference", "explicit missing page/margin dimensions", "bounded table grids and cell widths", "black heading styles", "light-gray table borders"],
                        "content_order_preserved": True})

        target = OUT / name
        built = io.BytesIO()
        doc.save(built)
        data = built.getvalue()
        if not target.exists() or not same_except_comment_dates(target.read_bytes(), data):
            target.write_bytes(data)
        journal.append({"document": name, "source_revision": BASE, "source_sha256": hashlib.sha256(raw).hexdigest(),
                        "candidate_path": str(target.relative_to(ROOT)), "candidate_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                        "changes": changes, "status": "edited-review-candidate-render-and-content-qa-required"})
    (OUT / "changes.json").write_text(json.dumps(journal, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"outputs": len(journal), "changes": sum(len(x["changes"]) for x in journal), "directory": str(OUT)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
