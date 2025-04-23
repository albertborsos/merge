# Git Merge Tool

## Overview
The Git Merge Tool is an interactive shell script that simplifies merging multiple Git branches into a target branch. It provides a user-friendly terminal interface using dialog boxes, eliminating the need to remember complex Git commands.

## Features
- Interactive branch selection through dialog menus
- Support for both existing branches or creating new target branches
- Branch filtering to focus on specific prefixes
- "Octopus merge" attempt (merging all branches at once) with fallback to sequential merging
- Guided conflict resolution workflow
- Safety checks to prevent issues with uncommitted changes

## Requirements
- Git
- `dialog` utility (install with `brew install dialog` on macOS)
- Bash shell environment

## Installation

1. Download the script
   ```bash
   curl -O https://raw.githubusercontent.com/username/repo/main/merge-tool.sh
   ```

2. Make it executable
   ```bash
   chmod +x merge-tool.sh
   ```

3. Optional: Add to your PATH for easier access
   ```bash
   mkdir -p ~/bin
   cp merge-tool.sh ~/bin/merge-tool
   echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc  # or ~/.bashrc
   source ~/.zshrc  # or ~/.bashrc
   ```

## Usage

1. Navigate to your git repository
   ```bash
   cd /path/to/your/repo
   ```

2. Run the script
   ```bash
   merge-tool
   ```

3. Follow the interactive prompts:
   - Select or create a target branch
   - Enter a prefix to filter source branches (optional)
   - Select multiple source branches to merge using checkboxes
   - Resolve any conflicts if they occur

## How It Works

The tool follows this workflow:
1. Verifies you're in a git repository with a clean working directory
2. Fetches the latest changes from remote
3. Guides you through target branch selection (existing or new)
4. Lets you filter source branches if needed
5. Displays checkboxes to select branches for merging
6. Tries an "octopus merge" (all branches at once)
7. Falls back to sequential merging if octopus merge fails
8. Provides an interactive conflict resolution interface when needed

## Configuration

You can modify these variables at the top of the script:
- `FOLDER`: Working directory (defaults to current directory)
- `BRANCH_FILTER_PREFIX`: Default filter for source branches

## Notes
- The script does not automatically push changes to remote
- All merges use `--no-ff` to preserve branch history
- ShellCheck is set up in the repository to maintain script quality