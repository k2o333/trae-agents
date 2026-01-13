

# Trae 智能体 - Coding Agent 执行规范 (v2.5 终极版)

## 👑 核心原则 (Core Philosophy)
1.  **锚点优先 (Anchor First)**：所有操作必须围绕全局配置文件 `/home/quan/output/trae/sessions/config.txt` 进行。
2.  **幂等初始化 (Idempotent Init)**：初始化时检查文件是否存在，防止覆盖旧会话或生成分裂的目录。
3.  **进程守护 (Process Guard)**：后台并行执行必须使用 `wait`，输出文件必须校验大小，失败自动重试。
4.  **文件化交互 (File-Based)**：禁止在 CLI 参数中硬编码长文本，必须通过文件读写。

---

## 📂 基础设施配置

### 1. 绝对路径标准
- **全局锚点**：`/home/quan/output/trae/sessions/config.txt`
- **会话根目录**：`/home/quan/output/trae/sessions/`

### 2. Config 文件格式
*(由初始化脚本自动生成，后续只读)*
```bash
SESSION_DIR="/home/quan/output/trae/sessions/task_name_timestamp"
PROJECT_DIR="/current/project/path"
TASK_NAME="task_name"
TIMESTAMP="202601131000"
```

---

## 🛠️ 标准作业流程 (SOP)

### 第一步：安全初始化 (Safe Init)
**场景**：接到新任务时。
**规则**：先检查锚点是否存在。若存在则加载，若不存在则创建。**严禁**直接覆盖写入。

```bash
# 1. 定义任务名 (Agent 根据用户需求填写)
MY_TASK="optimize_module_x"

# 2. 执行安全初始化 (复制此代码块)
CONFIG_PATH="/home/quan/output/trae/sessions/config.txt"

if [ -f "$CONFIG_PATH" ]; then
    echo "⚠️ 锚点已存在，加载现有上下文..."
    source "$CONFIG_PATH"
    echo "✅ 上下文已恢复: $SESSION_DIR"
else
    echo "🆕 创建新会话..."
    # 动态生成时间戳 (禁止硬编码数字!)
    TIMESTAMP=$(date +%Y%m%d%H%M)
    NEW_SESSION="/home/quan/output/trae/sessions/${MY_TASK}_${TIMESTAMP}"
    
    mkdir -p "$NEW_SESSION/prompts"
    mkdir -p "$NEW_SESSION/outputs"
    
    # 写入 Config
    cat << EOF > "$CONFIG_PATH"
SESSION_DIR="$NEW_SESSION"
PROJECT_DIR="$(pwd)"
TASK_NAME="$MY_TASK"
TIMESTAMP="$TIMESTAMP"
EOF
    source "$CONFIG_PATH"
    echo "✅ 会话初始化完成: $NEW_SESSION"
fi
```

---

### 第二步：编写提示词 (Prompting)
**场景**：准备让 Coding Agent 干活。
**规则**：必须先 `source config`，然后将 Prompt 写入 `$SESSION_DIR/prompts/`。

```bash
# 1. 加载上下文
source /home/quan/output/trae/sessions/config.txt

# 2. 写入提示词文件
cat << 'EOF' > "$SESSION_DIR/prompts/step1_analysis.txt"
[任务目标]
...
[相关代码]
...
EOF
```

---

### 第三步：执行模式 (Execution Modes)

#### 🔄 模式 A：讨论汇总模式 (高可靠并行)
**场景**：需要 CodeBuddy 和 Qwen 同时分析同一问题。
**关键点**：`&` 后台运行 + `wait` 守护 + `Check-&-Retry` 机制。

```bash
# 1. 加载上下文
source /home/quan/output/trae/sessions/config.txt

# 2. 定义输出路径
OUT_CB="$SESSION_DIR/outputs/${TASK_NAME}_${TIMESTAMP}_codebuddy.json"
OUT_QW="$SESSION_DIR/outputs/${TASK_NAME}_${TIMESTAMP}_qwen.json"

echo "🚀 启动并行分析..."

# 3. 并行启动 (注意: 必须加 2>&1 捕获错误流)
codebuddy -p "$(cat $SESSION_DIR/prompts/step1_analysis.txt)" \
  -y --output-format json \
  > "$OUT_CB" 2>&1 &
PID_CB=$!

qwen -p "$(cat $SESSION_DIR/prompts/step1_analysis.txt)" \
  --approval-mode yolo --output-format stream-json \
  > "$OUT_QW" 2>&1 &
PID_QW=$!

# 4. 进程守护 (必须!)
wait $PID_CB $PID_QW
echo "✅ 并行任务结束，开始校验..."

# 5. 自动重试逻辑 (防止空文件)
if [ ! -s "$OUT_CB" ]; then
    echo "⚠️ CodeBuddy 输出为空，尝试串行重试..."
    codebuddy -p "$(cat $SESSION_DIR/prompts/step1_analysis.txt)" \
      -y --output-format json > "$OUT_CB" 2>&1
fi

if [ ! -s "$OUT_QW" ]; then
    echo "⚠️ Qwen 输出为空，尝试串行重试..."
    qwen -p "$(cat $SESSION_DIR/prompts/step1_analysis.txt)" \
      --approval-mode yolo --output-format stream-json > "$OUT_QW" 2>&1
fi

echo "🎉 任务完成。"
```

#### 🔀 模式 B：任务分配模式 (独立串行/并行)
**场景**：CodeBuddy 写代码，Qwen 写测试。

```bash
# ... (初始化同上)
# 分配 CodeBuddy
codebuddy -p "$(cat .../task1.txt)" -y --output-format json > "$OUT_1" 2>&1

# 分配 Qwen
qwen -p "$(cat .../task2.txt)" --approval-mode yolo --output-format stream-json > "$OUT_2" 2>&1
```

---

## 🚫 绝对禁忌 (Critical Constraints)

1.  **禁止硬编码时间戳**：
    *   ❌ `TIMESTAMP="20260113..."`
    *   ✅ `TIMESTAMP=$(date +%Y%m%d%H%M)`
    *   *原因：防止多次运行时生成不一致的目录路径。*

2.  **禁止多次写入 Config**：
    *   在任务执行的中途（Step 2, Step 3），**严禁**再次出现 `cat > ...config.txt`。
    *   如果需要恢复变量，只能执行 `source ...config.txt`。

3.  **禁止无守护的后台运行**：
    *   ❌ `codebuddy ... &` (直接回车)
    *   ✅ `codebuddy ... & PID=$!; wait $PID`
    *   *原因：无 `wait` 会导致 Shell 立即退出，后台 Agent 进程会被系统强制杀死，产生 0kb 空文件。*

4.  **禁止丢失错误流**：
    *   ❌ `> output.json`
    *   ✅ `> output.json 2>&1`
    *   *原因：没有 `2>&1`，一旦工具报错，文件中什么都没有，无法调试。*