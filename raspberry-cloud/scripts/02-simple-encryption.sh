#!/bin/bash
###############################################################################
# Versión SIMPLIFICADA - Un solo disco con cifrado (sin RAID)
# Para pruebas en VM o sistemas sin RAID
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

log_info "=== Configuración de Disco Cifrado (Sin RAID) ==="

# Instalar herramientas
log_info "Instalando herramientas de cifrado..."
apt update
apt install -y cryptsetup lvm2 parted

log_info "Discos disponibles:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "sda\|vda"
echo ""

read -p "Introduce el disco a cifrar (ej: sdb, vdb): " DISK
DISK_PATH="/dev/${DISK}"

if [[ ! -b "$DISK_PATH" ]]; then
    log_error "El disco no existe"
    exit 1
fi

log_warn "Se cifrará: $DISK_PATH - TODOS LOS DATOS SE PERDERÁN"
read -p "¿Continuar? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Operación cancelada"
    exit 0
fi

# Limpiar disco
log_info "Limpiando disco..."
wipefs -a "$DISK_PATH"

# Crear partición
log_info "Creando partición..."
parted -s "$DISK_PATH" mklabel gpt
parted -s "$DISK_PATH" mkpart primary 0% 100%
sleep 2
partprobe

PART="${DISK_PATH}1"

# Configurar cifrado LUKS
log_info "Configurando cifrado LUKS2..."
cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --iter-time 5000 \
    --use-random \
    "$PART"

log_info "Abriendo volumen cifrado..."
cryptsetup luksOpen "$PART" secure_storage

# Crear sistema de archivos
log_info "Creando sistema de archivos..."
mkfs.ext4 -L SecureCloud /dev/mapper/secure_storage

# Montar
MOUNT_POINT="/mnt/secure_cloud"
mkdir -p "$MOUNT_POINT"
mount /dev/mapper/secure_storage "$MOUNT_POINT"

# Permisos
chown -R clouduser:clouduser "$MOUNT_POINT" 2>/dev/null || chown -R www-data:www-data "$MOUNT_POINT"
chmod 750 "$MOUNT_POINT"

# Backup header
BACKUP_DIR="/root/luks-backup"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cryptsetup luksHeaderBackup "$PART" \
    --header-backup-file "$BACKUP_DIR/luks-header-backup-$(date +%Y%m%d).img"

# Auto-montaje
log_info "¿Configurar auto-montaje? (yes/no): "
read -p "> " AUTO_MOUNT

if [[ "$AUTO_MOUNT" == "yes" ]]; then
    KEYFILE="/root/.luks-keyfile"
    dd if=/dev/urandom of="$KEYFILE" bs=4096 count=1
    chmod 400 "$KEYFILE"
    cryptsetup luksAddKey "$PART" "$KEYFILE"
    echo "secure_storage $PART $KEYFILE luks" >> /etc/crypttab
    echo "/dev/mapper/secure_storage $MOUNT_POINT ext4 defaults,noatime 0 2" >> /etc/fstab
fi

log_info "=== Configuración completada ==="
log_info "Punto de montaje: $MOUNT_POINT"
df -h "$MOUNT_POINT"
