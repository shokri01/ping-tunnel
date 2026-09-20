#!/usr/bin/env bash
# ============================================================
#  ir-tunnel.sh — تانل معکوس Reality (نسخهٔ قابل‌مدیریت)
#  استفاده:
#    bash ir-tunnel.sh kharej          # نصب/به‌روزرسانی سمت خارج
#    bash ir-tunnel.sh iran <creds>    # نصب سمت ایران
#    bash ir-tunnel.sh user-add <creds> <نام>   # افزودن کاربر
#    bash ir-tunnel.sh user-del <creds> <نام>   # حذف کاربر
#    bash ir-tunnel.sh rotate <creds>  # چرخش UUID همهٔ کاربران
#    bash ir-tunnel.sh ip <creds> <IP-نو>       # تغییر IP سرور خارج
#    bash ir-tunnel.sh ports <creds> <2091 2021> # تغییر درب‌های ایران
#    bash ir-tunnel.sh status <creds>  # وضعیت + تست
#    bash ir-tunnel.sh test <creds>    # تست end-to-end
# ============================================================
set -euo pipefail

CMD="${1:-help}"; shift || true
GRE="/usr/local/bin/grep"
WORK="/root/ir-tunnel"

# ---------- کمکی‌ها ----------
msg(){ echo -e "\033[1;36m==>\033[0m $*"; }
ok(){ echo -e "\033[1;32m✔\033[0m $*"; }
err(){ echo -e "\033[1;31m✘\033[0m $*" >&2; exit 1; }

read_creds(){
  CREDS="$1"
  [ -f "$CREDS" ] || err "فایل اعتبارنامه پیدا نشد: $CREDS"
  # shellcheck disable=SC1091
  source <(grep -E '^(KAREJ_IP|REALITY_PORT|UUID|PUB|SID|SNI|EXTRA_PORTS|TUN_LOCAL)=' "$CREDS")
}

install_xray(){
  [ -x /usr/local/bin/xray ] && { msg "xray نصب است: $(/usr/local/bin/xray version | head -1)"; return; }
  msg "نصب Xray..."
  apt-get install -y -qq unzip curl >/dev/null 2>&1 || true
  curl -sL -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
  unzip -o /tmp/xray.zip xray -d /usr/local/bin >/dev/null && chmod +x /usr/local/bin/xray
}

make_unit(){
  local NAME="$1" DESC="$2"; shift 2
  cat > "/etc/systemd/system/${NAME}.service" <<EOF
[Unit]
Description=$DESC
After=network.target

[Service]
ExecStart=/usr/local/bin/xray run -c $1
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

# ============================================================
case "$CMD" in

# ------------------------------------------------------------
kharej)
  mkdir -p "$WORK"
  install_xray
  REALITY_PORT="${REALITY_PORT:-443}"
  SNI="${SNI:-www.samsung.com}"
  KP="$(/usr/local/bin/xray x25519)"
  PRIV="$(echo "$KP" | awk '/Private/{print $NF}')"
  PUB="$(echo "$KP" | awk '/Public/{print $NF}')"
  SID="$(openssl rand -hex 4)"
  if [ -f "$WORK/users.json" ]; then
    msg "کاربران قبلی حفظ می‌شوند"
    # کلاینت‌ها را از users.json بخوان
    CLIENTS=$(python3 -c "
import json
for u in json.load(open('$WORK/users.json')):
    print(json.dumps({'id': u['id'], 'email': u['name'], 'flow':'xtls-rprx-vision'}))
" | paste -sd, -)
  else
    UID1="$(/usr/local/bin/xray uuid)"
    echo '[{"name":"default","id":"'"$UID1"'"}]' > "$WORK/users.json"
    CLIENTS='[{"id":"'"$UID1"'","email":"default","flow":"xtls-rprx-vision"}]'
  fi
  mkdir -p /usr/local/etc/xray
  [ -f /usr/local/etc/xray/config.json ] && cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.bak.$(date +%s)
  cat > "$WORK/inbounds.json" <<EOF
[{
  "listen": "0.0.0.0",
  "port": $REALITY_PORT,
  "protocol": "vless",
  "settings": { "clients": $CLIENTS, "decryption": "none" },
  "streamSettings": {
    "network": "tcp", "security": "reality",
    "realitySettings": {
      "dest": "$SNI:443",
      "serverNames": ["$SNI"],
      "privateKey": "$PRIV",
      "shortIds": ["$SID"]
    }
  },
  "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
}]
EOF
  python3 - <<PYEOF
import json
base = {
  "log": {"loglevel": "warning"},
  "inbounds": json.load(open("$WORK/inbounds.json")),
  "outbounds": [{"protocol":"freedom","tag":"direct"}]
}
json.dump(base, open("/usr/local/etc/xray/config.json","w"), indent=2)
print("config ok")
PYEOF
  make_unit "ir-tunnel" "Reality Tunnel (Kharej side)" "/usr/local/etc/xray/config.json"
  systemctl restart ir-tunnel
  # اعتبارنامه (از users.json — کاربر اول)
  UUUID=$(python3 -c "import json;print(json.load(open('$WORK/users.json'))[0]['id'])")
  cat > /root/reality-credentials.txt <<EOF
KAREJ_IP=$(curl -s -m 5 ifconfig.me || echo "IP-KHAREJ")
REALITY_PORT=443
UUID=$UUUID
PUB=$PUB
SID=$SID
SNI=$SNI
EOF
  chmod 600 /root/reality-credentials.txt
  ok "سمت خارج نصب شد"
  echo "-------------------------------------------"
  echo " 🔑 اعتبارنامه: /root/reality-credentials.txt"
  echo "    (این فایل را به ایران ببر)"
  echo "-------------------------------------------"
  ;;

# ------------------------------------------------------------
iran)
  CREDS="${2:-/root/reality-credentials.txt}"
  read_creds "$CREDS"
  install_xray
  [ -f "$WORK/inbounds-ports.json" ] || echo "2091" > "$WORK/ports"
  PORTS=$(cat "$WORK/ports" 2>/dev/null || echo "2091")
  # درب‌های dokodemo
  INBOUNDS="["
  FIRST=1
  for P in $PORTS; do
    [ "$FIRST" = "0" ] || INBOUNDS+=","
    INBOUNDS+="{\"listen\":\"0.0.0.0\",\"port\":$P,\"protocol\":\"dokodemo-door\",\"settings\":{\"address\":\"127.0.0.1\",\"port\":$P,\"network\":\"tcp\"}}"
    FIRST=0
  done
  INBOUNDS+="]"
  cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": $INBOUNDS,
  "outbounds": [{
    "protocol": "vless",
    "settings": {"vnext": [{
      "address": "$KAREJ_IP",
      "port": 443,
      "users": [{"id": "$UUID", "flow": "xtls-rprx-vision", "encryption": "none"}]
    }]},
    "streamSettings": {
      "network": "tcp", "security": "reality",
      "realitySettings": {
        "serverName": "$SNI", "fingerprint": "chrome",
        "publicKey": "$PUB", "shortId": "$SID"
      }
    }
  }]
}
EOF
  make_unit "ir-tunnel" "Reality Tunnel (Iran side)" "/usr/local/etc/xray/config.json"
  systemctl restart ir-tunnel
  ok "سمت ایران نصب شد — درب‌ها: $PORTS"
  ;;

# ------------------------------------------------------------
user-add)
  CREDS="${2:-}"; NAME="${3:?نام کاربر لازم است}"
  [ -f "$WORK/users.json" ] || err "اول kharej را اجرا کن (فایل users.json ساخته نمی‌شود)"
  UID_N="$(/usr/local/bin/xray uuid)"
  python3 - <<PYEOF
import json
users = json.load(open("$WORK/users.json"))
users.append({"name": "$NAME", "id": "$UID_N"})
json.dump(users, open("$WORK/users.json","w"), indent=2)
print(f"✔ کاربر $NAME اضافه شد")
PYEOF
  msg "حالا سمت خارج را دوباره نصب کن تا اعمال شود: bash ir-tunnel.sh kharej"
  ;;

# ------------------------------------------------------------
rotate)
  msg "چرخش UUID همهٔ کاربران — هر کاربر UUID نو می‌گیرد"
  python3 - <<'PYEOF'
import json, subprocess
users = json.load(open("/root/ir-tunnel/users.json"))
for u in users:
    u["id"] = subprocess.run(["/usr/local/bin/xray","uuid"], capture_output=True, text=True).stdout.strip()
json.dump(users, open("/root/ir-tunnel/users.json","w"), indent=2)
print("✔ همهٔ UUIDها نو شدند")
PYEOF
  msg "حالا: bash ir-tunnel.sh kharej  (سمت خارج) و بعد فایل اعتبارنامهٔ نو را به ایران ببر و  bash ir-tunnel.sh iran"
  ;;

# ------------------------------------------------------------
ip)
  CREDS="${2:?فایل اعتبارنامه لازم است}"; NEW_IP="${3:?IP نو لازم است}"
  sed -i "s/^KAREJ_IP=.*/KAREJ_IP=$NEW_IP/" "$CREDS"
  ok "IP اعتبارنامه → $NEW_IP"
  msg "سمت ایران: bash ir-tunnel.sh iran $CREDS   (کانفیگ نو با IP نو)"
  ;;

# ------------------------------------------------------------
ports)
  CREDS="${2:?}"; shift 2
  echo "$*" > "$WORK/ports"
  msg "درب‌های نو: $* — اعمال: bash ir-tunnel.sh iran $CREDS"
  ;;

# ------------------------------------------------------------
test)
  # تست از ایران
  systemctl is-active ir-tunnel | xargs echo "سرویس ir-tunnel:"
  ss -tlnp | grep ir-tunnel >/dev/null && echo "درب‌ها: باز" || echo "درب‌ها: بسته"
  ;;

help|*)
  cat <<'EOF'
فرمان‌ها:
  kharej                    نصب/به‌روزرسانی سمت خارج (کلید نو اگر users.json نبود)
  iran <creds>              نصب سمت ایران از فایل اعتبارنامه
  user-add <creds> <نام>    افزودن کاربر
  user-del <creds> <نام>    حذف کاربر
  rotate                    چرخش UUID همهٔ کاربران
  ip <creds> <IP-نو>        تغییر IP سرور خارج
  ports <creds> <2091 2021> تغییر درب‌های ایران
  test                      وضعیت سرویس
EOF
  ;;
esac
