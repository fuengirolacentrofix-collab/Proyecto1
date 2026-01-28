#!/bin/bash
###############################################################################
# Raspberry Pi 5 - Instalación de Nextcloud
# Servidor de nube privada optimizado para Raspberry Pi 5
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root (sudo)"
   exit 1
fi

log_info "=== Instalación de Nextcloud ==="

# Variables
NEXTCLOUD_VERSION="28.0.1"
NEXTCLOUD_DIR="/var/www/nextcloud"
DATA_DIR="/mnt/secure_cloud/nextcloud-data"
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS=$(openssl rand -base64 32)

# Solicitar dominio
read -p "Introduce tu dominio (ej: cloud.tudominio.com) o IP local: " DOMAIN

# 1. Instalar dependencias
log_info "Instalando dependencias..."
apt update
apt install -y \
    nginx \
    mariadb-server \
    php8.1-fpm \
    php8.1-mysql \
    php8.1-curl \
    php8.1-gd \
    php8.1-intl \
    php8.1-mbstring \
    php8.1-xml \
    php8.1-zip \
    php8.1-bcmath \
    php8.1-gmp \
    php8.1-imagick \
    php8.1-redis \
    php8.1-apcu \
    redis-server \
    unzip \
    wget \
    certbot \
    python3-certbot-nginx

# 2. Configurar MariaDB
log_info "Configurando MariaDB..."

# Optimizaciones para Raspberry Pi
cat > /etc/mysql/mariadb.conf.d/99-nextcloud.cnf << 'EOF'
[mysqld]
# Optimizaciones para Raspberry Pi 5
innodb_buffer_pool_size = 512M
innodb_log_file_size = 128M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1

# Configuración general
max_connections = 50
query_cache_type = 1
query_cache_limit = 2M
query_cache_size = 64M
tmp_table_size = 64M
max_heap_table_size = 64M

# Binlog
binlog_format = ROW
transaction_isolation = READ-COMMITTED

# Charset
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
EOF

systemctl restart mariadb

# Crear base de datos
mysql << EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

log_info "Base de datos creada"

# 3. Configurar PHP
log_info "Configurando PHP..."

PHP_INI="/etc/php/8.1/fpm/php.ini"
cp "$PHP_INI" "${PHP_INI}.backup"

# Optimizaciones PHP
sed -i 's/memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 10G/' "$PHP_INI"
sed -i 's/post_max_size = .*/post_max_size = 10G/' "$PHP_INI"
sed -i 's/max_execution_time = .*/max_execution_time = 3600/' "$PHP_INI"
sed -i 's/max_input_time = .*/max_input_time = 3600/' "$PHP_INI"
sed -i 's/;opcache.enable=.*/opcache.enable=1/' "$PHP_INI"
sed -i 's/;opcache.memory_consumption=.*/opcache.memory_consumption=128/' "$PHP_INI"
sed -i 's/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=16/' "$PHP_INI"
sed -i 's/;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' "$PHP_INI"
sed -i 's/;opcache.save_comments=.*/opcache.save_comments=1/' "$PHP_INI"

# Configurar PHP-FPM
PHP_FPM_CONF="/etc/php/8.1/fpm/pool.d/www.conf"
cp "$PHP_FPM_CONF" "${PHP_FPM_CONF}.backup"

sed -i 's/pm = .*/pm = dynamic/' "$PHP_FPM_CONF"
sed -i 's/pm.max_children = .*/pm.max_children = 20/' "$PHP_FPM_CONF"
sed -i 's/pm.start_servers = .*/pm.start_servers = 4/' "$PHP_FPM_CONF"
sed -i 's/pm.min_spare_servers = .*/pm.min_spare_servers = 2/' "$PHP_FPM_CONF"
sed -i 's/pm.max_spare_servers = .*/pm.max_spare_servers = 6/' "$PHP_FPM_CONF"

systemctl restart php8.1-fpm

# 4. Descargar Nextcloud
log_info "Descargando Nextcloud ${NEXTCLOUD_VERSION}..."
cd /tmp
wget "https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.zip"
wget "https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.zip.sha256"

# Verificar checksum
sha256sum -c "nextcloud-${NEXTCLOUD_VERSION}.zip.sha256" < "nextcloud-${NEXTCLOUD_VERSION}.zip"

# Extraer
unzip -q "nextcloud-${NEXTCLOUD_VERSION}.zip" -d /var/www/

# Crear directorio de datos
mkdir -p "$DATA_DIR"

# Configurar permisos
chown -R www-data:www-data "$NEXTCLOUD_DIR"
chown -R www-data:www-data "$DATA_DIR"
chmod -R 750 "$DATA_DIR"

# 5. Configurar Redis
log_info "Configurando Redis..."
sed -i 's/^# unixsocket /unixsocket /' /etc/redis/redis.conf
sed -i 's/^# unixsocketperm 700/unixsocketperm 770/' /etc/redis/redis.conf
usermod -a -G redis www-data
systemctl restart redis-server

# 6. Configurar Nginx
log_info "Configurando Nginx..."

cat > /etc/nginx/sites-available/nextcloud << EOF
upstream php-handler {
    server unix:/var/run/php/php8.1-fpm.sock;
}

# Redirigir HTTP a HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    
    # Para Let's Encrypt
    location ^~ /.well-known/acme-challenge {
        default_type text/plain;
        root /var/www/nextcloud;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    # SSL (se configurará con certbot)
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    
    # SSL hardening
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer" always;
    
    # Path
    root ${NEXTCLOUD_DIR};
    
    # Logs
    access_log /var/log/nginx/nextcloud.access.log;
    error_log /var/log/nginx/nextcloud.error.log;
    
    # Client body size
    client_max_body_size 10G;
    client_body_timeout 300s;
    fastcgi_buffers 64 4K;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
    
    # Nextcloud configuration
    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }
    
    location ^~ /.well-known {
        location = /.well-known/carddav { return 301 /remote.php/dav/; }
        location = /.well-known/caldav  { return 301 /remote.php/dav/; }
        location /.well-known/acme-challenge    { try_files \$uri \$uri/ =404; }
        location /.well-known/pki-validation    { try_files \$uri \$uri/ =404; }
        return 301 /index.php\$request_uri;
    }
    
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:\$|/)  { return 404; }
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }
    
    location ~ \.php(?:\$|/) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        set \$path_info \$fastcgi_path_info;
        
        try_files \$fastcgi_script_name =404;
        
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
        
        fastcgi_read_timeout 3600;
        fastcgi_send_timeout 3600;
        fastcgi_connect_timeout 3600;
    }
    
    location ~ \.(?:css|js|svg|gif|png|jpg|ico|wasm|tflite|map)$ {
        try_files \$uri /index.php\$request_uri;
        expires 6M;
        access_log off;
    }
    
    location ~ \.woff2?$ {
        try_files \$uri /index.php\$request_uri;
        expires 7d;
        access_log off;
    }
    
    location / {
        try_files \$uri \$uri/ /index.php\$request_uri;
    }
}
EOF

# Habilitar sitio
ln -sf /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test y reload
nginx -t
systemctl reload nginx

log_info "Nginx configurado"

# 7. Guardar credenciales
CREDS_FILE="/root/nextcloud-credentials.txt"
cat > "$CREDS_FILE" << EOF
╔════════════════════════════════════════════════════════════╗
║           CREDENCIALES DE NEXTCLOUD                        ║
╚════════════════════════════════════════════════════════════╝

Dominio: ${DOMAIN}
URL: https://${DOMAIN}

Base de Datos:
  Nombre: ${DB_NAME}
  Usuario: ${DB_USER}
  Contraseña: ${DB_PASS}

Directorio de datos: ${DATA_DIR}
Directorio de instalación: ${NEXTCLOUD_DIR}

IMPORTANTE: Guarda este archivo en un lugar seguro y elimínalo del servidor
EOF

chmod 600 "$CREDS_FILE"

log_info "=== Instalación de Nextcloud completada ==="
echo ""
log_info "Accede a: https://${DOMAIN}"
log_info "Completa la instalación web con estos datos:"
log_info "  - Usuario admin: (elige uno)"
log_info "  - Contraseña admin: (elige una fuerte)"
log_info "  - Directorio de datos: ${DATA_DIR}"
log_info "  - Base de datos: MariaDB/MySQL"
log_info "  - Usuario BD: ${DB_USER}"
log_info "  - Contraseña BD: ${DB_PASS}"
log_info "  - Nombre BD: ${DB_NAME}"
log_info "  - Host BD: localhost"
echo ""
log_warn "Credenciales guardadas en: ${CREDS_FILE}"
log_warn "IMPORTANTE: Configura SSL con certbot después de la instalación"
log_info "Comando: sudo certbot --nginx -d ${DOMAIN}"
