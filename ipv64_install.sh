#!/usr/bin/env bash
set -euo pipefail
# install_ipv64.sh – richtet den IPv64 Blocklist-Service ein.
# Als root ausführen:
#   chmod +x install_ipv64.sh
#   ./install_ipv64.sh
WORK_DIR="/etc/ipv64"
BLOCKLIST_DIR="$WORK_DIR/blocklists"
CONF_DIR="$WORK_DIR/conf"
SCRIPT_SRC="./ipv64_blocklist.sh"
WRAPPER_SRC="./ipv64_wrapper.sh"
SCRIPT_TGT="$WORK_DIR/ipv64_blocklist.sh"
WRAPPER_TGT="/usr/local/bin/ipv64"
URL_FILE="$CONF_DIR/blocklist_urls.conf"
SERVICE_CONF="$CONF_DIR/service.conf"
CHECKSUM_FILE="$WORK_DIR/checksums.txt"
WHITELIST_FILE="$BLOCKLIST_DIR/whitelist.txt"
LOG_FILE="/var/log/ipv64_blocklist.log"
LOGROTATE_FILE="/etc/logrotate.d/ipv64_blocklist"
SERVICE_NAME="ipv64_blocklist"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"
log(){ echo "$*"; }
# 🧪 Prüfe, ob IPv64 bereits installiert ist
if [[ -f "/usr/local/bin/ipv64" || -d "/etc/ipv64" ]]; then
  echo "⚠️  IPv64 scheint bereits installiert zu sein."
  echo "ℹ️  Du kannst mit 'ipv64 status' den Zustand prüfen oder mit 'ipv64 uninstall' alles entfernen."
  exit 0
fi
# 1) Prüfen, ob alle nötigen Tools installiert sind
MISSING=()
for cmd in ipset iptables ip6tables curl sha256sum awk systemctl; do
  command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if (( ${#MISSING[@]} )); then
  echo "❌  Fehlende Tools: ${MISSING[*]}"
  echo "Bitte installieren und erneut ausführen."
  exit 1
fi
# 2) Verzeichnisse anlegen
mkdir -p "$BLOCKLIST_DIR" "$CONF_DIR" "$(dirname "$LOG_FILE")"
chmod 700 "$WORK_DIR" "$BLOCKLIST_DIR" "$CONF_DIR"
# 2a) Logfile anlegen und Rechte setzen
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"
# 3) Konfigurationsdateien initial befüllen
echo "https://ipv64.net/blocklists/ipv64_blocklist_blocklistde_all.txt" >"$URL_FILE"
echo "OnCalendar=daily"      >"$SERVICE_CONF"
echo "OnBootSec=1min"        >>"$SERVICE_CONF"
read -rp "IPV64-Chain in INPUT-Chain einfügen? [J/n] " ans
ans=${ans:-J}
echo "AddInputChain=$( [[ $ans =~ ^[Jj] ]] && echo true || echo false )" >>"$SERVICE_CONF"
if iptables -nL DOCKER-USER &>/dev/null; then
  read -rp "IPV64-Chain in DOCKER-USER-Chain einfügen? [J/n] " ans2
  ans2=${ans2:-J}
  echo "AddDockerChain=$( [[ $ans2 =~ ^[Jj] ]] && echo true || echo false )" >>"$SERVICE_CONF"
else
  echo "AddDockerChain=false" >>"$SERVICE_CONF"
fi
touch "$WHITELIST_FILE" "$CHECKSUM_FILE"
chmod 600 "$URL_FILE" "$SERVICE_CONF" "$WHITELIST_FILE" "$CHECKSUM_FILE"
# 4) Logrotate konfigurieren
cat >"$LOGROTATE_FILE" <<EOF
$LOG_FILE {
  daily
  rotate 7
  compress
  missingok
  notifempty
  create 640 root adm
}
EOF
# 5) Skripte installieren
install -m 700 "$SCRIPT_SRC" "$SCRIPT_TGT"
install -m 755 "$WRAPPER_SRC" "$WRAPPER_TGT"
# 6) systemd Service & Timer erstellen
CALENDAR=$(grep '^OnCalendar=' "$SERVICE_CONF" | cut -d= -f2)
BOOTSEC=$(grep '^OnBootSec='  "$SERVICE_CONF" | cut -d= -f2)
cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=IPv64 Blocklist Updater
Wants=network-online.target
After=network-online.target
ConditionPathExists=$URL_FILE
[Service]
Type=oneshot
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStartPre=/usr/bin/env bash -c "\
source $SERVICE_CONF; \
iptables -nL IPV64      &>/dev/null || iptables -N IPV64; \
if [ \"\$AddInputChain\" = true ]; then iptables -C INPUT -j IPV64 &>/dev/null || iptables -I INPUT -j IPV64; fi; \
if [ \"\$AddDockerChain\" = true ] && iptables -nL DOCKER-USER &>/dev/null; then iptables -C DOCKER-USER -j IPV64 &>/dev/null || iptables -I DOCKER-USER -j IPV64;
fi; \
ip6tables -nL IPV64     &>/dev/null || ip6tables -N IPV64; \
if [ \"\$AddInputChain\" = true ]; then ip6tables -C INPUT -j IPV64 &>/dev/null || ip6tables -I INPUT -j IPV64; fi; \
if [ \"\$AddDockerChain\" = true ] && ip6tables -nL DOCKER-USER &>/dev/null; then ip6tables -C DOCKER-USER -j IPV64 &>/dev/null || ip6tables -I DOCKER-USER -j IPV64; fi"
ExecStart=$SCRIPT_TGT
[Install]
WantedBy=multi-user.target
EOF
cat >"$TIMER_FILE" <<EOF
[Unit]
Description=IPv64 Blocklist Timer
ConditionPathExists=$URL_FILE
[Timer]
OnCalendar=$CALENDAR
OnBootSec=$BOOTSEC
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now --quiet "$SERVICE_NAME.timer"
# 7) IPTables-Chains initial setzen
source "$SERVICE_CONF"
iptables -nL IPV64 &>/dev/null || iptables -N IPV64
if [ "$AddInputChain" = true ]; then
  iptables -C INPUT -j IPV64 &>/dev/null || iptables -I INPUT -j IPV64
fi
if [ "$AddDockerChain" = true ] && iptables -nL DOCKER-USER &>/dev/null; then
  iptables -C DOCKER-USER -j IPV64 &>/dev/null || iptables -I DOCKER-USER -j IPV64
fi
ip6tables -nL IPV64 &>/dev/null || ip6tables -N IPV64
if [ "$AddInputChain" = true ]; then
  ip6tables -C INPUT -j IPV64 &>/dev/null || ip6tables -I INPUT -j IPV64
fi
if [ "$AddDockerChain" = true ] && ip6tables -nL DOCKER-USER &>/dev/null; then
  ip6tables -C DOCKER-USER -j IPV64 &>/dev/null || ip6tables -I DOCKER-USER -j IPV64
fi
log "✅  Installation abgeschlossen — CLI verfügbar als 'ipv64'"
