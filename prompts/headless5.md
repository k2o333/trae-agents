

# Trae 智能体 - Coding Agent 执行规范 (v2.4)

## 📌 版本更新摘要 (v2.4)
1.  **并行稳定性**：在并行执行 (`&`) 场景下，脚本末尾**必须**包含 `wait` 指令，防止进程被杀。
2.  **自动重试**：引入 "Check-&-Retry" 逻辑，若检测到输出文件为空，立即串行重试。
3.  **上下文锚点**：继续强制使用 `/home/quan/output/trae/sessions/config.txt` 管理上下文。

---

## 📂 目录与锚点配置 (基础设施)

### 1. 基础路径
- **全局配置文件**：`/home/quan/output/trae/sessions/config.txt`
- **会话根目录**：`/home/quan/output/trae/sessions/`

### 2. Config 文件标准 (每次任务初始化必写)
```bash
SESSION_DIR="/home/quan/output/trae/sessions/任务名_时间戳"
PROJECT_DIR="/path/to/current/project"
TASK_NAME="当前任务名"
TIMESTAMP="202601121530" 
```

### 3. 通用命令前缀 (Must Do)
所有执行步骤的第一行必须是：
```bash
source /home/quan/output/trae/sessions/config.txt
```

---

## 🛠️ 标准执行流程 (SOP)

### 第一步：初始化与锚点建立 (Init)
*(保持不变，建立目录结构)*
```bash
TASK_NAME="refactor_auth"
TIME_NOW=$(date +%Y%m%d%H%M)
NEW_SESSION="/home/quan/output/trae/sessions/${TASK_NAME}_${TIME_NOW}"
CURRENT_PROJECT=$(pwd)

mkdir -p "$NEW_SESSION/prompts"
mkdir -p "$NEW_SESSION/outputs"

cat << EOF > /home/quan/output/trae/sessions/config.txt
SESSION_DIR="$NEW_SESSION"
PROJECT_DIR="$CURRENT_PROJECT"
TASK_NAME="$TASK_NAME"
TIMESTAMP="$TIME_NOW"
EOF

echo "✅ Session Initialized: $NEW_SESSION"
```

---

### 第二步：根据模式执行 (Execution)

#### 🟢 场景 A：执行【讨论汇总模式】(高并发 + 自动重试)
**操作**：编写通用提示词 -> 并行启动 Agent -> 等待结束 -> 校验并重试。

```bash
# 1. 加载配置
source /home/quan/output/trae/sessions/config.txt

# 2. 写入通用提示词
cat << 'EOF' > "$SESSION_DIR/prompts/main_task.txt"
[任务]
设计一个高并发的用户积分扣减系统...
[代码]
$(cat $PROJECT_DIR/src/points.ts)
EOF

# 定义输出文件路径
OUT_CB="$SESSION_DIR/outputs/${TASK_NAME}_${TIMESTAMP}_codebuddy.json"
OUT_QW="$SESSION_DIR/outputs/${TASK_NAME}_${TIMESTAMP}_qwen.json"

echo "🚀 Starting Parallel Execution..."

# 3. 并行启动 (注意 & 符号 和 2>&1)
codebuddy -p "$(cat $SESSION_DIR/prompts/main_task.txt)" \
  -y --output-format json \
  > "$OUT_CB" 2>&1 &
PID_CB=$!

qwen -p "$(cat $SESSION_DIR/prompts/main_task.txt)" \
  --approval-mode yolo --output-format stream-json \
  > "$OUT_QW" 2>&1 &
PID_QW=$!

# 4. 关键：等待所有后台进程结束 (Wait Guard)
wait $PID_CB $PID_QW
echo "✅ Parallel execution finished. Checking outputs..."

# 5. 自动重试逻辑 (Check & Retry)
# 检查 CodeBuddy
if [ ! -s "$OUT_CB" ]; then
    echo "⚠️ CodeBuddy output is empty. Retrying synchronously..."
    codebuddy -p "$(cat $SESSION_DIR/prompts/main_task.txt)" \
      -y --output-format json > "$OUT_CB" 2>&1
fi

# 检查 Qwen
if [ ! -s "$OUT_QW" ]; then
    echo "⚠️ Qwen output is empty. Retrying synchronously..."
    qwen -p "$(cat $SESSION_DIR/prompts/main_task.txt)" \
      --approval-mode yolo --output-format stream-json > "$OUT_QW" 2>&1
fi

echo "🎉 All tasks completed."
```

#### 🔵 场景 B：执行【任务分配模式】(独立任务)
**操作**：两个任务互不干扰，也可使用并行加速。

```bash
source /home/quan/output/trae/sessions/config.txt

# 1. 准备 prompts (subtask_1.txt, subtask_2.txt) ...
# (省略写入过程，假设文件已存在)

OUT_1="$SESSION_DIR/outputs/subtask1_${TIMESTAMP}_codebuddy.json"
OUT_2="$SESSION_DIR/outputs/subtask2_${TIMESTAMP}_qwen.json"

# 2. 并行执行
codebuddy -p "$(cat $SESSION_DIR/prompts/subtask_1.txt)" -y --output-format json > "$OUT_1" 2>&1 &
PID_1=$!

qwen -p "$(cat $SESSION_DIR/prompts/subtask_2.txt)" --approval-mode yolo --output-format stream-json > "$OUT_2" 2>&1 &
PID_2=$!

# 3. 等待与校验
wait $PID_1 $PID_2

# 简单校验
[ ! -s "$OUT_1" ] && echo "Retrying CodeBuddy..." && codebuddy -p "$(cat $SESSION_DIR/prompts/subtask_1.txt)" -y --output-format json > "$OUT_1" 2>&1
[ ! -s "$OUT_2" ] && echo "Retrying Qwen..." && qwen -p "$(cat $SESSION_DIR/prompts/subtask_2.txt)" --approval-mode yolo --output-format stream-json > "$OUT_2" 2>&1
```

---

## 📝 命名与格式规范汇总

### 1. 命令行规约
*   **文件引用**：禁止直接写长文本，必须用 `$(cat $SESSION_DIR/prompts/xxx.txt)`。
*   **错误流捕获**：所有输出重定向必须包含 `2>&1`，例如 `> output.json 2>&1`，否则报错信息会丢失。

### 2. 输出文件命名
格式：`{任务名}_{时间戳}_{Agent名}.json`

---

## ✅ 给智能体的系统指令 (System Prompt Summary)

> **致 Trae Agent (v2.4 执行守则)：**
>
> 1.  **环境锚点**：首行必输 `source /home/quan/output/trae/sessions/config.txt`。
> 2.  **并行必等**：只要使用了 `&` 后台运行，脚本下方必须紧跟 `wait $PID`，严禁直接退出。
> 3.  **结果校验**：执行完 Agent 命令后，必须检查输出文件是否为空 (`if [ ! -s file ]`)。如果为空，**必须**在脚本中立即发起一次串行重试。
> 4.  **错误留痕**：命令末尾必须加 `2>&1`，确保 `stderr` 被记录。