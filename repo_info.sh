#!/bin/bash

# Helper function to print messages
say() {
  echo -e "\n$(tput setaf 2)--> $1$(tput sgr0)\n"
}

# Function to get basic repo info
get_basic_repo_info() {
  say "Repo info for $(basename `git rev-parse --show-toplevel`)"
  say "Lines of Code:"
  cloc .
  say "Number of Commits:"
  git rev-list --count HEAD
  say "Date of First Commit:"
  echo $(git log --reverse --format="%ad" --date=short | head -n 1)
  say "Date of Last Commit:"
  echo $(git log -1 --format="%ad" --date=short)
  say "Number of Contributors:"
  git shortlog -sn | wc -l
}

# Function to get commit and change info
get_commit_and_change_info() {
  say "Top Contributors by Number of Commits:"
  git shortlog -sn | head -10
  say "Latest 5 commits:"
  git log --pretty=format:"%h - %an, %ar : %s" --graph -n 5 | cat
  say "Changes over the last 2 years:"
  git log --since="2 year ago" --pretty=tformat: --numstat | awk '{ add += $1; subs += $2; loc += $1 - $2 } END { printf "\033[1;32mAdded lines: %s, Removed lines: %s, Total lines: %s\033[0m\n", add, subs, loc }' | cat
}

# Function to get file info
get_file_info() {
  say "Most Changed Files:"
  git log --name-only --pretty=format: | sort | uniq -c | sort -nr | head -10 | cat
  say "Largest Files:"
  find . -type f -exec du -h {} + | sort -rh | head -10
}

# Function to get git info
get_git_info() {
  say "Latest Tags:"
  git tag --sort=-creatordate | head -10
  say "Branches:"
  git branch -a | cat
  say "Remote Repositories:"
  git remote -v
  say "Hottest 5 paths over the last 3 years:"
  git log --since="3 years ago" --name-only --pretty=format:"%h - %an, %ar : %s" | sort | uniq -c | sort -nr | head -5
}

# Function to get GitHub info
get_github_info() {
  say "GitHub Repository Info:"
  GH_PAGER="" gh repo view --json name,description,defaultBranchRef --jq '. | "Name: \(.name)\nDescription: \(.description)\nDefault Branch: \(.defaultBranchRef.name)"'
  say "Last 10 Closed Pull Requests:"
  GH_PAGER="" gh pr list --state closed --limit 10 --json number,title,author,closedAt,url --jq '.[] | select(.title | startswith("chore(deps)") | not) | "#\(.number) [closed at \(.closedAt | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%d-%m-%y %H:%M"))] [author: \(.author.login)]\n\(.url)\n\(.title)\n"'
  say "All Open Pull Requests:"
  GH_PAGER="" gh pr list --state open --json number,title,author,createdAt,url --jq '.[] | select(.title | startswith("chore(deps)") | not) | "#\(.number) [created at \(.createdAt | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%d-%m-%y %H:%M"))] [author: \(.author.login)]\n\(.url)\n\(.title)\n"'
  say "Recent Merges:"
  GH_PAGER="" gh pr list --state merged --limit 5 --json number,title,author,mergedAt,url --jq '.[] | select(.title | startswith("chore(deps)") | not) | "#\(.number) [merged at \(.mergedAt | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%d-%m-%y %H:%M"))] [author: \(.author.login)]\n\(.url)\n\(.title)\n"'
  say "Pull Request Reviewers:"
  GH_PAGER="" gh pr list --state all --json reviews --jq '[.[] | .reviews[].author.login] | group_by(.) | map({reviewer: .[0], count: length}) | sort_by(.count) | reverse | .[] | "\(.reviewer): \(.count) reviews"' | head -10
}

# Main function to get all repo info
repo_info() {
  get_basic_repo_info
  get_commit_and_change_info
  get_file_info
  get_git_info
  get_github_info
  echo -e "\n"
}

# Execute the main function
repo_info
