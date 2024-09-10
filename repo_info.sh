#!/bin/bash

FD_FLAGS="${FD_FLAGS:---type f --extension go --extension java --extension kt --extension tf}"
FD_FLAGS_ARRAY=(${=FD_FLAGS})

say() {
  echo -e "\n$(tput setaf 2)--> $1$(tput sgr0)\n"
}

check_gh_auth() {
  if ! gh auth status &>/dev/null; then
    say "GitHub CLI is not authenticated. Please run 'gh auth login' to authenticate."
    exit 1
  fi
}

check_github_token() {
  if [ -n "$GITHUB_TOKEN" ]; then
    say "GITHUB_TOKEN is set. Unsetting it to avoid authentication errors."
    unset GITHUB_TOKEN
  fi
}

get_insights() {
  local years=${1:-3}
  say "The $(basename `git rev-parse --show-toplevel`) repo
  has $(git shortlog -sn | wc -l) contributors and
  $(git rev-list --count HEAD) commits.
  First one was on $(git log --reverse --format="%ad" --date=short | head -n 1)
  and the last one was on $(git log -1 --format="%ad" --date=short).
  Its size is $(git count-objects -vH | grep "size-pack" | awk '{print $2 " " $3}').
  The repo has $(git tag --list | wc -l) tags and $(git branch -a | wc -l) branches."
  say "10 largest files:"
  fd "${FD_FLAGS_ARRAY[@]}" -t f | xargs du -h | sort -rh | head -10
  say "10 most recently modified repo files:"
  fd "${FD_FLAGS_ARRAY[@]}" -t f --exec git log -1 --format="%ai {}" {} | sort | tail -10
  say "Top Contributors by Number of Commits:"
  git shortlog -sn | head -10
  say "Latest 5 commits:"
  git log --pretty=format:"%h - %an, %ar : %s" --graph -n 5 | cat
  say "Changes over the last $years years:"
  git log --since="$years years ago" --pretty=tformat: --numstat | awk '{ add += $1; subs += $2; loc += $1 - $2 } END { printf "\033[1;32mAdded lines: %s, Removed lines: %s, Total lines: %s\033[0m\n", add, subs, loc }' | cat
  say "Most Changed Files:"
  git log --name-only --pretty=format: | grep -v '^$' | sort | uniq -c | sort -nr | head -10
  say "Latest Tags:"
  git tag --sort=-creatordate | head -10
  say "Branches:"
  git branch -a | grep -v "dependabot" | cat
  say "Remotes:"
  git remote -v
  say "Hottest (most changed) paths over the last $years years:"
  git log --since="$years years ago" --name-only --pretty=format:"%h - %an, %ar : %s" | sort | uniq -c | sort -nr | head -10
}

get_github_insights() {
  check_gh_auth
  check_github_token
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

repo_info() {
  get_insights 3
  get_github_insights
  say "Lines of Code:"
  cloc .
  echo -e "\n"
}