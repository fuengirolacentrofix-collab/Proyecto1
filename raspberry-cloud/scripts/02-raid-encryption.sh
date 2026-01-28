#!/bin/bash
###############################################################################
# Raspberry Pi 5 - Configuración RAID1 + Cifrado LUKS
# Configura dos discos de 1TB en RAID1 con cifrado completo
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

log_info "=== Configuración RAID1 + Cifrado LUKS ==="

# Instalar herramientas necesarias
log_info "Instalando herramientas de RAID y cifrado..."
apt update
apt install -y mdadm cryptsetup lvm2 parted

# ADVERTENCIA
log_warn "╔════════════════════════════════════════════════════════════╗"
log_warn "║  ADVERTENCIA: Este script BORRARÁ todos los datos         ║"
log_warn "║  de los discos especificados                               ║"
log_warn "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Discos disponibles:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "mmcblk"
echo ""

read -p "Introduce el primer disco (ej: sda): " DISK1
read -p "Introduce el segundo disco (ej: sdb): " DISK2

DISK1_PATH="/dev/${DISK1}"
DISK2_PATH="/dev/${DISK2}"

# Verificar que los discos existen
if [[ ! -b "$DISK1_PATH" ]] || [[ ! -b "$DISK2_PATH" ]]; then
    log_error "Uno o ambos discos no existen"
    exit 1
fi

log_warn "Se configurará RAID1 en: $DISK1_PATH y $DISK2_PATH"
read -p "¿Continuar? Esto BORRARÁ todos los datos (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Operación cancelada"
    exit 0
fi

# 1. Limpiar discos
log_info "Limpiando discos..."
wipefs -a "$DISK1_PATH"
wipefs -a "$DISK2_PATH"

# 2. Crear particiones
log_info "Creando particiones..."
parted -s "$DISK1_PATH" mklabel gpt
parted -s "$DISK1_PATH" mkpart primary 0% 100%
parted -s "$DISK1_PATH" set 1 raid on

parted -s "$DISK2_PATH" mklabel gpt
parted -s "$DISK2_PATH" mkpart primary 0% 100%
parted -s "$DISK2_PATH" set 1 raid on

# Esperar a que el kernel reconozca las particiones
sleep 2
partprobe

PART1="${DISK1_PATH}1"
PART2="${DISK2_PATH}1"

# 3. Crear RAID1
log_info "Creando array RAID1..."
mdadm --create /dev/md0 \
    --level=1 \
    --raid-devices=2 \
    --metadata=1.2 \
    "$PART1" "$PART2"

# Guardar configuración RAID
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u

log_info "RAID1 creado. Estado:"
cat /proc/mdstat

# 4. Configurar cifrado LUKS
log_info "Configurando cifrado LUKS2..."
log_warn "Necesitarás crear una contraseña FUERTE para el cifrado"
log_warn "IMPORTANTE: Guarda esta contraseña en un lugar seguro"
echo ""

cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --iter-time 5000 \
    --use-random \
    /dev/md0

log_info "Abriendo volumen cifrado..."
cryptsetup luksOpen /dev/md0 secure_storage

# 5. Crear sistema de archivos
log_info "Creando sistema de archivos ext4..."
mkfs.ext4 -L SecureCloud /dev/mapper/secure_storage

# 6. Crear punto de montaje
MOUNT_POINT="/mnt/secure_cloud"
mkdir -p "$MOUNT_POINT"

# 7. Montar
log_info "Montando volumen..."
mount /dev/mapper/secure_storage "$MOUNT_POINT"

# 8. Configurar permisos
chown -R clouduser:clouduser "$MOUNT_POINT"
chmod 750 "$MOUNT_POINT"

# 9. Backup del header LUKS (CRÍTICO)
log_info "Creando backup del header LUKS..."
BACKUP_DIR="/root/luks-backup"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

cryptsetup luksHeaderBackup /dev/md0 \
    --header-backup-file "$BACKUP_DIR/luks-header-backup-$(date +%Y%m%d).img"

log_warn "╔════════════════════════════════════════════════════════════╗"
log_warn "║  CRÍTICO: Backup del header LUKS guardado en:             ║"
log_warn "║  $BACKUP_DIR                                               ║"
log_warn "║  COPIA ESTE ARCHIVO A UN LUGAR SEGURO EXTERNO             ║"
log_warn "║  Sin él, NO podrás recuperar tus datos si hay problemas   ║"
log_warn "╚════════════════════════════════════════════════════════════╝"

# 10. Configurar auto-montaje con keyfile (opcional pero recomendado)
log_info "¿Deseas configurar auto-montaje con keyfile?"
log_warn "Esto permite que el sistema monte automáticamente el disco"
log_warn "pero reduce ligeramente la seguridad (la clave estará en el sistema)"
read -p "Configurar auto-montaje? (yes/no): " AUTO_MOUNT

if [[ "$AUTO_MOUNT" == "yes" ]]; then
    KEYFILE="/root/.luks-keyfile"
    
    # Generar keyfile
    dd if=/dev/urandom of="$KEYFILE" bs=4096 count=1
    chmod 400 "$KEYFILE"
    
    # Añadir keyfile a LUKS
    log_info "Añadiendo keyfile a LUKS (necesitarás introducir la contraseña)..."
    cryptsetup luksAddKey /dev/md0 "$KEYFILE"
    
    # Configurar crypttab
    echo "secure_storage /dev/md0 $KEYFILE luks" >> /etc/crypttab
    
    # Configurar fstab
    echo "/dev/mapper/secure_storage $MOUNT_POINT ext4 defaults,noatime 0 2" >> /etc/fstab
    
    log_info "Auto-montaje configurado"
else
    log_info "Montaje manual requerido en cada reinicio"
    log_info "Usa: cryptsetup luksOpen /dev/md0 secure_storage"
    log_info "     mount /dev/mapper/secure_storage $MOUNT_POINT"
fi

# 11. Habilitar TRIM para SSDs (si aplica)
log_info "¿Tus discos son SSDs? (yes/no): "
read -p "> " IS_SSD

if [[ "$IS_SSD" == "yes" ]]; then
    # Habilitar TRIM periódico
    systemctl enable fstrim.timer
    systemctl start fstrim.timer
    log_info "TRIM habilitado para SSDs"
fi

# 12. Información del sistema
log_info "=== Configuración completada ==="
echo ""
log_info "Información del RAID:"
mdadm --detail /dev/md0
echo ""
log_info "Información del cifrado:"
cryptsetup luksDump /dev/md0 | head -20
echo ""
log_info "Espacio disponible:"
df -h "$MOUNT_POINT"
echo ""
log_info "Punto de montaje: $MOUNT_POINT"
log_info "Usuario propietario: clouduser"

# 13. Crear script de monitoreo RAID
cat > /usr/local/bin/check-raid.sh << 'EOF'
#!/bin/bash
# Script de monitoreo RAID

STATUS=$(cat /proc/mdstat | grep -A 2 md0)
FAILED=$(mdadm --detail /dev/md0 | grep "Failed Devices" | awk '{print $4}')

if [[ "$FAILED" != "0" ]]; then
    echo "ALERTA: RAID degradado - $FAILED disco(s) fallido(s)"
    echo "$STATUS"
    # Aquí puedes añadir notificación por email
fi
EOF

chmod +x /usr/local/bin/check-raid.sh

# Añadir a cron para verificación diaria
(crontab -l 2>/dev/null; echo "0 6 * * * /usr/local/bin/check-raid.sh") | crontab -

log_info "Script de monitoreo RAID instalado (se ejecuta diariamente a las 6:00)"

log_warn "╔════════════════════════════════════════════════════════════╗"
log_warn "║  RECUERDA:                                                 ║"
log_warn "║  1. Guarda la contraseña de cifrado en lugar seguro       ║"
log_warn "║  2. Copia el backup del header LUKS a otro dispositivo    ║"
log_warn "║  3. Monitorea el estado del RAID regularmente             ║"
log_warn "╚════════════════════════════════════════════════════════════╝"
