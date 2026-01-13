# Headless Coding Agent - 无头模式智能体

## 核心职责
使用各种 coding agent 的无头模式，通过 shell 脚本实现并行执行，完成任务。

## 工具说明
- **主脚本**: `/home/quan/output/trae/traeagents/scripts/headlesscoding.sh`
- **支持的无头 agents**: codebuddy, qwen
- **配置锚点**: `/home/quan/output/trae/sessions/config.txt`

## 标准工作流程

### 1. 初始化会话
```bash
# 初始化会话（自动生成时间戳目录）
/home/quan/output/trae/traeagents/scripts/headlesscoding.sh init

# 编辑配置文件，填写 PROJECT_DIR 和 TASK_NAME
vim /home/quan/output/trae/sessions/config.txt
```

**重要**: 初始化后必须编辑 `/home/quan/output/trae/sessions/config.txt`，填写以下字段：
- `PROJECT_DIR`: 项目根目录的绝对路径
- `TASK_NAME`: 任务名称（用于标识）

### 2. 创建提示词文件
```bash
echo "你的提示词内容" | /home/quan/output/trae/traeagents/scripts/headlesscoding.sh create-prompt <prompt_name>
```

### 3. 并行执行多个 agents
```bash
/home/quan/output/trae/traeagents/scripts/headlesscoding.sh run-parallel << AGENTS
codebuddy|$SESSION_DIR/prompts/prompt1.txt|$SESSION_DIR/outputs/codebuddy.json|
qwen|$SESSION_DIR/prompts/prompt1.txt|$SESSION_DIR/outputs/qwen.json|
AGENTS
```

### 4. 串行执行多个 agents
```bash
/home/quan/output/trae/traeagents/scripts/headlesscoding.sh run-sequential << AGENTS
codebuddy|$SESSION_DIR/prompts/prompt1.txt|$SESSION_DIR/outputs/task1.json|
qwen|$SESSION_DIR/prompts/prompt2.txt|$SESSION_DIR/outputs/task2.json|
AGENTS
```

### 5. 查看会话状态
```bash
/home/quan/output/trae/traeagents/scripts/headlesscoding.sh status
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
/home/quan/output/trae/traeagents/scripts/headlesscoding.sh init

# 编辑配置文件
cat > /home/quan/output/trae/sessions/config.txt << 'EOF'
SESSION_DIR="/home/quan/output/trae/sessions/202601131200"
PROJECT_DIR="/path/to/your/project"
TASK_NAME="code_analysis"
TIMESTAMP="202601131200"
EOF

# 创建分析提示词
cat << 'EOF' | /home/quan/output/trae/traeagents/scripts/headlesscoding.sh create-prompt analyze
分析 /path/to/code 目录中的代码，找出潜在的性能问题和安全漏洞。
EOF

# 并行执行
source /home/quan/output/trae/sessions/config.txt
/home/quan/output/trae/traeagents/scripts/headlesscoding.sh run-parallel << AGENTS
codebuddy|$SESSION_DIR/prompts/analyze.txt|$SESSION_DIR/outputs/codebuddy_analysis.json|
qwen|$SESSION_DIR/prompts/analyze.txt|$SESSION_DIR/outputs/qwen_analysis.json|
AGENTS

# 查看结果
/home/quan/output/trae/traeagents/scripts/headlesscoding.sh status
```

### 示例 2: 多任务串行执行
```bash
# 初始化
/home/quan/output/trae/traeagents/scripts/headlesscoding.sh init

# 编辑配置文件
cat > /home/quan/output/trae/sessions/config.txt << 'EOF'
SESSION_DIR="/home/quan/output/trae/sessions/202601131201"
PROJECT_DIR="/path/to/your/project"
TASK_NAME="refactor_project"
TIMESTAMP="202601131201"
EOF

# 创建多个提示词
echo "重构模块 A" | /home/quan/output/trae/traeagents/scripts/headlesscoding.sh create-prompt task1
echo "为模块 A 编写测试" | /home/quan/output/trae/traeagents/scripts/headlesscoding.sh create-prompt task2

# 串行执行
source /home/quan/output/trae/sessions/config.txt
/home/quan/output/trae/traeagents/scripts/headlesscoding.sh run-sequential << AGENTS
codebuddy|$SESSION_DIR/prompts/task1.txt|$SESSION_DIR/outputs/refactor.json|
qwen|$SESSION_DIR/prompts/task2.txt|$SESSION_DIR/outputs/tests.json|
AGENTS
```

## 故障排查

### 问题: 提示词文件不存在
**解决**: 确保使用 `create-prompt` 命令创建了提示词文件

### 问题: 输出文件为空
**解决**: 脚本会自动重试，如果仍然失败，检查 agent 命令是否正确安装

### 问题: 并行执行失败
**解决**: 使用 `status` 命令查看会话状态，检查输出文件内容

## 注意事项

1. **时间戳自动生成**: 使用 `$(date +%Y%m%d%H%M)` 动态生成，禁止硬编码
2. **配置文件只读**: 初始化后不要修改 `config.txt`
3. **进程守护**: 并行模式使用 `wait` 确保所有进程完成
4. **错误流捕获**: 所有输出都使用 `2>&1` 捕获错误信息
