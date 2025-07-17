#!/usr/bin/env bash
set -euo pipefail
WRAPPER_PATH="/usr/local/bin/ipv64"
CMD="${1:-}"
WORK_DIR="/etc/ipv64"
SCRIPT="$WORK_DIR/ipv64_blocklist.sh"
SERVICE="ipv64_blocklist"
LOG="/var/log/ipv64_blocklist.log"
BLOCKLIST_DIR="$WORK_DIR/blocklists"
remove_chain(){
  iptables -C INPUT -j IPV64 &>/dev/null && iptables -D INPUT -j IPV64 || :
  ip6tables -C INPUT -j IPV64 &>/dev/null && ip6tables -D INPUT -j IPV64 || :
  iptables -C DOCKER-USER -j IPV64 &>/dev/null && iptables -D DOCKER-USER -j IPV64 || :
  ip6tables -C DOCKER-USER -j IPV64 &>/dev/null && ip6tables -D DOCKER-USER -j IPV64 || :
  iptables -nL IPV64 &>/dev/null && iptables -F IPV64 && iptables -X IPV64 || :
  ip6tables -nL IPV64 &>/dev/null && ip6tables -F IPV64 && ip6tables -X IPV64 || :
  # Alle ipset-Sets mit _v4 oder _v6 löschen
  for set in $(ipset list -n | grep -E '_v[46]$'); do
    ipset destroy "$set" &>/dev/null || :
  done
}
update() {
  echo -ne "🔄 Starte IPv64-Update… "
  # Spinner-Zeichen
  spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  i=0
  start=$(date +%s)
  # Temporäre Log-Datei für Update-Ausgabe
  tmp_log=$(mktemp)
  # Starte Update im Hintergrund, leite Ausgabe um
  IPV64_VERBOSE=1 bash "$SCRIPT" >"$tmp_log" 2>&1 &
  pid=$!
  # Spinner anzeigen, bis Prozess fertig ist
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r🔄 IPv64-Update läuft… ${spin:i++%${#spin}:1} "
    sleep 0.1
  done
  wait "$pid"
  end=$(date +%s)
  duration=$((end - start))
  # Abschlusszeile
  printf "\r✅  IPv64-Update abgeschlossen in ${duration}s\n"
  # Zeige die Log-Ausgabe danach
  echo -e "\n📄 Update-Log:"
  cat "$tmp_log"
  rm -f "$tmp_log"
}
OK_ICON="✅ "
FAIL_ICON="❌ "
case "$CMD" in
  update)
    update
    ;;
  status)
    echo "📊 IPv64 Blocklist Status"
    echo "-------------------------"
    for setname in $(ipset list -n | grep ipv64); do
      count=$(ipset list "$setname" 2>/dev/null \
                | awk '/Number of entries/ {print $4}' || echo 0)
      printf "  %-20s %5d Einträge\n" "$setname" "$count"
    done
    echo; echo "📅 Letztes Update:"
    pattern="Update durchgeführt"
    if grep -q "$pattern" "$LOG"; then
      # letzte Zeile mit dem Pattern holen und Timestamp extrahieren
      ts=$(grep "$pattern" "$LOG" | tail -n1 | sed -nE 's/^\[([^]]+)\].*/\1/p')
      echo "Letztes Update durchgeführt am: $ts"
    else
    echo "Noch kein Update durchgeführt"
    fi
    echo; echo "🛠️ Service Timer"
    timer_info=$(systemctl list-timers --all | grep "$SERVICE" || echo "")
    if [[ -n "$timer_info" ]]; then
      next_run=$(echo "$timer_info" | awk '{print $1, $2, $3, $4}')
      last_run=$(echo "$timer_info" | awk '{print $8, $9, $10, $11}')
      remaining=$(echo "$timer_info" | awk '{print $5, $6}')
      echo -e "⏲️  Nächste Ausführung: $next_run"
      echo -e "🕓  Letzte Ausführung:  $last_run"
      echo -e "⏳   Verbleibend:        $remaining"
    else
      echo "⚠️  Kein Timer aktiv für $SERVICE"
    fi
    echo; echo "🛡️ Firewall"
    echo "-------------------------"
    printf "  %-30s %s\n" "IPV64-Chain vorhanden" \
      "$(iptables -nL IPV64 &>/dev/null && echo "$OK_ICON" || echo "$FAIL_ICON")"
    printf "  %-30s %s\n" "IPV64 in INPUT-Chain" \
      "$(iptables -C INPUT -j IPV64 &>/dev/null && echo "$OK_ICON" || echo "$FAIL_ICON")"
    if iptables -nL DOCKER-USER &>/dev/null; then
      printf "  %-30s %s\n" "IPV64 in DOCKER-USER-Chain" \
        "$(iptables -C DOCKER-USER -j IPV64 &>/dev/null && echo "$OK_ICON" || echo "$FAIL_ICON")"
    else
      printf "  %-30s %s\n" "DOCKER-USER-Chain nicht vorhanden" "$FAIL_ICON"
    fi
    ;;
  uninstall)
    echo "🧹 Entferne IPv64 Blocklist-Service…"
    systemctl disable --now "$SERVICE.timer" > /dev/null 2>&1
    remove_chain
    rm -f $LOG
    rm -f "/etc/systemd/system/$SERVICE.service" "/etc/systemd/system/$SERVICE.timer"
    systemctl daemon-reload
    rm -rf "/etc/ipv64" "/etc/logrotate.d/ipv64_blocklist" "$WRAPPER_PATH"
    echo "✅  Deinstallation abgeschlossen."
    ;;
  *)
    echo "Usage: ipv64 {update|status|uninstall}"
    exit 1
    ;;
esac
