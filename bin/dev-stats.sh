#!/usr/bin/env bash
# dev-stats helper: account discovery and contribution fetching.
#
#   dev-stats.sh list                          -> JSON array of {provider,host,user}
#   dev-stats.sh fetch <provider> <host> <user> [year] -> {provider,host,user,days:{"YYYY-MM-DD":n},years:[..]}
#                                               or {"error":"<code>"}
#
# Uses each platform's own CLI login (gh, glab, tea, fj). It never reads,
# prints or forwards tokens. Output is JSON only; remote error text is never
# echoed, only fixed error codes.
set -uo pipefail
export LC_ALL=C GH_PROMPT_DISABLED=1 NO_COLOR=1 NO_PROMPT=1 GLAB_CHECK_UPDATE=false

CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}"
MANUAL="$CONFIG_ROOT/dev-stats/accounts.json"

valid_host() { [[ ${1:-} =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$ ]]; }
valid_user() { [[ ${1:-} =~ ^[A-Za-z0-9_][A-Za-z0-9_.@-]*$ ]] && ((${#1} <= 64)); }

emit() { jq -cn --arg p "$1" --arg h "$2" --arg u "$3" '{provider:$p,host:$h,user:$u}'; }
fail() { jq -cn --arg e "$1" '{error:$e}'; exit 1; }

# ---------------------------------------------------------------- discovery

detect_github() {
  command -v gh >/dev/null || return 0
  local file="${GH_CONFIG_DIR:-$CONFIG_ROOT/gh}/hosts.yml" host user
  [[ -r $file ]] || return 0
  while read -r host; do
    valid_host "$host" || continue
    user=$(timeout 15 gh api user --hostname "$host" --jq .login 2>/dev/null </dev/null) || continue
    valid_user "$user" && emit github "$host" "$user"
  done < <(grep -E '^[A-Za-z0-9.:-]+:[[:space:]]*$' "$file" | sed 's/:[[:space:]]*$//')
}

detect_gitlab() {
  command -v glab >/dev/null || return 0
  local file="${GLAB_CONFIG_DIR:-$CONFIG_ROOT/glab-cli}/config.yml" host user
  [[ -r $file ]] || return 0
  while read -r host; do
    valid_host "$host" || continue
    user=$(timeout 15 glab api --hostname "$host" user 2>/dev/null </dev/null | jq -r '.username // empty') || continue
    valid_user "$user" && emit gitlab "$host" "$user"
  done < <(awk '/^hosts:/{h=1;next} h&&/^[^ ]/{h=0} h&&/^  [A-Za-z0-9.:-]+:[[:space:]]*$/{gsub(/[ :]*$/,"");gsub(/^ +/,"");print}' "$file")
}

detect_forgejo() {
  local host user url
  # tea (Gitea CLI): `tea login add`
  if command -v tea >/dev/null; then
    while IFS=$'\t' read -r url user; do
      host=${url#*://}; host=${host%%/*}
      valid_host "$host" && valid_user "$user" && emit forgejo "$host" "$user"
    done < <(timeout 15 tea login list --output json 2>/dev/null </dev/null |
      jq -r '.[]? | [(.url // .URL // ""), (.user // .User // "")] | @tsv' 2>/dev/null)
  fi
  # fj (forgejo-cli): `fj auth login`
  local keys="$DATA_ROOT/forgejo-cli/keys.json"
  if [[ -r $keys ]]; then
    while IFS=$'\t' read -r host user; do
      valid_host "$host" && valid_user "$user" && emit forgejo "$host" "$user"
    done < <(jq -r '(.hosts // {}) | to_entries[]? | [.key, (.value.name // .value.username // "")] | @tsv' "$keys" 2>/dev/null)
  fi
}

detect_manual() {
  [[ -r $MANUAL ]] || return 0
  local p h u
  while IFS=$'\t' read -r p h u; do
    [[ $p == gitea ]] && p=forgejo
    [[ $p =~ ^(github|gitlab|forgejo)$ ]] && valid_host "$h" && valid_user "$u" && emit "$p" "$h" "$u"
  done < <(jq -r '.[]? | select(type == "object") | [(.provider // ""), (.host // ""), (.user // "")] | @tsv' "$MANUAL" 2>/dev/null)
}

cmd_list() {
  { detect_manual; detect_github; detect_gitlab; detect_forgejo; } 2>/dev/null |
    jq -cs 'reduce .[] as $a ([]; if any(.[]; . == $a) then . else . + [$a] end)'
}

# -------------------------------------------------------------------- fetch
# Each fetch_* prints {"days":{"YYYY-MM-DD":n},"years":[...]} for the rolling
# last year, or for one calendar year when a 4-digit year is given as $3.

fetch_github() { # host user [year]
  local args=(-f login="$2")
  if [[ -n ${3:-} ]]; then args+=(-f from="$3-01-01T00:00:00Z" -f to="$3-12-31T23:59:59Z"); fi
  timeout 30 gh api graphql --hostname "$1" "${args[@]}" \
    -f query='query($login:String!,$from:DateTime,$to:DateTime){user(login:$login){contributionsCollection(from:$from,to:$to){contributionYears contributionCalendar{weeks{contributionDays{date contributionCount}}}}}}' \
    2>/dev/null </dev/null |
    jq -c '.data.user.contributionsCollection as $c
      | {days: ([$c.contributionCalendar.weeks[].contributionDays[] | {(.date): .contributionCount}] | add // {}),
         years: ($c.contributionYears // [])}'
}

fetch_gitlab() { # host user [year]  (counts activity events per day; GitLab keeps ~3 years)
  local id range cy
  id=$(timeout 20 glab api --hostname "$1" "users?username=$2" 2>/dev/null </dev/null | jq -r '.[0].id // empty') || return 1
  [[ $id =~ ^[0-9]+$ ]] || return 1
  if [[ -n ${3:-} ]]; then
    range="after=$(($3 - 1))-12-31&before=$(($3 + 1))-01-01"
  else
    range="after=$(date -d '366 days ago' +%F)"
  fi
  cy=$(date +%Y)
  timeout 60 glab api --hostname "$1" --paginate "users/$id/events?$range&per_page=100" 2>/dev/null </dev/null |
    jq -cs --argjson y "[$cy, $((cy - 1)), $((cy - 2))]" \
      '{days: (add // [] | map(.created_at[0:10]) | group_by(.) | map({(.[0]): length}) | add // {}), years: $y}'
}

fetch_forgejo() { # host user  (public heatmap, rolling year only, https only)
  timeout 30 curl -fsS --proto '=https' --max-time 25 "https://$1/api/v1/users/$2/heatmap" 2>/dev/null |
    jq -c '{days: (map({d: (.timestamp | strftime("%Y-%m-%d")), c: (.contributions // 0)}) | group_by(.d) | map({(.[0].d): (map(.c) | add)}) | add // {}), years: []}'
}

cmd_fetch() {
  local provider=${1:-} host=${2:-} user=${3:-} year=${4:-} out
  [[ $provider =~ ^(github|gitlab|forgejo)$ ]] && valid_host "$host" && valid_user "$user" || fail bad-account
  if [[ -n $year ]]; then
    [[ $year =~ ^(19[7-9][0-9]|20[0-9][0-9])$ ]] || fail bad-account
  fi
  case $provider in
    github)  command -v gh   >/dev/null || fail no-cli ;;
    gitlab)  command -v glab >/dev/null || fail no-cli ;;
    forgejo) command -v curl >/dev/null || fail no-cli ;;
  esac
  out=$("fetch_$provider" "$host" "$user" "$year") || fail request-failed
  [[ -n $out ]] && jq -e '(.days | type) == "object"' <<<"$out" >/dev/null 2>&1 || fail bad-response
  jq -cn --arg p "$provider" --arg h "$host" --arg u "$user" --argjson d "$out" \
    '{provider:$p,host:$h,user:$u} + $d'
}

case ${1:-} in
  list)  cmd_list ;;
  fetch) shift; cmd_fetch "$@" ;;
  *)     fail bad-account ;;
esac
