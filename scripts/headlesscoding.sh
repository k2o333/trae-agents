#!/bin/bash

# Headless Coding Agent - 并行执行脚本
# 支持多个 coding agents 的并行无头模式执行

set -e

# 全局配置
CONFIG_PATH="/home/quan/output/trae/sessions/config.txt"
SESSION_DIR=""
PROJECT_DIR=""
TASK_NAME=""
TIMESTAMP=""

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 安全初始化函数
safe_init() {
    log_info "创建新会话..."
    TIMESTAMP=$(date +%Y%m%d%H%M)
    NEW_SESSION="/home/quan/output/trae/sessions/${TIMESTAMP}"
    
    mkdir -p "$NEW_SESSION/prompts"
    mkdir -p "$NEW_SESSION/outputs"
    
    cat << EOF > "$CONFIG_PATH"
SESSION_DIR="$NEW_SESSION"
PROJECT_DIR=""
TASK_NAME=""
TIMESTAMP="$TIMESTAMP"
EOF
    source "$CONFIG_PATH"
    log_success "会话初始化完成: $NEW_SESSION"
    log_warning "请手动编辑 $CONFIG_PATH，填写 PROJECT_DIR 和 TASK_NAME"
}

# 创建提示词文件
create_prompt() {
    local prompt_name="$1"
    local content="$2"
    
    if [ -z "$prompt_name" ] || [ -z "$content" ]; then
        log_error "提示词名称和内容不能为空"
        exit 1
    fi
    
    echo "$content" > "$SESSION_DIR/prompts/${prompt_name}.txt"
    log_success "提示词已创建: $SESSION_DIR/prompts/${prompt_name}.txt"
}

# 执行单个 agent
run_agent() {
    local agent_name="$1"
    local prompt_file="$2"
    local output_file="$3"
    local extra_args="$4"
    
    log_info "启动 $agent_name..."
    
    case "$agent_name" in
        codebuddy)
            codebuddy -p "$(cat "$prompt_file")" $extra_args -y --max-turns 200 > "$output_file" 2>&1
            ;;
        qwen)
            qwen -p "$(cat "$prompt_file")" $extra_args --approval-mode yolo --output-format stream-json > "$output_file" 2>&1
            ;;
        *)
            log_error "未知的 agent: $agent_name"
            return 1
            ;;
    esac
    
    if [ -s "$output_file" ]; then
        log_success "$agent_name 执行完成: $output_file"
        return 0
    else
        log_warning "$agent_name 输出为空"
        return 1
    fi
}

# 并行执行多个 agents
run_parallel() {
    local agents_json="$1"
    
    log_info "启动并行执行..."
    
    local pids=()
    local outputs=()
    local agents=()
    local prompts=()
    
    while IFS='|' read -r agent prompt output args; do
        [ -z "$agent" ] && continue
        
        local full_output="${output:-$SESSION_DIR/outputs/${TASK_NAME}_${TIMESTAMP}_${agent}.json}"
        local full_prompt="${prompt:-$SESSION_DIR/prompts/default.txt}"
        
        log_info "准备启动 $agent (prompt: $full_prompt, output: $full_output)"
        
        case "$agent" in
            codebuddy)
                codebuddy -p "$(cat "$full_prompt")" $args -y --max-turns 200 > "$full_output" 2>&1 &
                ;;
            qwen)
                qwen -p "$(cat "$full_prompt")" $args --approval-mode yolo --output-format stream-json > "$full_output" 2>&1 &
                ;;
            *)
                log_error "未知的 agent: $agent"
                continue
                ;;
        esac
        
        pids+=($!)
        outputs+=("$full_output")
        agents+=("$agent")
    done <<< "$agents_json"
    
    log_info "等待所有进程完成..."
    for i in "${!pids[@]}"; do
        wait ${pids[$i]} || log_warning "进程 ${agents[$i]} 退出异常"
    done
    
    log_info "校验输出文件..."
    for i in "${!outputs[@]}"; do
        if [ ! -s "${outputs[$i]}" ]; then
            log_warning "${agents[$i]} 输出为空，尝试串行重试..."
            local full_prompt="${prompts[$i]:-$SESSION_DIR/prompts/default.txt}"
            
            case "${agents[$i]}" in
                codebuddy)
                    codebuddy -p "$(cat "$full_prompt")" -y --max-turns 200 > "${outputs[$i]}" 2>&1
                    ;;
                qwen)
                    qwen -p "$(cat "$full_prompt")" --approval-mode yolo --output-format stream-json > "${outputs[$i]}" 2>&1
                    ;;
            esac
        fi
    done
    
    log_success "并行任务完成"
}

# 串行执行多个 agents
run_sequential() {
    local agents_json="$1"
    
    log_info "启动串行执行..."
    
    while IFS='|' read -r agent prompt output args; do
        [ -z "$agent" ] && continue
        
        local full_output="${output:-$SESSION_DIR/outputs/${TASK_NAME}_${TIMESTAMP}_${agent}.json}"
        local full_prompt="${prompt:-$SESSION_DIR/prompts/default.txt}"
        
        run_agent "$agent" "$full_prompt" "$full_output" "$args"
    done <<< "$agents_json"
    
    log_success "串行任务完成"
}

# 显示帮助信息
show_help() {
    cat << EOF
Headless Coding Agent - 并行执行脚本

用法:
    $0 <command> [options]

命令:
    init                       初始化会话（生成时间戳目录）
    create-prompt <name>       创建提示词文件 (从 stdin 读取内容)
    run-parallel <agents>      并行执行多个 agents
    run-sequential <agents>    串行执行多个 agents
    run-agent <agent> <prompt> <output> [args]  执行单个 agent
    status                     显示当前会话状态
    help                       显示此帮助信息

agents 格式 (每行一个 agent):
    agent_name|prompt_file|output_file|extra_args
    
示例:
    # 初始化
    $0 init
    
    # 编辑 config.txt 填写 PROJECT_DIR 和 TASK_NAME
    # vim /home/quan/output/trae/sessions/config.txt
    
    # 创建提示词
    echo "分析代码" | $0 create-prompt analysis
    
    # 并行执行
    $0 run-parallel << AGENTS
codebuddy|$SESSION_DIR/prompts/analysis.txt|$SESSION_DIR/outputs/codebuddy.json|
qwen|$SESSION_DIR/prompts/analysis.txt|$SESSION_DIR/outputs/qwen.json|
AGENTS

    # 串行执行
    $0 run-sequential << AGENTS
codebuddy|$SESSION_DIR/prompts/task1.txt|$SESSION_DIR/outputs/task1.json|
qwen|$SESSION_DIR/prompts/task2.txt|$SESSION_DIR/outputs/task2.json|
AGENTS

EOF
}

# 显示会话状态
show_status() {
    if [ -f "$CONFIG_PATH" ]; then
        source "$CONFIG_PATH"
        echo "会话信息:"
        echo "  任务名: $TASK_NAME"
        echo "  时间戳: $TIMESTAMP"
        echo "  会话目录: $SESSION_DIR"
        echo "  项目目录: $PROJECT_DIR"
        echo ""
        echo "提示词文件:"
        ls -1 "$SESSION_DIR/prompts/" 2>/dev/null || echo "  (无)"
        echo ""
        echo "输出文件:"
        ls -lh "$SESSION_DIR/outputs/" 2>/dev/null || echo "  (无)"
    else
        log_warning "未找到活动会话"
    fi
}

# 主函数
main() {
    case "$1" in
        init)
            safe_init
            ;;
        create-prompt)
            if [ -z "$2" ]; then
                log_error "请指定提示词名称"
                exit 1
            fi
            source "$CONFIG_PATH" 2>/dev/null || { log_error "请先初始化会话"; exit 1; }
            create_prompt "$2" "$(cat)"
            ;;
        run-parallel)
            source "$CONFIG_PATH" 2>/dev/null || { log_error "请先初始化会话"; exit 1; }
            run_parallel "$(cat)"
            ;;
        run-sequential)
            source "$CONFIG_PATH" 2>/dev/null || { log_error "请先初始化会话"; exit 1; }
            run_sequential "$(cat)"
            ;;
        run-agent)
            source "$CONFIG_PATH" 2>/dev/null || { log_error "请先初始化会话"; exit 1; }
            run_agent "$2" "$3" "$4" "$5"
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
