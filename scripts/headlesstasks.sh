#!/bin/bash

# Headless Coding Agent - 并行执行脚本
# 支持多个 coding agents 的并行无头模式执行

set -e

# 全局配置 - 使用环境变量或默认值
TRAE_ROOT="${TRAE_ROOT:-/home/quan/output/trae}"
CONFIG_PATH="${CONFIG_PATH:-$TRAE_ROOT/sessions/config.txt}"
AGENTS_CONFIG_PATH="${AGENTS_CONFIG_PATH:-$TRAE_ROOT/traeagents/config/agents.conf}"
SESSION_DIR=""
PROJECT_DIR=""
TASK_NAME=""
TIMESTAMP=""
declare -A AGENTS_CONFIG

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 加载 agent 配置文件
load_agents_config() {
    if [ ! -f "$AGENTS_CONFIG_PATH" ]; then
        log_error "Agent 配置文件不存在: $AGENTS_CONFIG_PATH"
        exit 1
    fi

    local agent_count=0
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        
        if [[ "$key" =~ ^AGENT_([0-9]+)_(NAME|COMMAND|ARGS|PROMPT_ARGS)$ ]]; then
            local agent_num="${BASH_REMATCH[1]}"
            local prop="${BASH_REMATCH[2]}"
            AGENTS_CONFIG["${agent_num}_${prop}"]="$value"
            agent_count=$((agent_count + 1))
        fi
    done < "$AGENTS_CONFIG_PATH"

    log_info "已加载 $((agent_count / 4)) 个 agent 配置"
}

# 获取最大 agent 编号
get_max_agent_num() {
    local max_num=0
    for key in "${!AGENTS_CONFIG[@]}"; do
        if [[ "$key" =~ ^([0-9]+)_NAME$ ]]; then
            local num="${BASH_REMATCH[1]}"
            [ "$num" -gt "$max_num" ] && max_num="$num"
        fi
    done
    echo "$max_num"
}

# 获取 agent 配置
get_agent_config() {
    local agent_name="$1" prop="$2"
    local max_num=$(get_max_agent_num)
    
    for agent_num in $(seq 1 "$max_num"); do
        if [ "${AGENTS_CONFIG[${agent_num}_NAME]}" == "$agent_name" ]; then
            local config_key="${agent_num}_${prop}"
            if [ -v "AGENTS_CONFIG[$config_key]" ]; then
                echo "${AGENTS_CONFIG[$config_key]}"
                return 0
            else
                return 1
            fi
        fi
    done
    return 1
}

# 构建 agent 参数
build_agent_args() {
    local agent_name="$1" extra_args="$2"
    
    local agent_args
    if get_agent_config "$agent_name" "ARGS" >/dev/null 2>&1; then
        agent_args=$(get_agent_config "$agent_name" "ARGS")
    else
        agent_args=""
    fi
    
    if [ -n "$agent_args" ] && [ -n "$extra_args" ]; then
        echo "$agent_args $extra_args"
    else
        echo "${agent_args}${extra_args}"
    fi
}

# 执行 agent 命令
execute_agent_command() {
    local agent_name="$1" prompt_file="$2" output_file="$3" extra_args="$4"
    
    local agent_command=$(get_agent_config "$agent_name" "COMMAND")
    [ -z "$agent_command" ] && { log_error "未找到 agent 配置: $agent_name"; return 1; }
    
    local agent_prompt_args="-p"
    if get_agent_config "$agent_name" "PROMPT_ARGS" >/dev/null 2>&1; then
        agent_prompt_args=$(get_agent_config "$agent_name" "PROMPT_ARGS")
    fi
    
    local full_args=$(build_agent_args "$agent_name" "$extra_args")
    
    if [ -n "$agent_prompt_args" ]; then
        $agent_command $agent_prompt_args "$(cat "$prompt_file")" $full_args > "$output_file" 2>&1
    else
        $agent_command "$(cat "$prompt_file")" $full_args > "$output_file" 2>&1
    fi
}

# 列出所有已配置的 agents
list_agents() {
    local max_num=$(get_max_agent_num)
    
    for agent_num in $(seq 1 "$max_num"); do
        local name="${AGENTS_CONFIG[${agent_num}_NAME]}"
        [ -z "$name" ] && continue
        
        echo "  Agent $agent_num: $name"
        echo "    Command: ${AGENTS_CONFIG[${agent_num}_COMMAND]}"
        echo "    Args: ${AGENTS_CONFIG[${agent_num}_ARGS]}"
        
        local prompt_args="${AGENTS_CONFIG[${agent_num}_PROMPT_ARGS]}"
        if [ -n "${prompt_args+x}" ]; then
            echo "    Prompt Args: $prompt_args"
        else
            echo "    Prompt Args: -p (default)"
        fi
    done
}

# 验证配置文件
validate_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_error "配置文件不存在: $config_file"
        return 1
    fi
    
    source "$config_file"
    
    if [ -z "$PROJECT_DIR" ]; then
        log_error "PROJECT_DIR 未配置"
        return 1
    fi
    
    if [ -z "$TASK_NAME" ]; then
        log_error "TASK_NAME 未配置"
        return 1
    fi
    
    if [ ! -d "$PROJECT_DIR" ]; then
        log_warning "PROJECT_DIR 不存在: $PROJECT_DIR"
    fi
    
    return 0
}

# 验证提示词文件
validate_prompt_file() {
    local prompt_file="$1"
    
    if [ ! -f "$prompt_file" ]; then
        log_error "提示词文件不存在: $prompt_file"
        return 1
    fi
    
    if [ ! -s "$prompt_file" ]; then
        log_error "提示词文件为空: $prompt_file"
        return 1
    fi
    
    return 0
}

# 安全初始化函数
safe_init() {
    log_info "创建新会话..."
    TIMESTAMP=$(date +%Y%m%d%H%M)
    NEW_SESSION="$TRAE_ROOT/sessions/${TIMESTAMP}"
    
    mkdir -p "$NEW_SESSION/prompts" "$NEW_SESSION/outputs"
    
    cat > "$CONFIG_PATH" << EOF
SESSION_DIR="$NEW_SESSION"
PROJECT_DIR=""
TASK_NAME=""
TIMESTAMP="$TIMESTAMP"
EOF
    source "$CONFIG_PATH"
    log_success "会话初始化完成: $NEW_SESSION"
    log_warning "请手动编辑 $CONFIG_PATH，填写 PROJECT_DIR 和 TASK_NAME"
}

# 创建提示词文件（从 stdin 读取）
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

# 创建提示词文件（heredoc 方式，推荐）
create_prompt_heredoc() {
    local prompt_name="$1"
    
    if [ -z "$prompt_name" ]; then
        log_error "请指定提示词名称"
        exit 1
    fi
    
    cat > "$SESSION_DIR/prompts/${prompt_name}.txt"
    log_success "提示词已创建: $SESSION_DIR/prompts/${prompt_name}.txt"
}

# 执行单个 agent
run_agent() {
    local agent_name="$1" prompt_file="$2" output_file="$3" extra_args="$4"
    
    log_info "启动 $agent_name..."
    validate_prompt_file "$prompt_file" || return 1
    
    mkdir -p "$(dirname "$output_file")"
    execute_agent_command "$agent_name" "$prompt_file" "$output_file" "$extra_args"
    
    if [ -s "$output_file" ]; then
        log_success "$agent_name 执行完成: $output_file"
        return 0
    else
        log_warning "$agent_name 输出为空"
        return 1
    fi
}

# 重启失败的 agent
restart_agent() {
    local i="$1"
    local agent=${agents[$i]} prompt=${prompts[$i]} output=${outputs[$i]}
    local retry_count=${retries[$i]:-0} max_retries=3
    
    if [ $retry_count -ge $max_retries ]; then
        log_warning "$agent 已达最大重试次数"
        return 1
    fi
    
    log_warning "$agent 输出为空或异常，准备重启 (重试 $((retry_count + 1))/$max_retries)..."
    
    local args=${agent_extra_args[$i]:-""}
    execute_agent_command "$agent" "$prompt" "$output" "$args" &
    local new_pid=$!
    
    pids[$i]=$new_pid
    retries[$i]=$((retry_count + 1))
    log_info "$agent 已重启 (PID: $new_pid)"
    return 0
}

# 监控 agent 健康状态并自动重启
check_agents_health() {
    local check_interval=10
    
    while true; do
        local all_done=true
        
        for i in "${!pids[@]}"; do
            local pid=${pids[$i]}
            [ -z "$pid" ] || [ "$pid" == "-1" ] && continue
            
            if kill -0 "$pid" 2>/dev/null; then
                all_done=false
            else
                local output=${outputs[$i]}
                if [ ! -s "$output" ]; then
                    restart_agent "$i" && all_done=false
                fi
            fi
        done
        
        [ "$all_done" = true ] && break
        sleep $check_interval
    done
}

# 并行执行多个 agents
run_parallel() {
    local agents_json="$1"
    local start_delay=3  # 启动间隔（秒）
    
    log_info "启动并行执行..."
    
    declare -a pids outputs agents prompts retries agent_extra_args
    
    while IFS='|' read -r agent prompt output args; do
        [ -z "$agent" ] && continue
        
        local full_output="${output:-$SESSION_DIR/outputs/${TASK_NAME}_${TIMESTAMP}_${agent}.json}"
        local full_prompt="${prompt:-$SESSION_DIR/prompts/default.txt}"
        
        if ! get_agent_config "$agent" "COMMAND" >/dev/null; then
            log_error "未找到 agent 配置: $agent"
            continue
        fi
        
        log_info "准备启动 $agent (prompt: $full_prompt, output: $full_output)"
        
        execute_agent_command "$agent" "$full_prompt" "$full_output" "$args" &
        pids+=($!)
        outputs+=("$full_output")
        agents+=("$agent")
        prompts+=("$full_prompt")
        retries+=(0)
        agent_extra_args+=("$args")
        
        log_info "$agent 已启动 (PID: ${pids[-1]})"
        sleep $start_delay
    done <<< "$agents_json"
    
    log_info "启动监控进程，每10秒检查一次..."
    check_agents_health &
    local monitor_pid=$!
    
    log_info "等待所有进程完成..."
    for i in "${!pids[@]}"; do
        wait ${pids[$i]} 2>/dev/null || log_warning "进程 ${agents[$i]} 退出"
    done
    
    kill $monitor_pid 2>/dev/null
    
    log_info "校验输出文件..."
    for i in "${!outputs[@]}"; do
        if [ ! -s "${outputs[$i]}" ]; then
            log_warning "${agents[$i]} 输出为空"
        else
            log_success "${agents[$i]} 执行完成"
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
        
        if ! get_agent_config "$agent" "COMMAND" >/dev/null; then
            log_error "未找到 agent 配置: $agent"
            continue
        fi
        
        if ! validate_prompt_file "$full_prompt"; then
            log_error "跳过 $agent：提示词文件无效"
            continue
        fi
        
        log_info "准备启动 $agent (prompt: $full_prompt, output: $full_output)"
        
        execute_agent_command "$agent" "$full_prompt" "$full_output" "$args" &
        pids+=($!)
        outputs+=("$full_output")
        agents+=("$agent")
        prompts+=("$full_prompt")
        retries+=(0)
        agent_extra_args+=("$args")
        
        log_info "$agent 已启动 (PID: ${pids[-1]})"
        sleep $start_delay
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
    create-prompt <name>       创建提示词文件 (从 stdin 读取内容，管道方式)
    prompt <name>              创建提示词文件 (heredoc 方式，推荐)
    run-parallel <agents>      并行执行多个 agents
    run-sequential <agents>    串行执行多个 agents
    run-agent <agent> <prompt> <output> [args]  执行单个 agent
    list-agents                列出所有已配置的 agents
    status                     显示当前会话状态
    help                       显示此帮助信息

agents 格式 (每行一个 agent):
    agent_name|prompt_file|output_file|extra_args

Agent 配置文件:
    配置文件位置: $AGENTS_CONFIG_PATH
    
    配置格式:
        AGENT_<编号>_NAME=<agent名称>
        AGENT_<编号>_COMMAND=<命令>
        AGENT_<编号>_ARGS=<参数>
        AGENT_<编号>_PROMPT_ARGS=<提示词参数> (可选)
    
    PROMPT_ARGS 配置说明:
        - 不配置此项: 使用默认值 -p
        - 配置为空值: 不使用任何提示词参数 (如: AGENT_X_PROMPT_ARGS=)
        - 配置具体值: 使用指定的参数 (如: AGENT_X_PROMPT_ARGS=--prompt)
    
    示例:
        # 使用默认 -p 参数
        AGENT_1_NAME=qwen
        AGENT_1_COMMAND=qwen
        AGENT_1_ARGS=--approval-mode yolo --output-format stream-json
        # AGENT_1_PROMPT_ARGS 未配置，将使用 -p
        
        # 使用自定义参数
        AGENT_2_NAME=codebuddy
        AGENT_2_COMMAND=codebuddy
        AGENT_2_ARGS=-y --max-turns 200
        AGENT_2_PROMPT_ARGS=--prompt
        
        # 不使用任何提示词参数
        AGENT_3_NAME=claude-code
        AGENT_3_COMMAND=ccr
        AGENT_3_ARGS=-y
        AGENT_3_PROMPT_ARGS=
    
    添加新 agent:
        1. 编辑 $AGENTS_CONFIG_PATH
        2. 添加新的 AGENT_<编号>_NAME, AGENT_<编号>_COMMAND, AGENT_<编号>_ARGS, AGENT_<编号>_PROMPT_ARGS
        3. 使用 list-agents 命令验证配置
    
示例:
    # 初始化
    $0 init
    
    # 编辑 config.txt 填写 PROJECT_DIR 和 TASK_NAME
    # vim /home/quan/output/trae/sessions/config.txt
    
    # 列出已配置的 agents
    $0 list-agents
    
    # 创建提示词 (方式1: 管道方式)
    echo "分析代码" | $0 create-prompt analysis
    
    # 创建提示词 (方式2: heredoc 方式，推荐)
    $0 prompt vector_bt_analysis << 'PROMPT'
    请深入分析并讨论 vector bt 回测框架为什么速度快，从技术架构、核心算法、性能优化策略等角度进行详细阐述。
    要求内容全面、专业，包含代码示例和技术细节。
    PROMPT
    
    # 并行执行
    $0 run-parallel << AGENTS
qwen|$SESSION_DIR/prompts/analysis.txt|$SESSION_DIR/outputs/qwen.json|
codebuddy|$SESSION_DIR/prompts/analysis.txt|$SESSION_DIR/outputs/codebuddy.json|
AGENTS

    # 串行执行
    $0 run-sequential << AGENTS
qwen|$SESSION_DIR/prompts/task1.txt|$SESSION_DIR/outputs/task1.json|
codebuddy|$SESSION_DIR/prompts/task2.txt|$SESSION_DIR/outputs/task2.json|
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
            [ -z "$2" ] && { log_error "请指定提示词名称"; exit 1; }
            source "$CONFIG_PATH" 2>/dev/null || { log_error "请先初始化会话"; exit 1; }
            validate_config "$CONFIG_PATH" || exit 1
            create_prompt "$2" "$(cat)"
            ;;
        prompt)
            [ -z "$2" ] && { log_error "请指定提示词名称"; exit 1; }
            source "$CONFIG_PATH" 2>/dev/null || { log_error "请先初始化会话"; exit 1; }
            validate_config "$CONFIG_PATH" || exit 1
            create_prompt_heredoc "$2"
            ;;
        run-parallel)
            source "$CONFIG_PATH" 2>/dev/null || { log_error "请先初始化会话"; exit 1; }
            validate_config "$CONFIG_PATH" || exit 1
            load_agents_config
            run_parallel "$(cat)"
            ;;
        run-sequential)
            source "$CONFIG_PATH" 2>/dev/null || { log_error "请先初始化会话"; exit 1; }
            validate_config "$CONFIG_PATH" || exit 1
            load_agents_config
            run_sequential "$(cat)"
            ;;
        run-agent)
            [ -z "$2" ] && { log_error "请指定 agent 名称"; exit 1; }
            [ -z "$3" ] && { log_error "请指定提示词文件"; exit 1; }
            source "$CONFIG_PATH" 2>/dev/null || { log_error "请先初始化会话"; exit 1; }
            validate_config "$CONFIG_PATH" || exit 1
            validate_prompt_file "$3" || exit 1
            load_agents_config
            run_agent "$2" "$3" "$4" "$5"
            ;;
        list-agents)
            load_agents_config
            echo "已配置的 Agents:"
            list_agents
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
