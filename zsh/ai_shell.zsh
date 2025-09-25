#!/usr/bin/env zsh

# ZSH AI Command Assistant Plugin - Clean Version
# Transforms natural language into shell commands using AI

# API Configuration (configure one of the options below)
AI_PROVIDER=${AI_PROVIDER:-"ollama"}  # openai, anthropic, ollama
API_KEY=${OPENAI_API_KEY:-""}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-""}
OLLAMA_URL=${OLLAMA_URL:-"http://localhost:11434"}
OLLAMA_MODEL=${OLLAMA_MODEL:-"deepseek-coder-v2:16b"}

# Animation configuration
AI_ANIMATION_STYLE=${AI_ANIMATION_STYLE:-"spinner"}
AI_ANIMATION_SPEED=${AI_ANIMATION_SPEED:-0.15}

# Define animation styles
declare -A ANIMATION_FRAMES
ANIMATION_FRAMES[spinner]="⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
ANIMATION_FRAMES[dots]="⠁ ⠂ ⠄ ⡀ ⢀ ⠠ ⠐ ⠈"
ANIMATION_FRAMES[pulse]="● ◐ ○ ◑"
ANIMATION_FRAMES[snake]="●○○○○ ○●○○○ ○○●○○ ○○○●○ ○○○○● ○○○●○ ○○●○○ ○●○○○"

# Function to call OpenAI API
_call_openai() {
    local prompt="$1"
    curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        -d "{
            \"model\": \"gpt-4o-mini\",
            \"messages\": [
                {
                    \"role\": \"system\",
                    \"content\": \"You are an assistant that converts natural language to shell commands. Respond ONLY with the command, no explanations, markdown or additional formatting. If you don't know the exact command, suggest the closest possible one.\"
                },
                {
                    \"role\": \"user\",
                    \"content\": \"$prompt\"
                }
            ],
            \"max_tokens\": 200,
            \"temperature\": 0.1
        }" | jq -r '.choices[0].message.content' 2>/dev/null
}

# Function to call Anthropic Claude API
_call_anthropic() {
    local prompt="$1"
    curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"claude-3-haiku-20240307\",
            \"max_tokens\": 200,
            \"messages\": [
                {
                    \"role\": \"user\",
                    \"content\": \"Convert this natural language description to a shell command. Respond ONLY with the command, no explanations: $prompt\"
                }
            ]
        }" | jq -r '.content[0].text' 2>/dev/null
}

# Function to call Ollama (local)
_call_ollama() {
    local prompt="$1"
    curl -s -X POST "$OLLAMA_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$OLLAMA_MODEL\",
            \"prompt\": \"Convert this description to a shell command. Respond ONLY with the command, no explanations: $prompt\",
            \"stream\": false,
            \"options\": {
                \"temperature\": 0.1
            }
        }" | jq -r '.response' 2>/dev/null
}

# Function to clean and validate received command
_clean_command() {
    local cmd="$1"
    # Remove markdown, backticks and unnecessary line breaks
    cmd=$(echo "$cmd" | sed 's/```[a-z]*//g' | sed 's/```//g' | tr -d '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    # Remove common prefixes
    cmd="${cmd#\$ }"
    cmd="${cmd#> }"
    echo "$cmd"
}

# ZLE widget to intercept Enter key and check for AI commands
ai_accept_line() {
    local buffer_content="$BUFFER"

    # Check if line starts with # followed by text
    if [[ "$buffer_content" =~ ^#[[:space:]]*(.+) ]]; then
        # Extract text after #
        local user_input="${buffer_content#\#}"
        user_input="${user_input#"${user_input%%[![:space:]]*}"}"

        # If empty, show error
        if [[ -z "$user_input" ]]; then
            zle -M "❌ Type a description after #"
            return 1
        fi

        # Add original command to history
        print -s "$buffer_content"

        # Process with AI (keep original buffer)
        ai_process_command_zle "$user_input" "$buffer_content"
        return 0
    fi

    # Normal behavior for non-AI commands
    zle .accept-line
}

# AI processing function for ZLE widget
ai_process_command_zle() {
    local user_input="$1"
    local original_buffer="$2"
    local command_result=""

    # Show animated loading in buffer
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local frame_count=${#frames}

    # Show animation for at least 0.8 seconds
    for i in {1..8}; do
        local current_frame=${frames[$(((i-1) % frame_count))]}
        BUFFER="${original_buffer} ${current_frame}"
        CURSOR=${#BUFFER}
        zle redisplay
        sleep 0.1
    done

    # Call appropriate API based on configuration
    case "$AI_PROVIDER" in
        "openai")
            if [[ -z "$API_KEY" ]]; then
                zle -M "❌ Error: OPENAI_API_KEY not configured"
                return 1
            fi
            command_result=$(_call_openai "$user_input")
            ;;
        "anthropic")
            if [[ -z "$ANTHROPIC_API_KEY" ]]; then
                zle -M "❌ Error: ANTHROPIC_API_KEY not configured"
                return 1
            fi
            command_result=$(_call_anthropic "$user_input")
            ;;
        "ollama")
            command_result=$(_call_ollama "$user_input")
            ;;
        *)
            zle -M "❌ Error: Invalid AI_PROVIDER. Use: openai, anthropic, or ollama"
            return 1
            ;;
    esac

    # Clear animation from buffer
    BUFFER=""
    zle redisplay

    # Check if there was an error in API call
    if [[ $? -ne 0 ]] || [[ -z "$command_result" ]] || [[ "$command_result" == "null" ]]; then
        zle -M "❌ Error calling AI API. Check your configuration."
        return 1
    fi

    # Clean and process received command
    local clean_command=$(_clean_command "$command_result")

    # Check if command was processed correctly
    if [[ -z "$clean_command" ]]; then
        zle -M "❌ Could not generate a valid command"
        return 1
    fi

    # Replace buffer with generated command
    BUFFER="$clean_command"
    CURSOR=${#BUFFER}
    zle redisplay
}

# Function to change animation style
ai_animation_style() {
    local style="$1"
    if [[ -z "$style" ]]; then
        echo "🎨 Available animation styles:"
        echo "   spinner, dots, pulse, snake"
        echo ""
        echo "🎯 Current style: $AI_ANIMATION_STYLE"
        echo ""
        echo "📝 To change: ai-animation <style>"
        echo "   Example: ai-animation spinner"
        return
    fi

    if [[ -n "${ANIMATION_FRAMES[$style]}" ]]; then
        export AI_ANIMATION_STYLE="$style"
        echo "✅ Animation changed to: $style"
    else
        echo "❌ Style '$style' not found. Use ai-animation to see options."
    fi
}

# Function to show configuration information
ai_command_info() {
    echo "\033[36m🤖 ZSH AI Command Assistant\033[0m"
    echo "=========================="
    echo "Current provider: \033[33m$AI_PROVIDER\033[0m"
    echo "Animation: \033[35m$AI_ANIMATION_STYLE\033[0m"
    echo "Speed: \033[34m${AI_ANIMATION_SPEED}s\033[0m"
    echo "Activation method: \033[32m# <description>\033[0m"
    echo ""
    echo "Required configuration:"
    case "$AI_PROVIDER" in
        "openai")
            echo "- export OPENAI_API_KEY='your-key-here'"
            ;;
        "anthropic")
            echo "- export ANTHROPIC_API_KEY='your-key-here'"
            ;;
        "ollama")
            echo "- Ollama running at: $OLLAMA_URL"
            echo "- Model: $OLLAMA_MODEL"
            ;;
    esac
    echo ""
    echo "To change provider: export AI_PROVIDER='openai|anthropic|ollama'"
    echo "To change animation: ai-animation <style>"
    echo ""
    echo "🎯 \033[1mHow to use:\033[0m"
    echo "Type: \033[33m# list files modified today\033[0m"
    echo "Press Enter and the command will be generated!"
}

# Register ZLE widget and bind to Enter key
zle -N ai_accept_line
bindkey '^M' ai_accept_line

# Useful aliases
alias ai-info='ai_command_info'
alias ai-animation='ai_animation_style'

# Initialization message
if [[ "$ZSH_AI_PLUGIN_VERBOSE" == "1" ]]; then
    echo "🤖 AI Command Assistant plugin loaded!"
    echo "💡 Use: \033[33m# <your description>\033[0m and press Enter"
    echo "🎨 Use 'ai-animation' to see animation styles."
fi
