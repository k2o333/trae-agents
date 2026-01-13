

# Trae智能体 - Coding Agent 执行规范 (v2.0)

## 📌 核心原则
1. **强制验证**：每完成编码相关任务，必须调用 coding agent 的无头模式进行验证或优化。
2. **会话隔离**：每次执行任务前，必须在指定目录下创建独立的**任务会话文件夹**，用于存放所有中间产物（提示词txt、输出json）。
3. **文件引用**：严禁直接在命令行参数中输入长文本。必须先将提示词写入 `.txt` 文件，通过 `cat` 命令读取，以防止换行符被终端误判为回车。
4. **产物分离**：中间过程文件存放在会话文件夹，**最终交付代码/文档**必须写入用户当前工作的**项目根目录**或指定的目标路径。

## 📂 目录与文件管理

### 1. 基础路径配置
- **会话根目录**：`/home/quan/output/trae/sessions/`
- **当前任务目录变量**：`$SESSION_DIR`
- **命名规则**：`{任务名称}_{时间戳}/` (时间戳格式：YYYYMMDDHHMM)

### 2. 文件分类
| 文件类型 | 存放位置 (`$SESSION_DIR`) | 命名规则 | 用途 |
| :--- | :--- | :--- | :--- |
| **提示词文件** | `$SESSION_DIR/prompts/` | `{步骤名}.txt` | 解决命令行换行问题 |
| **Agent输出** | `$SESSION_DIR/outputs/` | `{步骤名}_{agent}.json` | 原始的JSON/Stream流数据 |
| **最终交付物** | **当前项目工作区** | `项目原有结构` 或 `指定文件名.md` | 最终合并后的代码或文档 |

## 🛠️ 标准执行流程 (Standard Operating Procedure)

### 第一步：初始化会话环境
在执行任何 Agent 之前，必须先构建目录结构：
```bash
# 定义变量
TASK_NAME="user_auth_feature"
TIMESTAMP=$(date +%Y%m%d%H%M)
SESSION_DIR="/home/quan/output/trae/sessions/${TASK_NAME}_${TIMESTAMP}"

# 创建目录结构
mkdir -p "$SESSION_DIR/prompts"
mkdir -p "$SESSION_DIR/outputs"

echo "Session created at: $SESSION_DIR"
```

### 第二步：写入提示词文件
将原本要传入 `-p` 的长文本写入 txt 文件：
```bash
# 将提示词写入文件（支持多行文本）
cat << 'EOF' > "$SESSION_DIR/prompts/step1_logic.txt"
这里是复杂的任务描述：
1. 请分析用户登录逻辑
2. 检查 SQL 注入风险
3. 代码需要符合 PEP8 规范
EOF
```

### 第三步：执行无头模式命令
使用 `$(cat ...)` 读取文件内容作为参数。

#### Option A: codebuddy
```bash
codebuddy -p "$(cat $SESSION_DIR/prompts/step1_logic.txt)" \
  --output-format json \
  -y \
  > "$SESSION_DIR/outputs/step1_logic_codebuddy.json"
```

#### Option B: qwen
```bash
qwen -p "$(cat $SESSION_DIR/prompts/step1_logic.txt)" \
  --output-format stream-json \
  --approval-mode yolo \
  > "$SESSION_DIR/outputs/step1_logic_qwen.json"
```

## 🔄 协作模式策略

### 1️⃣ 讨论汇总模式 (Discussion & Summary)
**场景**：需要多视角验证复杂逻辑。
1. 创建 `$SESSION_DIR`。
2. 写入同一个提示词到 `$SESSION_DIR/prompts/full_task.txt`。
3. 并行或串行调用 `codebuddy` 和 `qwen`，输出到 `$SESSION_DIR/outputs/`。
4. **最终动作**：智能体读取两个 JSON 文件，综合最优解，将最终代码写入**当前项目文件**（如 `./src/auth.py`）或生成汇总 Markdown 到项目根目录。

### 2️⃣ 任务分配模式 (Task Delegation)
**场景**：任务可拆解，独立执行。
1. 创建 `$SESSION_DIR`。
2. 拆分提示词：
   - 写入 `$SESSION_DIR/prompts/subtask_1.txt`
   - 写入 `$SESSION_DIR/prompts/subtask_2.txt`
3. 分配执行：
   - `codebuddy` 读取 `subtask_1.txt` -> 输出至 `outputs/subtask_1_cb.json`
   - `qwen` 读取 `subtask_2.txt` -> 输出至 `outputs/subtask_2_qw.json`
4. **最终动作**：解析 JSON 中的代码块，分别应用到项目对应的源文件中。

## ⚠️ 关键注意事项
- **路径检查**：执行 `cat` 命令前，确保 txt 文件路径正确。
- **JSON 解析**：Agent 在读取 `$SESSION_DIR/outputs/*.json` 后，**必须**提取其中的 `code` 或 `content` 字段，将其应用到实际项目中，而不是仅仅生成 JSON 文件就结束。
- **清理机制**：除非用户特别要求，否则保留 `$SESSION_DIR` 以备回溯，不自动删除。

## 🎯 完整执行示例 (One-Shot Example)

假设任务是“生成登录接口并编写测试用例”：

```bash
# 1. 初始化
export SESSION_DIR="/home/quan/output/trae/sessions/login_api_202601121530"
mkdir -p "$SESSION_DIR/prompts" "$SESSION_DIR/outputs"

# 2. 准备 codebuddy 的任务（实现接口）
cat << 'EOF' > "$SESSION_DIR/prompts/impl.txt"
使用 FastAPI 实现一个 /login 接口，包含 JWT token 生成逻辑。
要求：使用 Pydantic 模型，处理 401 错误。
EOF

# 3. 准备 qwen 的任务（编写测试）
cat << 'EOF' > "$SESSION_DIR/prompts/test.txt"
为 FastAPI 的 /login 接口编写 Pytest 测试用例。
包括：成功登录、密码错误、用户不存在三种场景。
EOF

# 4. 执行 Agent
codebuddy -p "$(cat $SESSION_DIR/prompts/impl.txt)" --output-format json -y > "$SESSION_DIR/outputs/impl_codebuddy.json"
qwen -p "$(cat $SESSION_DIR/prompts/test.txt)" --output-format stream-json --approval-mode yolo > "$SESSION_DIR/outputs/test_qwen.json"

# 5. (智能体后续动作 - 伪代码)
# 读取 impl_codebuddy.json -> 提取代码 -> 写入 ./app/routers/auth.py
# 读取 test_qwen.json -> 提取代码 -> 写入 ./tests/test_auth.py
```

***

### 修改说明（供用户参考）

1.  **解决换行符问题**：现在所有命令都强制使用 `$(cat path/to/file.txt)`。这允许你在 txt 文件中随意换行、使用特殊字符，而不会破坏终端命令结构。
2.  **解决文件混乱问题**：引入了 `/sessions/{任务名}_{时间戳}/` 结构。并且在内部细分了 `prompts` 和 `outputs` 文件夹，保持 `/home/quan/output/trae/sessions` 根目录整洁。
3.  **解决产物分离问题**：明确区分了“过程文件”（JSON/TXT）和“最终交付物”（源代码/MD文档）。过程文件留在 Session 目录供调试，最终代码必须回写到实际的项目路径中。