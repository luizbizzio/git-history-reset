# Security Policy

## Supported versions

Security fixes are provided only for the latest version of this repository.

| Version | Supported |
| --- | --- |
| Latest `main` | Yes |
| Older commits or forks | No |

If you report an issue, reproduce it against the latest version first.

## Reporting a vulnerability

Please do **not** open a public issue for a security problem.

Use GitHub private vulnerability reporting for this repository if it is available. If private reporting is not available, contact the maintainer privately through GitHub before sharing details publicly.

When reporting a vulnerability, include:

- what the issue is
- which OS and shell you used
- the exact command or input that triggered it
- whether it affects Windows, Linux, or both
- whether `gh`, `git`, or local signing tools were involved
- a minimal reproduction if possible
- the potential impact

A good report is reproducible, specific, and short.

## What is in scope

Security reports are especially useful for issues like these:

- command injection
- unsafe handling of repository names, paths, or arguments
- credential leakage through logs, files, or process arguments
- insecure temporary file handling
- unsafe file permissions on installed launchers or scripts
- destructive behavior outside the selected repository or workspace
- update or install flows that allow unintended code execution
- misuse of `gh`, `git`, GPG, or signing flows that exposes secrets or credentials
- bugs that let the tool overwrite or remove files outside its intended paths

## What is out of scope

The following are generally not considered security vulnerabilities in this project:

- force-pushing rewritten history when the user explicitly confirms it
- deletion or replacement of Git history inside the selected repository after confirmation
- failure caused by a broken local Git, GPG, shell, or OS setup
- issues caused by running the tool as root or with unnecessary `sudo`
- secrets already exposed on the local machine before the tool runs
- mistakes caused by selecting the wrong repository after the tool shows the plan and asks for confirmation
- problems in third-party services such as GitHub itself, Git, GPG, package managers, or the OS

## Safe usage expectations

This tool is intentionally destructive when used correctly. That does **not** make every destructive outcome a security bug.

Before using it:

- verify the selected repository carefully
- keep backups
- understand that history rewrite changes commit ancestry permanently after push
- review the plan shown by the tool before typing `RESET`
- review the push confirmation before typing `YES` or `Y`

## Security recommendations for users

To reduce risk when using this repository:

- do not run the tool with `sudo` unless a specific package manager step requires it
- do not pipe remote scripts into a root shell
- use the latest version of the repository
- keep `gh` authenticated only on machines you trust
- configure Git signing only if you understand your local signing setup
- review the generated workspace and backup files before deleting them
- test first on a throwaway repository if you are unsure

## Disclosure approach

Please allow reasonable time for investigation and a fix before public disclosure.

If the report is valid, the goal is to:

1. reproduce the issue
2. assess impact
3. prepare a fix
4. publish the fix
5. disclose the issue responsibly

## Hardening goals for this project

This repository aims to:

- avoid unsafe defaults
- require explicit confirmations for destructive actions
- create backups before rewrite operations
- keep install and update flows predictable
- avoid modifying files outside the intended install and workspace paths
- prefer safer push behavior with `--force-with-lease` instead of raw `--force`

## No warranty

This project is provided as-is. You are responsible for reviewing commands before running them and for understanding the effect of rewriting Git history.
