# Políticas y Procedimientos de Seguridad

## 🛡️ Resumen de Seguridad

Este sistema implementa múltiples capas de seguridad para proteger tus datos privados:

- **Nivel 1**: Cifrado de disco completo (LUKS2 AES-256)
- **Nivel 2**: Firewall restrictivo (UFW)
- **Nivel 3**: Protección contra intrusiones (Fail2ban, AIDE)
- **Nivel 4**: Hardening del sistema operativo
- **Nivel 5**: VPN para acceso remoto seguro
- **Nivel 6**: Monitorización y alertas continuas

## 🔐 Cifrado

### Cifrado en Reposo
- **Algoritmo**: LUKS2 con AES-XTS-PLAIN64
- **Tamaño de clave**: 512 bits
- **Hash**: SHA-512
- **Almacenamiento**: RAID1 completo cifrado

### Cifrado en Tránsito
- **HTTPS**: TLS 1.2/1.3 con cifrados modernos
- **VPN**: WireGuard con ChaCha20-Poly1305
- **SSH**: Ed25519 + RSA con algoritmos hardened

## 🔒 Autenticación

### SSH
- ❌ Contraseñas deshabilitadas
- ✅ Solo claves públicas (Ed25519/RSA 4096)
- ✅ Máximo 3 intentos de login
- ✅ Banner de advertencia
- ✅ Logging verbose

### Nextcloud
- ✅ Contraseñas fuertes requeridas (14+ caracteres)
- ✅ 2FA disponible (TOTP)
- ✅ Límite de intentos de login
- ✅ Sesiones con timeout

### VPN
- ✅ Autenticación por clave pública
- ✅ Clientes individuales con claves únicas
- ✅ Revocación de clientes comprometidos

## 🚨 Detección de Intrusiones

### Fail2ban
Protección activa contra:
- Ataques de fuerza bruta SSH
- Escaneo de puertos
- Ataques a Nginx
- Bots maliciosos

**Configuración**:
- 3 intentos fallidos = ban de 1 hora
- 3 bans = ban de 24 horas (recidive)
- IPs locales en whitelist

### AIDE (Advanced Intrusion Detection)
- Monitoreo de integridad de archivos críticos
- Verificación diaria automática
- Alertas por cambios no autorizados

**Archivos monitorizados**:
- `/etc/ssh/`
- `/etc/network/`
- `/etc/cron.*`
- `/etc/sudoers`
- `/etc/passwd`, `/etc/shadow`
- `/usr/local/bin/`

## 🔍 Auditoría

### Auditd
Registro completo de:
- Cambios en configuración de red
- Modificaciones de usuarios/grupos
- Cambios en sudoers
- Intentos de login
- Cambios en cron
- Carga/descarga de módulos del kernel

### Logs
Ubicación de logs críticos:
- `/var/log/auth.log` - Autenticación
- `/var/log/fail2ban.log` - Bans
- `/var/log/nginx/` - Acceso web
- `/var/log/audit/` - Auditoría del sistema
- `/var/log/cloud-backup.log` - Backups

**Retención**: 12 semanas con rotación automática

## 🌐 Firewall

### Reglas UFW

**Puertos abiertos**:
- 22/TCP - SSH (limitado)
- 80/TCP - HTTP (redirige a HTTPS)
- 443/TCP - HTTPS
- 51820/UDP - WireGuard VPN

**Política por defecto**:
- Entrante: DENY
- Saliente: ALLOW

### Protección DDoS
- Rate limiting en SSH
- SYN cookies habilitadas
- Límites de conexiones simultáneas

## 🔑 Gestión de Claves

### Claves Críticas a Proteger

> [!CAUTION]
> La pérdida de estas claves puede resultar en pérdida PERMANENTE de datos

1. **Contraseña LUKS**: Cifrado del disco
   - Ubicación: Solo en tu memoria + backup externo
   - Backup header: `/root/luks-backup/`

2. **Contraseña Restic**: Backups cifrados
   - Ubicación: `/root/.restic-password`
   - Permisos: 600 (solo root)

3. **Claves SSH**: Acceso al sistema
   - Ubicación: `~/.ssh/id_ed25519`
   - Backup: Guardar en lugar seguro

4. **Claves WireGuard**: Acceso VPN
   - Servidor: `/etc/wireguard/server_private.key`
   - Clientes: `/etc/wireguard/clients/`

### Rotación de Claves

**SSH** (anualmente):
```bash
ssh-keygen -t ed25519 -C "nueva-clave-$(date +%Y)"
# Añadir a authorized_keys
# Eliminar clave antigua después de verificar
```

**VPN** (cuando sea necesario):
```bash
sudo add-vpn-client.sh nuevo-cliente
# Revocar cliente antiguo editando /etc/wireguard/wg0.conf
```

## 🚨 Procedimientos de Emergencia

### Sistema Comprometido

1. **Desconectar de Internet**
   ```bash
   sudo ufw disable
   sudo systemctl stop wg-quick@wg0
   ```

2. **Revisar logs**
   ```bash
   sudo lastb | head -50
   sudo journalctl -xe
   sudo fail2ban-client status
   ```

3. **Verificar integridad**
   ```bash
   sudo aide --check
   sudo rkhunter --check
   ```

4. **Restaurar desde backup**
   ```bash
   sudo restore-cloud.sh
   ```

### Disco RAID Fallido

1. **Verificar estado**
   ```bash
   cat /proc/mdstat
   mdadm --detail /dev/md0
   ```

2. **Reemplazar disco**
   ```bash
   sudo mdadm /dev/md0 --fail /dev/sdX1
   sudo mdadm /dev/md0 --remove /dev/sdX1
   # Reemplazar físicamente el disco
   sudo mdadm /dev/md0 --add /dev/sdY1
   ```

3. **Monitorear reconstrucción**
   ```bash
   watch cat /proc/mdstat
   ```

### Contraseña LUKS Olvidada

> [!WARNING]
> Sin la contraseña LUKS o el backup del header, los datos son IRRECUPERABLES

**Si tienes backup del header**:
1. Intenta todas las contraseñas posibles
2. Contacta con experto en recuperación de datos
3. Como último recurso, restaura desde backups externos

### Acceso SSH Perdido

1. **Acceso físico**
   - Conecta monitor y teclado
   - Login local

2. **Recuperar acceso SSH**
   ```bash
   # Verificar servicio
   sudo systemctl status sshd
   
   # Revisar configuración
   sudo sshd -t
   
   # Añadir nueva clave
   cat nueva-clave.pub >> ~/.ssh/authorized_keys
   ```

## 📋 Checklist de Auditoría Mensual

- [ ] Ejecutar `sudo lynis audit system`
- [ ] Revisar logs de fail2ban
- [ ] Verificar estado del RAID
- [ ] Comprobar espacio en disco
- [ ] Test de restauración de backup
- [ ] Revisar usuarios del sistema
- [ ] Verificar actualizaciones pendientes
- [ ] Comprobar temperatura máxima del mes
- [ ] Revisar clientes VPN activos
- [ ] Verificar certificados SSL (expiración)

## 🔄 Actualizaciones de Seguridad

### Automáticas
- Actualizaciones de seguridad: Diarias (unattended-upgrades)
- Reinicio automático: Deshabilitado (manual)

### Manuales
```bash
# Verificar actualizaciones
sudo apt update
sudo apt list --upgradable

# Aplicar actualizaciones
sudo apt upgrade -y

# Reiniciar si es necesario
sudo needrestart
```

## 📊 Indicadores de Seguridad

### KPIs a Monitorizar

1. **Intentos de login fallidos**: < 10/día
2. **IPs baneadas**: Revisar semanalmente
3. **Temperatura**: < 70°C
4. **Uso de disco**: < 80%
5. **Uptime**: > 99%
6. **Backups exitosos**: 100%

### Alertas Configuradas

- 🌡️ Temperatura > 75°C
- 💾 Disco > 90%
- 🔴 Servicio caído
- ⚠️ RAID degradado
- 🔒 Múltiples intentos de login fallidos
- 📦 Backup fallido

## 🎯 Mejores Prácticas

### Contraseñas
- ✅ Mínimo 14 caracteres
- ✅ Mezcla de mayúsculas, minúsculas, números, símbolos
- ✅ Única para cada servicio
- ✅ Gestor de contraseñas recomendado
- ❌ Nunca reutilizar contraseñas

### Acceso Remoto
- ✅ Siempre usar VPN
- ✅ Verificar certificados SSL
- ✅ Cerrar sesión después de usar
- ❌ Nunca desde redes públicas sin VPN

### Backups
- ✅ Verificar backups mensualmente
- ✅ Guardar backup del header LUKS externamente
- ✅ Test de restauración trimestral
- ✅ Backups offsite recomendados

### Mantenimiento
- ✅ Revisar logs semanalmente
- ✅ Actualizar sistema mensualmente
- ✅ Auditoría de seguridad trimestral
- ✅ Rotación de claves anualmente

## 📞 Contactos de Emergencia

Mantén una lista de:
- [ ] Experto en Linux/seguridad de confianza
- [ ] Servicio de recuperación de datos
- [ ] Proveedor de Internet (para port forwarding)
- [ ] Documentación offline de este sistema

---

**Última actualización**: 2026-01-28  
**Próxima revisión**: 2026-04-28
