#!/usr/bin/env bash
# --- Omasync Shared Library ---
# Sourced by omasync and omasync-setup. Do NOT execute directly.

# =============================================================================
# XDG Paths & Defaults
# =============================================================================

OMASYNC_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omablue/omasync"
OMASYNC_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omablue/omasync"

LOG_DIR="$OMASYNC_DATA_DIR/logs"
DEFAULT_SSH_DIR="$HOME/.ssh"
RSYNC_BASE_FLAGS="-avzh --progress --partial"
DRY_RUN="false"
LOG_KEEP_COUNT=10

# =============================================================================
# Output Helpers
# =============================================================================

msg()  { printf '%s\n' "$1"; }
err()  { printf '[ERROR] %s\n' "$1" >&2; }
die()  { err "$1"; exit 1; }

oma_notify() {
  local title="$1" body="${2:-}" urgency="${3:-normal}"
  notify-send -a "Omasync" -u "$urgency" "$title" "$body" 2>/dev/null || true
}

oma_notify_err() { oma_notify "$1" "${2:-}" critical; }

# =============================================================================
# Dependency Check
# =============================================================================

check_dependencies() {
  local missing=()
  for cmd in ssh rsync rofi notify-send; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -gt 0 ]] && die "Required tools not found: ${missing[*]}"
}

# =============================================================================
# Directory & Config Init
# =============================================================================

ensure_dirs() {
  mkdir -p "$OMASYNC_CONFIG_DIR"/{devices,profiles,links}
  mkdir -p "$OMASYNC_DATA_DIR/logs"
  mkdir -p "${DEFAULT_SSH_DIR:-$HOME/.ssh}"
  chmod 700 "${DEFAULT_SSH_DIR:-$HOME/.ssh}"
}

generate_default_config() {
  local config="$OMASYNC_CONFIG_DIR/omasync.conf"
  [[ -f "$config" ]] && return 0

  cat > "$config" << 'CONF'
# omasync — Global Configuration

LOG_DIR="$HOME/.local/share/omablue/omasync/logs"
DEFAULT_SSH_DIR="$HOME/.ssh"
RSYNC_BASE_FLAGS="-avzh --progress --partial"
DRY_RUN="false"
LOG_KEEP_COUNT=10
CONF
}

# =============================================================================
# Config Loading (safe whitelist-only parsing — no source/eval)
# =============================================================================

_parse_value() {
  local val="$1"
  val="${val#\"}" ; val="${val%\"}"
  val="${val#\'}" ; val="${val%\'}"
  val="${val//\$HOME/$HOME}"
  printf '%s' "$val"
}

load_global_config() {
  local config="$OMASYNC_CONFIG_DIR/omasync.conf"
  [[ -f "$config" ]] || { err "Global config not found: $config"; return 1; }

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(_parse_value "$(echo "$value" | xargs)")
    case "$key" in
      LOG_DIR)          LOG_DIR="$value" ;;
      DEFAULT_SSH_DIR)  DEFAULT_SSH_DIR="$value" ;;
      RSYNC_BASE_FLAGS) RSYNC_BASE_FLAGS="$value" ;;
      DRY_RUN)          [[ "$value" =~ ^(true|false)$ ]] && DRY_RUN="$value" ;;
      LOG_KEEP_COUNT)   [[ "$value" =~ ^[0-9]+$ ]] && LOG_KEEP_COUNT="$value" ;;
    esac
  done < "$config"
}

load_device() {
  local name="$1"
  local conf="$OMASYNC_CONFIG_DIR/devices/${name}.conf"
  [[ -f "$conf" ]] || { err "Device not found: $name"; return 1; }

  DEVICE_NAME="" DEVICE_HOST="" DEVICE_PORT="22"
  DEVICE_USER="" DEVICE_KEY="" DEVICE_TYPE="linux" DEVICE_TAILSCALE="false"

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(_parse_value "$(echo "$value" | xargs)")
    case "$key" in
      DEVICE_NAME)      DEVICE_NAME="$value" ;;
      DEVICE_HOST)      DEVICE_HOST="$value" ;;
      DEVICE_PORT)      [[ "$value" =~ ^[0-9]+$ ]] && DEVICE_PORT="$value" ;;
      DEVICE_USER)      DEVICE_USER="$value" ;;
      DEVICE_KEY)       DEVICE_KEY="$value" ;;
      DEVICE_TYPE)      [[ "$value" =~ ^(termux|linux|macos)$ ]] && DEVICE_TYPE="$value" ;;
      DEVICE_TAILSCALE) [[ "$value" =~ ^(true|false)$ ]] && DEVICE_TAILSCALE="$value" ;;
    esac
  done < "$conf"

  [[ -n "$DEVICE_NAME" ]] || { err "Device $name: missing DEVICE_NAME"; return 1; }
  [[ -n "$DEVICE_HOST" ]] || { err "Device $name: missing DEVICE_HOST"; return 1; }
  [[ -n "$DEVICE_USER" ]] || { err "Device $name: missing DEVICE_USER"; return 1; }
}

load_profile() {
  local name="$1"
  local conf="$OMASYNC_CONFIG_DIR/profiles/${name}.conf"
  [[ -f "$conf" ]] || { err "Profile not found: $name"; return 1; }

  PROFILE_NAME="" LOCAL_PATH="" REMOTE_PATH=""
  DIRECTION="push" RSYNC_EXCLUDE="" RSYNC_DELETE="false" DEVICE_ID=""

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(_parse_value "$(echo "$value" | xargs)")
    case "$key" in
      PROFILE_NAME)  PROFILE_NAME="$value" ;;
      LOCAL_PATH)    LOCAL_PATH="$value" ;;
      REMOTE_PATH)   REMOTE_PATH="$value" ;;
      DIRECTION)     [[ "$value" =~ ^(push|pull|both)$ ]] && DIRECTION="$value" ;;
      RSYNC_EXCLUDE) RSYNC_EXCLUDE="$value" ;;
      RSYNC_DELETE)  [[ "$value" =~ ^(true|false)$ ]] && RSYNC_DELETE="$value" ;;
      DEVICE_ID)     DEVICE_ID="$value" ;;
    esac
  done < "$conf"

  [[ -n "$PROFILE_NAME" ]] || { err "Profile $name: missing PROFILE_NAME"; return 1; }
  [[ -n "$LOCAL_PATH" ]]   || { err "Profile $name: missing LOCAL_PATH"; return 1; }
  # REMOTE_PATH is optional for base profiles (no DEVICE_ID)
  [[ -z "$DEVICE_ID" ]] || [[ -n "$REMOTE_PATH" ]] || { err "Profile $name: missing REMOTE_PATH"; return 1; }
}

# Load a device-profile link: merges base profile + link overrides.
# Caller gets PROFILE_NAME, LOCAL_PATH, REMOTE_PATH, DIRECTION, RSYNC_EXCLUDE, RSYNC_DELETE set.
load_link() {
  local device_id="$1" profile_id="$2"
  local link_conf="$OMASYNC_CONFIG_DIR/links/${device_id}--${profile_id}.conf"
  local base_conf="$OMASYNC_CONFIG_DIR/profiles/${profile_id}.conf"
  [[ -f "$link_conf" ]] || { err "Link not found: ${device_id}--${profile_id}"; return 1; }
  [[ -f "$base_conf" ]] || { err "Base profile not found: ${profile_id}"; return 1; }

  # Load base profile first
  PROFILE_NAME="" LOCAL_PATH="" REMOTE_PATH=""
  DIRECTION="push" RSYNC_EXCLUDE="" RSYNC_DELETE="false" DEVICE_ID=""
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(_parse_value "$(echo "$value" | xargs)")
    case "$key" in
      PROFILE_NAME)  PROFILE_NAME="$value" ;;
      LOCAL_PATH)    LOCAL_PATH="$value" ;;
      DIRECTION)     [[ "$value" =~ ^(push|pull|both)$ ]] && DIRECTION="$value" ;;
      RSYNC_EXCLUDE) RSYNC_EXCLUDE="$value" ;;
      RSYNC_DELETE)  [[ "$value" =~ ^(true|false)$ ]] && RSYNC_DELETE="$value" ;;
    esac
  done < "$base_conf"

  # Apply link overrides (REMOTE_PATH required; DIRECTION/EXCLUDE/DELETE optional)
  local LINK_DEVICE="" LINK_PROFILE="" LINK_REMOTE="" LINK_DIR="" LINK_EXCL="" LINK_DEL=""
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key=$(echo "$key" | xargs)
    value=$(_parse_value "$(echo "$value" | xargs)")
    case "$key" in
      REMOTE_PATH)   LINK_REMOTE="$value" ;;
      DIRECTION)     [[ "$value" =~ ^(push|pull|both)$ ]] && LINK_DIR="$value" ;;
      RSYNC_EXCLUDE) LINK_EXCL="$value" ;;
      RSYNC_DELETE)  [[ "$value" =~ ^(true|false)$ ]] && LINK_DEL="$value" ;;
    esac
  done < "$link_conf"

  [[ -n "$LINK_REMOTE" ]] || { err "Link ${device_id}--${profile_id}: missing REMOTE_PATH"; return 1; }
  REMOTE_PATH="$LINK_REMOTE"
  DEVICE_ID="$device_id"
  [[ -n "$LINK_DIR" ]]  && DIRECTION="$LINK_DIR"
  [[ -n "$LINK_EXCL" ]] && RSYNC_EXCLUDE="$LINK_EXCL"
  [[ -n "$LINK_DEL" ]]  && RSYNC_DELETE="$LINK_DEL"
  [[ -n "$PROFILE_NAME" ]] || { err "Base profile $profile_id: missing PROFILE_NAME"; return 1; }
  [[ -n "$LOCAL_PATH" ]]   || { err "Base profile $profile_id: missing LOCAL_PATH"; return 1; }
}

# =============================================================================
# Listing Helpers
# =============================================================================

list_devices() {
  local dir="$OMASYNC_CONFIG_DIR/devices"
  [[ -d "$dir" ]] || return 1
  local files=("$dir"/*.conf)
  [[ -e "${files[0]}" ]] || return 1
  for f in "${files[@]}"; do basename "$f" .conf; done
}

list_profiles() {
  local dir="$OMASYNC_CONFIG_DIR/profiles"
  [[ -d "$dir" ]] || return 1
  local files=("$dir"/*.conf)
  [[ -e "${files[0]}" ]] || return 1
  for f in "${files[@]}"; do basename "$f" .conf; done
}

list_device_profiles() {
  local device="$1"
  local dir="$OMASYNC_CONFIG_DIR/profiles"
  [[ -d "$dir" ]] || return 1
  local files=("$dir/${device}-"*.conf)
  [[ -e "${files[0]}" ]] || return 1
  for f in "${files[@]}"; do basename "$f" .conf; done
}

# List base profiles: profiles/ files with no DEVICE_ID (reusable templates)
list_base_profiles() {
  local dir="$OMASYNC_CONFIG_DIR/profiles"
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*.conf; do
    [[ -f "$f" ]] || continue
    local dev_id=""
    while IFS='=' read -r k v; do
      [[ "$k" =~ ^[[:space:]]*# ]] && continue
      k=$(echo "$k" | xargs)
      if [[ "$k" == "DEVICE_ID" ]]; then
        v=$(_parse_value "$(echo "$v" | xargs)")
        dev_id="$v"
        break
      fi
    done < "$f"
    [[ -z "$dev_id" ]] && basename "$f" .conf
  done
}

# List profile IDs linked to a device (from links/ dir)
list_links_for_device() {
  local device_id="$1"
  local dir="$OMASYNC_CONFIG_DIR/links"
  [[ -d "$dir" ]] || return 0
  for f in "$dir/${device_id}--"*.conf; do
    [[ -f "$f" ]] || continue
    local base; base=$(basename "$f" .conf)
    echo "${base#${device_id}--}"
  done
}

sanitize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-_'
}

# =============================================================================
# SSH Helpers
# =============================================================================

test_connection() {
  local name="$1"
  load_device "$name" || return 1

  local opts=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  [[ -n "$DEVICE_KEY" && -f "$DEVICE_KEY" ]] && opts+=(-i "$DEVICE_KEY")
  opts+=(-p "$DEVICE_PORT")

  ssh "${opts[@]}" "${DEVICE_USER}@${DEVICE_HOST}" exit 2>/dev/null
}

generate_device_key() {
  local device_name="$1"
  local key_path="${DEFAULT_SSH_DIR}/omasync_${device_name}"

  if [[ -f "$key_path" ]]; then
    echo "$key_path"
    return 0
  fi

  ssh-keygen -t ed25519 -f "$key_path" -N "" -C "omasync@${device_name}" -q
  chmod 600 "$key_path"
  chmod 644 "${key_path}.pub"
  echo "$key_path"
}

# =============================================================================
# Tailscale & Network Discovery
# =============================================================================

is_tailscale_available() {
  command -v tailscale &>/dev/null && tailscale status &>/dev/null 2>&1
}

scan_tailscale_peers() {
  command -v jq &>/dev/null || return 1
  tailscale status --json 2>/dev/null | \
    jq -r '.Peer[] | select(.Online == true) | "\(.HostName)\t\(.TailscaleIPs[0])\t\(.OS)"' 2>/dev/null
}

get_local_subnet() {
  local conn
  conn=$(nmcli -t -f NAME connection show --active 2>/dev/null | head -1) || return 1
  nmcli -g IP4.ADDRESS connection show "$conn" 2>/dev/null | head -1
}

scan_lan_hosts() {
  local -a ips
  # Get IPv4 addresses only from ARP table (both REACHABLE and STALE)
  mapfile -t ips < <(ip neigh show 2>/dev/null | \
    grep -E 'REACHABLE|STALE' | \
    awk '{print $1}' | \
    grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | \
    sort -u)

  [[ ${#ips[@]} -eq 0 ]] && return 0

  for ip in "${ips[@]}"; do
    for port in 22 8022; do
      timeout 1 bash -c "echo > /dev/tcp/${ip}/${port}" 2>/dev/null && {
        printf '%s\t%s\n' "$ip" "$port"
        break
      }
    done
  done
}

check_ssh_key_installed() {
  local key="$1" user="$2" host="$3" port="$4"
  local opts=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new
              -p "$port" -i "$key")
  ssh "${opts[@]}" "${user}@${host}" exit 2>/dev/null
}

resolve_host() {
  local name="$1"
  load_device "$name" || return 1

  local resolved="$DEVICE_HOST"

  if [[ "$DEVICE_TAILSCALE" == "true" ]] && \
     [[ ! "$DEVICE_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && \
     command -v tailscale &>/dev/null; then

    local ts_ip
    ts_ip=$(tailscale ip "$DEVICE_HOST" 2>/dev/null | head -1) || true

    if [[ -z "$ts_ip" ]] && command -v jq &>/dev/null; then
      ts_ip=$(tailscale status --json 2>/dev/null | \
        jq -r --arg n "$DEVICE_HOST" \
        '.Peer[] | select(.HostName == $n) | .TailscaleIPs[0]' 2>/dev/null) || true
      [[ "$ts_ip" == "null" ]] && ts_ip=""
    fi

    [[ -n "$ts_ip" ]] && resolved="$ts_ip"
  fi

  echo "$resolved"
}

# =============================================================================
# Rsync Command Builder
# =============================================================================

build_rsync_cmd() {
  local device="$1" profile="$2" direction_override="${3:-}"

  load_device "$device" || return 1
  load_profile "$profile" || return 1

  local direction="${direction_override:-$DIRECTION}"
  local host
  host=$(resolve_host "$device")

  local socket_dir="/tmp/omasync-${USER}"
  mkdir -p "$socket_dir" && chmod 700 "$socket_dir"

  local ssh_cmd="ssh -p ${DEVICE_PORT}"
  [[ -n "$DEVICE_KEY" && -f "$DEVICE_KEY" ]] && ssh_cmd+=" -i ${DEVICE_KEY}"
  ssh_cmd+=" -o ControlMaster=auto"
  ssh_cmd+=" -o ControlPath=${socket_dir}/%r@%h:%p"
  ssh_cmd+=" -o ControlPersist=600"
  ssh_cmd+=" -o ServerAliveInterval=30"
  ssh_cmd+=" -o ServerAliveCountMax=3"
  ssh_cmd+=" -o Compression=no"

  local -a flags
  IFS=' ' read -ra flags <<< "$RSYNC_BASE_FLAGS"

  if [[ -n "$RSYNC_EXCLUDE" ]]; then
    IFS=',' read -ra excludes <<< "$RSYNC_EXCLUDE"
    for pattern in "${excludes[@]}"; do
      pattern=$(echo "$pattern" | xargs)
      [[ -n "$pattern" ]] && flags+=(--exclude="$pattern")
    done
  fi

  [[ "$RSYNC_DELETE" == "true" && "$direction" != "both" ]] && flags+=(--delete)
  [[ "$direction" == "both" ]] && flags+=(--update)
  [[ "$DRY_RUN" == "true" ]] && flags+=(--dry-run)

  local remote="${DEVICE_USER}@${host}:${REMOTE_PATH}/"
  local local_path="${LOCAL_PATH}/"

  RSYNC_CMD_FLAGS=("${flags[@]}")
  RSYNC_CMD_SSH="$ssh_cmd"

  case "$direction" in
    push) RSYNC_CMD_PAIRS=("$local_path" "$remote") ;;
    pull) RSYNC_CMD_PAIRS=("$remote" "$local_path") ;;
    both) RSYNC_CMD_PAIRS=("$remote" "$local_path" "$local_path" "$remote") ;;
  esac
}

# =============================================================================
# Sync Execution & Logging
# =============================================================================

execute_sync() {
  local device="$1" profile="$2"
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local log_file="${LOG_DIR}/${device}_${profile}_${timestamp}.log"

  mkdir -p "$LOG_DIR"
  build_rsync_cmd "$device" "$profile" || return 1

  local exit_code=0 i=0
  local pair_count=${#RSYNC_CMD_PAIRS[@]}

  while [[ $i -lt $pair_count ]]; do
    local src="${RSYNC_CMD_PAIRS[$i]}"
    local dest="${RSYNC_CMD_PAIRS[$((i+1))]}"
    ((i+=2))

    printf '$ rsync %s -e "%s" "%s" "%s"\n\n' \
      "${RSYNC_CMD_FLAGS[*]}" "$RSYNC_CMD_SSH" "$src" "$dest" | tee -a "$log_file"

    rsync "${RSYNC_CMD_FLAGS[@]}" -e "$RSYNC_CMD_SSH" "$src" "$dest" 2>&1 | tee -a "$log_file"
    local rc=${PIPESTATUS[0]}

    if [[ $rc -ne 0 ]]; then
      exit_code=$rc
      printf '[ERROR] rsync exited with code %d\n' "$rc" | tee -a "$log_file"
    fi
  done

  if [[ $exit_code -eq 0 ]]; then
    date -Iseconds > "$OMASYNC_DATA_DIR/${device}_${profile}.last_sync"
  fi

  rotate_logs "$device" "$profile"
  return $exit_code
}

# =============================================================================
# Log Rotation & Last-Sync Tracking
# =============================================================================

rotate_logs() {
  local device="$1" profile="$2"
  local count=${LOG_KEEP_COUNT:-10}
  local -a logs
  mapfile -t logs < <(ls -t "${LOG_DIR}/${device}_${profile}_"*.log 2>/dev/null)
  for (( i=count; i<${#logs[@]}; i++ )); do rm -f "${logs[$i]}"; done
}

get_last_sync() {
  local device="$1" profile="${2:-}"
  local ts_file="$OMASYNC_DATA_DIR/${device}${profile:+_${profile}}.last_sync"

  if [[ -z "$profile" ]]; then
    local latest="" latest_time=0
    for f in "$OMASYNC_DATA_DIR/${device}_"*.last_sync; do
      [[ -f "$f" ]] || continue
      local t
      t=$(date -d "$(<"$f")" +%s 2>/dev/null) || continue
      if [[ $t -gt $latest_time ]]; then latest_time=$t; latest="$f"; fi
    done
    ts_file="${latest:-}"
  fi

  [[ -n "$ts_file" && -f "$ts_file" ]] || { echo "never"; return; }

  local ts epoch_then diff
  ts=$(<"$ts_file")
  epoch_then=$(date -d "$ts" +%s 2>/dev/null) || { echo "never"; return; }
  diff=$(( $(date +%s) - epoch_then ))

  if   [[ $diff -lt 60 ]];    then echo "just now"
  elif [[ $diff -lt 3600 ]];  then echo "$((diff/60))m ago"
  elif [[ $diff -lt 86400 ]]; then echo "$((diff/3600))h ago"
  else                              echo "$((diff/86400))d ago"
  fi
}

# =============================================================================
# Save Config Helpers
# =============================================================================

save_device_config() {
  local slug="$1" name="$2" host="$3" port="$4" user="$5" key="$6" type="$7" tailscale="${8:-false}"
  local conf="$OMASYNC_CONFIG_DIR/devices/${slug}.conf"

  cat > "$conf" << EOF
# Device: $name — created $(date +%Y-%m-%d)

DEVICE_NAME="$name"
DEVICE_HOST="$host"
DEVICE_PORT="$port"
DEVICE_USER="$user"
DEVICE_KEY="$key"
DEVICE_TYPE="$type"
DEVICE_TAILSCALE="$tailscale"
EOF
}

save_profile_config() {
  local slug="$1" name="$2" local_path="$3" remote_path="$4" direction="$5" exclude="$6" delete="$7" device_id="${8:-}"
  local conf="$OMASYNC_CONFIG_DIR/profiles/${slug}.conf"

  cat > "$conf" << EOF
# Sync Profile: $name — created $(date +%Y-%m-%d)

PROFILE_NAME="$name"
LOCAL_PATH="$local_path"
REMOTE_PATH="$remote_path"
DIRECTION="$direction"
RSYNC_EXCLUDE="$exclude"
RSYNC_DELETE="$delete"
DEVICE_ID="$device_id"
EOF
}

# Save a base profile (no remote path, no device ID — reusable template)
save_base_profile_config() {
  local slug="$1" name="$2" local_path="$3" direction="$4" exclude="$5" delete="$6"
  local conf="$OMASYNC_CONFIG_DIR/profiles/${slug}.conf"

  cat > "$conf" << EOF
# Base Profile: $name — created $(date +%Y-%m-%d)
# Link this profile to devices via omasync-setup → Manage Device → Link Profile

PROFILE_NAME="$name"
LOCAL_PATH="$local_path"
DIRECTION="$direction"
RSYNC_EXCLUDE="$exclude"
RSYNC_DELETE="$delete"
EOF
}

# Save a link: maps profile_id to device_id with device-specific remote path
save_link_config() {
  local device_id="$1" profile_id="$2" remote_path="$3"
  local direction="${4:-}" exclude="${5:-}" delete="${6:-}"
  mkdir -p "$OMASYNC_CONFIG_DIR/links"
  local conf="$OMASYNC_CONFIG_DIR/links/${device_id}--${profile_id}.conf"

  cat > "$conf" << EOF
# Link: profile '$profile_id' → device '$device_id' — created $(date +%Y-%m-%d)

LINK_DEVICE="$device_id"
LINK_PROFILE="$profile_id"
REMOTE_PATH="$remote_path"
EOF
  # Write optional per-device overrides (empty = inherit from base profile)
  if [[ -n "$direction" ]]; then printf 'DIRECTION="%s"\n'      "$direction" >> "$conf"; fi
  if [[ -n "$exclude" ]];   then printf 'RSYNC_EXCLUDE="%s"\n'  "$exclude"   >> "$conf"; fi
  if [[ -n "$delete" ]];    then printf 'RSYNC_DELETE="%s"\n'   "$delete"    >> "$conf"; fi
  return 0
}

# =============================================================================
# Bootstrap (call on source)
# =============================================================================

omasync_init() {
  check_dependencies
  ensure_dirs
  generate_default_config
  load_global_config
}
