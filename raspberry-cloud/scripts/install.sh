#!/bin/bash
###############################################################################
# Script Maestro de Instalación
# Ejecuta todos los scripts de instalación en orden
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[PASO $1/7]${NC} $2"; }

if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root (sudo)"
   exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║     RASPBERRY PI 5 - SISTEMA DE NUBE PRIVADA SEGURA       ║"
echo "║                                                            ║"
echo "║              Instalación Completa Automatizada            ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_warn "Este script instalará y configurará:"
echo "  1. Sistema operativo hardened"
echo "  2. RAID1 + Cifrado LUKS"
echo "  3. Seguridad avanzada (Firewall, Fail2ban, AIDE)"
echo "  4. Nextcloud"
echo "  5. VPN WireGuard"
echo "  6. Sistema de backups"
echo "  7. Monitorización"
echo ""
log_warn "La instalación completa puede tardar 1-2 horas"
echo ""

read -p "¿Deseas continuar? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Instalación cancelada"
    exit 0
fi

# Función para ejecutar script con manejo de errores
run_script() {
    local step=$1
    local script=$2
    local description=$3
    
    log_step "$step" "$description"
    
    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        log_error "Script no encontrado: $script"
        exit 1
    fi
    
    chmod +x "$SCRIPT_DIR/$script"
    
    if bash "$SCRIPT_DIR/$script"; then
        log_info "✓ Completado: $description"
        echo ""
    else
        log_error "✗ Error en: $description"
        log_error "Revisa los logs y ejecuta manualmente: $script"
        exit 1
    fi
}

# PASO 1: Sistema Base
run_script 1 "01-os-setup.sh" "Configuración del sistema base y hardening"

log_warn "╔════════════════════════════════════════════════════════════╗"
log_warn "║  REINICIO REQUERIDO                                        ║"
log_warn "║  El sistema necesita reiniciarse para aplicar cambios     ║"
log_warn "║  Después del reinicio, ejecuta este script nuevamente     ║"
log_warn "║  con la opción --continue                                 ║"
log_warn "╚════════════════════════════════════════════════════════════╝"
echo ""

# Crear flag para continuar después del reinicio
touch /root/.cloud-install-step1-complete

read -p "¿Reiniciar ahora? (yes/no): " REBOOT
if [[ "$REBOOT" == "yes" ]]; then
    log_info "Reiniciando en 5 segundos..."
    sleep 5
    reboot
else
    log_info "Reinicia manualmente y ejecuta: sudo $0 --continue"
    exit 0
fi
