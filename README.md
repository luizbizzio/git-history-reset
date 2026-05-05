<h1 align="center">Git History Reset 🔁</h1>

<p align="center">Reset a repository history into a single fresh commit, with GitHub repo selection, snapshot backup, and automatic push.</p>

Works on **Windows** and **Linux**.
Use it when you want to:

- clean a repository history before publishing
- restart a project as a fresh public repo
- keep the current files, but remove old commits
- remove old large files from Git history without downloading the full old history by default
- do it with a safer flow, not with random Git commands

## Features 📊

- Lists your GitHub repositories with `gh`
- Works with public and private repositories
- Shows repositories in a readable alphabetical list
- Clones only the selected branch by default, using shallow history
- Creates a `.zip` snapshot backup of the current files by default
- Rebuilds history as a single new commit
- Pushes the rewritten branch automatically with `--force-with-lease`
- Removes the temporary clone after a successful push
- Supports optional signed commits, depending on your local Git setup
- Supports full history backup as an advanced option
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

### Windows

```powershell
ghr -Uninstall
```

### Linux

```bash
ghr --uninstall
```

## Common usage 🧪

### Normal reset

```bash
ghr
```

### Test without pushing

Windows:

```powershell
ghr -NoPush -KeepClone
```

Linux:

```bash
ghr --no-push --keep-clone
```

### Skip the first confirmation

Windows:

```powershell
ghr -Yes
```

Linux:

```bash
ghr --yes
```

### Skip backup

Windows:

```powershell
ghr -NoBackup
```

Linux:

```bash
ghr --no-backup
```

### Create a full Git history backup

Windows:

```powershell
ghr -FullHistoryBackup
```

Linux:

```bash
ghr --full-history-backup
```

### Force signed commit

Windows:

```powershell
ghr -Sign
```

Linux:

```bash
ghr --sign
```

### Force unsigned commit

Windows:

```powershell
ghr -NoSign
```

Linux:

```bash
ghr --no-sign
```

### Filter repositories before listing

Windows:

```powershell
ghr -Filter repo_name
```

Linux:

```bash
ghr --filter repo_name
```

---

## How it works

1. Checks Git and GitHub CLI
2. Reads your authenticated GitHub account
3. Lists repositories in an alphabetical view
4. Clones only the selected branch with shallow history by default
5. Creates a `.zip` snapshot backup of the current files
6. Rewrites the history into one new commit
7. Pushes the result to GitHub with `--force-with-lease`
8. Removes the temporary clone after a successful push

## Confirmation

The tool asks for `RESET` before rewriting the repository history.

After that confirmation, the default flow continues automatically.

To test without pushing, use:

- Windows: `ghr -NoPush -KeepClone`
- Linux: `ghr --no-push --keep-clone`

## Backup

Before rewriting history, the tool creates a `.zip` snapshot backup of the current repository files.

Example backup files:

```text
.../git-history-reset-workspace/backups/<repo-name>-<timestamp>.zip
.../git-history-reset-workspace/backups/<repo-name>-<timestamp>.txt
```

This backup contains the current files, not the old Git history.

If you want a full Git history backup, use:

- Windows: `ghr -FullHistoryBackup`
- Linux: `ghr --full-history-backup`

Full history backup creates a Git bundle, but it requires downloading the full old repository history.

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
- removing old large files that are no longer in the current branch

---

## License 📄

This project is licensed under the Apache License Version 2.0 - see the [LICENSE](LICENSE) file for details.
