#!/bin/sh
set -eu

export ASSUME_ALWAYS_YES=yes
export IGNORE_OSVERSION=yes

log() { printf '\n==> %s\n' "$*"; }
need() { [ -e "$1" ] || { echo "Chybí $1" >&2; exit 1; }; }

log "Balíčkový repozitář a binární závislosti"
mkdir -p /usr/local/etc/pkg/repos
cat > /usr/local/etc/pkg/repos/FreeBSD.conf <<'EOF'
FreeBSD: { url: "pkg+https://pkg.FreeBSD.org/${ABI}/latest", mirror_type: "srv", enabled: yes }
EOF
pkg bootstrap -f
pkg update -f
pkg install -y git pkgconf nginx php84 php84-bcmath php84-ctype php84-curl php84-dom php84-fileinfo php84-filter php84-gd php84-gettext php84-iconv php84-ldap php84-mbstring php84-mysqli php84-session php84-simplexml php84-sockets php84-xml php84-xmlreader php84-xmlwriter mariadb114-server mariadb114-client curl libevent libxml2 pcre2 fping

log "Porty Zabbix 8"
if ! pkg info -e zabbix8-server || ! pkg info -e zabbix8-agent || ! pkg info -e 'zabbix8-frontend-php84'; then
  if [ ! -f /usr/ports/net-mgmt/zabbix8-server/Makefile ]; then
    git clone --depth 1 https://git.FreeBSD.org/ports.git /usr/ports
  fi
  need /usr/ports/net-mgmt/zabbix8-server/Makefile
  cat > /etc/make.conf <<'EOF'
BATCH=yes
ALLOW_UNSUPPORTED_SYSTEM=yes
DEFAULT_VERSIONS+= php=84 mysql=114m
EOF
  for port in zabbix8-server zabbix8-agent zabbix8-frontend; do
    case "$port" in
      zabbix8-frontend) installed='zabbix8-frontend-php84' ;;
      *) installed="$port" ;;
    esac
    if ! pkg info -e "$installed"; then
      if [ "$port" != zabbix8-server ] && pkg search -q "^${installed}-8\\." | grep -q .; then
        pkg install -y "$installed"
      else
        if [ "$port" = zabbix8-server ]; then
          make -C "/usr/ports/net-mgmt/$port" OPTIONS_UNSET='IPMI SNMP SSH UNIXODBC' package install clean
        else
          make -C "/usr/ports/net-mgmt/$port" package install clean
        fi
      fi
    fi
  done
fi

log "MariaDB"
sysrc mysql_enable=YES
service mysql-server onestart 2>/dev/null || service mysql-server status
SECRET_DIR=/var/db/zabbix-install
install -d -m 700 "$SECRET_DIR"
if [ ! -s "$SECRET_DIR/db-password" ]; then
  umask 077
  openssl rand -hex 24 > "$SECRET_DIR/db-password"
fi
DB_PASSWORD=$(cat "$SECRET_DIR/db-password")
mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
CREATE USER IF NOT EXISTS 'zabbix'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER 'zabbix'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

SCHEMA=/usr/local/share/zabbix8/server/database/mysql
need "$SCHEMA/schema.sql"
if ! mysql -uroot -N -e "SELECT 1 FROM information_schema.tables WHERE table_schema='zabbix' AND table_name='dbversion'" | grep -q 1; then
  log "První import databáze"
  mysql -uroot zabbix < "$SCHEMA/schema.sql"
  mysql -uroot zabbix < "$SCHEMA/images.sql"
  mysql -uroot zabbix < "$SCHEMA/data.sql"
fi

log "Konfigurace serveru a agenta"
SERVER_CONF=/usr/local/etc/zabbix8/zabbix_server.conf
AGENT_CONF=/usr/local/etc/zabbix8/zabbix_agentd.conf
need "$SERVER_CONF.sample"
need "$AGENT_CONF.sample"
cp "$SERVER_CONF.sample" "$SERVER_CONF"
cp "$AGENT_CONF.sample" "$AGENT_CONF"
sed -i '' -E '/^[[:space:]]*(DBHost|DBName|DBUser|DBPassword|Timeout)=/d' "$SERVER_CONF"
sed -i '' -E '/^[[:space:]]*(Server|ServerActive|Hostname|UserParameter|Timeout)=/d' "$AGENT_CONF"
cat >> "$SERVER_CONF" <<EOF
DBHost=127.0.0.1
DBName=zabbix
DBUser=zabbix
DBPassword=${DB_PASSWORD}
Timeout=15
EOF
chmod 600 "$SERVER_CONF"
cat >> "$AGENT_CONF" <<'EOF'
Server=127.0.0.1
ServerActive=127.0.0.1
Hostname=spos-zabbix8
Timeout=15
UserParameter=sposdk.cert.days,/usr/local/libexec/zabbix/sposdk-cert-days.sh
EOF
install -d -m 755 /usr/local/libexec/zabbix
install -m 755 /vagrant/scripts/sposdk-cert-days.sh /usr/local/libexec/zabbix/sposdk-cert-days.sh

log "PHP a nginx"
sysrc php_fpm_enable=YES nginx_enable=YES zabbix_server_enable=YES zabbix_agentd_enable=YES
cat > /usr/local/etc/php.ini <<'EOF'
date.timezone = Europe/Prague
max_execution_time = 300
memory_limit = 256M
post_max_size = 32M
upload_max_filesize = 16M
EOF
FRONTEND=$(pkg info -l zabbix8-frontend-php84 | awk '/\/api_jsonrpc.php$/ {sub(/\/api_jsonrpc.php$/, "", $1); print $1; exit}')
[ -n "$FRONTEND" ] || { echo 'Nelze najít frontend' >&2; exit 1; }
install -d -m 750 -o www -g www "$FRONTEND/conf"
cat > "$FRONTEND/conf/zabbix.conf.php" <<EOF
<?php
\$DB['TYPE'] = 'MYSQL';
\$DB['SERVER'] = '127.0.0.1';
\$DB['PORT'] = '3306';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER'] = 'zabbix';
\$DB['PASSWORD'] = '${DB_PASSWORD}';
\$DB['SCHEMA'] = '';
\$DB['ENCRYPTION'] = false;
\$ZBX_SERVER = '127.0.0.1';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = 'SmEjDiL · FreeBSD 14.3 · Zabbix 8';
EOF
chown www:www "$FRONTEND/conf/zabbix.conf.php"
chmod 600 "$FRONTEND/conf/zabbix.conf.php"
cat > /usr/local/etc/nginx/nginx.conf <<EOF
worker_processes auto;
events { worker_connections 1024; }
http {
  include mime.types;
  default_type application/octet-stream;
  server {
    listen 80;
    server_name localhost;
    root $FRONTEND;
    index index.php;
    client_max_body_size 16m;
    location / { try_files \$uri \$uri/ /index.php?\$args; }
    location ~ \\.php\$ {
      fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
      fastcgi_pass 127.0.0.1:9000;
      fastcgi_index index.php;
      include fastcgi_params;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    location ~ /\\.(?!well-known) { deny all; }
    location ~ ^/(conf|app|include|local|vendor)/ { deny all; }
  }
}
EOF
nginx -t
for svc in php-fpm nginx zabbix_server zabbix_agentd; do
  service "$svc" restart 2>/dev/null || service "$svc" start
done

log "Založení monitorovaných hostů"
/usr/local/bin/php /vagrant/scripts/configure-hosts.php

log "Hotovo: http://127.0.0.1:8080/"
echo "Heslo Admin je ve VM v /var/db/zabbix-install/admin-password (přístup root)."
