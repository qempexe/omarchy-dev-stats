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

# ------------------------------------------------------------------ one day
# What happened on one (local) day: commits pushed on any branch, and pull
# requests opened or merged. GitHub only for now.
#
#   -> {date, commits:[{repo,branch,sha,title,url,at}],
#       prs:[{repo,number,title,url,state,event}], partial}
#
# Commits come from every branch of the repositories pushed to since that day,
# filtered to the account's own (linked) author emails, so feature-branch work
# shows up even though GitHub's calendar doesn't count it. `partial` is true
# when one of the caps below may have hidden something.

DAY_REPOS=25      # most recently pushed repositories looked at
DAY_REFS=100      # branches listed per repository
DAY_BRANCHES=60   # branches whose history is read, across all repositories
DAY_COMMITS=50    # commits per branch

day_github() { # host user day
  local host=$1 user=$2 day=$3 since until since_s meta id i=0 decl="" body="" o n b refs hist
  local -a vars=()
  since=$(date -d "$day 00:00:00" +%Y-%m-%dT%H:%M:%S%:z) || return 1
  until=$(date -d "$day 23:59:59" +%Y-%m-%dT%H:%M:%S%:z) || return 1
  since_s=$(date -d "$since" +%s) || return 1

  # 1. who, the pull requests, and the most recently pushed repositories
  meta=$(timeout 30 gh api graphql --hostname "$host" -F n="$DAY_REPOS" -f login="$user" \
    -f opened="is:pr author:$user created:$since..$until" \
    -f merged="is:pr author:$user merged:$since..$until" \
    -f query='query($login:String!,$n:Int!,$opened:String!,$merged:String!){
      user(login:$login){ id
        repositories(first:$n, orderBy:{field:PUSHED_AT,direction:DESC},
                     ownerAffiliations:[OWNER,COLLABORATOR,ORGANIZATION_MEMBER]){ nodes{ nameWithOwner pushedAt } } }
      opened: search(type:ISSUE, query:$opened, first:50){ nodes{ ...pr } }
      merged: search(type:ISSUE, query:$merged, first:50){ nodes{ ...pr } } }
      fragment pr on PullRequest { number title url state repository{ nameWithOwner } }' \
    2>/dev/null </dev/null) || return 1
  id=$(jq -r '.data.user.id // empty' <<<"$meta")
  [[ $id =~ ^[A-Za-z0-9_=-]{1,100}$ ]] || return 1

  # 2. the branches of the repositories pushed to on or after the day, with the
  #    date of each tip. Names are checked and only ever passed as variables.
  local pushed
  pushed=$(jq -r --argjson s "$since_s" \
    '.data.user.repositories.nodes[]? | select((.pushedAt | fromdateiso8601) >= $s) | .nameWithOwner' <<<"$meta") || return 1
  while IFS=/ read -r o n; do
    [[ $o =~ ^[A-Za-z0-9_.-]{1,100}$ && $n =~ ^[A-Za-z0-9_.-]{1,100}$ ]] || continue
    decl+=",\$o$i:String!,\$n$i:String!"
    body+=" r$i: repository(owner:\$o$i, name:\$n$i){ nameWithOwner defaultBranchRef{ name } refs(refPrefix:\"refs/heads/\", first:\$refs){ totalCount nodes{ name target{ ... on Commit{ committedDate } } } } }"
    vars+=(-f "o$i=$o" -f "n$i=$n")
    i=$((i + 1))
  done <<<"$pushed"

  refs='{"data":{}}'
  if ((i > 0)); then
    refs=$(timeout 30 gh api graphql --hostname "$host" "${vars[@]}" -F refs="$DAY_REFS" \
      -f query="query(\$refs:Int!$decl){$body}" 2>/dev/null </dev/null) || return 1
  fi

  # 3. the history of the branches whose tip is on or after the day (a branch that
  #    stopped before it can't hold that day's commits), by this account only
  local wanted
  wanted=$(jq -r --argjson s "$since_s" --argjson cap "$DAY_BRANCHES" \
    '[.data // {} | .[] | select(. != null) | .nameWithOwner as $r | .refs.nodes[]?
      | select(.target.committedDate != null and (.target.committedDate | fromdateiso8601) >= $s)
      | {r: $r, b: .name, at: .target.committedDate}]
     | sort_by(.at) | reverse | .[:$cap][] | (.r | split("/")) as $p | [$p[0], $p[1], .b] | @tsv' <<<"$refs") || return 1
  i=0; decl=""; body=""; vars=()
  while IFS=$'\t' read -r o n b; do
    [[ $o =~ ^[A-Za-z0-9_.-]{1,100}$ && $n =~ ^[A-Za-z0-9_.-]{1,100}$ && $b =~ ^[A-Za-z0-9_./+@-]{1,250}$ ]] || continue
    decl+=",\$o$i:String!,\$n$i:String!,\$b$i:String!"
    body+=" h$i: repository(owner:\$o$i, name:\$n$i){ nameWithOwner ref(qualifiedName:\$b$i){ name target{ ...hist } } }"
    vars+=(-f "o$i=$o" -f "n$i=$n" -f "b$i=refs/heads/$b")
    i=$((i + 1))
  done <<<"$wanted"

  hist='{"data":{}}'
  if ((i > 0)); then
    hist=$(timeout 45 gh api graphql --hostname "$host" "${vars[@]}" \
      -f id="$id" -f since="$since" -f until="$until" -F commits="$DAY_COMMITS" \
      -f query="query(\$id:ID!,\$since:GitTimestamp!,\$until:GitTimestamp!,\$commits:Int!$decl){$body}
        fragment hist on Commit { history(first:\$commits, since:\$since, until:\$until, author:{id:\$id}){
          pageInfo{ hasNextPage } nodes{ oid messageHeadline committedDate url } } }" \
      2>/dev/null </dev/null) || return 1
  fi

  jq -cn --arg d "$day" --argjson m "$meta" --argjson r "$refs" --argjson h "$hist" --argjson s "$since_s" \
    --argjson repocap "$DAY_REPOS" --argjson refcap "$DAY_REFS" --argjson brcap "$DAY_BRANCHES" '
    def prs($ev): [($m.data[$ev].nodes // [])[] | select(.number != null)
      | {repo: .repository.nameWithOwner, number, title, url, state, event: $ev}];
    ($m.data.user.repositories.nodes // []) as $all
    | ($r.data // {} | [.[] | select(. != null)]) as $listed
    | ($h.data // {} | [.[] | select(. != null and .ref != null)]) as $branches
    | {date: $d,
       # a commit on several branches is listed once, under the default branch if
       # it is on it, otherwise under the branch with the newest tip
       commits: (([$listed[] | {(.nameWithOwner): (.defaultBranchRef.name // "")}] | add // {}) as $default
                 | [$branches | to_entries[] | .key as $rank | .value | .nameWithOwner as $repo | .ref.name as $b
                    | .ref.target.history.nodes[]?
                    | {repo: $repo, branch: $b, sha: .oid, title: .messageHeadline, url, at: .committedDate,
                       pick: (if $b == $default[$repo] then -1 else $rank end)}]
                 | group_by(.sha) | map(min_by(.pick) | del(.pick)) | sort_by(.at) | reverse | .[:200]),
       # opened and merged the same day: one entry, "opened,merged"
       prs: (prs("opened") + prs("merged") | group_by(.url)
             | map(.[0] + {event: ([.[].event] | if index("opened") and index("merged") then "opened,merged" else .[0] end)}) | .[:100]),
       partial: (
         # every repository looked at was pushed after the day: older ones may hold more
         (($all | length) >= $repocap and ($all | last | .pushedAt | fromdateiso8601) >= $s)
         or any($listed[]; .refs.totalCount > $refcap)
         or ([$listed[] | .refs.nodes[]? | select(.target.committedDate != null and (.target.committedDate | fromdateiso8601) >= $s)] | length) > $brcap
         or any($branches[]; .ref.target.history.pageInfo.hasNextPage == true))}'
}

cmd_day() {
  local provider=${1:-} host=${2:-} user=${3:-} day=${4:-} out
  [[ $provider =~ ^(github|gitlab|forgejo)$ ]] && valid_host "$host" && valid_user "$user" || fail bad-account
  [[ $day =~ ^(19[7-9][0-9]|20[0-9][0-9])-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] || fail bad-account
  [[ $provider == github ]] || fail unsupported
  command -v gh >/dev/null || fail no-cli
  out=$(day_github "$host" "$user" "$day") || fail request-failed
  [[ -n $out ]] && jq -e '(.commits | type) == "array" and (.prs | type) == "array"' <<<"$out" >/dev/null 2>&1 || fail bad-response
  printf '%s\n' "$out"
}

case ${1:-} in
  list)  cmd_list ;;
  fetch) shift; cmd_fetch "$@" ;;
  day)   shift; cmd_day "$@" ;;
  *)     fail bad-account ;;
esac
