# Example.com Domain Configuration

This directory contains the DNS configuration for the `example.com` domain.

## Files:
- `example.com.db` - Forward zone file for example.com

## Usage:
This is a template/example domain. Copy this structure for your own domains:

```bash
mkdir -p config/yourdomain.com
cp config/example.com/example.com.db config/yourdomain.com/yourdomain.com.db
# Edit the zone file for your domain
```

## Zone File Structure:
The zone file follows modern BIND standards with proper formatting and includes:
- SOA record with appropriate parameters
- NS records for name servers
- A records for hosts
- CNAME records for aliases
