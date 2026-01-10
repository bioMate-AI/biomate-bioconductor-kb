# Galaxy启动流程详解

## 🚀 启动命令分析

```bash
./run.sh [start|stop|restart|status]
```

## 📋 完整启动流程

### 1️⃣ **入口脚本** (`run.sh`)

```bash
#!/bin/sh
cd "$(dirname "$0")"                    # 切换到Galaxy根目录
. ./scripts/common_startup_functions.sh  # 加载公共启动函数
```

#### 环境变量加载
```bash
# 加载本地环境配置（如果存在）
GALAXY_LOCAL_ENV_FILE='./config/local_env.sh'
if [ -f "$GALAXY_LOCAL_ENV_FILE" ]; then
    . "$GALAXY_LOCAL_ENV_FILE"          # 加载用户自定义环境变量
fi

# 设置PID和日志文件
GALAXY_PID=${GALAXY_PID:-galaxy.pid}
GALAXY_LOG=${GALAXY_LOG:-galaxy.log}
```

### 2️⃣ **参数解析** (`parse_common_args()`)

支持的启动参数：
```bash
./run.sh                    # 前台运行
./run.sh start              # 后台守护进程运行
./run.sh stop               # 停止服务
./run.sh restart            # 重启服务
./run.sh status             # 查看状态
```

高级参数：
```bash
--skip-eggs                 # 跳过Python包安装
--skip-wheels              # 跳过wheels安装
--skip-samples             # 跳过样本数据
--dev-wheels               # 开发模式wheels
--no-create-venv           # 不创建虚拟环境
--skip-client-build        # 跳过前端构建
--skip-tool-dependency-initialization  # 跳过工具依赖初始化
--skip-venv               # 跳过虚拟环境
```

### 3️⃣ **公共启动处理** (`run_common_start_up()`)

调用 `./scripts/common_startup.sh`，执行以下步骤：

#### A. **环境检查和准备**
```bash
# 1. 检查Python版本
find_python_command()
# 输出: "Using Python: /path/to/python3"

# 2. 虚拟环境设置
if [ ! -d ".venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv .venv
fi

# 3. 激活虚拟环境
echo "Activating virtualenv at .venv"
. .venv/bin/activate
```

#### B. **依赖安装**
```bash
# 1. 检查pip版本
check_pip_version()

# 2. 安装Python依赖
echo "Installing dependencies..."
pip install -r requirements.txt

# 3. 安装Galaxy特定包
pip install -e .
```

#### C. **前端构建**
```bash
# 1. Node.js环境检查
if command -v node >/dev/null; then
    echo "Building client..."
    cd client/
    npm ci                  # 安装Node.js依赖
    npm run build          # 构建前端资源
    cd ..
fi
```

### 4️⃣ **Python环境配置** (`setup_python()`)

```bash
# 1. Conda环境激活（如果配置）
if [ "$GALAXY_CONDA_ENV" ]; then
    conda_activate()
    echo "Activating Conda environment: $_galaxy_"
fi

# 2. Python路径设置
PYTHONPATH=lib:$PYTHONPATH
export PYTHONPATH
```

### 5️⃣ **测试工具配置**（可选）

```bash
if [ "$GALAXY_RUN_WITH_TEST_TOOLS" ]; then
    export GALAXY_CONFIG_OVERRIDE_TOOL_CONFIG_FILE="test/functional/tools/sample_tool_conf.xml"
    export GALAXY_CONFIG_ENABLE_BETA_WORKFLOW_MODULES="true"
    export GALAXY_CONFIG_OVERRIDE_ENABLE_BETA_TOOL_FORMATS="true"
    export GALAXY_CONFIG_INTERACTIVETOOLS_ENABLE="true"
    export GALAXY_CONFIG_OVERRIDE_WEBHOOKS_DIR="test/functional/webhooks"
fi
```

### 6️⃣ **配置文件解析** (`set_galaxy_config_file_var()`)

```bash
# 1. 查找配置文件
if [ -f "config/galaxy.yml" ]; then
    GALAXY_CONFIG_FILE="config/galaxy.yml"
elif [ -f "config/galaxy.ini" ]; then
    GALAXY_CONFIG_FILE="config/galaxy.ini"
else
    echo "Using default configuration"
fi

echo "Using config file: $GALAXY_CONFIG_FILE"
```

### 7️⃣ **工具依赖初始化**（可选）

```bash
if [ "$INITIALIZE_TOOL_DEPENDENCIES" -eq 1 ]; then
    echo "Initializing tool dependencies..."
    python ./scripts/manage_tool_dependencies.py init_if_needed
    # 这会安装Conda环境和工具依赖
fi
```

### 8️⃣ **服务器选择** (`find_server()`)

Galaxy支持多种服务器运行模式：

```bash
find_server() {
    # 1. 检查是否使用Gravity（新的进程管理器）
    if command -v galaxyctl >/dev/null; then
        run_server="galaxyctl"
        server_args="$gravity_args"
        echo "Using Gravity process manager"
    
    # 2. 检查是否使用Gunicorn（推荐的WSGI服务器）
    elif python -c "import gunicorn" 2>/dev/null; then
        run_server="gunicorn"
        server_args="'galaxy.webapps.galaxy.fast_factory:factory()' $gunicorn_args"
        echo "Using Gunicorn WSGI server"
    
    # 3. 回退到传统的Paste服务器
    else
        run_server="python"
        server_args="scripts/galaxy-main.py $paster_args"
        echo "Using Paste HTTP server"
    fi
}
```

### 9️⃣ **最终执行**

```bash
echo "Executing: $run_server $server_args"
eval GALAXY_ROOT_DIR="." $run_server $server_args
```

## 🏗️ 具体执行路径分析

### 路径A: **Gravity模式**（现代推荐方式）
```bash
galaxyctl start
├── 读取 gravity_config.yml
├── 启动 gunicorn 进程
├── 启动 celery 进程（后台任务）
├── 启动 celery-beat 进程（定时任务）
└── 进程监控和管理
```

### 路径B: **Gunicorn模式**（传统WSGI）
```bash
gunicorn 'galaxy.webapps.galaxy.fast_factory:factory()'
├── 加载 WSGI 应用工厂
├── 创建 Galaxy 应用实例
├── 初始化数据库连接池
├── 加载工具箱
├── 启动 Web 服务器
└── 监听 HTTP 请求
```

### 路径C: **开发模式**（脚本直接运行）
```bash
python scripts/galaxy-main.py
├── 解析命令行参数
├── 创建 Galaxy 应用
├── 启动开发服务器
└── 单进程模式运行
```

## 🔄 应用初始化流程

一旦选定服务器，Galaxy应用的初始化过程：

### 1. **应用工厂** (`galaxy.webapps.galaxy.fast_factory:factory()`)
```python
def factory():
    # 1. 读取配置
    config = GalaxyAppConfiguration()
    
    # 2. 创建Galaxy应用实例
    gx_app = GalaxyApplication(configure_logging=False, **config.kwargs)
    
    # 3. 创建FastAPI应用
    app = get_asgi_app(gx_app)
    
    return app
```

### 2. **Galaxy应用初始化** (`lib/galaxy/app.py`)
```python
class GalaxyApplication:
    def __init__(self, config):
        # 1. 配置验证和初始化
        self.config = config
        
        # 2. 数据库初始化
        self.model = galaxy.model.mapping.init_models_from_config(config)
        
        # 3. 安全组件
        self.security = galaxy.security.IdEncodingHelper()
        
        # 4. 数据类型注册表
        self.datatypes_registry = Registry()
        
        # 5. 工具箱加载（耗时操作）
        self.toolbox = tools.ToolBox(config_filenames, self)
        
        # 6. 作业管理器
        self.job_manager = JobManager(self)
        
        # 7. 工作流管理器
        self.workflow_manager = workflows.WorkflowsManager(self)
        
        # 8. AI助手初始化（我们添加的）
        self.ai_assistant = get_ai_assistant_instance(self)
```

### 3. **Web应用构建** (`lib/galaxy/webapps/galaxy/buildapp.py`)
```python
def app_factory(global_config, **kwargs):
    # 1. 创建FastAPI应用
    app = FastAPI(title="Galaxy", version="25.1")
    
    # 2. 添加中间件
    app.add_middleware(GalaxyASGIMiddleware)
    
    # 3. 注册路由
    from .api.workflows import router as workflows_router
    from .api.ai_assistant import router as ai_router
    app.include_router(workflows_router)
    app.include_router(ai_router)
    
    # 4. 添加静态文件服务
    app.mount("/static", StaticFiles(directory="static"))
    
    return app
```

## 📊 启动时间分析

典型的Galaxy启动时间分布：

```
总启动时间: 60-120秒（取决于工具数量）

├── 环境准备: 5-10秒
│   ├── 虚拟环境激活: 1秒
│   ├── 依赖检查: 2-5秒  
│   └── 前端构建: 2-4秒
│
├── 应用初始化: 30-80秒
│   ├── 配置加载: 2秒
│   ├── 数据库连接: 3-5秒
│   ├── 工具箱加载: 20-60秒 ⭐ 最耗时
│   ├── 数据类型注册: 2-5秒
│   └── 管理器初始化: 3-8秒
│
├── Web服务器启动: 5-10秒
│   ├── WSGI应用创建: 2-3秒
│   ├── 路由注册: 1-2秒
│   ├── 中间件加载: 1-2秒
│   └── 端口监听: 1-3秒
│
└── 健康检查: 5-10秒
    ├── 数据库连通性: 1-2秒
    ├── 工具可用性: 2-5秒
    └── API响应测试: 2-3秒
```

## 🔧 启动优化建议

### 开发环境优化：
```bash
# 跳过耗时步骤
./run.sh --skip-tool-dependency-initialization --skip-client-build

# 使用测试工具集（更少的工具）
GALAXY_RUN_WITH_TEST_TOOLS=1 ./run.sh
```

### 生产环境优化：
```bash
# 使用Gravity进程管理
pip install gravity
galaxyctl start

# 预编译静态资源
npm run build:production

# 数据库连接池优化
# 在config/galaxy.yml中配置：
database:
  engine_options:
    pool_size: 20
    max_overflow: 30
```

这就是Galaxy完整的启动流程！它展现了一个企业级Python应用应该具备的所有特征：环境管理、依赖处理、配置加载、模块化初始化、多种部署模式支持等。