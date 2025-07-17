# IPv64 Blocklist Service

🛡️ Automatischer IP-Blocker für Linux-Firewalls basierend auf IPv64.net-Blocklisten.

---

## 🔧 Features

- Regelmäßiges Herunterladen von IPv64-Blocklisten
- Whitelist für eigene Ausnahmen
- Systemd-Service für tägliche Updates
- CLI
- Logfile

---

## 🚀 Installation

1. **Voraussetzungen installieren**
   
       sudo apt install ipset iptables ip6tables curl sha256sum awk
   
3.   **Projektdateien vorbereiten**
  
     Lege die folgenden Dateien im selben Verzeichnis ab:

      - install_ipv64.sh
   
      - ipv64_blocklist.sh
   
      - ipv64-wrapper.sh

  5. **Installation ausführen**

         chmod +x install_ipv64.sh
     
         sudo ./install_ipv64.sh

---

## 🧪 CLI-Befehle

| Befehl | Beschreibung |
|----------------|---------------------|
|ipv64 status    | Zeigt aktuellen Status |
|ipv64 update    | Führt ein manuelles Update der Blocklisten durch |
|ipv64 uninstall | Entfernt den Service und alle Konfigurationen |

---

## 📝 Konfiguration

- Blocklist-URLs: Bearbeite /etc/ipv64/conf/blocklist_urls.conf, um weitere Listen hinzuzufügen.

- Whitelist: Trage IPs oder Netze in /etc/ipv64/blocklists/whitelist.txt ein, die nicht geblockt werden sollen.

- Update-Zeitpunkt:

     Passe /etc/ipv64/conf/service.conf an:

      OnCalendar=daily

---

## 📄 Logdatei

Alle Aktionen werden protokolliert unter:
                    
    /var/log/ipv64_blocklist.log

---

## 🧹 Deinstallation

sudo ipv64 uninstall
