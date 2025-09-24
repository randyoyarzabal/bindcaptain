# Reverse DNS Zones

This directory contains reverse DNS zone files for PTR record resolution.

## Files:
- `40.25.172.in-addr.arpa.db` - Reverse zone for 172.25.40.x subnet
- `42.25.172.in-addr.arpa.db` - Reverse zone for 172.25.42.x subnet  
- `50.25.172.in-addr.arpa.db` - Reverse zone for 172.25.50.x subnet
- `reverse.in-addr.arpa.db` - Template reverse zone file

## Purpose:
Reverse zones enable reverse DNS lookups (IP to hostname resolution) which are:
- Required for many services (email, SSH, etc.)
- Useful for logging and monitoring
- Best practice for professional DNS implementations

## Automated Generation:
The `bindcaptain_refresh.sh` script can automatically generate reverse zone entries based on A records in forward zones.
