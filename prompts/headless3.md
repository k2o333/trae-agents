

# Trae智能体 - Coding Agent 执行规范 (v2.2)

## 📌 核心变更 (v2.2)
1.  **引入全局配置锚点**：不再依赖记忆路径或手动复制粘贴。所有操作必须通过读取 `/home/quan/output/trae/sessions/config.txt` 获取当前上下文。
2.  **上下文持久化**：任务初始化时必须写入 Config 文件；后续所有步骤（写入 Prompt、执行 Tool）必须先读取 Config 文件。

## 📂 目录与文件管理

### 1. 基础路径配置
- **会话根目录**：`/home/quan/output/trae/sessions/`
- **全局配置文件**：`/home/quan/output/trae/sessions/config.txt` (核心锚点)
- **当前任务目录**：`{SessionDir}` (由配置文件定义)

### 2. Config 文件格式规范
每次任务开始时重写，格式必须为 **Shell 变量赋值格式**，以便直接 `source`：
```bash
SESSION_DIR="/home/quan/output/trae/sessions/任务名_时间戳"
PROJECT_DIR="/path/to/current/project"
TASK_NAME="当前任务名"
```

## ⚙️ 命令执行通用规则

### 🔴 规则 1：Read-Config-First (先读配置)
在执行任何具体的写文件或调用工具命令前，**必须**先加载配置文件。
```bash
# 标准开头
source /home/quan/output/trae/sessions/config.txt
```

### 🔴 规则 2：命令多行排版 (Keep Clean)
所有 Agent 调用命令（`codebuddy`, `qwen` 等）必须使用 `\` 换行。

### 🔴 规则 3：文件引用
禁止直接在命令行写长文本，必须使用 `$(cat "$SESSION_DIR/prompts/...")`。

---

## 🛠️ 标准执行流程 (SOP)

### 第一步：初始化任务 (Init & Anchor)
**目标**：创建目录并建立“上下文锚点”。
**场景**：当用户下达一个新的复杂编程任务时。

```bash
# 1. 定义本次任务变量
TASK_NAME="refactor_auth_module"
TIMESTAMP=$(date +%Y%m%d%H%M)
NEW_SESSION="/home/quan/output/trae/sessions/${TASK_NAME}_${TIMESTAMP}"
CURRENT_PROJECT=$(pwd) # 或者指定具体路径

# 2. 创建目录结构
mkdir -p "$NEW_SESSION/prompts"
mkdir -p "$NEW_SESSION/outputs"

# 3. 写入全局锚点 Config (关键步骤！覆盖写入)
cat << EOF > /home/quan/output/trae/sessions/config.txt
SESSION_DIR="$NEW_SESSION"
PROJECT_DIR="$CURRENT_PROJECT"
TASK_NAME="$TASK_NAME"
EOF

# 4. 验证
cat /home/quan/output/trae/sessions/config.txt
echo "✅ Session initialized & Config updated."
```

### 第二步：编写提示词 (Safe Write)
**目标**：将分析或指令写入文件。
**场景**：无论在哪个终端窗口，只要加载 config 就能找到位置。

```bash
# 1. 加载配置
source /home/quan/output/trae/sessions/config.txt

# 2. 写入提示词 (使用变量)
cat << 'EOF' > "$SESSION_DIR/prompts/step1_plan.txt"
[任务目标]
重构用户登录逻辑...

[代码引用]
$(cat $PROJECT_DIR/src/auth.ts)
EOF

echo "📝 Prompt written to: $SESSION_DIR/prompts/step1_plan.txt"
```

### 第三步：并行/执行 Agent (Headless Run)
**目标**：调用工具生成代码或分析。由于读取了 config，即使 Trae 开了新终端也能正确执行。

#### 示例 A：运行 CodeBuddy (编码)
```bash
# 1. 加载配置
source /home/quan/output/trae/sessions/config.txt

# 2. 执行命令
codebuddy -p "$(cat $SESSION_DIR/prompts/step1_plan.txt)" \
  --output-format json \
  -y \
  > "$SESSION_DIR/outputs/step1_codebuddy.json"
```

#### 示例 B：运行 Qwen (审查/并行)
*可以在另一个终端窗口直接粘贴运行，无需修改路径。*
```bash
# 1. 加载配置
source /home/quan/output/trae/sessions/config.txt

# 2. 执行命令
qwen -p "$(cat $SESSION_DIR/prompts/step1_plan.txt)" \
  --output-format json \
  --approval-mode yolo \
  > "$SESSION_DIR/outputs/step1_qwen.json"
```

---

## 🎯 修复与调试场景

如果 Trae 在中途突然断开或开启了一个没有任何环境变量的新终端，你只需要执行标准开头即可恢复上下文：

```bash
# 😱 糟糕，这是个新终端，变量都没了？
# 😎 没关系，直接 source 锚点文件：
source /home/quan/output/trae/sessions/config.txt

# 验证一下
echo "Resumed session: $SESSION_DIR"
# 继续你的工作...
```

## ✅ 给智能体的系统指令 (System Prompt Summary)

> **致 Trae Agent：**
> 当你执行任务时，**不要**信任 Shell 的环境变量持久性。
> 1.  **开始任务时**：必须生成目录并重写 `/home/quan/output/trae/sessions/config.txt`。
> 2.  **执行步骤时**：生成的每一个 Shell 代码块，**第一行必须是** `source /home/quan/output/trae/sessions/config.txt`。
> 3.  **引用路径时**：统一使用 `$SESSION_DIR` 和 `$PROJECT_DIR`，禁止硬编码长路径。