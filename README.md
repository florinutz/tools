a set of tools I use to make my life easier

in .zshrc add the following code to load all the tools:

```zsh
for file in ~/.my-tools/*.sh; do
  source "$file"
done
```

## Tools

### `repo_info.sh` - Get information about a git repository

```zsh
repo_info()
```