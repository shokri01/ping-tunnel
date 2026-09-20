# 🚇 تانل معکوس Reality — کیت مدیریت (ir-tunnel.sh)

## معماری
```
کاربر ──ریلیتی──► ایران:2091 (درب) ──تانل ریلیتی دوم──► خارج:443 ──► اینترنت
```

## نصب (روی سرورهای جدید)

### قدم ۱ — بسته را به هر دو سرور ببر
```bash
scp /root/tunnel-kit/ir-tunnel.sh root@<سرور-جدید>:/root/
```

### قدم ۲ — سمت سرور خارج
```bash
bash /root/ir-tunnel.sh kharej
```
- خودش xray نصب می‌کند، کلیدها را می‌سازد، سرویس ir-tunnel را بالا می‌آورد
- پورت ریلیتی = 443 (اگر 443 خالی است)
- کلیدها → `/root/reality-credentials.txt`

### قدم ۳ — اعتبارنامه را به ایران ببر
```bash
scp root@<IP-خارج>:/root/reality-credentials.txt /root/
```

### قدم ۴ — سمت ایران
```bash
bash /root/ir-tunnel.sh iran /root/reality-credentials.txt
```
- پیش‌فرض درب: 2091 — برای تغییر قبل از این قدم: `bash ir-tunnel.sh ports /root/reality-credentials.txt 2091 2021 2083`

## مدیریت روزمره

| می‌خواهم | فرمان (روی ایران) |
|---|---|
| کاربر نو | `bash /root/ir-tunnel.sh user-add /root/reality-credentials.txt ali` |
| چرخش همهٔ UUIDها | `bash /root/ir-tunnel.sh rotate` |
| IP سرور خارج عوض شد | `bash /root/ir-tunnel.sh ip /root/reality-credentials.txt <IP-نو>` و بعد `bash /root/ir-tunnel.sh iran /root/reality-credentials.txt` |
| درب نو / حذف درب | `bash /root/ir-tunnel.sh ports /root/reality-credentials.txt 2091 2021` و بعد `bash /root/ir-tunnel.sh iran ...` |
| وضعیت | `systemctl status ir-tunnel` |

## تست
```bash
# روی ایران:
curl -m 10 --socks5-hostname 127.0.0.1:10808 https://www.google.com -o /dev/null -w "%{http_code}\n"
# روی ایران (اگر socks تست اضافه شده باشد) — یا پورت کاربر:
curl -m 10 -k --resolve x:2091:127.0.0.1 https://www.google.com:2091 -o /dev/null -w "%{http_code}\n" 2>/dev/null
# ساده‌تر: از یک اپ موبایل وصل شو و ببین سبز است
```

## نکات مهم
1. پورت ریلیتی روی خارج = **443** (بهترین پنهان‌کاری). اگر 443 اشغال بود، `REALITY_PORT=38443 bash ir-tunnel.sh kharej` و در فایروال بازش کن
2. SNI باید از سرور خارج باز باشد — سامسونگ/اپل امن‌اند
3. بعد از هر تغییر سمت خارج: `bash ir-tunnel.sh kharej` دوباره، و فایل اعتبارنامه را دوباره به ایران ببر
4. فایل `users.json` در سرور خارج کاربران را نگه می‌دارد — پشتیبانش را داشته باش
