#!/bin/bash
###############################################################################
# Auditoría y Pentesting Automatizado
# Ejecuta herramientas de auditoría de seguridad
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ejecutarse como root (sudo)"
   exit 1
fi

REPORT_DIR="/root/security-audit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$REPORT_DIR"

log_info "╔════════════════════════════════════════════════════════════╗"
log_info "║     AUDITORÍA DE SEGURIDAD AUTOMATIZADA                   ║"
log_info "╚════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# 1. LYNIS - Auditoría completa del sistema
# ============================================================================

log_info "[1/7] Ejecutando Lynis (Auditoría del sistema)..."

if ! command -v lynis &> /dev/null; then
    apt install -y lynis
fi

lynis audit system --quick --report-file "$REPORT_DIR/lynis-report.txt" > "$REPORT_DIR/lynis-output.txt" 2>&1

# ============================================================================
# 2. CHKROOTKIT - Detección de rootkits
# ============================================================================

log_info "[2/7] Ejecutando chkrootkit..."

if ! command -v chkrootkit &> /dev/null; then
    apt install -y chkrootkit
fi

chkrootkit > "$REPORT_DIR/chkrootkit.txt" 2>&1

# ============================================================================
# 3. RKHUNTER - Detección de rootkits avanzada
# ============================================================================

log_info "[3/7] Ejecutando rkhunter..."

if ! command -v rkhunter &> /dev/null; then
    apt install -y rkhunter
fi

rkhunter --update
rkhunter --check --skip-keypress --report-warnings-only > "$REPORT_DIR/rkhunter.txt" 2>&1

# ============================================================================
# 4. NMAP - Escaneo de puertos (auto-pentesting)
# ============================================================================

log_info "[4/7] Ejecutando nmap (escaneo de puertos)..."

if ! command -v nmap &> /dev/null; then
    apt install -y nmap
fi

# Escaneo completo
nmap -sS -sV -O -p- localhost > "$REPORT_DIR/nmap-localhost.txt" 2>&1

# Escaneo de vulnerabilidades
nmap --script vuln localhost > "$REPORT_DIR/nmap-vulns.txt" 2>&1

# ============================================================================
# 5. NIKTO - Escaneo de vulnerabilidades web
# ============================================================================

log_info "[5/7] Ejecutando Nikto (vulnerabilidades web)..."

if ! command -v nikto &> /dev/null; then
    apt install -y nikto
fi

nikto -h https://localhost -output "$REPORT_DIR/nikto.txt" 2>&1 || true

# ============================================================================
# 6. OPENVAS/GVM - Vulnerability Scanner (opcional)
# ============================================================================

log_info "[6/7] Verificando configuración de seguridad..."

# Verificar permisos de archivos críticos
cat > "$REPORT_DIR/file-permissions.txt" << EOF
=== PERMISOS DE ARCHIVOS CRÍTICOS ===

/etc/passwd:
$(ls -l /etc/passwd)

/etc/shadow:
$(ls -l /etc/shadow)

/etc/ssh/sshd_config:
$(ls -l /etc/ssh/sshd_config)

/root:
$(ls -ld /root)

Archivos SUID:
$(find / -perm -4000 -type f 2>/dev/null)

Archivos world-writable:
$(find / -perm -002 -type f 2>/dev/null | head -20)
EOF

# ============================================================================
# 7. ANÁLISIS DE LOGS
# ============================================================================

log_info "[7/7] Analizando logs de seguridad..."

cat > "$REPORT_DIR/log-analysis.txt" << EOF
=== ANÁLISIS DE LOGS DE SEGURIDAD ===

Últimos intentos de login fallidos:
$(lastb | head -20)

Últimos logins exitosos:
$(last | head -20)

IPs baneadas por Fail2ban:
$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP" || echo "Fail2ban no configurado")

Alertas de seguridad en syslog:
$(grep -i "security\|auth\|fail" /var/log/syslog | tail -50)

Conexiones de red activas:
$(netstat -tunap | grep ESTABLISHED)
EOF

# ============================================================================
# GENERAR REPORTE CONSOLIDADO
# ============================================================================

log_info "Generando reporte consolidado..."

cat > "$REPORT_DIR/RESUMEN.txt" << EOF
╔════════════════════════════════════════════════════════════╗
║     REPORTE DE AUDITORÍA DE SEGURIDAD                      ║
║     Fecha: $(date)                                         ║
╚════════════════════════════════════════════════════════════╝

ARCHIVOS GENERADOS:
  - lynis-report.txt       : Auditoría completa del sistema
  - chkrootkit.txt         : Detección de rootkits
  - rkhunter.txt           : Detección avanzada de rootkits
  - nmap-localhost.txt     : Escaneo de puertos
  - nmap-vulns.txt         : Vulnerabilidades detectadas
  - nikto.txt              : Vulnerabilidades web
  - file-permissions.txt   : Permisos de archivos críticos
  - log-analysis.txt       : Análisis de logs

RESUMEN DE HALLAZGOS:

1. LYNIS Score:
$(grep "Hardening index" "$REPORT_DIR/lynis-output.txt" || echo "Ver lynis-report.txt")

2. Rootkits detectados:
$(grep -i "warning\|infected" "$REPORT_DIR/chkrootkit.txt" | wc -l) advertencias en chkrootkit
$(grep -i "warning" "$REPORT_DIR/rkhunter.txt" | wc -l) advertencias en rkhunter

3. Puertos abiertos:
$(grep "open" "$REPORT_DIR/nmap-localhost.txt" | wc -l) puertos abiertos detectados

4. Vulnerabilidades web:
$(grep -i "OSVDB" "$REPORT_DIR/nikto.txt" 2>/dev/null | wc -l || echo "0") vulnerabilidades potenciales

5. Intentos de intrusión:
$(lastb | wc -l) intentos de login fallidos registrados

RECOMENDACIONES:
  1. Revisa lynis-report.txt para sugerencias de hardening
  2. Investiga cualquier advertencia de rootkit
  3. Cierra puertos innecesarios detectados por nmap
  4. Aplica parches para vulnerabilidades web encontradas
  5. Monitorea IPs con intentos de login fallidos

PRÓXIMOS PASOS:
  - Ejecutar esta auditoría mensualmente
  - Implementar sugerencias de Lynis
  - Mantener sistema actualizado
  - Revisar logs regularmente

EOF

# Calcular score de seguridad
LYNIS_SCORE=$(grep "Hardening index" "$REPORT_DIR/lynis-output.txt" | grep -oP '\d+' | head -1 || echo "0")
OPEN_PORTS=$(grep "open" "$REPORT_DIR/nmap-localhost.txt" | wc -l)
FAILED_LOGINS=$(lastb | wc -l)

cat >> "$REPORT_DIR/RESUMEN.txt" << EOF

╔════════════════════════════════════════════════════════════╗
║     SCORE DE SEGURIDAD                                     ║
╚════════════════════════════════════════════════════════════╝

Lynis Hardening Index: ${LYNIS_SCORE}/100
Puertos abiertos: ${OPEN_PORTS}
Intentos de intrusión: ${FAILED_LOGINS}

EOF

if [[ $LYNIS_SCORE -gt 80 ]]; then
    echo "Estado: ✅ EXCELENTE" >> "$REPORT_DIR/RESUMEN.txt"
elif [[ $LYNIS_SCORE -gt 60 ]]; then
    echo "Estado: ⚠️  BUENO (mejorable)" >> "$REPORT_DIR/RESUMEN.txt"
else
    echo "Estado: ❌ REQUIERE ATENCIÓN" >> "$REPORT_DIR/RESUMEN.txt"
fi

# ============================================================================
# FINALIZAR
# ============================================================================

log_info ""
log_info "╔════════════════════════════════════════════════════════════╗"
log_info "║     AUDITORÍA COMPLETADA                                   ║"
log_info "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Reportes guardados en: $REPORT_DIR"
log_info "Lee el resumen: cat $REPORT_DIR/RESUMEN.txt"
echo ""

# Mostrar resumen
cat "$REPORT_DIR/RESUMEN.txt"

# Comprimir reportes
cd "$(dirname "$REPORT_DIR")"
tar -czf "$(basename "$REPORT_DIR").tar.gz" "$(basename "$REPORT_DIR")"
log_info "Reportes comprimidos: $(basename "$REPORT_DIR").tar.gz"
