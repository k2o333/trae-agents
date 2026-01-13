# Trae智能体 - Coding Agent执行规范

## 📌 核心原则
**每完成编码相关任务，必须调用coding agent的无头模式进行验证或优化。**

## 🤖 支持的Coding Agent
- `codebuddy`
- `qwen`

## ⚙️ 无头模式执行命令

### codebuddy 无头模式
```bash
codebuddy -p "your prompt" \
  --output-format json \
  -y \
  > {任务名称}_{时间戳}_codebuddy.json
```

### qwen 无头模式  
```bash
qwen -p "your prompt" \
  --output-format stream-json \
  --approval-mode yolo \
  > {任务名称}_{时间戳}_qwen.json
```

### 📝 文件命名规则
输出文件必须命名为：`{任务名称}_{时间戳}_{codingagent名称}.json`
- **任务名称**：小写，用下划线分隔
- **时间戳**：YYYYMMDDHHMM格式（如：202601121530）
- **codingagent名称**：codebuddy 或 qwen

**示例**：`user_authentication_202601121530_codebuddy.json`

## 🔄 执行模式

### 1️⃣ 讨论汇总模式
**执行方式**：将完整任务同时提交给两个coding agent，分别执行后汇总结果。
```bash
# 同时执行两个agent
codebuddy -p "完整任务描述" --output-format json -y > taskname_timestamp_codebuddy.json
qwen -p "完整任务描述" --output-format stream-json --approval-mode yolo > taskname_timestamp_qwen.json
```

### 2️⃣ 任务分配模式  
**执行方式**：将任务拆分为子任务，每个子任务分配给一个coding agent独立执行。如果子任务数量超过coding agent数量 则轮流负载均衡。
```bash
# 子任务1分配给codebuddy
codebuddy -p "子任务1描述" --output-format json -y > subtask1_timestamp_codebuddy.json

# 子任务2分配给qwen
qwen -p "子任务2描述" --output-format stream-json --approval-mode yolo > subtask2_timestamp_qwen.json
```

## ⚠️ 注意事项
- `your prompt` 参数可替换为任何具体的任务描述
- 两种模式的选择将在用户提示词中明确指定


## 🎯 执行示例
```bash
# 讨论汇总模式示例
codebuddy -p "生成用户注册功能的代码" --output-format json -y > user_registration_202601121530_codebuddy.json
qwen -p "生成用户注册功能的代码" --output-format stream-json --approval-mode yolo > user_registration_202601121530_qwen.json

# 任务分配模式示例
codebuddy -p "验证用户输入的邮箱格式" --output-format json -y > email_validation_202601121531_codebuddy.json
qwen -p "实现密码强度检查逻辑" --output-format stream-json --approval-mode yolo > password_check_202601121531_qwen.json
```