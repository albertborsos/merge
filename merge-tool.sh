#!/bin/bash

# Branch Deployment Tool
# For merging multiple branches into a target branch

# Configuration
FOLDER="$(pwd)"
BRANCH_FILTER_PREFIX="" # Default prefix

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Error: dialog is not installed. Please install it first."
    echo "On macOS: brew install dialog"
    exit 1
fi

# Function to select target branch
select_target_branch() {
    # Ask user whether to use existing branch or create new one
    branch_option=$(dialog --clear --title "Target Branch Selection" --menu \
        "Choose target branch option:" 10 60 2 \
        "existing" "Use an existing branch" \
        "new" "Create a new branch" 2>&1 >/dev/tty)

    if [ -z "$branch_option" ]; then
        clear
        echo "No option selected. Exiting."
        exit 0
    fi

    if [ "$branch_option" = "existing" ]; then
        # Get all local branches
        local branches=()
        while read -r branch; do
            branches+=("$branch" "$branch")
        done < <(git -C "$FOLDER" branch --format="%(refname:short)" | sort)

        if [ ${#branches[@]} -eq 0 ]; then
            dialog --msgbox "No local branches found!" 8 40
            exit 1
        fi

        # Show dialog for branch selection
        target_branch=$(dialog --clear --title "Select Target Branch" --menu \
            "Choose existing branch to use as target:" 20 60 15 \
            "${branches[@]}" 2>&1 >/dev/tty)

        if [ -z "$target_branch" ]; then
            clear
            echo "No branch selected. Exiting."
            exit 0
        fi

        # Checkout the selected branch
        git -C "$FOLDER" checkout "$target_branch" || exit 1
        echo "Using existing branch: $target_branch"

    else
        # Get name for new branch
        target_branch=$(dialog --clear --title "New Branch" --inputbox \
            "Enter name for the new target branch:" 8 60 2>&1 >/dev/tty)

        if [ -z "$target_branch" ]; then
            clear
            echo "No branch name provided. Exiting."
            exit 0
        fi

        # Check if branch exists locally
        if git -C "$FOLDER" show-ref --verify --quiet "refs/heads/$target_branch"; then
            choice=$(dialog --clear --title "Branch Exists" --menu \
                "Branch '$target_branch' already exists locally. What would you like to do?" 12 70 2 \
                "delete" "Delete it and create fresh from main/master branch" \
                "keep" "Keep and use the branch in its current state" 2>&1 >/dev/tty)

            case "$choice" in
                delete)
                    echo "Deleting existing target branch..."
                    git -C "$FOLDER" checkout master 2>/dev/null || git -C "$FOLDER" checkout main
                    git -C "$FOLDER" branch -D "$target_branch" || exit 1
                    # Create new branch from current branch (main/master)
                    git -C "$FOLDER" checkout -b "$target_branch" || exit 1
                    ;;
                keep)
                    echo "Using existing target branch in its current state..."
                    git -C "$FOLDER" checkout "$target_branch" || exit 1
                    ;;
                *)
                    # User canceled
                    clear
                    echo "Operation canceled. Exiting."
                    exit 0
                    ;;
            esac
        else
            # Create new branch from current branch
            git -C "$FOLDER" checkout -b "$target_branch" || exit 1
        fi

        echo "Using branch: $target_branch"
    fi

    return 0
}

# Function to list and select source branches
select_source_branches() {
    local prefix="$1"
    local target="$2"

    # Get all source branches
    local available_branches=()

    if [ -z "$prefix" ]; then
        # No prefix specified, get all remote branches (excluding HEAD and target branch)
        while read -r branch; do
            if [ "$branch" != "$target" ]; then
                available_branches+=("$branch")
            fi
        done < <(git -C "$FOLDER" branch -r | sed 's/origin\///' | grep -v "HEAD" | sort)
    else
        # Filter by prefix
        while read -r branch; do
            if [ "$branch" != "$target" ]; then
                available_branches+=("$branch")
            fi
        done < <(git -C "$FOLDER" branch -r | grep "origin/${prefix}" | sed 's/origin\///' | sort)
    fi

    # Create options for dialog
    local options=()
    for branch in "${available_branches[@]}"; do
        options+=("$branch" "$branch" "off")
    done

    if [ ${#options[@]} -eq 0 ]; then
        return 1
    fi

    # Show dialog for branch selection
    selected=$(dialog --clear --title "Select Source Branches" --checklist \
        "Choose branches to merge into target branch:" 20 60 15 \
        "${options[@]}" 2>&1 >/dev/tty)

    if [ -z "$selected" ]; then
        return 1
    fi

    echo "$selected"
}

# Function to attempt octopus merge
octopus_merge() {
    local target_branch="$1"
    shift
    local available_branches=("$@")

    echo "Attempting octopus merge of all branches..."

    # Prepare branch references for octopus merge
    local branches_to_merge=()
    for branch in "${available_branches[@]}"; do
        branch=$(echo "$branch" | tr -d '"')
        branches_to_merge+=("origin/$branch")
    done

    # Try octopus merge
    if git -C "$FOLDER" merge --no-ff "${branches_to_merge[@]}" --no-edit; then
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
    local available_branches=("$@")

    echo "Starting sequential merge of branches..."

    for branch in "${available_branches[@]}"; do
        branch=$(echo "$branch" | tr -d '"')
        echo "----------------------------------------"
        echo "Now merging: $branch into $target_branch"
        echo "----------------------------------------"

        if ! git -C "$FOLDER" merge --no-ff "origin/$branch" --no-edit; then
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
            "Conflict detected while merging:\n\n→→→ $conflicting_branch ←←←\n\nPlease resolve conflicts in your editor and choose an option:" 15 70 3 \
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
                    git -C "$FOLDER" commit --no-edit
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
    if ! git -C "$FOLDER" diff --quiet || ! git -C "$FOLDER" diff --staged --quiet; then
        dialog --msgbox "Working directory is not clean. Please commit or stash changes first." 8 50
        clear
        exit 1
    fi

    # Update repository
    git -C "$FOLDER" fetch origin

    # Select target branch
    select_target_branch
    target_branch=$(git -C "$FOLDER" branch --show-current)

    # Get branch prefix for filtering
    BRANCH_FILTER_PREFIX=$(dialog --clear --title "Branch Prefix" --inputbox \
        "Enter prefix to filter source branches (leave empty for all branches):" 8 60 "$BRANCH_FILTER_PREFIX" 2>&1 >/dev/tty)

    # Select source branches to merge
    if ! selected_branches=$(select_source_branches "$BRANCH_FILTER_PREFIX" "$target_branch") || [ -z "$selected_branches" ]; then
        clear
        echo "No branches found or selected or no matching branches found. Exiting."
        exit 0
    fi
    echo "Selected branches: $selected_branches"

    # Convert space-separated string to array
    IFS=' ' read -r -a branch_array <<< "$selected_branches"

    # First try octopus merge
    if ! octopus_merge "$target_branch" "${branch_array[@]}"; then
        # If octopus fails, do sequential merges
        sequential_merge "$target_branch" "${branch_array[@]}"
    fi

    dialog --msgbox "Merges completed successfully into branch: $target_branch\n\nNote: Changes have NOT been pushed to remote." 10 60
    clear
    echo "Merge process completed. Your changes are in branch: $target_branch"
}

# Run the main function
main

exit 0