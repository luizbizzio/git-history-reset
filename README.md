# Git History Reset 🔁

Reset a repository history into a single fresh commit, with backup, GitHub repo selection, and optional push.

Works on **Windows** and **Linux**.
Use it when you want to:

- clean a repository history before publishing
- restart a project as a fresh public repo
- keep the current files, but remove old commits
- do it with a safer flow, not with random Git commands

## Features

- Lists your GitHub repositories with `gh`
- Works with public and private repositories
- Shows repositories in a readable alphabetical list
- Clones into a dedicated workspace
- Creates a `.bundle` backup before changing anything
- Rebuilds history as a single new commit
- Supports optional signed commits, depending on your local Git setup
- Can push the rewritten history automatically
- Provides a short alias: `ghr`

## Important warning ⚠️

This tool **rewrites Git history**.

That means:

- old commits are replaced by one new commit
- pushing the result requires a force-style push, done with `--force-with-lease`
- GitHub issues, pull requests, releases, stars, and other platform data are **not** deleted by this tool
- selecting the wrong repository can permanently replace the wrong history

Use it only when you understand the impact of rewriting history.

## What this does not do ❌

This tool does **not** delete:

- GitHub issues
- pull requests
- releases
- stars or watchers
- forks
- workspace backups during uninstall

---

## Requirements 🧰

The tool expects:

- Git
- GitHub CLI (`gh`)
- a GitHub account authenticated in `gh`

If `gh` is missing, the tool can try to install it.  
If your Git identity is missing, the tool can ask to configure `git user.name` and `git user.email`.

---

## Install or update 🚀

### Windows 🪟

Run this in **CMD**, **PowerShell**, or **Windows Terminal**:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='https://raw.githubusercontent.com/luizbizzio/git-history-reset/main/windows/git-history-reset.ps1'; $f=Join-Path $env:TEMP 'git-history-reset.ps1'; Invoke-WebRequest $u -OutFile $f -UseBasicParsing; & powershell -NoProfile -ExecutionPolicy Bypass -File $f -Install -SourceUrl $u; & \"$env:USERPROFILE\bin\ghr.cmd\""
```

Installs or updates the tool and starts `ghr` immediately.

### Linux 🐧

```bash
u='https://raw.githubusercontent.com/luizbizzio/git-history-reset/main/linux/git-history-reset.sh'; curl -fsSL "$u" | bash -s -- --install --source-url "$u" && export PATH="$HOME/.local/bin:$PATH" && ghr
```

Installs or updates the tool, refreshes PATH for the current shell, and starts `ghr`.

## Run ▶️

After installation, use:

```bash
ghr
```

or:

```bash
git-history-reset
```

If the current shell still does not find `ghr`, open a new terminal or refresh the PATH for the current session.

## Uninstall 🗑️

After installation, remove the tool with:

```bash
ghr --uninstall
```

## Common usage 🧪

### Dry run

```bash
ghr --dry-run
```

### Skip the first confirmation

```bash
ghr --yes
```

### Push automatically at the end

```bash
ghr --push-force
```

### Remove the temporary clone after a successful push

```bash
ghr --remove-clone-on-success
```

### Force signed commit

```bash
ghr --sign
```

### Force unsigned commit

```bash
ghr --no-sign
```

### Filter repositories before listing

```bash
ghr --filter repo_name
```

---

## How it works

1. Checks Git and GitHub CLI
2. Reads your authenticated GitHub account
3. Lists repositories in an alphabetical view
4. Clones the selected repository into a workspace
5. Creates a `.bundle` backup
6. Rewrites the history into one new commit
7. Optionally pushes the result to GitHub

## Confirmations

The tool uses two confirmations by design:

- `RESET` before the destructive operation
- `YES` or `Y` before the final push

This makes accidental history rewrites less likely.

## Backup

Before rewriting history, the tool creates a Git bundle backup.

Example backup files:

```text
.../git-history-reset-workspace/backups/<repo-name>-<timestamp>.bundle
.../git-history-reset-workspace/backups/<repo-name>-<timestamp>.txt
```

That means you still have a backup of the old repository state before the rewrite.

## Workspace

Default workspace location:

- Windows: `%USERPROFILE%\git-history-reset-workspace`
- Linux: `~/git-history-reset-workspace`

By default, uninstall removes the installed command files, but **does not delete the workspace**.
That is intentional, because the workspace may contain backups you still want.

## Why `--force-with-lease` instead of `--force`

Because `--force-with-lease` is safer.

- `--force` pushes even if the remote branch changed in a way you did not expect
- `--force-with-lease` refuses the push if the remote is not in the state you expected

So this tool still does a force-style push, but with one more safety check.

## Notes about signed commits

If your local Git is configured to sign commits, the tool can inherit that behavior.

On Windows, the first signed commit attempt may fail if the signing agent is still waking up.
The script retries once for that case.

Whether the commit becomes **Verified** on GitHub depends on your local signing setup, key, and email configuration.

## Good use cases

- publishing a cleaned version of a project
- restarting a repository with a fresh public history
- keeping the current files while dropping the old commit timeline

---

## License 📄

This project is licensed under the Apache License Version 2.0 - see the [LICENSE](LICENSE) file for details.
