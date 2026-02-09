# zsh-claude-code-shell

An oh-my-zsh plugin that translates natural language comments into shell commands using [Claude Code](https://claude.ai/claude-code).

> **Note:** This is a fork of [ArielTM/zsh-claude-code-shell](https://github.com/ArielTM/zsh-claude-code-shell).

## Demo

```bash
#? find all js files larger than 100kb modified in the last week and show their sizes
```
Press Enter, and the line becomes:
```bash
find . -name "*.js" -size +100k -mtime -7 -exec ls -lh {} \;
```
Review the command, press Enter again to execute.

Another example:
```bash
#? recursively find and delete all node_modules folders
```
Becomes:
```bash
find . -type d -name "node_modules" -prune -exec rm -rf {} +
```

## Prerequisites

- [Claude Code CLI](https://claude.ai/claude-code) installed and authenticated
- zsh shell
- [oh-my-zsh](https://ohmyz.sh/) (optional, for easiest installation)

## Installation

### oh-my-zsh

Clone to your custom plugins directory:

```bash
git clone https://github.com/leochatain/zsh-claude-code-shell ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-claude-code-shell
```

Add to your `~/.zshrc`:

```bash
plugins=(... zsh-claude-code-shell)
```

Restart your shell or run `source ~/.zshrc`.

### Manual

Clone the repository and source the plugin:

```bash
git clone https://github.com/leochatain/zsh-claude-code-shell ~/zsh-claude-code-shell
echo 'source ~/zsh-claude-code-shell/zsh-claude-code-shell.plugin.zsh' >> ~/.zshrc
```

### zinit

```bash
zinit light leochatain/zsh-claude-code-shell
```

### zplug

```bash
zplug "leochatain/zsh-claude-code-shell"
```

## Usage

1. Type a query starting with `#? ` followed by what you want to do
2. Press Enter
3. The comment is replaced with the generated command
4. Review the command, press Enter to execute (or edit it first)

### Examples

```bash
#? find all TODO comments in typescript files
# becomes: grep -rn "TODO" --include="*.ts" .

#? show top 10 largest files in current directory recursively
# becomes: find . -type f -exec du -h {} + | sort -rh | head -10

#? kill all processes matching "node"
# becomes: pkill -f node

#? compress all log files older than 30 days
# becomes: find . -name "*.log" -mtime +30 -exec gzip {} \;

#? show git commits from last week with stats
# becomes: git log --since="1 week ago" --stat

#? find duplicate files by md5 hash
# becomes: find . -type f -exec md5sum {} + | sort | uniq -w32 -dD
```

## Configuration

Set these environment variables in your `~/.zshrc` before the plugin loads:

| Variable | Default | Description |
|----------|---------|-------------|
| `ZSH_CLAUDE_SHELL_DISABLED` | `0` | Set to `1` to disable the plugin |
| `ZSH_CLAUDE_SHELL_MODEL` | (default) | Override the Claude model (e.g., `sonnet`, `opus`) |
| `ZSH_CLAUDE_SHELL_DEBUG` | `0` | Set to `1` to show debug output |
| `ZSH_CLAUDE_SHELL_FANCY_LOADING` | `1` | Set to `0` to use simple loading message instead of animated spinner |
| `ZSH_CLAUDE_SHELL_HISTORY_LINES` | `5` | Number of recent commands to include as context (set to `0` to disable) |

### Example

```bash
# Use a specific model
export ZSH_CLAUDE_SHELL_MODEL="sonnet"

# Temporarily disable
export ZSH_CLAUDE_SHELL_DISABLED=1
```

## How It Works

The plugin overrides zsh's `accept-line` widget (the Enter key handler). When you press Enter:

1. If the line starts with `#? ` or `#?? `, it extracts your query
2. Gathers context: current directory and recent command history (last 5 commands by default)
3. Calls `claude -p` with the context and your query
4. For `#?` (generate): replaces the buffer with the generated command
5. For `#??` (explain): displays the explanation and sets the buffer to the original command
6. You review and press Enter again to execute (for generate mode) or edit as needed

Lines that don't start with `#? ` or `#?? ` work normally.

### Context Features

The plugin automatically includes:
- **Current directory**: Helps Claude understand your working location
- **Recent command history**: Last 5 commands (configurable) to provide context about what you're working on
- **Security**: Automatically filters out sensitive commands containing passwords, tokens, API keys, sudo, etc.

This context helps Claude generate more relevant commands. For example, if you recently cloned a repository and changed into its directory, asking `#? run tests` will be aware of your project context.

To disable history context, set `ZSH_CLAUDE_SHELL_HISTORY_LINES=0` in your `~/.zshrc`.

## License

MIT
