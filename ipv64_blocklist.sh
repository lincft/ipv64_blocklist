#!/usr/bin/env bash
set -euo pipefail
WORK_DIR="/etc/ipv64"
BLOCKLIST_DIR="$WORK_DIR/blocklists"
CONF_DIR="$WORK_DIR/conf"
URL_FILE="$CONF_DIR/blocklist_urls.conf"
CHECKSUM_FILE="$WORK_DIR/checksums.txt"
WHITELIST_FILE="$BLOCKLIST_DIR/whitelist.txt"
LOG_FILE="/var/log/ipv64_blocklist.log"
VERBOSE=${IPV64_VERBOSE:-0}
# Logging-Funktion
log() {
  echo "[$(date +'%F %T')] $*" >>"$LOG_FILE"
  [[ "$VERBOSE" == "1" ]] && echo "$*"
}
# Whitelist laden
declare -A WHITELIST
if [[ -f "$WHITELIST_FILE" ]]; then
  while IFS= read -r ip; do
    [[ "$ip" =~ ^#|^$ ]] && continue
    WHITELIST["$ip"]=1
  done <"$WHITELIST_FILE"
fi
# Blocklist aktualisieren
update_blocklist() {
  local url="$1"
  [[ $url =~ ^https://[A-Za-z0-9./?=_-]+$ ]] || { log "Ungültige URL: $url"; return 1; }
  local key=$(basename "$url")
  key="${key%.*}"
  local ip_list="$BLOCKLIST_DIR/${key}.txt"
  local tmp; tmp=$(mktemp)
  log "⬇️ Lade $url"
  curl -fsSL "$url" -o "$tmp" || { log "Download fehlgeschlagen: $url"; return 1; }
  local new_sum; new_sum=$(sha256sum "$tmp" | cut -d' ' -f1)
  local old_sum; old_sum=$(grep -E "^${key} " "$CHECKSUM_FILE" 2>/dev/null | cut -d' ' -f2 || echo "")
  if [[ $new_sum != $old_sum ]]; then
    log "⬆️ Update für $key"
    mv "$tmp" "$ip_list"
    local has4=0 has6=0
    while IFS= read -r ip; do [[ $ip == *:* ]] && has6=1 || has4=1; done <"$ip_list"
    # IPv4
    if (( has4 )); then
      local set4="${key}_v4"
      iptables -D IPV64 -m set --match-set "$set4" src -j DROP &>/dev/null || true
      sleep 1
      ipset flush "$set4" &>/dev/null || true
      sleep 1
      local tmpf; tmpf=$(mktemp)
      echo "create $set4 hash:net family inet maxelem 200000" >"$tmpf"
      while IFS= read -r ip; do
        [[ $ip == *:* ]] && continue
        [[ -n "${WHITELIST[$ip]:-}" ]] && continue
        echo "add $set4 $ip -exist"
      done <"$ip_list" >>"$tmpf"
      ipset restore -f "$tmpf" && rm -f "$tmpf"
      iptables -A IPV64 -m set --match-set "$set4" src -j DROP
    fi
    # IPv6
    if (( has6 )); then
      local set6="${key}_v6"
      ip6tables -D IPV64 -m set --match-set "$set6" src -j DROP &>/dev/null || true
      sleep 1
      ipset flush "$set6" &>/dev/null || true
      sleep 1
      local tmpf; tmpf=$(mktemp)
      echo "create $set6 hash:net family inet6 maxelem 200000" >"$tmpf"
      while IFS= read -r ip; do
        [[ $ip != *:* ]] && continue
        [[ -n "${WHITELIST[$ip]:-}" ]] && continue
        echo "add $set6 $ip -exist"
      done <"$ip_list" >>"$tmpf"
      ipset restore -f "$tmpf" && rm -f "$tmpf"
      ip6tables -A IPV64 -m set --match-set "$set6" src -j DROP
    fi
    log "📝 Prüfsumme für '$key' aktualisiert"
    grep -vE "^${key} " "$CHECKSUM_FILE" >"$CHECKSUM_FILE.tmp"
    echo "$key $new_sum" >>"$CHECKSUM_FILE.tmp"
    mv "$CHECKSUM_FILE.tmp" "$CHECKSUM_FILE"
  else
    rm -f "$tmp"
    log "✅  $key ist aktuell"
  fi
}
# Alle URLs durchlaufen
mapfile -t urls < <(grep -E '^[^#]' "$URL_FILE")
for url in "${urls[@]}"; do
  update_blocklist "$url" || { [[ "$VERBOSE" == "1" ]] && log "❌  Ein Fehler ist mit $url aufgetreten"; }
done
[[ "$VERBOSE" == "1" ]] && log "✅  Update durchgeführt"
