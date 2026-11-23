#!/usr/bin/env bash
# Set up this computer for AI coding agents. Run it yourself, in your own
# terminal, not from an agent: it installs into your home folder and writes
# Claude Code's settings, which a sandboxed agent can't do.
#
# It only adds what's missing, and never overwrites a file that differs from
# what it would write: it writes a proposed copy next to it and tells you.
# Re-running it is safe. It never uses sudo; it tells you what to install.
#
# Usage: scripts/setup-dev-machine.sh [step...]
#   steps: tools skills aws claude   (default: all, in that order)
# Reads config.local/machine.env; see config/machine.env.example.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
config=${DEV_MACHINE_CONFIG:-$repo/config.local/machine.env}
[[ -f $config ]] || { echo "Missing $config. Copy config/machine.env.example there and fill it in."; exit 1; }
set -a; source "$config"; set +a

bin=$HOME/.local/bin
todo=()   # things the person has to do by hand, printed at the end
say() { printf '%-7s %s\n' "$1" "$2"; }

# Write $2 to file $1 unless it's already identical. If $1 exists and differs,
# write $1.proposed instead and add a to-do.
put_file() {
  local file=$1 content=$2
  mkdir -p "$(dirname "$file")"
  if [[ ! -e $file ]]; then
    printf '%s' "$content" > "$file"; chmod 600 "$file"; say wrote "$file"
  elif [[ "$(cat "$file")" == "${content%$'\n'}" ]]; then
    say ok "$file"
  else
    printf '%s' "$content" > "$file.proposed"; chmod 600 "$file.proposed"
    say differs "$file (proposed version in $file.proposed)"
    todo+=("Compare $file with $file.proposed: diff $file $file.proposed")
  fi
}

step_tools() {
  mkdir -p "$bin"
  case ":$PATH:" in *":$bin:"*) ;; *) todo+=("Add $bin to your PATH, then open a new terminal");; esac
  export PATH="$bin:$PATH"

  local missing=()
  for c in git curl unzip bwrap socat; do command -v "$c" >/dev/null || missing+=("$c"); done
  if ((${#missing[@]})); then
    local pkgs=${missing[*]}; pkgs=${pkgs/bwrap/bubblewrap}
    say missing "${missing[*]}"; todo+=("Install system packages: sudo apt install $pkgs")
  else say ok "git, curl, unzip, bubblewrap, socat"; fi

  # Node.js: the official build, checked against nodejs.org's published checksums, under ~/.local.
  local have=0; command -v node >/dev/null && have=$(node -p 'process.versions.node.split(".")[0]')
  if ((have >= NODE_MAJOR)); then say ok "node $(node --version)"; else
    local d f; d=$(mktemp -d)
    local base=https://nodejs.org/dist/latest-v$NODE_MAJOR.x
    curl -fsSL -o "$d/SHASUMS256.txt" "$base/SHASUMS256.txt"
    f=$(grep -o "node-v$NODE_MAJOR[^ ]*-linux-x64.tar.xz" "$d/SHASUMS256.txt")
    curl -fsSL -o "$d/$f" "$base/$f"
    (cd "$d" && grep " $f\$" SHASUMS256.txt | sha256sum -c --quiet)
    mkdir -p "$HOME/.local/opt"; tar -xJf "$d/$f" -C "$HOME/.local/opt"
    ln -sfn "$HOME/.local/opt/${f%.tar.xz}" "$HOME/.local/opt/node"
    for b in node npm npx corepack; do ln -sfn "$HOME/.local/opt/node/bin/$b" "$bin/$b"; done
    rm -rf "$d"; say installed "node $(node --version)"
  fi

  # npm installs global packages into ~/.local, so they need no sudo and land on PATH.
  if [[ $(npm config get prefix) != "$HOME/.local" ]]; then npm config set prefix "$HOME/.local"; say set "npm prefix ~/.local"; else say ok "npm prefix ~/.local"; fi

  if command -v openspec >/dev/null; then say ok "openspec $(openspec --version)"; else
    npm install -g @fission-ai/openspec >/dev/null; say installed "openspec $(openspec --version)"; fi

  # AWS CLI v2, installed for this user only.
  if command -v aws >/dev/null; then say ok "$(aws --version)"; else
    local d; d=$(mktemp -d)
    curl -fsSL -o "$d/awscliv2.zip" https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
    unzip -q "$d/awscliv2.zip" -d "$d"
    "$d/aws/install" -i "$HOME/.local/aws-cli" -b "$bin" >/dev/null
    rm -rf "$d"; say installed "$(aws --version)"
  fi

  if command -v gh >/dev/null; then say ok "$(gh --version | head -1)"; else
    say missing gh; todo+=("Install the GitHub CLI: https://github.com/cli/cli#installation"); fi
  if command -v claude >/dev/null; then say ok "claude $(claude --version 2>/dev/null | head -1)"; else
    say missing claude; todo+=("Install Claude Code: https://code.claude.com/docs/en/setup"); fi
}

# Link each skill folder into ~/.agents/skills, and from there into ~/.claude/skills.
link_skill() {
  local src=$1 n; n=$(basename "$src")
  mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills"
  local a=$HOME/.agents/skills/$n c=$HOME/.claude/skills/$n
  if [[ -L $a && $(readlink "$a") == "$src" ]]; then :; elif [[ -e $a || -L $a ]]; then
    todo+=("$a exists and isn't a link to $src; move it aside and re-run"); say differs "$a"; return
  else ln -s "$src" "$a"; fi
  if [[ -L $c && $(readlink "$c") == "../../.agents/skills/$n" ]]; then say ok "skill $n"; elif [[ -e $c || -L $c ]]; then
    todo+=("$c exists and isn't a link to ~/.agents/skills/$n; move it aside and re-run"); say differs "$c"
  else ln -s "../../.agents/skills/$n" "$c"; say linked "skill $n"; fi
}

step_skills() {
  local dir=$FACTORY_SKILLS_DIR
  if [[ ! -d $dir/.git ]]; then
    if git clone -q "$FACTORY_SKILLS_REPO" "$dir"; then say cloned "$dir"; else
      say failed "clone $FACTORY_SKILLS_REPO"; todo+=("Sign in to GitHub (RUNBOOK.md step 2), then re-run: $0 skills"); return; fi
  fi
  for s in "$dir"/skills/*/; do link_skill "${s%/}"; done
  link_skill "$repo/skills/dev-machine-setup"
}

step_aws() {
  # Your admin profile, named "admin" so its token file name is known in advance.
  local cfg=$HOME/.aws/config
  if grep -q '^\[profile admin\]' "$cfg" 2>/dev/null; then say ok "$cfg has profile admin"; else
    mkdir -p "$HOME/.aws"
    cat >> "$cfg" <<EOF
[profile admin]
sso_session = admin
sso_account_id = $ADMIN_ACCOUNT_ID
sso_role_name = $ADMIN_ROLE
region = $AWS_REGION

[sso-session admin]
sso_start_url = $SSO_START_URL
sso_region = $SSO_REGION
sso_registration_scopes = sso:account:access
EOF
    chmod 600 "$cfg"; say wrote "profile admin in $cfg"
  fi

  # The agents' own config file; Claude Code's settings point agents at it.
  put_file "$HOME/.aws/agent-config" "# AWS config for agent sessions only. Written by dev-machine's setup-dev-machine.sh.
# Sign in as the agent user with: AWS_CONFIG_FILE=~/.aws/agent-config aws sso login --sso-session agent --no-browser

[sso-session agent]
sso_start_url = $SSO_START_URL
sso_region = $SSO_REGION
sso_registration_scopes = sso:account:access

[profile agent-builder]
sso_session = agent
sso_account_id = $AGENT_ACCOUNT_ID
sso_role_name = $BUILDER_ROLE
region = $AWS_REGION

[profile agent-viewonly]
sso_session = agent
sso_account_id = $AGENT_ACCOUNT_ID
sso_role_name = $READONLY_ROLE
region = $AWS_REGION
"
}

step_claude() {
  local want; want=$(node "$repo/scripts/render-claude-settings.mjs")
  local file=$HOME/.claude/settings.json
  # Compare as JSON, so formatting differences don't count.
  if [[ -f $file ]] && node -e '
      const fs=require("fs"); const a=JSON.parse(fs.readFileSync(process.argv[1]));
      const b=JSON.parse(process.argv[2]); process.exit(JSON.stringify(a)===JSON.stringify(b)?0:1)' "$file" "$want" 2>/dev/null
  then say ok "$file"; else put_file "$file" "$want"; fi
  todo+=("Restart Claude Code so it picks up its settings")
}

steps=("$@"); ((${#steps[@]})) || steps=(tools skills aws claude)
for s in "${steps[@]}"; do
  case $s in tools|skills|aws|claude) echo "== $s"; "step_$s";; *) echo "Unknown step: $s"; exit 2;; esac
done

if ((${#todo[@]})); then
  echo; echo "Still to do:"; for t in "${todo[@]}"; do echo "  - $t"; done
fi
echo; echo "Next: the sign-in steps in RUNBOOK.md, then ask Claude to run scripts/check-dev-machine.sh."
