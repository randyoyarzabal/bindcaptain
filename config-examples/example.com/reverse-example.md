# Reverse DNS Zones

This directory contains reverse DNS zone files for PTR record resolution.

## Files:
- `1.0.10.in-addr.arpa.db` - Reverse zone for 10.0.1.x subnet
- `2.0.10.in-addr.arpa.db` - Reverse zone for 10.0.2.x subnet  
- `3.0.10.in-addr.arpa.db` - Reverse zone for 10.0.3.x subnet
- `reverse.in-addr.arpa.db` - Template reverse zone file

## Purpose:
Reverse zones enable reverse DNS lookups (IP to hostname resolution) which are:
- Required for many services (email, SSH, etc.)
- Useful for logging and monitoring
- Best practice for professional DNS implementations

## Automated Generation:
PTR records are automatically created when A records are added using `bc.create_record`. No external tools or cron jobs are required - reverse DNS is handled inline for immediate consistency.
