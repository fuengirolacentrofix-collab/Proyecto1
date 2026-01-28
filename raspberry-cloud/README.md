# Raspberry Pi 5 - Sistema de Nube Privada Segura

Sistema completo de almacenamiento en la nube privado y ultra-seguro para Raspberry Pi 5 con cifrado RAID1, VPN, y múltiples capas de seguridad.

## 🎯 Características

### Seguridad Básica
- **Almacenamiento Cifrado**: RAID1 con cifrado LUKS2 (1TB)
- **Nube Privada**: Nextcloud optimizado para Raspberry Pi 5
- **Acceso Remoto Seguro**: VPN WireGuard
- **Seguridad Avanzada**: Firewall, Fail2ban, SSH hardening, AIDE
- **Backups Automáticos**: Sistema de backups cifrados con restic
- **Monitorización**: Prometheus + scripts personalizados
- **Alertas**: Temperatura, disco, seguridad

### 🛡️ Seguridad Militar (NUEVO)
- **Port Knocking**: SSH completamente invisible
- **2FA**: Autenticación de dos factores obligatoria
- **Suricata IDS/IPS**: Detección y prevención de intrusiones en tiempo real
- **OSSEC HIDS**: Monitoreo de integridad del sistema
- **SELinux/AppArmor**: Control de acceso obligatorio (MAC)
- **Honeypot**: Trampa para atacantes en puerto 22
- **Geoblocking**: Bloqueo de países de alto riesgo
- **Canary Tokens**: Detección de acceso no autorizado
- **USBGuard**: Protección contra BadUSB
- **Auditoría Automatizada**: Escaneo completo de vulnerabilidades

## 📋 Requisitos

### Hardware
- Raspberry Pi 5 (4GB+ RAM recomendado)
- 2x Discos duros externos de 1TB (para RAID1)
- MicroSD 32GB+ (para sistema operativo)
- Fuente de alimentación oficial
- Conexión a Internet

### Software
- Raspberry Pi OS Lite 64-bit (instalación fresca)
- Acceso SSH configurado
- Usuario con privilegios sudo

## 🚀 Instalación Rápida

### 1. Preparación Inicial

```bash
# Actualizar sistema
sudo apt update && sudo apt upgrade -y

# Clonar repositorio
cd ~
git clone <tu-repositorio> raspberry-cloud
cd raspberry-cloud/scripts

# Dar permisos de ejecución
chmod +x *.sh
```

### 2. Instalación por Pasos

Ejecuta los scripts en orden:

```bash
# Paso 1: Configurar sistema base y hardening
sudo ./01-os-setup.sh

# Reiniciar (IMPORTANTE)
sudo reboot

# Paso 2: Configurar RAID1 + Cifrado
sudo ./02-raid-encryption.sh

# Paso 3: Hardening de seguridad
sudo ./03-security-hardening.sh

# Paso 4: Instalar Nextcloud
sudo ./04-nextcloud-install.sh

# Paso 5: Configurar VPN WireGuard
sudo ./05-wireguard-vpn.sh

# Paso 6: Sistema de backups
sudo ./06-backup-system.sh

# Paso 7: Monitorización
sudo ./07-monitoring.sh

# OPCIONAL - Seguridad Nivel Militar:
# Paso 8: Hardening avanzado (Port knocking, IDS/IPS, Honeypot, etc.)
sudo ./08-advanced-hardening.sh

# Paso 9: 2FA para SSH
sudo ./09-ssh-2fa.sh
setup-user-2fa.sh  # Ejecutar como usuario normal

# Paso 10: Auditoría de seguridad
sudo ./10-security-audit.sh
```

### 3. Configuración Post-Instalación

#### Configurar Nextcloud
1. Accede a `https://tu-dominio-o-ip`
2. Crea usuario administrador
3. Usa las credenciales de BD guardadas en `/root/nextcloud-credentials.txt`

#### Configurar SSL (Let's Encrypt)
```bash
sudo certbot --nginx -d tu-dominio.com
```

#### Configurar Port Forwarding en Router
- Puerto 443 (HTTPS) → IP de Raspberry Pi
- Puerto 51820 (UDP, WireGuard) → IP de Raspberry Pi

## 📱 Conectar Clientes VPN

### Crear nuevo cliente
```bash
sudo add-vpn-client.sh nombre-cliente
```

Esto generará:
- Archivo de configuración en `/etc/wireguard/clients/`
- Código QR para móviles

### Importar en dispositivos
- **Windows/Linux**: Importa el archivo `.conf` en WireGuard
- **Android/iOS**: Escanea el código QR con la app WireGuard

## 🛠️ Comandos Útiles

### Estado del Sistema
```bash
sudo security-status.sh      # Estado de seguridad
sudo system-monitor.sh        # Monitorización general
sudo vpn-status.sh           # Estado VPN
sudo backup-status.sh        # Estado de backups
sudo daily-report.sh         # Reporte completo
```

### Gestión de Backups
```bash
sudo backup-cloud.sh         # Backup manual
sudo restore-cloud.sh        # Restaurar backup
```

### Gestión VPN
```bash
sudo add-vpn-client.sh <nombre>    # Añadir cliente
sudo systemctl restart wg-quick@wg0 # Reiniciar VPN
```

### Servicios
```bash
# Reiniciar servicios
sudo systemctl restart nginx
sudo systemctl restart php8.1-fpm
sudo systemctl restart mariadb

# Ver logs
sudo journalctl -u nginx -f
sudo journalctl -u wg-quick@wg0 -f
sudo tail -f /var/log/fail2ban.log
```

## 🔒 Seguridad

### Capas de Seguridad Implementadas

1. **Cifrado en Reposo**: LUKS2 con AES-256
2. **Cifrado en Tránsito**: TLS 1.3, WireGuard
3. **Firewall**: UFW con reglas restrictivas
4. **Protección contra Intrusiones**: Fail2ban, AIDE
5. **SSH Hardening**: Solo claves, algoritmos modernos
6. **Auditoría**: auditd con reglas completas
7. **Kernel Hardening**: sysctl optimizado

### Archivos Críticos a Guardar

⚠️ **IMPORTANTE**: Guarda estos archivos en un lugar seguro externo:

- `/root/luks-backup/luks-header-backup-*.img` - Header LUKS
- `/root/.restic-password` - Contraseña de backups
- `/root/nextcloud-credentials.txt` - Credenciales Nextcloud
- `/root/wireguard-info.txt` - Info VPN
- `/etc/wireguard/clients/*.conf` - Configuraciones VPN clientes

## 📊 Monitorización

### Prometheus
- URL: `http://localhost:9090`
- Métricas: Sistema, Nginx, Node

### Alertas Automáticas
- Temperatura > 75°C
- Disco > 90%
- Servicios caídos
- RAID degradado

### Reportes
- Reporte diario: 8:00 AM (por email si configurado)
- Verificación temperatura: cada 5 minutos
- Backups: diariamente a las 2:00 AM

## 🔧 Mantenimiento

### Tareas Diarias (Automáticas)
- ✓ Verificación de temperatura
- ✓ Monitoreo de RAID
- ✓ Reporte de seguridad

### Tareas Semanales
```bash
# Verificar actualizaciones
sudo apt update && sudo apt list --upgradable

# Revisar logs de seguridad
sudo lastb | head -20
sudo fail2ban-client status sshd
```

### Tareas Mensuales
```bash
# Auditoría de seguridad
sudo lynis audit system

# Verificar integridad de archivos
sudo aide --check

# Test de restauración de backup
sudo restore-cloud.sh
```

## 🆘 Solución de Problemas

### RAID Degradado
```bash
# Ver estado
cat /proc/mdstat
mdadm --detail /dev/md0

# Reemplazar disco fallido
sudo mdadm /dev/md0 --remove /dev/sdX1
sudo mdadm /dev/md0 --add /dev/sdY1
```

### Nextcloud Lento
```bash
# Optimizar base de datos
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint

# Limpiar caché
sudo -u www-data php /var/www/nextcloud/occ files:cleanup
```

### VPN No Conecta
```bash
# Verificar servicio
sudo systemctl status wg-quick@wg0

# Ver logs
sudo journalctl -u wg-quick@wg0 -n 50

# Verificar firewall
sudo ufw status
```

## 📚 Documentación Adicional

- [SECURITY.md](docs/SECURITY.md) - Políticas de seguridad
- [MAINTENANCE.md](docs/MAINTENANCE.md) - Guía de mantenimiento
- [Nextcloud Documentation](https://docs.nextcloud.com/)
- [WireGuard Documentation](https://www.wireguard.com/quickstart/)

## ⚡ Optimizaciones para Raspberry Pi 5

- PHP-FPM optimizado para ARM
- MariaDB con configuración de baja memoria
- Redis para caché
- OPcache habilitado
- Nginx con compresión gzip
- Límites de recursos ajustados

## 🔄 Actualizaciones

### Actualizar Nextcloud
```bash
sudo -u www-data php /var/www/nextcloud/updater/updater.phar
sudo -u www-data php /var/www/nextcloud/occ upgrade
```

### Actualizar Sistema
```bash
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y
```

## 📞 Soporte

Para problemas o preguntas:
1. Revisa los logs: `/var/log/`
2. Ejecuta: `sudo daily-report.sh`
3. Consulta la documentación específica

## 📝 Licencia

Este proyecto es de código abierto. Úsalo bajo tu propia responsabilidad.

---

**Creado para Raspberry Pi 5 - Sistema de Nube Privada Ultra-Seguro**
