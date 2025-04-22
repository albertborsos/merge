#!/bin/bash

# Branch Merge Tool
# This script helps with merging multiple package branches into a target branch

# Configuration
FOLDER="$(pwd)"
PACKAGE_BRANCH_PREFIX="" # Will be set via dialog

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Error: dialog is not installed. Please install it first."
    echo "On macOS: brew install dialog"
    exit 1
fi

# Function to create or switch to target branch
create_target_branch() {
    local target_branch="$1"

    # Check if branch exists locally
    if git -C "$FOLDER" show-ref --verify --quiet "refs/heads/$target_branch"; then
        echo "Target branch exists locally. Deleting it..."
        git -C "$FOLDER" checkout master || git -C "$FOLDER" checkout main
        git -C "$FOLDER" branch -D "$target_branch" || return 1
    fi

    # Check if branch exists on remote
    if git -C "$FOLDER" ls-remote --exit-code --heads origin "$target_branch" &>/dev/null; then
        echo "Target branch exists on remote. Note: It will be deleted on push."
    fi

    # Create new branch from current branch
    git -C "$FOLDER" checkout -b "$target_branch" || return 1

    echo "Using target branch: $target_branch"
    return 0
}

# Function to list and select package branches
select_package_branches() {
    local prefix="$1"

    # Get all package branches
    # Replace the mapfile line with this:
    local package_branches=()
    while read -r branch; do
        package_branches+=("$branch")
    done < <(git -C "$FOLDER" branch -r | grep "origin/${prefix}" | sed 's/origin\///' | sort)

    if [ ${#package_branches[@]} -eq 0 ]; then
        dialog --msgbox "No branches found with prefix '${prefix}'!" 8 50
        return 1
    fi

    # Create options for dialog
    local options=()
    for branch in "${package_branches[@]}"; do
        options+=("$branch" "$branch" "off")
    done

    # Show dialog for branch selection
    selected=$(dialog --clear --title "Select Source Branches" --checklist \
        "Choose branches to merge into target branch:" 20 60 15 \
        "${options[@]}" 2>&1 >/dev/tty)

    echo "$selected"
}

# Function to attempt octopus merge
octopus_merge() {
    local target_branch="$1"
    shift
    local package_branches=("$@")

    echo "Attempting octopus merge of all branches..."

    # Prepare branch references for octopus merge
    local branches_to_merge=()
    for branch in "${package_branches[@]}"; do
        branch=$(echo "$branch" | tr -d '"')
        branches_to_merge+=("origin/$branch")
    done

    # Try octopus merge
    if git -C "$FOLDER" merge --no-ff "${branches_to_merge[@]}" -m "Octopus merge of branches into $target_branch"; then
        return 0
    else
        echo "Octopus merge failed. Aborting and trying individual merges."
        git -C "$FOLDER" merge --abort
        return 1
    fi
}

# Function to merge branches one by one
sequential_merge() {
    local target_branch="$1"
    shift
    local package_branches=("$@")

    echo "Starting sequential merge of branches..."

    for branch in "${package_branches[@]}"; do
        branch=$(echo "$branch" | tr -d '"')
        echo "Merging $branch into $target_branch..."

        if ! git -C "$FOLDER" merge --no-ff "origin/$branch" -m "$branch is merged to $target_branch"; then
            # Merge conflict occurred
            conflict_resolution "$target_branch" "$branch"
        else
            echo "Successfully merged $branch"
        fi
    done

    return 0
}

# Function to handle conflict resolution
conflict_resolution() {
    local target_branch="$1"
    local conflicting_branch="$2"

    while true; do
        choice=$(dialog --clear --title "Merge Conflict" --menu \
            "Conflict detected while merging $conflicting_branch\nPlease resolve conflicts in your editor and choose an option:" 15 60 3 \
            "continue" "Commit resolved conflicts and continue" \
            "abort" "Abort this merge and skip branch" \
            "exit" "Exit the script completely" 2>&1 >/dev/tty)

        case "$choice" in
            continue)
                # Check if conflicts are resolved
                if git -C "$FOLDER" diff --name-only --diff-filter=U | grep -q .; then
                    dialog --msgbox "Conflicts are still present. Please resolve all conflicts first." 8 50
                else
                    git -C "$FOLDER" add .
                    git -C "$FOLDER" commit -m "Resolved merge conflicts from $conflicting_branch"
                    return 0
                fi
                ;;
            abort)
                git -C "$FOLDER" merge --abort
                return 1
                ;;
            exit)
                clear
                echo "Exiting script. Target branch may be in an inconsistent state."
                exit 1
                ;;
            *)
                ;;
        esac
    done
}

# Main script execution
main() {
    # Ensure we're in a git repository
    if ! git -C "$FOLDER" rev-parse --is-inside-work-tree &>/dev/null; then
        echo "Error: Not in a git repository"
        exit 1
    fi

    # Check for clean working directory
    if ! git -C "$FOLDER" diff --quiet && ! git -C "$FOLDER" diff --staged --quiet; then
        dialog --msgbox "Working directory is not clean. Please commit or stash changes first." 8 50
        exit 1
    fi

    # Update repository
    git -C "$FOLDER" fetch origin

    # Get target branch name
    target_branch=$(dialog --clear --title "Target Branch" --inputbox "Enter name for target branch:" 8 40 2>&1 >/dev/tty)
    if [ -z "$target_branch" ]; then
        clear
        echo "No branch name provided. Exiting."
        exit 0
    fi

    # Get branch prefix for filtering
    PACKAGE_BRANCH_PREFIX=$(dialog --clear --title "Branch Prefix" --inputbox "Enter prefix to filter source branches:" 8 40 "package/" 2>&1 >/dev/tty)
    if [ -z "$PACKAGE_BRANCH_PREFIX" ]; then
        PACKAGE_BRANCH_PREFIX="package/" # Default if nothing entered
    fi

    # Create or switch to target branch
    if ! create_target_branch "$target_branch"; then
        dialog --msgbox "Failed to create target branch!" 8 40
        exit 1
    fi

    # Select source branches to merge
    selected_branches=$(select_package_branches "$PACKAGE_BRANCH_PREFIX")
    if [ -z "$selected_branches" ]; then
        clear
        echo "No branches selected. Exiting."
        exit 0
    fi

    # Convert space-separated string to array
    IFS=' ' read -r -a branch_array <<< "$selected_branches"

    # First try octopus merge
    if ! octopus_merge "$target_branch" "${branch_array[@]}"; then
        # If octopus fails, do sequential merges
        sequential_merge "$target_branch" "${branch_array[@]}"
    fi

    # Ask to push changes
    if dialog --clear --title "Push Changes" --yesno "Do you want to push the target branch to origin?" 8 50; then
        # Delete remote branch if it exists before pushing
        if git -C "$FOLDER" ls-remote --exit-code --heads origin "$target_branch" &>/dev/null; then
            echo "Deleting existing remote branch..."
            git -C "$FOLDER" push origin --delete "$target_branch"
        fi
        git -C "$FOLDER" push origin "$target_branch" -u
        echo "Changes pushed to origin/$target_branch"
    else
        echo "Changes not pushed. You can push manually later."
    fi

    dialog --msgbox "Merges completed successfully!" 8 40
    clear
}

# Run the main function
main

exit 0