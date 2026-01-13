# Headless Coding Agent - 无头模式智能体

## 核心职责
使用各种 coding agent 的无头模式，通过 shell 脚本实现并行执行，完成任务。

## 工具说明
- **主脚本**: `/home/quan/output/trae/traeagents/scripts/headlesstasks.sh`
- **Agent 配置文件**: `/home/quan/output/trae/traeagents/config/agents.conf`
- **会话配置锚点**: `/home/quan/output/trae/sessions/config.txt`

## Agent 配置

### 配置文件位置
`/home/quan/output/trae/traeagents/config/agents.conf`

### 配置格式
```bash
AGENT_<编号>_NAME=<agent名称>
AGENT_<编号>_COMMAND=<命令>
AGENT_<编号>_ARGS=<参数>
```

### 配置示例
```bash
# Agent 1: Qwen
AGENT_1_NAME=qwen
AGENT_1_COMMAND=qwen
AGENT_1_ARGS=--approval-mode yolo --output-format stream-json

# Agent 2: CodeBuddy
AGENT_2_NAME=codebuddy
AGENT_2_COMMAND=codebuddy
AGENT_2_ARGS=-y --max-turns 200

# Agent 3: 自定义 Agent
AGENT_3_NAME=custom_agent
AGENT_3_COMMAND=/path/to/custom/agent
AGENT_3_ARGS=--custom-arg1 value1 --custom-arg2 value2
```

### 添加新 Agent
1. 编辑 `/home/quan/output/trae/traeagents/config/agents.conf`
2. 添加新的 `AGENT_<编号>_NAME`, `AGENT_<编号>_COMMAND`, `AGENT_<编号>_ARGS`
3. 使用 `list-agents` 命令验证配置

### 列出已配置的 Agents
```bash
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh list-agents
```

## 标准工作流程

### 1. 初始化会话
```bash
# 初始化会话（自动生成时间戳目录）
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh init

# 编辑配置文件，填写 PROJECT_DIR 和 TASK_NAME
vim /home/quan/output/trae/sessions/config.txt
```

**重要**: 初始化后必须编辑 `/home/quan/output/trae/sessions/config.txt`，填写以下字段：
- `PROJECT_DIR`: 项目根目录的绝对路径
- `TASK_NAME`: 任务名称（用于标识）

### 2. 列出已配置的 Agents
```bash
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh list-agents
```

### 3. 创建提示词文件

**方式1: 管道方式（简单提示词）**
```bash
echo "你的提示词内容" | /home/quan/output/trae/traeagents/scripts/headlesstasks.sh create-prompt <prompt_name>
```

**方式2: heredoc 方式（复杂/多行提示词，推荐）**
```bash
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh prompt <prompt_name> << 'EOF'
你的提示词内容
可以是多行文本
包含特殊字符也没有问题
EOF
```

**为什么推荐使用 heredoc 方式：**
- ✅ 避免管道命令被意外中断导致 `>` 提示符卡住
- ✅ 支持多行文本，格式清晰
- ✅ 不需要转义特殊字符（如 `$`, `"`, `'`, `` ` `` 等）
- ✅ 更适合包含中文、代码示例等复杂内容的提示词

### 4. 并行执行多个 agents
```bash
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh run-parallel << AGENTS
qwen|$SESSION_DIR/prompts/prompt1.txt|$SESSION_DIR/outputs/qwen.json|
codebuddy|$SESSION_DIR/prompts/prompt1.txt|$SESSION_DIR/outputs/codebuddy.json|
AGENTS
```

### 5. 串行执行多个 agents
```bash
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh run-sequential << AGENTS
qwen|$SESSION_DIR/prompts/prompt1.txt|$SESSION_DIR/outputs/task1.json|
codebuddy|$SESSION_DIR/prompts/prompt2.txt|$SESSION_DIR/outputs/task2.json|
AGENTS
```

### 6. 查看会话状态
```bash
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh status
```

## 执行模式说明

### 并行模式 (run-parallel)
- **用途**: 多个 agent 同时处理同一任务或不同任务
- **特点**: 
  - 使用后台进程并行执行
  - 自动等待所有进程完成
  - 自动校验输出文件，失败自动重试
  - 捕获错误流 (2>&1)

### 串行模式 (run-sequential)
- **用途**: 按顺序执行多个任务
- **特点**:
  - 依次执行每个 agent
  - 前一个完成后才执行下一个
  - 适用于有依赖关系的任务

## Agents 格式规范

每行一个 agent，使用 `|` 分隔字段：
```
agent_name|prompt_file|output_file|extra_args
```

字段说明：
- `agent_name`: agent 名称 (codebuddy 或 qwen)
- `prompt_file`: 提示词文件路径 (相对于会话目录或绝对路径)
- `output_file`: 输出文件路径 (可选，默认为 `$SESSION_DIR/outputs/${TASK_NAME}_${TIMESTAMP}_${agent}.json`)
- `extra_args`: 额外参数 (可选)

## 关键约束

1. **必须先初始化会话**: 执行任何任务前必须先运行 `init` 命令
2. **必须填写配置文件**: 初始化后必须编辑 config.txt 填写 PROJECT_DIR 和 TASK_NAME
3. **提示词文件必须存在**: 执行前确保提示词文件已创建
4. **输出目录自动创建**: 脚本会自动创建 `$SESSION_DIR/outputs/` 目录
5. **错误捕获**: 所有命令都使用 `2>&1` 捕获错误流
6. **幂等性**: 可以安全地重复执行相同命令

## 使用示例

### 示例 1: 代码分析并行执行
```bash
# 初始化
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh init

# 编辑配置文件
cat > /home/quan/output/trae/sessions/config.txt << 'EOF'
SESSION_DIR="/home/quan/output/trae/sessions/202601131200"
PROJECT_DIR="/path/to/your/project"
TASK_NAME="code_analysis"
TIMESTAMP="202601131200"
EOF

# 列出已配置的 agents
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh list-agents

# 创建分析提示词 (推荐使用 heredoc 方式)
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh prompt analyze << 'EOF'
分析 /path/to/code 目录中的代码，找出潜在的性能问题和安全漏洞。
EOF

# 并行执行
source /home/quan/output/trae/sessions/config.txt
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh run-parallel << AGENTS
qwen|$SESSION_DIR/prompts/analyze.txt|$SESSION_DIR/outputs/qwen_analysis.json|
codebuddy|$SESSION_DIR/prompts/analyze.txt|$SESSION_DIR/outputs/codebuddy_analysis.json|
AGENTS

# 查看结果
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh status
```

### 示例 2: 多任务串行执行
```bash
# 初始化
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh init

# 编辑配置文件
cat > /home/quan/output/trae/sessions/config.txt << 'EOF'
SESSION_DIR="/home/quan/output/trae/sessions/202601131201"
PROJECT_DIR="/path/to/your/project"
TASK_NAME="refactor_project"
TIMESTAMP="202601131201"
EOF

# 创建多个提示词
echo "重构模块 A" | /home/quan/output/trae/traeagents/scripts/headlesstasks.sh create-prompt task1
echo "为模块 A 编写测试" | /home/quan/output/trae/traeagents/scripts/headlesstasks.sh create-prompt task2

# 串行执行
source /home/quan/output/trae/sessions/config.txt
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh run-sequential << AGENTS
qwen|$SESSION_DIR/prompts/task1.txt|$SESSION_DIR/outputs/refactor.json|
codebuddy|$SESSION_DIR/prompts/task2.txt|$SESSION_DIR/outputs/tests.json|
AGENTS
```

## 添加新 Agent

### 步骤 1: 编辑 Agent 配置文件
```bash
vim /home/quan/output/trae/traeagents/config/agents.conf
```

### 步骤 2: 添加新 Agent 配置
在配置文件末尾添加新的 agent 配置：

```bash
# Agent 3: 自定义 Agent
AGENT_3_NAME=your_agent_name
AGENT_3_COMMAND=/path/to/your/agent/command
AGENT_3_ARGS=--your-arg1 value1 --your-arg2 value2
```

**配置说明**:
- `AGENT_<编号>_NAME`: agent 的唯一标识符，用于在执行时指定
- `AGENT_<编号>_COMMAND`: agent 的可执行命令或脚本路径
- `AGENT_<编号>_ARGS`: agent 的默认参数，这些参数会在每次执行时自动添加

### 步骤 3: 验证配置
```bash
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh list-agents
```

你应该能看到新添加的 agent 在列表中。

### 步骤 4: 使用新 Agent
现在你可以在 `run-parallel` 或 `run-sequential` 命令中使用新添加的 agent：

```bash
# 并行执行
/home/quan/output/trae/traeagents/scripts/headlesstasks.sh run-parallel << AGENTS
qwen|$SESSION_DIR/prompts/task1.txt|$SESSION_DIR/outputs/qwen.json|
codebuddy|$SESSION_DIR/prompts/task1.txt|$SESSION_DIR/outputs/codebuddy.json|
your_agent_name|$SESSION_DIR/prompts/task1.txt|$SESSION_DIR/outputs/your_agent.json|
AGENTS
```

### 注意事项
1. **编号连续性**: 建议使用连续的编号（如 AGENT_1, AGENT_2, AGENT_3）
2. **名称唯一性**: 确保每个 agent 的 NAME 是唯一的
3. **命令可执行性**: 确保 COMMAND 指定的命令或脚本具有执行权限
4. **参数有效性**: 确保 ARGS 中的参数格式正确，符合 agent 的要求
5. **无需重启**: 配置文件修改后立即生效，无需重启任何服务

## 故障排查

### 问题: 提示词文件不存在
**解决**: 确保使用 `create-prompt` 命令创建了提示词文件

### 问题: 输出文件为空
**解决**: 脚本会自动重试，如果仍然失败，检查 agent 命令是否正确安装

### 问题: 并行执行失败
**解决**: 使用 `status` 命令查看会话状态，检查输出文件内容

### 问题: 未找到 agent 配置
**解决**: 
1. 检查 agent 名称是否拼写正确
2. 使用 `list-agents` 命令查看已配置的 agents
3. 确认 `/home/quan/output/trae/traeagents/config/agents.conf` 文件存在且格式正确

### 问题: Agent 命令执行失败
**解决**:
1. 检查 agent 命令是否已安装并在 PATH 中
2. 检查 agent 命令是否有执行权限
3. 手动运行 agent 命令测试是否正常工作
4. 检查 agent 参数是否正确

### 问题: 配置文件格式错误
**解决**:
1. 确保每行配置格式为 `AGENT_<编号>_<属性>=<值>`
2. 确保编号、属性名称使用大写
3. 确保没有多余的空格或特殊字符
4. 使用 `list-agents` 命令验证配置

## 注意事项

1. **时间戳自动生成**: 使用 `$(date +%Y%m%d%H%M)` 动态生成，禁止硬编码
2. **配置文件只读**: 初始化后不要修改 `config.txt`
3. **进程守护**: 并行模式使用 `wait` 确保所有进程完成
4. **错误流捕获**: 所有输出都使用 `2>&1` 捕获错误信息
