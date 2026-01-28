# Guía de Mantenimiento

## 📅 Calendario de Mantenimiento

### Tareas Automáticas ✅

Estas tareas se ejecutan automáticamente:

| Tarea | Frecuencia | Hora | Script |
|-------|-----------|------|--------|
| Backup completo | Diario | 2:00 AM | `backup-cloud.sh` |
| Reporte del sistema | Diario | 8:00 AM | `daily-report.sh` |
| Monitoreo temperatura | Cada 5 min | - | `temp-monitor.sh` |
| Verificación RAID | Diario | 6:00 AM | `check-raid.sh` |
| Verificación AIDE | Diario | 3:00 AM | `aide-check` |
| Actualizaciones seguridad | Diario | 4:00 AM | `unattended-upgrades` |
| Rotación de logs | Semanal | Domingo | `logrotate` |

### Tareas Manuales 🔧

#### Diarias
- [ ] Revisar email de reporte diario (si configurado)
- [ ] Verificar alertas de temperatura/disco

#### Semanales
```bash
# Revisar logs de seguridad
sudo lastb | head -20
sudo fail2ban-client status sshd

# Verificar servicios
sudo system-monitor.sh

# Revisar espacio en disco
df -h
```

#### Mensuales
```bash
# Actualizar sistema
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y

# Auditoría de seguridad
sudo lynis audit system

# Verificar integridad
sudo aide --check

# Revisar clientes VPN
sudo vpn-status.sh

# Test de backup
sudo restore-cloud.sh
# (restaurar un archivo de prueba)

# Verificar certificados SSL
sudo certbot certificates
```

#### Trimestrales
- [ ] Cambiar contraseñas críticas
- [ ] Revisar usuarios del sistema
- [ ] Auditoría completa de seguridad
- [ ] Test completo de restauración
- [ ] Verificar backup del header LUKS
- [ ] Limpiar archivos antiguos

#### Anuales
- [ ] Rotación de claves SSH
- [ ] Renovación de certificados (si no es automático)
- [ ] Revisión completa de configuración
- [ ] Actualización de documentación
- [ ] Plan de recuperación ante desastres

## 🔧 Procedimientos de Mantenimiento

### Actualización del Sistema

```bash
# 1. Verificar actualizaciones disponibles
sudo apt update
sudo apt list --upgradable

# 2. Crear snapshot de backup antes de actualizar
sudo backup-cloud.sh

# 3. Aplicar actualizaciones
sudo apt upgrade -y

# 4. Verificar si se requiere reinicio
sudo needrestart

# 5. Si es necesario, reiniciar
sudo reboot

# 6. Después del reinicio, verificar servicios
sudo system-monitor.sh
```

### Actualización de Nextcloud

```bash
# 1. Backup antes de actualizar
sudo backup-cloud.sh

# 2. Poner en modo mantenimiento
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on

# 3. Actualizar
sudo -u www-data php /var/www/nextcloud/updater/updater.phar

# 4. Ejecutar upgrade
sudo -u www-data php /var/www/nextcloud/occ upgrade

# 5. Optimizar base de datos
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint

# 6. Salir de modo mantenimiento
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off

# 7. Verificar
curl -I https://tu-dominio.com
```

### Limpieza de Disco

```bash
# Limpiar caché de Nextcloud
sudo -u www-data php /var/www/nextcloud/occ files:cleanup

# Limpiar logs antiguos
sudo journalctl --vacuum-time=30d

# Limpiar paquetes
sudo apt autoremove -y
sudo apt autoclean

# Limpiar archivos temporales
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# Verificar espacio liberado
df -h
```

### Mantenimiento del RAID

```bash
# Verificar estado
cat /proc/mdstat
sudo mdadm --detail /dev/md0

# Verificar errores
sudo mdadm --examine /dev/sda1 /dev/sdb1

# Scrubbing (verificación de integridad)
echo check > /sys/block/md0/md/sync_action

# Monitorear progreso
watch cat /proc/mdstat

# Ver resultado
cat /sys/block/md0/md/mismatch_cnt
# (debe ser 0)
```

### Mantenimiento de Backups

```bash
# Verificar backups recientes
sudo backup-status.sh

# Listar snapshots
export RESTIC_PASSWORD_FILE="/root/.restic-password"
export RESTIC_REPOSITORY="/mnt/secure_cloud/backups"
restic snapshots

# Verificar integridad
restic check --read-data-subset=10%

# Limpiar snapshots antiguos manualmente
restic forget --keep-daily 30 --keep-weekly 12 --keep-monthly 12 --prune

# Estadísticas
restic stats
```

### Mantenimiento de VPN

```bash
# Ver clientes conectados
sudo vpn-status.sh

# Revocar cliente comprometido
sudo nano /etc/wireguard/wg0.conf
# (eliminar sección [Peer] del cliente)
sudo systemctl restart wg-quick@wg0

# Añadir nuevo cliente
sudo add-vpn-client.sh nombre-nuevo-cliente

# Verificar logs
sudo journalctl -u wg-quick@wg0 -n 50
```

## 🔍 Monitorización

### Comandos de Diagnóstico

```bash
# Estado general del sistema
sudo system-monitor.sh

# Estado de seguridad
sudo security-status.sh

# Temperatura
vcgencmd measure_temp

# Uso de CPU
top -bn1 | head -15

# Uso de memoria
free -h

# Uso de disco
df -h

# Procesos de red
sudo netstat -tulpn | grep LISTEN

# Logs en tiempo real
sudo tail -f /var/log/syslog
sudo journalctl -f
```

### Métricas Importantes

| Métrica | Valor Normal | Acción si Excede |
|---------|--------------|------------------|
| Temperatura CPU | < 70°C | Verificar ventilación |
| Uso de disco | < 80% | Limpiar archivos |
| Uso de RAM | < 80% | Reiniciar servicios |
| Load average | < 2.0 | Investigar procesos |
| Uptime | > 30 días | Normal |

## 🚨 Resolución de Problemas

### Nextcloud Lento

```bash
# 1. Verificar recursos
htop

# 2. Reiniciar servicios
sudo systemctl restart php8.1-fpm
sudo systemctl restart nginx
sudo systemctl restart redis-server

# 3. Limpiar caché
sudo -u www-data php /var/www/nextcloud/occ files:scan --all
sudo -u www-data php /var/www/nextcloud/occ files:cleanup

# 4. Optimizar BD
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
```

### Disco Lleno

```bash
# 1. Identificar uso
sudo du -sh /* | sort -h
sudo du -sh /mnt/secure_cloud/* | sort -h

# 2. Limpiar backups antiguos
restic forget --keep-daily 15 --keep-weekly 8 --prune

# 3. Limpiar logs
sudo journalctl --vacuum-size=100M

# 4. Limpiar Nextcloud
sudo -u www-data php /var/www/nextcloud/occ trashbin:cleanup --all-users
sudo -u www-data php /var/www/nextcloud/occ versions:cleanup
```

### Servicio Caído

```bash
# Identificar servicio
sudo systemctl list-units --failed

# Ver logs del servicio
sudo journalctl -u nombre-servicio -n 50

# Reiniciar servicio
sudo systemctl restart nombre-servicio

# Verificar estado
sudo systemctl status nombre-servicio
```

### Alta Temperatura

```bash
# Verificar temperatura
vcgencmd measure_temp

# Verificar procesos
htop

# Verificar ventilación física
# - Limpiar polvo
# - Verificar ventilador
# - Mejorar flujo de aire

# Reducir carga temporalmente
sudo systemctl stop nextcloud-cron
```

## 📊 Logs Importantes

### Ubicaciones de Logs

```bash
# Sistema
/var/log/syslog
/var/log/auth.log
/var/log/kern.log

# Servicios
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/log/fail2ban.log
/var/log/cloud-backup.log

# Systemd
sudo journalctl -u nginx
sudo journalctl -u php8.1-fpm
sudo journalctl -u mariadb
sudo journalctl -u wg-quick@wg0
```

### Análisis de Logs

```bash
# Últimos errores
sudo journalctl -p err -n 50

# Logs de un servicio específico
sudo journalctl -u nginx --since "1 hour ago"

# Seguir logs en tiempo real
sudo journalctl -f

# Buscar en logs
sudo grep "error" /var/log/nginx/error.log | tail -20
```

## 🔄 Backup y Restauración

### Backup Manual

```bash
# Backup completo
sudo backup-cloud.sh

# Verificar backup
sudo backup-status.sh
```

### Restauración

```bash
# Listar backups
sudo restore-cloud.sh
# (seguir instrucciones interactivas)

# Restaurar archivo específico
export RESTIC_PASSWORD_FILE="/root/.restic-password"
export RESTIC_REPOSITORY="/mnt/secure_cloud/backups"
restic restore latest --target /tmp/restore --include /ruta/al/archivo
```

## 📋 Checklist de Mantenimiento Mensual

```markdown
## Mantenimiento Mes: ___________

### Sistema
- [ ] Actualizar sistema operativo
- [ ] Verificar espacio en disco
- [ ] Revisar temperatura máxima
- [ ] Verificar uptime y estabilidad

### Seguridad
- [ ] Ejecutar lynis audit
- [ ] Revisar fail2ban logs
- [ ] Verificar AIDE
- [ ] Revisar usuarios SSH

### Servicios
- [ ] Actualizar Nextcloud
- [ ] Optimizar base de datos
- [ ] Limpiar caché
- [ ] Verificar certificados SSL

### Backups
- [ ] Test de restauración
- [ ] Verificar integridad
- [ ] Limpiar snapshots antiguos
- [ ] Verificar espacio de backups

### RAID
- [ ] Verificar estado
- [ ] Ejecutar scrubbing
- [ ] Verificar errores

### VPN
- [ ] Revisar clientes activos
- [ ] Verificar conectividad
- [ ] Revisar logs

### Notas
_______________________________________________
_______________________________________________
_______________________________________________
```

## 📞 Contactos y Recursos

### Comandos de Emergencia

```bash
# Parada de emergencia
sudo systemctl stop nginx php8.1-fpm mariadb

# Desconectar de Internet
sudo ufw disable

# Modo solo lectura
sudo mount -o remount,ro /mnt/secure_cloud
```

### Recursos Útiles

- Documentación Nextcloud: https://docs.nextcloud.com/
- WireGuard: https://www.wireguard.com/
- Raspberry Pi: https://www.raspberrypi.org/documentation/

---

**Mantén este documento actualizado con tus procedimientos específicos**
