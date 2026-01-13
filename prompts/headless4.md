# Trae 智能体 - Coding Agent 执行规范 (v2.3)

## 📌 版本更新摘要 (v2.3)
1.  **核心架构**：保持 v2.2 的全局配置锚点 (`config.txt`) 机制，确保上下文持久化。
2.  **新增策略**：引入双 Agent (CodeBuddy/Qwen) 的 **讨论汇总模式** 与 **任务分配模式**。
3.  **统一约束**：所有模式下的命令执行，必须严格遵循 "Read-Config-First" 和 "File-Based-Prompt" 原则。

---

## 📂 目录与锚点配置 (基础设施)

### 1. 基础路径
- **全局配置文件**：`/home/quan/output/trae/sessions/config.txt` (核心锚点)
- **会话根目录**：`/home/quan/output/trae/sessions/`

### 2. Config 文件标准 (每次任务初始化必写)
```bash
SESSION_DIR="/home/quan/output/trae/sessions/任务名_时间戳"
PROJECT_DIR="/path/to/current/project"
TASK_NAME="当前任务名"
TIMESTAMP="202601121530" # 统一时间戳，方便文件对齐
```

### 3. 通用命令前缀 (Must Do)
所有执行步骤的第一行必须是：
```bash
source /home/quan/output/trae/sessions/config.txt
```

---

## 🤖 智能体工具与模式定义

### 支持的 Coding Agent
1.  **CodeBuddy** (擅长代码生成/重构)
2.  **Qwen** (擅长代码审查/逻辑推演)

### 🔄 模式一：讨论汇总模式 (Discussion Mode)
**场景**：复杂、高风险任务。需要两个 Agent 针对**同一个问题**给出方案，然后人工或主 Agent 汇总最优解。
**逻辑**：One Prompt -> Two Agents -> Two Outputs.

### 🔄 模式二：任务分配模式 (Task Allocation Mode)
**场景**：大型任务或模块化任务。将大任务拆解为子任务，负载均衡。
**逻辑**：Prompt A -> Agent 1; Prompt B -> Agent 2.

---

## 🛠️ 标准执行流程 (SOP)

### 第一步：初始化与锚点建立 (Init)
**目标**：创建目录并固化上下文。

```bash
# 1. 定义变量
TASK_NAME="refactor_auth"
TIME_NOW=$(date +%Y%m%d%H%M)
NEW_SESSION="/home/quan/output/trae/sessions/${TASK_NAME}_${TIME_NOW}"
CURRENT_PROJECT=$(pwd)

# 2. 创建结构
mkdir -p "$NEW_SESSION/prompts"
mkdir -p "$NEW_SESSION/outputs"

# 3. 写入全局锚点 (覆盖写入)
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

#### 🟢 场景 A：执行【讨论汇总模式】
**操作**：编写一个主提示词，让两个 Agent 同时跑。

```bash
# 1. 加载配置
source /home/quan/output/trae/sessions/config.txt

# 2. 写入通用提示词
cat << 'EOF' > "$SESSION_DIR/prompts/main_task.txt"
[任务]
设计一个高并发的用户积分扣减系统，要求保证幂等性。
[当前代码]
$(cat $PROJECT_DIR/src/points.ts)
EOF

# 3. CodeBuddy 执行
codebuddy -p "$(cat $SESSION_DIR/prompts/main_task.txt)" \
  -y \
  --output-format json \
  > "$SESSION_DIR/outputs/${TASK_NAME}_${TIMESTAMP}_codebuddy.json" &

# 4. Qwen 执行 (后台并行推荐使用 &, 或顺序执行)
qwen -p "$(cat $SESSION_DIR/prompts/main_task.txt)" \
  --approval-mode yolo \
  --output-format stream-json \
  > "$SESSION_DIR/outputs/${TASK_NAME}_${TIMESTAMP}_qwen.json" &

echo "🚀 双 Agent 讨论模式已启动，结果输出至 outputs 目录"
```

#### 🔵 场景 B：执行【任务分配模式】
**操作**：将任务拆分为两个子文件，分别指派。

```bash
# 1. 加载配置
source /home/quan/output/trae/sessions/config.txt

# 2. 写入子任务提示词
# 子任务 1：接口实现
cat << 'EOF' > "$SESSION_DIR/prompts/subtask_1_impl.txt"
请基于 RESTful 规范实现用户注册接口...
EOF

# 子任务 2：单元测试
cat << 'EOF' > "$SESSION_DIR/prompts/subtask_2_test.txt"
请为用户注册接口编写 Jest 单元测试用例...
EOF

# 3. 分配 CodeBuddy 做实现
codebuddy -p "$(cat $SESSION_DIR/prompts/subtask_1_impl.txt)" \
  -y \
  --output-format json \
  > "$SESSION_DIR/outputs/subtask1_${TIMESTAMP}_codebuddy.json"

# 4. 分配 Qwen 做测试
qwen -p "$(cat $SESSION_DIR/prompts/subtask_2_test.txt)" \
  --approval-mode yolo \
  --output-format stream-json \  
  > "$SESSION_DIR/outputs/subtask2_${TIMESTAMP}_qwen.json"

echo "🚀 任务分配模式执行完毕"
```

---

## 📝 命名与格式规范汇总

### 1. 文件引用规范
禁止在命令行直接写长文本，必须使用文件引用：
- ❌ 错误：`codebuddy -p "很长的任务描述..."`
- ✅ 正确：`codebuddy -p "$(cat $SESSION_DIR/prompts/task.txt)"`

### 2. 输出文件命名
由 `$SESSION_DIR/outputs/` 统一接管，命名格式：
`{任务名}_{时间戳}_{Agent名}.json`
> 时间戳建议直接引用 Config 中的 `$TIMESTAMP` 变量，确保文件组的一致性。


