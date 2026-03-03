#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${HOME}/git-history-reset-workspace"
INSTALL_ROOT="${HOME}/.local/share/git-history-reset"
BIN_ROOT="${HOME}/.local/bin"
MESSAGE="Initial commit"
FILTER=""
SOURCE_URL=""
INSTALL=0
UNINSTALL=0
YES=0
DRY_RUN=0
PUSH_FORCE=0
SIGN=0
NO_SIGN=0
REMOVE_CLONE_ON_SUCCESS=0
SELF_PATH="${BASH_SOURCE[0]:-}"

USE_COLOR=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  USE_COLOR=1
fi
if [ "$USE_COLOR" -eq 1 ]; then
  C_RESET=$'\033[0m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_DIM=$'\033[2m'
  C_WHITE=$'\033[97m'
else
  C_RESET=''
  C_CYAN=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
  C_DIM=''
  C_WHITE=''
fi

write_section() {
  printf '\n'
  printf '[>] %s\n' "$1"
}

write_info_line() {
  printf '  %-18s %s\n' "$1" "$2"
}

write_warn_line() {
  printf '%s\n' "$1"
}

write_error_line() {
  printf '%s\n' "$1" >&2
}

write_success_line() {
  printf '%s\n' "$1"
}

write_step_line() {
  printf '  - %s\n' "$1"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

resolve_tool_path() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  return 1
}

require_tool() {
  local name="$1"
  local path
  if ! path="$(resolve_tool_path "$name")"; then
    write_error_line "$name is required but was not found in PATH."
    exit 1
  fi
  printf '%s' "$path"
}

get_path_entries() {
  local value="$1"
  local oldifs="$IFS"
  IFS=':'
  read -r -a _path_entries <<< "$value"
  IFS="$oldifs"
  printf '%s\n' "${_path_entries[@]}"
}

path_contains_entry() {
  local path_value="$1"
  local target="$2"
  local normalized_target
  normalized_target="$(python3 - <<PY
import os
print(os.path.realpath(os.path.expanduser(${target@Q})))
PY
 2>/dev/null || printf '%s' "$target")"
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    local normalized_entry
    normalized_entry="$(python3 - <<PY
import os
print(os.path.realpath(os.path.expanduser(${entry@Q})))
PY
 2>/dev/null || printf '%s' "$entry")"
    if [ "$normalized_entry" = "$normalized_target" ]; then
      return 0
    fi
  done < <(get_path_entries "$path_value")
  return 1
}

get_sudo_prefix() {
  if [ "$(id -u)" -eq 0 ]; then
    printf ''
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    printf 'sudo'
    return 0
  fi
  return 1
}

download_file() {
  local url="$1"
  local output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$output" "$url"
    return 0
  fi
  return 1
}

ensure_download_tool() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  local sudo_prefix
  if ! sudo_prefix="$(get_sudo_prefix)"; then
    return 1
  fi

  if command -v apt >/dev/null 2>&1; then
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix apt update
      $sudo_prefix apt install wget -y
    else
      apt update
      apt install wget -y
    fi
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix dnf install -y wget
    else
      dnf install -y wget
    fi
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix yum install -y wget
    else
      yum install -y wget
    fi
    return 0
  fi

  if command -v zypper >/dev/null 2>&1; then
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix zypper --non-interactive install wget
    else
      zypper --non-interactive install wget
    fi
    return 0
  fi

  return 1
}

install_gh_linux() {
  local answer
  write_warn_line "GitHub CLI (gh) is required to list repositories, including private ones."
  read -r -p "Install GitHub CLI now? [Y/N] " answer
  case "$(lower "$answer")" in
    y|yes) ;;
    *) write_error_line "GitHub CLI is required. Operation cancelled."; exit 1 ;;
  esac

  local sudo_prefix
  if ! sudo_prefix="$(get_sudo_prefix)"; then
    write_error_line "Root access or sudo is required to install GitHub CLI automatically on this system."
    exit 1
  fi

  if command -v apt >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    ensure_download_tool || { write_error_line "curl or wget is required to install GitHub CLI automatically."; exit 1; }
    local tmp_key
    tmp_key="$(mktemp)"
    trap 'rm -f "$tmp_key"' RETURN
    if ! download_file "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "$tmp_key"; then
      write_error_line "Failed to download GitHub CLI signing key."
      exit 1
    fi
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix mkdir -p -m 755 /etc/apt/keyrings
      cat "$tmp_key" | $sudo_prefix tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
      $sudo_prefix chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      $sudo_prefix mkdir -p -m 755 /etc/apt/sources.list.d
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $sudo_prefix tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      $sudo_prefix apt update
      $sudo_prefix apt install gh -y
    else
      mkdir -p -m 755 /etc/apt/keyrings
      cat "$tmp_key" > /etc/apt/keyrings/githubcli-archive-keyring.gpg
      chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      mkdir -p -m 755 /etc/apt/sources.list.d
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
      apt update
      apt install gh -y
    fi
    rm -f "$tmp_key"
    trap - RETURN
  elif command -v dnf5 >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix dnf install -y dnf5-plugins
      $sudo_prefix dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
      $sudo_prefix dnf install -y gh --repo gh-cli
    else
      dnf install -y dnf5-plugins
      dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
      dnf install -y gh --repo gh-cli
    fi
  elif command -v dnf >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix dnf install -y 'dnf-command(config-manager)'
      $sudo_prefix dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      $sudo_prefix dnf install -y gh --repo gh-cli
    else
      dnf install -y 'dnf-command(config-manager)'
      dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      dnf install -y gh --repo gh-cli
    fi
  elif command -v yum >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    if [ -n "$sudo_prefix" ]; then
      if ! command -v yum-config-manager >/dev/null 2>&1; then
        $sudo_prefix yum install -y yum-utils
      fi
      $sudo_prefix yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      $sudo_prefix yum install -y gh
    else
      if ! command -v yum-config-manager >/dev/null 2>&1; then
        yum install -y yum-utils
      fi
      yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      yum install -y gh
    fi
  elif command -v zypper >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix zypper addrepo https://cli.github.com/packages/rpm/gh-cli.repo
      $sudo_prefix zypper ref
      $sudo_prefix zypper --non-interactive install gh
    else
      zypper addrepo https://cli.github.com/packages/rpm/gh-cli.repo
      zypper ref
      zypper --non-interactive install gh
    fi
  elif command -v brew >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    brew install gh
  elif command -v pacman >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix pacman -S --noconfirm github-cli
    else
      pacman -S --noconfirm github-cli
    fi
  elif command -v apk >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix apk add github-cli
    else
      apk add github-cli
    fi
  elif command -v pkg >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix pkg install -y gh
    else
      pkg install -y gh
    fi
  elif command -v xbps-install >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix xbps-install -y github-cli
    else
      xbps-install -y github-cli
    fi
  elif command -v nix-env >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    nix-env -iA nixos.gh
  elif command -v conda >/dev/null 2>&1; then
    write_section "Installing GitHub CLI"
    conda install gh --channel conda-forge -y
  else
    write_error_line "No supported package manager was detected for automatic GitHub CLI installation."
    write_error_line "Install gh manually from https://cli.github.com/ and run the script again."
    exit 1
  fi

  if ! command -v gh >/dev/null 2>&1; then
    write_error_line "GitHub CLI installation completed, but gh is still not available in PATH for this shell."
    write_error_line "Open a new shell or add the correct install location to PATH, then run the script again."
    exit 1
  fi

  write_success_line "GitHub CLI installed successfully."
}

ensure_gh() {
  if command -v gh >/dev/null 2>&1; then
    return 0
  fi
  install_gh_linux
}

ensure_gh_auth() {
  write_section "Checking GitHub authentication"
  if gh auth status --active >/dev/null 2>&1; then
    write_success_line "GitHub authentication is active."
    return 0
  fi
  write_warn_line "GitHub CLI is installed but not authenticated."
  write_warn_line "Interactive GitHub login will start now."
  gh auth login --git-protocol https
  if ! gh auth status --active >/dev/null 2>&1; then
    write_error_line "Authentication did not complete successfully."
    exit 1
  fi
  write_success_line "GitHub authentication is active."
}

get_authenticated_login() {
  local login
  login="$(gh api user --jq .login | tr -d '\r' | tr -d '\n')"
  login="$(trim "$login")"
  if [ -z "$login" ]; then
    write_error_line "Could not determine the authenticated GitHub account."
    exit 1
  fi
  printf '%s' "$login"
}

ensure_git_identity() {
  local login="$1"
  local current_name current_email
  current_name="$(git config --global --get user.name 2>/dev/null || true)"
  current_email="$(git config --global --get user.email 2>/dev/null || true)"
  current_name="$(trim "$current_name")"
  current_email="$(trim "$current_email")"

  if [ -n "$current_name" ] && [ -n "$current_email" ]; then
    return 0
  fi

  write_section "Checking Git identity"

  if [ -z "$current_name" ]; then
    write_warn_line "git user.name is not set."
  else
    write_info_line 'git user.name' "$current_name"
  fi

  if [ -z "$current_email" ]; then
    write_warn_line "git user.email is not set."
  else
    write_info_line 'git user.email' "$current_email"
  fi

  local answer
  read -r -p "Configure missing Git identity values now? [Y/N] " answer
  case "$(lower "$answer")" in
    y|yes) ;;
    *)
      write_error_line "git user.name and user.email must be configured before creating the replacement commit."
      exit 1
      ;;
  esac

  if [ -z "$current_name" ]; then
    local entered_name
    while true; do
      read -r -p "Enter git user.name: " entered_name
      entered_name="$(trim "$entered_name")"
      if [ -n "$entered_name" ]; then
        git config --global user.name "$entered_name"
        current_name="$entered_name"
        break
      fi
      write_warn_line "git user.name cannot be empty."
    done
  fi

  if [ -z "$current_email" ]; then
    local entered_email suggested_email
    suggested_email="${login}@users.noreply.github.com"
    while true; do
      read -r -p "Enter git user.email [$suggested_email]: " entered_email
      entered_email="$(trim "$entered_email")"
      if [ -z "$entered_email" ]; then
        entered_email="$suggested_email"
      fi
      if [[ "$entered_email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
        git config --global user.email "$entered_email"
        current_email="$entered_email"
        break
      fi
      write_warn_line "Please enter a valid email address."
    done
  fi

  write_success_line "Git identity configured."
  write_info_line 'git user.name' "$current_name"
  write_info_line 'git user.email' "$current_email"
}

fetch_repos() {
  local login="$1"
  gh repo list "$login" --limit 1000 --json name,nameWithOwner,isPrivate,defaultBranchRef,isFork,updatedAt,url,visibility --template '{{range .}}{{.nameWithOwner}}{{"\t"}}{{if .isPrivate}}PRIVATE{{else}}PUBLIC{{end}}{{"\t"}}{{if .defaultBranchRef}}{{.defaultBranchRef.name}}{{else}}-{{end}}{{"\t"}}{{if .isFork}}fork{{else}}source{{end}}{{"\t"}}{{slice .updatedAt 0 10}}{{"\t"}}{{.url}}{{"\n"}}{{end}}' | LC_ALL=C sort -f
}

show_repo_table() {
  local -n names_ref=$1
  local -n vis_ref=$2
  local -n branch_ref=$3
  local -n kind_ref=$4
  local -n updated_ref=$5

  printf '\n'
  printf '%sAvailable repositories%s\n\n' "$C_CYAN" "$C_RESET"
  printf '%s%3s  %-44s  %-9s  %-14s  %-8s  %-10s%s\n' "$C_WHITE" '#' 'Repository' 'Visibility' 'Branch' 'Kind' 'Updated' "$C_RESET"
  printf '%s%3s  %-44s  %-9s  %-14s  %-8s  %-10s%s\n' "$C_DIM" '---' '--------------------------------------------' '---------' '--------------' '--------' '----------' "$C_RESET"

  local i
  for ((i=0; i<${#names_ref[@]}; i++)); do
    local name="${names_ref[$i]}"
    local vis="${vis_ref[$i]}"
    local branch="${branch_ref[$i]}"
    local kind="${kind_ref[$i]}"
    local updated="${updated_ref[$i]}"
    local row_color="$C_DIM"
    if [ "$vis" = 'PRIVATE' ] || [ "$vis" = 'private' ]; then
      row_color="$C_YELLOW"
    fi
    if [ ${#name} -gt 44 ]; then
      name="${name:0:41}..."
    fi
    if [ ${#branch} -gt 14 ]; then
      branch="${branch:0:11}..."
    fi
    printf '%s%3d  %-44s  %-9s  %-14s  %-8s  %-10s%s\n' "$row_color" "$((i+1))" "$name" "$vis" "$branch" "$kind" "$updated" "$C_RESET"
  done
}

read_repo_selection() {
  local max="$1"
  local raw
  while true; do
    printf '\n'
    read -r -p 'Select the repository number: ' raw
    case "$raw" in
      ''|*[!0-9]*) write_warn_line "Please enter a valid number between 1 and $max." ;;
      *) if [ "$raw" -ge 1 ] && [ "$raw" -le "$max" ]; then printf '%s' "$raw"; return 0; else write_warn_line "Please enter a valid number between 1 and $max."; fi ;;
    esac
  done
}

with_git_prompt_disabled() {
  local old_prompt="${GIT_TERMINAL_PROMPT-__UNSET__}"
  export GIT_TERMINAL_PROMPT=0
  "$@"
  local rc=$?
  if [ "$old_prompt" = '__UNSET__' ]; then
    unset GIT_TERMINAL_PROMPT
  else
    export GIT_TERMINAL_PROMPT="$old_prompt"
  fi
  return $rc
}

try_create_commit() {
  local output rc
  set +e
  output="$("$@" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    return 0
  fi
  case "$output" in
    *'gpg failed to sign the data'*|*'failed to write commit object'*|*'gpg-agent'*)
      write_warn_line "Commit signing failed on the first attempt. Retrying once after a short delay."
      sleep 2
      set +e
      output="$("$@" 2>&1)"
      rc=$?
      set -e
      if [ $rc -eq 0 ]; then
        write_success_line "Commit succeeded on retry."
        return 0
      fi
      write_error_line "$output"
      return $rc
      ;;
    *)
      write_error_line "$output"
      return $rc
      ;;
  esac
}

new_shim_content() {
  local script_path="$1"
  cat <<SH
#!/usr/bin/env sh
exec "$script_path" "\$@"
SH
}

install_self() {
  local current_script_path="$SELF_PATH"
  local current_script_is_file=1
  if [ -z "$current_script_path" ] || [ ! -f "$current_script_path" ]; then
    current_script_is_file=0
  fi

  mkdir -p "$INSTALL_ROOT" "$BIN_ROOT"

  local target_script_path="$INSTALL_ROOT/git-history-reset.sh"
  local shim_path="$BIN_ROOT/git-history-reset"
  local alias_shim_path="$BIN_ROOT/ghr"
  local source_url_file="$INSTALL_ROOT/source-url.txt"
  local effective_source_url="$SOURCE_URL"

  if [ -z "$effective_source_url" ] && [ -f "$source_url_file" ]; then
    effective_source_url="$(tr -d '\r' < "$source_url_file")"
    effective_source_url="$(trim "$effective_source_url")"
  fi

  write_section "Installing script"
  if [ -n "$effective_source_url" ]; then
    write_info_line 'Source URL' "$effective_source_url"
    local temp_file
    temp_file="$(mktemp)"
    download_file "$effective_source_url" "$temp_file" || { write_error_line "Failed to download the script from the source URL."; rm -f "$temp_file"; exit 1; }
    cp "$temp_file" "$target_script_path"
    rm -f "$temp_file"
    printf '%s\n' "$effective_source_url" > "$source_url_file"
  else
    if [ "$current_script_is_file" -ne 1 ]; then
      write_error_line "This install mode needs --source-url when the script is run from stdin or a pipe."
      exit 1
    fi
    write_info_line 'Source file' "$current_script_path"
    local source_full target_full
    source_full="$(cd "$(dirname "$current_script_path")" && pwd -P)/$(basename "$current_script_path")"
    target_full="$(cd "$INSTALL_ROOT" && pwd -P)/git-history-reset.sh"
    if [ "$source_full" != "$target_full" ]; then
      cp "$current_script_path" "$target_script_path"
    fi
  fi

  chmod +x "$target_script_path"
  new_shim_content "$target_script_path" > "$shim_path"
  new_shim_content "$target_script_path" > "$alias_shim_path"
  chmod +x "$shim_path" "$alias_shim_path"

  local path_changed=0
  if ! path_contains_entry "${PATH:-}" "$BIN_ROOT"; then
    if ! grep -Fqs "$BIN_ROOT" <<< "$(printf '%s' "${PATH:-}")"; then
      path_changed=1
    fi
  fi

  write_success_line "Installation completed."
  write_info_line 'Script path' "$target_script_path"
  write_info_line 'Launcher' "$shim_path"
  write_info_line 'Alias' "$alias_shim_path"

  if path_contains_entry "${PATH:-}" "$BIN_ROOT"; then
    write_success_line "'git-history-reset' and 'ghr' are already available through your current PATH."
  else
    write_warn_line "A PATH export may still be required before 'ghr' is available by name in this shell."
  fi

  printf '\n'
  printf 'Run now in this session:\n'
  printf '  export PATH="%s:$PATH" && ghr\n' "$BIN_ROOT"
  printf '  %s\n' "$alias_shim_path"
}

uninstall_self() {
  local shim_path="$BIN_ROOT/git-history-reset"
  local alias_shim_path="$BIN_ROOT/ghr"

  write_section "Uninstalling"

  if [ -f "$shim_path" ]; then
    rm -f "$shim_path"
    write_success_line "Launcher removed."
  else
    write_warn_line "Launcher was not found."
  fi

  if [ -f "$alias_shim_path" ]; then
    rm -f "$alias_shim_path"
    write_success_line "Alias removed."
  else
    write_warn_line "Alias was not found."
  fi

  if [ -d "$INSTALL_ROOT" ]; then
    rm -rf "$INSTALL_ROOT"
    write_success_line "Installed files removed."
  else
    write_warn_line "Install directory was not found."
  fi

  local current_path="${PATH:-}"
  local new_path=""
  local first=1
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    if [ "$entry" = "$BIN_ROOT" ]; then
      continue
    fi
    if [ $first -eq 1 ]; then
      new_path="$entry"
      first=0
    else
      new_path="$new_path:$entry"
    fi
  done < <(get_path_entries "$current_path")
  export PATH="$new_path"

  if [ -d "$BIN_ROOT" ] && [ -z "$(find "$BIN_ROOT" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
    rmdir "$BIN_ROOT" 2>/dev/null || true
  fi

  write_success_line "Uninstall completed."
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --install|--update)
        INSTALL=1
        ;;
      --uninstall)
        UNINSTALL=1
        ;;
      --yes)
        YES=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --push-force)
        PUSH_FORCE=1
        ;;
      --sign)
        SIGN=1
        ;;
      --no-sign)
        NO_SIGN=1
        ;;
      --remove-clone-on-success)
        REMOVE_CLONE_ON_SUCCESS=1
        ;;
      --workspace-root)
        shift
        WORKSPACE_ROOT="$1"
        ;;
      --install-root)
        shift
        INSTALL_ROOT="$1"
        ;;
      --bin-root)
        shift
        BIN_ROOT="$1"
        ;;
      --message)
        shift
        MESSAGE="$1"
        ;;
      --filter)
        shift
        FILTER="$1"
        ;;
      --source-url)
        shift
        SOURCE_URL="$1"
        ;;
      -h|--help)
        cat <<USAGE
Usage: git-history-reset.sh [options]
  --install
  --update
  --uninstall
  --yes
  --dry-run
  --push-force
  --sign
  --no-sign
  --remove-clone-on-success
  --workspace-root <path>
  --install-root <path>
  --bin-root <path>
  --message <text>
  --filter <text>
  --source-url <url>
USAGE
        exit 0
        ;;
      *)
        write_error_line "Unknown argument: $1"
        exit 1
        ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"

  if [ "$INSTALL" -eq 1 ] && [ "$UNINSTALL" -eq 1 ]; then
    write_error_line "Use either --install or --uninstall, not both."
    exit 1
  fi
  if [ "$SIGN" -eq 1 ] && [ "$NO_SIGN" -eq 1 ]; then
    write_error_line "Use either --sign or --no-sign, not both."
    exit 1
  fi

  if [ "$INSTALL" -eq 1 ]; then
    install_self
    exit 0
  fi

  if [ "$UNINSTALL" -eq 1 ]; then
    uninstall_self
    exit 0
  fi

  write_section "Checking tools"
  local git_path
  git_path="$(require_tool git)"
  ensure_gh
  ensure_gh_auth

  write_section "Configuring git credentials"
  if gh auth setup-git >/dev/null 2>&1; then
    write_success_line "git is configured to use GitHub CLI credentials."
  else
    write_warn_line "Could not configure git credentials automatically. Clone and push may still work depending on your environment."
  fi

  write_section "Reading authenticated GitHub account"
  local login
  login="$(get_authenticated_login)"
  write_info_line 'GitHub account' "$login"

  ensure_git_identity "$login"

  write_section "Fetching repositories"
  local repo_lines
  repo_lines="$(fetch_repos "$login")"
  if [ -z "$(trim "$repo_lines")" ]; then
    write_error_line "No repositories were returned for the authenticated account."
    exit 1
  fi

  local -a names visibilities branches kinds updates urls
  while IFS=$'\t' read -r name visibility branch kind updated url; do
    [ -z "$name" ] && continue
    names+=("$name")
    visibilities+=("${visibility:-PUBLIC}")
    branches+=("${branch:--}")
    kinds+=("${kind:-source}")
    updates+=("${updated:--}")
    urls+=("${url:-}")
  done <<< "$repo_lines"

  if [ ${#names[@]} -eq 0 ]; then
    write_error_line "No repositories were returned for the authenticated account."
    exit 1
  fi

  if [ -n "$FILTER" ]; then
    local -a fnames fvis fbranches fkinds fupdates furls
    local i
    for ((i=0; i<${#names[@]}; i++)); do
      if [[ "${names[$i]}" == *"$FILTER"* ]]; then
        fnames+=("${names[$i]}")
        fvis+=("${visibilities[$i]}")
        fbranches+=("${branches[$i]}")
        fkinds+=("${kinds[$i]}")
        fupdates+=("${updates[$i]}")
        furls+=("${urls[$i]}")
      fi
    done
    if [ ${#fnames[@]} -eq 0 ]; then
      write_error_line "No repositories matched filter '$FILTER'."
      exit 1
    fi
    names=("${fnames[@]}")
    visibilities=("${fvis[@]}")
    branches=("${fbranches[@]}")
    kinds=("${fkinds[@]}")
    updates=("${fupdates[@]}")
    urls=("${furls[@]}")
    write_success_line "Found ${#names[@]} matching repositories."
  else
    write_success_line "Found ${#names[@]} repositories."
    printf '\n'
    local typed_filter
    read -r -p 'Filter by name and press Enter to continue, or just press Enter to show all: ' typed_filter
    typed_filter="$(trim "$typed_filter")"
    if [ -n "$typed_filter" ]; then
      local -a fnames fvis fbranches fkinds fupdates furls
      local i
      for ((i=0; i<${#names[@]}; i++)); do
        if [[ "${names[$i]}" == *"$typed_filter"* ]]; then
          fnames+=("${names[$i]}")
          fvis+=("${visibilities[$i]}")
          fbranches+=("${branches[$i]}")
          fkinds+=("${kinds[$i]}")
          fupdates+=("${updates[$i]}")
          furls+=("${urls[$i]}")
        fi
      done
      if [ ${#fnames[@]} -eq 0 ]; then
        write_error_line "No repositories matched filter '$typed_filter'."
        exit 1
      fi
      names=("${fnames[@]}")
      visibilities=("${fvis[@]}")
      branches=("${fbranches[@]}")
      kinds=("${fkinds[@]}")
      updates=("${fupdates[@]}")
      urls=("${furls[@]}")
      write_success_line "Found ${#names[@]} matching repositories."
    fi
  fi

  show_repo_table names visibilities branches kinds updates
  local selection
  selection="$(read_repo_selection "${#names[@]}")"
  local idx=$((selection - 1))

  local full_name="${names[$idx]}"
  local visibility="${visibilities[$idx]}"
  local default_branch="${branches[$idx]}"
  local repo_kind="${kinds[$idx]}"
  local repo_url="${urls[$idx]}"
  local repo_name="${full_name##*/}"
  local clone_url="$repo_url.git"

  local timestamp
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  local workspace_root_full clones_root backups_root clone_folder_name clone_path bundle_path meta_path
  workspace_root_full="$(mkdir -p "$WORKSPACE_ROOT" && cd "$WORKSPACE_ROOT" && pwd -P)"
  clones_root="$workspace_root_full/clones"
  backups_root="$workspace_root_full/backups"
  clone_folder_name="$(printf '%s' "$full_name" | sed 's/[^a-zA-Z0-9._-]/-/g')-$timestamp"
  clone_path="$clones_root/$clone_folder_name"
  bundle_path="$backups_root/$clone_folder_name.bundle"
  meta_path="$backups_root/$clone_folder_name.txt"

  write_section "Plan"
  write_info_line 'Repository' "$full_name"
  write_info_line 'Visibility' "$visibility"
  write_info_line 'Kind' "$repo_kind"
  write_info_line 'Default branch' "$default_branch"
  write_info_line 'Remote' "$clone_url"
  write_info_line 'Clone path' "$clone_path"
  write_info_line 'Backup' "$bundle_path"
  write_info_line 'Commit message' "$MESSAGE"
  write_info_line 'Dry run' "$( [ "$DRY_RUN" -eq 1 ] && printf 'yes' || printf 'no' )"
  write_info_line 'Push after reset' "$( [ "$PUSH_FORCE" -eq 1 ] && printf 'yes (automatic)' || printf 'ask for YES' )"
  write_info_line 'Cleanup clone' "$( [ "$REMOVE_CLONE_ON_SUCCESS" -eq 1 ] && printf 'yes' || printf 'no' )"

  printf '\n'
  write_warn_line "This script clones the selected repository into a dedicated workspace, rewrites its Git history into a single new commit, and can optionally push the rewritten history back to GitHub."
  write_warn_line "GitHub issues, pull requests, releases, and other platform data are not deleted by this script."

  if [ "$DRY_RUN" -eq 1 ]; then
    write_success_line "Dry run completed. Nothing was changed."
    exit 0
  fi

  if [ "$YES" -ne 1 ]; then
    printf '\n'
    local confirmation
    read -r -p 'Type RESET to continue: ' confirmation
    if [ "$(upper="$(printf '%s' "$confirmation" | tr '[:lower:]' '[:upper:]')"; printf '%s' "$upper")" != 'RESET' ]; then
      write_error_line "Operation cancelled."
      exit 1
    fi
  fi

  write_section "Preparing workspace"
  mkdir -p "$clones_root" "$backups_root"
  rm -rf "$clone_path"

  write_section "Cloning repository"
  with_git_prompt_disabled gh repo clone "$full_name" "$clone_path"
  write_success_line "Clone completed."

  cd "$clone_path"

  write_section "Creating backup"
  local head_before
  head_before="$(git rev-parse HEAD 2>/dev/null || true)"
  git bundle create "$bundle_path" --all >/dev/null
  {
    printf 'repo_name=%s\n' "$repo_name"
    printf 'full_name=%s\n' "$full_name"
    printf 'default_branch=%s\n' "$default_branch"
    printf 'remote_url=%s\n' "$clone_url"
    printf 'old_head=%s\n' "$head_before"
    printf 'created_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$meta_path"
  write_success_line "Backup created."
  write_info_line 'Bundle' "$bundle_path"
  write_info_line 'Metadata' "$meta_path"

  write_section "Rewriting history"
  local current_branch
  current_branch="$(git branch --show-current | tr -d '\r')"
  current_branch="$(trim "$current_branch")"
  if [ -z "$current_branch" ] || [ "$current_branch" = '-' ]; then
    current_branch="$default_branch"
  fi
  if [ -z "$current_branch" ] || [ "$current_branch" = '-' ]; then
    write_error_line "Could not determine the current branch."
    exit 1
  fi

  write_info_line 'Current branch' "$current_branch"
  local temp_branch="ghr-reset-$timestamp"

  local user_name user_email commit_gpgsign gpg_format signing_key
  user_name="$(git config --get user.name 2>/dev/null || true)"
  user_email="$(git config --get user.email 2>/dev/null || true)"
  commit_gpgsign="$(git config --get commit.gpgsign 2>/dev/null || true)"
  gpg_format="$(git config --get gpg.format 2>/dev/null || true)"
  signing_key="$(git config --get user.signingkey 2>/dev/null || true)"

  [ -n "$user_name" ] && write_info_line 'Commit name' "$user_name" || write_warn_line "git user.name is not set in your Git config."
  [ -n "$user_email" ] && write_info_line 'Commit email' "$user_email" || write_warn_line "git user.email is not set in your Git config."

  local sign_mode='inherit'
  [ "$SIGN" -eq 1 ] && sign_mode='force-sign'
  [ "$NO_SIGN" -eq 1 ] && sign_mode='force-no-sign'
  write_info_line 'Signing mode' "$sign_mode"
  write_info_line 'commit.gpgsign' "${commit_gpgsign:-'(not set)'}"
  write_info_line 'gpg.format' "${gpg_format:-'(not set)'}"
  write_info_line 'Signing key' "${signing_key:-'(not set)'}"

  write_step_line 'Creating orphan branch'
  git checkout --orphan "$temp_branch"

  write_step_line 'Staging files'
  git add --all

  write_step_line 'Checking staged changes'
  set +e
  git diff --cached --quiet
  local diff_exit=$?
  set -e
  if [ $diff_exit -ne 0 ] && [ $diff_exit -ne 1 ]; then
    write_error_line "git diff --cached --quiet failed with exit code $diff_exit."
    exit 1
  fi

  write_step_line 'Creating commit'
  local -a commit_cmd
  commit_cmd=(git commit)
  [ "$SIGN" -eq 1 ] && commit_cmd+=(-S)
  [ "$NO_SIGN" -eq 1 ] && commit_cmd+=(--no-gpg-sign)
  [ $diff_exit -eq 0 ] && commit_cmd+=(--allow-empty)
  commit_cmd+=(-m "$MESSAGE")
  try_create_commit "${commit_cmd[@]}"

  write_step_line 'Replacing original branch'
  git branch -M "$current_branch"

  local new_head new_commit_count full_head
  new_head="$(git rev-parse --short HEAD | tr -d '\r')"
  new_commit_count="$(git rev-list --count HEAD | tr -d '\r')"
  full_head="$(git rev-parse HEAD | tr -d '\r')"

  write_success_line "History rewrite completed."
  write_info_line 'Branch' "$current_branch"
  write_info_line 'New HEAD' "$new_head"
  write_info_line 'Commits now' "$new_commit_count"

  local should_push=0
  if [ "$PUSH_FORCE" -eq 1 ]; then
    should_push=1
  else
    write_section "Push confirmation"
    write_warn_line "This will push the rewritten history to GitHub using --force-with-lease."
    local push_confirmation push_value
    read -r -p 'Type YES to push now: ' push_confirmation
    push_value="$(printf '%s' "$push_confirmation" | tr '[:lower:]' '[:upper:]')"
    if [ "$push_value" = 'YES' ] || [ "$push_value" = 'Y' ]; then
      should_push=1
    else
      write_warn_line "Push skipped."
    fi
  fi

  local commit_web_url=''
  if [ $should_push -eq 1 ]; then
    write_section "Pushing rewritten history"
    with_git_prompt_disabled git push origin "$current_branch" --force-with-lease
    write_success_line "Push completed."
    commit_web_url="${repo_url%/}/commit/$full_head"
  fi

  if [ "$REMOVE_CLONE_ON_SUCCESS" -eq 1 ] && [ $should_push -eq 1 ]; then
    cd "$original_pwd"
    rm -rf "$clone_path"
    write_success_line "Workspace clone removed."
  fi

  write_section "Repository links"
  write_info_line 'Repository URL' "$repo_url"
  if [ -n "$commit_web_url" ]; then
    write_info_line 'Commit URL' "$commit_web_url"
  else
    write_info_line 'Commit URL' '(available after push)'
  fi
  if ! { [ "$REMOVE_CLONE_ON_SUCCESS" -eq 1 ] && [ $should_push -eq 1 ]; }; then
    write_info_line 'Workspace clone' "$clone_path"
  fi
}

original_pwd="$(pwd -P)"
main "$@"
