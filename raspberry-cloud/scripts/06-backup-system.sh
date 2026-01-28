#!/bin/bash
###############################################################################
# Raspberry Pi 5 - Sistema de Backups Automáticos
# Backups cifrados con restic
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

log_info "=== Configuración de Sistema de Backups ==="

# 1. Instalar restic
log_info "Instalando restic..."
apt update
apt install -y restic

# 2. Configurar repositorio de backups
BACKUP_DIR="/mnt/secure_cloud/backups"
DATA_DIR="/mnt/secure_cloud/nextcloud-data"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

log_info "Inicializando repositorio de backups..."
log_warn "Crea una contraseña FUERTE para los backups"

# Generar contraseña aleatoria o solicitar una
read -p "¿Generar contraseña aleatoria? (yes/no): " GEN_PASS

if [[ "$GEN_PASS" == "yes" ]]; then
    BACKUP_PASSWORD=$(openssl rand -base64 32)
    echo "$BACKUP_PASSWORD" > /root/.restic-password
    chmod 600 /root/.restic-password
    log_info "Contraseña generada y guardada en /root/.restic-password"
else
    read -sp "Introduce contraseña para backups: " BACKUP_PASSWORD
    echo ""
    echo "$BACKUP_PASSWORD" > /root/.restic-password
    chmod 600 /root/.restic-password
fi

# Inicializar repositorio
export RESTIC_PASSWORD_FILE="/root/.restic-password"
export RESTIC_REPOSITORY="$BACKUP_DIR"

restic init

# 3. Crear script de backup
cat > /usr/local/bin/backup-cloud.sh << 'EOF'
#!/bin/bash

# Configuración
export RESTIC_PASSWORD_FILE="/root/.restic-password"
export RESTIC_REPOSITORY="/mnt/secure_cloud/backups"
DATA_DIR="/mnt/secure_cloud/nextcloud-data"
LOG_FILE="/var/log/cloud-backup.log"

# Logging
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Backup iniciado: $(date)"
echo "╚════════════════════════════════════════════════════════════╝"

# Backup de datos de Nextcloud
echo "[INFO] Realizando backup de datos..."
restic backup "$DATA_DIR" \
    --exclude="$DATA_DIR/*/cache" \
    --exclude="$DATA_DIR/*/thumbnails" \
    --exclude="*.tmp" \
    --tag nextcloud-data

# Backup de configuración del sistema
echo "[INFO] Realizando backup de configuración..."
restic backup \
    /etc/nginx \
    /etc/wireguard \
    /etc/ssh \
    /etc/fail2ban \
    --tag system-config

# Backup de base de datos
echo "[INFO] Realizando backup de base de datos..."
DB_BACKUP_DIR="/tmp/db-backup"
mkdir -p "$DB_BACKUP_DIR"

mysqldump --single-transaction nextcloud > "$DB_BACKUP_DIR/nextcloud.sql"
restic backup "$DB_BACKUP_DIR" --tag database

rm -rf "$DB_BACKUP_DIR"

# Limpiar snapshots antiguos (mantener últimos 30 días, 12 semanales, 12 mensuales)
echo "[INFO] Limpiando snapshots antiguos..."
restic forget \
    --keep-daily 30 \
    --keep-weekly 12 \
    --keep-monthly 12 \
    --prune

# Verificar integridad
echo "[INFO] Verificando integridad del repositorio..."
restic check --read-data-subset=5%

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Backup completado: $(date)"
echo "╚════════════════════════════════════════════════════════════╝"
EOF

chmod +x /usr/local/bin/backup-cloud.sh

# 4. Crear script de restauración
cat > /usr/local/bin/restore-cloud.sh << 'EOF'
#!/bin/bash

export RESTIC_PASSWORD_FILE="/root/.restic-password"
export RESTIC_REPOSITORY="/mnt/secure_cloud/backups"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║              RESTAURACIÓN DE BACKUP                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Listar snapshots disponibles
echo "Snapshots disponibles:"
restic snapshots

echo ""
read -p "Introduce el ID del snapshot a restaurar: " SNAPSHOT_ID

if [[ -z "$SNAPSHOT_ID" ]]; then
    echo "Error: Debes especificar un snapshot ID"
    exit 1
fi

read -p "Directorio de destino para restauración: " RESTORE_DIR

if [[ -z "$RESTORE_DIR" ]]; then
    echo "Error: Debes especificar un directorio de destino"
    exit 1
fi

mkdir -p "$RESTORE_DIR"

echo "Restaurando snapshot $SNAPSHOT_ID en $RESTORE_DIR..."
restic restore "$SNAPSHOT_ID" --target "$RESTORE_DIR"

echo ""
echo "Restauración completada en: $RESTORE_DIR"
EOF

chmod +x /usr/local/bin/restore-cloud.sh

# 5. Programar backups automáticos
log_info "Configurando backups automáticos..."

# Backup diario a las 2:00 AM
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup-cloud.sh") | crontab -

# 6. Crear script de información de backups
cat > /usr/local/bin/backup-status.sh << 'EOF'
#!/bin/bash

export RESTIC_PASSWORD_FILE="/root/.restic-password"
export RESTIC_REPOSITORY="/mnt/secure_cloud/backups"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║              ESTADO DE BACKUPS                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "=== Snapshots recientes ==="
restic snapshots --last 10
echo ""

echo "=== Estadísticas del repositorio ==="
restic stats
echo ""

echo "=== Espacio usado ==="
du -sh /mnt/secure_cloud/backups
echo ""

echo "=== Último backup ==="
if [[ -f /var/log/cloud-backup.log ]]; then
    tail -20 /var/log/cloud-backup.log
fi
EOF

chmod +x /usr/local/bin/backup-status.sh

# 7. Realizar primer backup
log_info "¿Deseas realizar el primer backup ahora? (yes/no): "
read -p "> " DO_BACKUP

if [[ "$DO_BACKUP" == "yes" ]]; then
    log_info "Realizando primer backup..."
    /usr/local/bin/backup-cloud.sh
fi

log_info "=== Sistema de backups configurado ==="
echo ""
log_info "COMANDOS ÚTILES:"
log_info "  - Realizar backup manual: sudo backup-cloud.sh"
log_info "  - Ver estado de backups: sudo backup-status.sh"
log_info "  - Restaurar backup: sudo restore-cloud.sh"
echo ""
log_info "Backups automáticos: Diariamente a las 2:00 AM"
log_info "Retención: 30 días diarios, 12 semanales, 12 mensuales"
echo ""
log_warn "IMPORTANTE: Contraseña de backups en /root/.restic-password"
log_warn "Guarda esta contraseña en un lugar seguro externo"
