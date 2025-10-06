# Troubleshooting Guide

Common issues and solutions for BindCaptain DNS server.

## Quick Diagnostics

### Check System Status

```bash
# Overall status
sudo ./bindcaptain.sh status

# Container status
sudo podman ps | grep bindcaptain

# BIND process status
sudo podman exec bindcaptain ps aux | grep named
```

### Test DNS Resolution

```bash
# Test forward lookup
dig @localhost example.com

# Test reverse lookup
dig @localhost -x 192.168.1.100

# Test with nslookup
nslookup example.com localhost
```

## Common Issues

### Container Issues

#### Container Won't Start

**Symptoms:**
- Container fails to start
- Error messages about port binding
- Permission denied errors

**Solutions:**

```bash
# Check if port 53 is in use
sudo netstat -tlnp | grep :53

# Kill conflicting processes
sudo pkill -f named
sudo systemctl stop named

# Check Podman status
sudo systemctl status podman

# Start container with debug
sudo podman run --rm -it bindcaptain:latest named -g -u named -d 3
```

#### Container Keeps Restarting

**Symptoms:**
- Container starts then immediately stops
- Restart loop in logs
- Configuration errors

**Solutions:**

```bash
# Check container logs
sudo podman logs bindcaptain

# Check configuration syntax
sudo named-checkconf /opt/bindcaptain/config/named.conf

# Validate zone files
sudo ./bindcaptain.sh validate

# Start with minimal config
sudo podman run --rm -it bindcaptain:latest named -g -u named -c /dev/null
```

### DNS Resolution Issues

#### DNS Not Resolving

**Symptoms:**
- DNS queries timeout
- "Name or service not known" errors
- No response from DNS server

**Solutions:**

```bash
# Check BIND status
sudo podman exec bindcaptain systemctl status named

# Check zone configuration
sudo ./tools/bindcaptain_manager.sh validate-zone example.com

# Test with dig
dig @localhost example.com +trace

# Check firewall
sudo firewall-cmd --list-all
sudo firewall-cmd --add-service=dns --permanent
sudo firewall-cmd --reload
```

#### Wrong DNS Responses

**Symptoms:**
- Incorrect IP addresses returned
- Old records still showing
- Zone not updated

**Solutions:**

```bash
# Reload BIND configuration
sudo ./bindcaptain.sh reload

# Check zone file
sudo cat /opt/bindcaptain/zones/example.com.db

# Validate zone
sudo named-checkzone example.com /opt/bindcaptain/zones/example.com.db

# Force zone reload
sudo ./tools/bindcaptain_manager.sh refresh
```

### Configuration Issues

#### Configuration Syntax Errors

**Symptoms:**
- BIND won't start
- Configuration validation fails
- Syntax error messages

**Solutions:**

```bash
# Check main configuration
sudo named-checkconf /opt/bindcaptain/config/named.conf

# Check specific zone
sudo named-checkzone example.com /opt/bindcaptain/zones/example.com.db

# Validate all zones
sudo ./bindcaptain.sh validate

# Edit configuration
sudo nano /opt/bindcaptain/config/named.conf
```

#### Zone File Issues

**Symptoms:**
- Zone not loading
- Zone validation fails
- Missing records

**Solutions:**

```bash
# Check zone file syntax
sudo named-checkzone example.com /opt/bindcaptain/zones/example.com.db

# Recreate zone file
sudo ./tools/config-setup.sh create-zone example.com

# Check file permissions
sudo ls -la /opt/bindcaptain/zones/

# Fix permissions
sudo chown root:named /opt/bindcaptain/zones/*.db
sudo chmod 640 /opt/bindcaptain/zones/*.db
```

### Permission Issues

#### Permission Denied Errors

**Symptoms:**
- Cannot write to zone files
- Cannot start container
- Access denied errors

**Solutions:**

```bash
# Fix ownership
sudo chown -R root:root /opt/bindcaptain
sudo chown -R root:named /opt/bindcaptain/zones/

# Fix permissions
sudo chmod +x /opt/bindcaptain/tools/*.sh
sudo chmod 640 /opt/bindcaptain/zones/*.db

# Check SELinux
sudo setsebool -P container_manage_cgroup on
sudo restorecon -R /opt/bindcaptain/
```

#### SELinux Issues

**Symptoms:**
- Container cannot access files
- Permission denied on mounts
- SELinux audit errors

**Solutions:**

```bash
# Check SELinux status
sudo getenforce

# Enable container SELinux booleans
sudo setsebool -P container_manage_cgroup on
sudo setsebool -P container_use_cephfs on

# Fix file contexts
sudo restorecon -R /opt/bindcaptain/
sudo chcon -R -t container_file_t /opt/bindcaptain/

# Check audit logs
sudo ausearch -m avc -ts recent
```

### Network Issues

#### Port Binding Issues

**Symptoms:**
- Cannot bind to port 53
- Port already in use
- Permission denied on port

**Solutions:**

```bash
# Check what's using port 53
sudo netstat -tlnp | grep :53
sudo lsof -i :53

# Kill conflicting processes
sudo pkill -f named
sudo systemctl stop named

# Check firewall
sudo firewall-cmd --list-ports
sudo firewall-cmd --add-port=53/tcp --permanent
sudo firewall-cmd --add-port=53/udp --permanent
sudo firewall-cmd --reload
```

#### Firewall Issues

**Symptoms:**
- DNS queries blocked
- Cannot connect from external hosts
- Firewall blocking traffic

**Solutions:**

```bash
# Check firewall status
sudo systemctl status firewalld
sudo firewall-cmd --state

# Add DNS service
sudo firewall-cmd --add-service=dns --permanent
sudo firewall-cmd --reload

# Check firewall rules
sudo firewall-cmd --list-all

# Test connectivity
telnet localhost 53
```

## Debugging Commands

### Container Debugging

```bash
# Check container logs
sudo podman logs bindcaptain

# Execute commands in container
sudo podman exec -it bindcaptain bash

# Check container processes
sudo podman exec bindcaptain ps aux

# Monitor container resources
sudo podman stats bindcaptain
```

### BIND Debugging

```bash
# Start BIND with debug logging
sudo podman exec bindcaptain named -g -u named -d 3

# Check BIND configuration
sudo podman exec bindcaptain named-checkconf /etc/named.conf

# Test zone files
sudo podman exec bindcaptain named-checkzone example.com /var/named/example.com.db

# Monitor DNS queries
sudo podman exec bindcaptain tcpdump -i any port 53
```

### System Debugging

```bash
# Check system logs
sudo journalctl -u bindcaptain
sudo journalctl -u podman

# Check DNS resolution
dig @localhost example.com +trace
nslookup example.com localhost

# Check network connectivity
ping localhost
telnet localhost 53
```

## Log Analysis

### BIND Logs

```bash
# View BIND logs
sudo tail -f /opt/bindcaptain/logs/named.log

# Search for errors
sudo grep -i error /opt/bindcaptain/logs/named.log

# Search for specific queries
sudo grep "example.com" /opt/bindcaptain/logs/named.log
```

### Container Logs

```bash
# View container logs
sudo podman logs bindcaptain

# Follow logs in real-time
sudo podman logs -f bindcaptain

# View logs with timestamps
sudo podman logs -t bindcaptain
```

### System Logs

```bash
# View systemd logs
sudo journalctl -u bindcaptain -f

# View Podman logs
sudo journalctl -u podman -f

# Search for specific errors
sudo journalctl -u bindcaptain | grep -i error
```

## Performance Issues

### High CPU Usage

**Symptoms:**
- High CPU usage by BIND
- Slow DNS responses
- System performance degradation

**Solutions:**

```bash
# Check BIND processes
sudo podman exec bindcaptain top

# Monitor query patterns
sudo podman exec bindcaptain tcpdump -i any port 53

# Check zone file sizes
sudo ls -lh /opt/bindcaptain/zones/

# Optimize configuration
sudo nano /opt/bindcaptain/config/named.conf
```

### Memory Issues

**Symptoms:**
- High memory usage
- Out of memory errors
- Container killed by OOM

**Solutions:**

```bash
# Check memory usage
sudo podman stats bindcaptain

# Monitor BIND memory
sudo podman exec bindcaptain ps aux | grep named

# Check zone file sizes
sudo du -sh /opt/bindcaptain/zones/

# Optimize cache settings
sudo nano /opt/bindcaptain/config/named.conf
```

## Recovery Procedures

### Complete Reset

```bash
# Stop and remove container
sudo ./bindcaptain.sh stop
sudo podman rm bindcaptain

# Remove container image
sudo podman rmi bindcaptain:latest

# Clean configuration
sudo rm -rf /opt/bindcaptain/config/*
sudo rm -rf /opt/bindcaptain/zones/*

# Rebuild and restart
sudo ./bindcaptain.sh build
sudo ./tools/config-setup.sh wizard
sudo ./bindcaptain.sh run
```

### Zone Recovery

```bash
# Restore from backup
sudo ./tools/config-setup.sh restore backup-2024-01-15

# Recreate specific zone
sudo ./tools/config-setup.sh create-zone example.com

# Restore zone file
sudo cp /opt/bindcaptain/backups/example.com.db /opt/bindcaptain/zones/
sudo chown root:named /opt/bindcaptain/zones/example.com.db
sudo chmod 640 /opt/bindcaptain/zones/example.com.db
```

### Configuration Recovery

```bash
# Restore configuration
sudo cp /opt/bindcaptain/backups/named.conf /opt/bindcaptain/config/

# Validate configuration
sudo named-checkconf /opt/bindcaptain/config/named.conf

# Reload BIND
sudo ./bindcaptain.sh reload
```

## Getting Help

### Log Collection

```bash
# Collect diagnostic information
sudo ./bindcaptain.sh diagnose > bindcaptain-diagnosis.txt

# Collect logs
sudo podman logs bindcaptain > container-logs.txt
sudo tail -100 /opt/bindcaptain/logs/named.log > bind-logs.txt

# Collect configuration
sudo cp /opt/bindcaptain/config/named.conf configuration.txt
```

### Support Information

When seeking help, provide:

- **OS and version**: `cat /etc/os-release`
- **Podman version**: `podman --version`
- **Container status**: `sudo ./bindcaptain.sh status`
- **Error messages**: From logs and command output
- **Configuration**: Relevant config files
- **Steps to reproduce**: What you were doing when the issue occurred

---

**Still having issues?** Check the [Configuration Reference](config-reference.md) or [DNS Operations](dns-operations.md) for more detailed information.
