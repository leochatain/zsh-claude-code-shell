# zsh-claude-code-shell - Generate shell commands from natural language using Claude Code
# Usage: Type "#? <description>" to generate a command, "#?? <command>" to explain a command

# Configuration
: ${ZSH_CLAUDE_SHELL_DISABLED:=0}
: ${ZSH_CLAUDE_SHELL_MODEL:=sonnet}
: ${ZSH_CLAUDE_SHELL_DEBUG:=0}
: ${ZSH_CLAUDE_SHELL_FANCY_LOADING:=1}  # Set to 0 to use simple loading message

# System prompts
_ZSH_CLAUDE_EXPLAIN_PROMPT="You are a shell command explainer. The user may provide their last executed command and current directory for context.

The user will give you a shell command to explain. Explain what it does concisely:
- First line: one-sentence summary of the overall command.
- Then explain each flag and argument using \"\`flag\`: explanation\" format.
- If it's a pipeline, explain each stage.
- Keep it brief. No preamble, no sign-off."

_ZSH_CLAUDE_GENERATE_PROMPT="You are a shell command generator. The user may provide their last executed command and current directory for context to help you understand what they're working on.

When the user references \"last command\", \"previous command\", \"that command\", or \"the command\", they are referring to the command shown in the \"Last command:\" context field.

Your ONLY job is to output a single shell command that accomplishes the user's request. Output ONLY the raw shell command - no markdown, no code blocks, no explanations, no comments, no backticks. Just the executable command itself on a single line. If you need to look up command syntax, you may use web search."

# Thinking verbs (from Claude Code)
_ZSH_CLAUDE_THINKING_VERBS=(
    "Accomplishing" "Actioning" "Actualizing" "Baking" "Brewing"
    "Calculating" "Cerebrating" "Churning" "Clauding" "Coalescing"
    "Cogitating" "Computing" "Conjuring" "Considering" "Cooking"
    "Crafting" "Creating" "Crunching" "Deliberating" "Determining"
    "Doing" "Effecting" "Finagling" "Forging" "Forming" "Generating"
    "Hatching" "Herding" "Honking" "Hustling" "Ideating" "Inferring"
    "Manifesting" "Marinating" "Moseying" "Mulling" "Mustering" "Musing"
    "Noodling" "Percolating" "Pondering" "Processing" "Puttering"
    "Reticulating" "Ruminating" "Schlepping" "Shucking" "Simmering"
    "Smooshing" "Spinning" "Stewing" "Synthesizing" "Thinking"
    "Transmuting" "Vibing" "Working"
)

# Spinner animation (runs in background, writes to /dev/tty)
_zsh_claude_spinner() {
    local spinchars='✽⊹✦◈'
    local spin_len=4
    local words_len=${#_ZSH_CLAUDE_THINKING_VERBS[@]}
    local i=1
    local w=$(( RANDOM % words_len + 1 ))  # Start with random word
    local tick=0

    # Colors for shimmering effect (cyan gradient)
    local -a colors=('\033[96m' '\033[36m' '\033[96m' '\033[36m')
    local color_idx=1

    # Hide cursor
    printf '\033[?25l' > /dev/tty

    while true; do
        local char="${spinchars[$i]}"
        local word="${_ZSH_CLAUDE_THINKING_VERBS[$w]}"
        local color="${colors[$color_idx]}"

        # Print spinner with shimmering color effect
        printf '\r\033[K%b%s %s...\033[0m' "$color" "$char" "$word" > /dev/tty

        i=$(( i % spin_len + 1 ))
        tick=$(( tick + 1 ))
        color_idx=$(( color_idx % 4 + 1 ))

        # Change word every ~12 ticks (~1.2 seconds)
        if (( tick % 12 == 0 )); then
            w=$(( RANDOM % words_len + 1 ))
        fi
        sleep 0.1
    done
}

# Stop spinner and cleanup
_zsh_claude_stop_spinner() {
    local pid=$1
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        # Small delay to let the process terminate
        sleep 0.05
    fi
    # Show cursor, clear spinner line, move up one line, clear that line too
    # This returns cursor to the original query line position
    printf '\033[?25h\r\033[K\033[A\r\033[K' > /dev/tty
}

# Check if claude CLI is available (lazy check - deferred until first use)
_zsh_claude_check_cli() {
    if ! command -v claude &> /dev/null; then
        echo "zsh-claude-code-shell: 'claude' command not found. Please install Claude Code CLI."
        return 1
    fi
    return 0
}

# Trim leading/trailing whitespace
_zsh_claude_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    echo "$s"
}

# Sanitize output - remove markdown code blocks and trim whitespace
# Usage: _zsh_claude_sanitize <text> [--explain]
_zsh_claude_sanitize() {
    local input="$1"

    # Remove markdown code block markers (```bash, ```, etc.)
    input="${input#\`\`\`*$'\n'}"  # Remove opening ```lang\n
    input="${input%\`\`\`}"         # Remove closing ```
    input="${input#\`\`\`}"         # Remove opening ``` without newline

    # Remove single backticks wrapping the whole command (not for explain mode)
    if [[ "$2" != "--explain" ]] && [[ "$input" == \`*\` ]]; then
        input="${input#\`}"
        input="${input%\`}"
    fi

    echo "$(_zsh_claude_trim "$input")"
}

# Get the last command for context
_zsh_claude_get_history_context() {
    # Get the last command from history
    local last_cmd
    last_cmd=$(fc -ln -1 2>/dev/null) || return

    last_cmd=$(_zsh_claude_trim "$last_cmd")

    # Skip if empty or if it's a #? or #?? query
    [[ -z "$last_cmd" ]] && return
    [[ "$last_cmd" == '#?'* ]] && return

    echo "Last command: $last_cmd"
}

# Get current directory context
_zsh_claude_get_directory_context() {
    local current_dir="$PWD"

    # Replace $HOME with ~ for readability
    current_dir="${current_dir/#$HOME/~}"

    echo "Current directory: $current_dir"
}

# Print debug information to terminal
_zsh_claude_print_debug() {
    local mode="$1" system_prompt="$2" enhanced_query="$3"
    print -r -- "" > /dev/tty
    print -r -- "=== DEBUG MODE ===" > /dev/tty
    print -r -- "" > /dev/tty
    print -r -- "Mode: $mode" > /dev/tty
    print -r -- "" > /dev/tty
    print -r -- "System Prompt:" > /dev/tty
    print -r -- "----------------" > /dev/tty
    print -r -- "$system_prompt" > /dev/tty
    print -r -- "" > /dev/tty
    print -r -- "User Prompt:" > /dev/tty
    print -r -- "------------" > /dev/tty
    print -r -- "$enhanced_query" > /dev/tty
    print -r -- "" > /dev/tty
    print -r -- "=================" > /dev/tty
    print -r -- "" > /dev/tty
}

# Main widget that intercepts Enter key
_zsh_claude_accept_line() {
    # Pass through if disabled
    if [[ "$ZSH_CLAUDE_SHELL_DISABLED" == "1" ]]; then
        zle .accept-line
        return
    fi

    # Only trigger in interactive mode
    if [[ ! -o interactive ]]; then
        zle .accept-line
        return
    fi

    # Detect mode: #?? (explain) must be checked before #? (generate)
    local mode=""
    if [[ "$BUFFER" == '#?? '* ]]; then
        mode="explain"
    elif [[ "$BUFFER" == '#? '* ]]; then
        mode="generate"
    else
        zle .accept-line
        return
    fi

    # Pass through multi-line buffers
    if [[ "$BUFFER" == *$'\n'* ]]; then
        zle .accept-line
        return
    fi

    # Extract query (remove prefix)
    local query
    if [[ "$mode" == "explain" ]]; then
        query="${BUFFER:4}"  # skip "#?? "
    else
        query="${BUFFER:3}"  # skip "#? "
    fi

    # Check for --DEBUG flag
    local debug_mode=0
    if [[ "$query" == '--DEBUG '* ]]; then
        debug_mode=1
        query="${query:8}"  # skip "--DEBUG "
    fi

    # Skip empty queries
    if [[ -z "${query// }" ]]; then
        zle .accept-line
        return
    fi

    # Check if claude CLI is available
    if ! _zsh_claude_check_cli; then
        zle reset-prompt
        return 1
    fi

    # Start spinner or show simple message
    local spinner_pid=""
    if [[ "$ZSH_CLAUDE_SHELL_FANCY_LOADING" == "1" ]]; then
        # Print newline so spinner appears below the query line
        print > /dev/tty
        # Disable job notifications to prevent [1] 12345 and terminated messages
        setopt local_options no_notify no_monitor
        _zsh_claude_spinner &
        spinner_pid=$!
        disown $spinner_pid 2>/dev/null
    else
        if [[ "$mode" == "explain" ]]; then
            zle -R "Explaining command..."
        else
            zle -R "Generating command..."
        fi
    fi

    # Build context for the query
    local dir_context=$(_zsh_claude_get_directory_context)
    local hist_context=$(_zsh_claude_get_history_context)

    # Build enhanced query with context
    local enhanced_query=""
    [[ -n "$dir_context" ]] && enhanced_query+="${dir_context}"$'\n'
    [[ -n "$hist_context" ]] && enhanced_query+="${hist_context}"$'\n'
    if [[ -n "$enhanced_query" ]]; then
        enhanced_query+=$'\n'"User request: ${query}"
    else
        enhanced_query="$query"
    fi

    # Select mode-appropriate system prompt
    local system_prompt
    if [[ "$mode" == "explain" ]]; then
        system_prompt="$_ZSH_CLAUDE_EXPLAIN_PROMPT"
    else
        system_prompt="$_ZSH_CLAUDE_GENERATE_PROMPT"
    fi

    # Print debug information if --DEBUG flag was used
    if (( debug_mode )); then
        [[ -n "$spinner_pid" ]] && _zsh_claude_stop_spinner "$spinner_pid"
        spinner_pid=""
        _zsh_claude_print_debug "$mode" "$system_prompt" "$enhanced_query"
    fi

    # Build claude command
    local claude_args=("-p" "--output-format" "text")
    claude_args+=("--tools" "WebSearch,WebFetch")
    claude_args+=("--system-prompt" "$system_prompt")
    if [[ -n "$ZSH_CLAUDE_SHELL_MODEL" ]]; then
        claude_args+=("--model" "$ZSH_CLAUDE_SHELL_MODEL")
    fi

    # Call Claude Code CLI with output to temp file so we can use wait
    local tmpfile="${TMPDIR:-/tmp}/zsh-claude-$$"
    local claude_pid
    local exit_code
    local cmd

    if (( ZSH_CLAUDE_SHELL_DEBUG )); then
        claude "${claude_args[@]}" "$enhanced_query" > "$tmpfile" 2>&1 &
    else
        claude "${claude_args[@]}" "$enhanced_query" > "$tmpfile" 2>/dev/null &
    fi
    claude_pid=$!

    # Set up trap to clean up on interrupt (Ctrl+C)
    trap '
        kill $claude_pid 2>/dev/null
        [[ -n "$spinner_pid" ]] && _zsh_claude_stop_spinner "$spinner_pid"
        rm -f "$tmpfile"
        trap - INT
        zle reset-prompt
        return 130
    ' INT

    # Wait for claude to finish
    wait $claude_pid
    exit_code=$?

    # Reset trap and stop spinner
    trap - INT
    [[ -n "$spinner_pid" ]] && _zsh_claude_stop_spinner "$spinner_pid"

    # Read output from temp file
    cmd=$(<"$tmpfile")
    rm -f "$tmpfile"

    # Handle interrupt (Ctrl+C) - exit code 130 = 128 + SIGINT(2)
    if [[ $exit_code -eq 130 ]] || [[ $exit_code -eq 143 ]]; then
        zle reset-prompt
        return 130
    fi

    # Handle errors
    if [[ $exit_code -ne 0 ]] || [[ -z "$cmd" ]]; then
        zle -M "Error: Failed to ${mode} command (exit code: $exit_code)"
        zle reset-prompt
        return 1
    fi

    if [[ "$mode" == "explain" ]]; then
        # Sanitize and print explanation to terminal
        cmd=$(_zsh_claude_sanitize "$cmd" --explain)
        print -r -- "" > /dev/tty
        print -r -- "$cmd" > /dev/tty
        print -r -- "" > /dev/tty

        # Clear buffer since this is just an explanation, not a command to execute
        BUFFER=""
        CURSOR=0
    else
        # Sanitize the output
        cmd=$(_zsh_claude_sanitize "$cmd")

        # Replace buffer with generated command
        BUFFER="$cmd"
        CURSOR=${#BUFFER}
    fi

    zle reset-prompt
}

# Initialize the plugin
zle -N accept-line _zsh_claude_accept_line
