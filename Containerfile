# ⚓ BindCaptain - Multi-stage Containerfile for Modern BIND DNS
# Optimized for minimal final image size and maximum reusability
# Updated for BIND 9.16+ compatibility and security best practices

# =============================================================================
# BUILD STAGE - Install packages and prepare files
# =============================================================================
FROM docker.io/rockylinux:9 AS builder

# Install BIND and tools in build stage
RUN dnf update -y && \
    dnf install -y \
        bind \
        bind-utils \
        bind-chroot \
        curl \
        wget && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Verify BIND version for compatibility
RUN named -v

# Create directory structure
RUN mkdir -p \
        /build/var/named/data \
        /build/var/named/dynamic \
        /build/var/named/slaves \
        /build/var/log/named \
        /build/var/run/named \
        /build/usr/local/scripts \
        /build/var/backups/bind \
        /build/etc/bind

# Create essential BIND files (generic)
RUN echo '$TTL 3H' > /build/var/named/named.empty && \
    echo '@       IN SOA  @ rname.invalid. (' >> /build/var/named/named.empty && \
    echo '                        0       ; serial' >> /build/var/named/named.empty && \
    echo '                        1D      ; refresh' >> /build/var/named/named.empty && \
    echo '                        1H      ; retry' >> /build/var/named/named.empty && \
    echo '                        1W      ; expire' >> /build/var/named/named.empty && \
    echo '                        3H )    ; minimum' >> /build/var/named/named.empty && \
    echo '        NS      @' >> /build/var/named/named.empty && \
    echo '        A       127.0.0.1' >> /build/var/named/named.empty && \
    echo '        AAAA    ::1' >> /build/var/named/named.empty

RUN echo '$TTL 1D' > /build/var/named/named.localhost && \
    echo '@       IN SOA  @ rname.invalid. (' >> /build/var/named/named.localhost && \
    echo '                        0       ; serial' >> /build/var/named/named.localhost && \
    echo '                        1D      ; refresh' >> /build/var/named/named.localhost && \
    echo '                        1H      ; retry' >> /build/var/named/named.localhost && \
    echo '                        1W      ; expire' >> /build/var/named/named.localhost && \
    echo '                        3H )    ; minimum' >> /build/var/named/named.localhost && \
    echo '        NS      @' >> /build/var/named/named.localhost && \
    echo '        A       127.0.0.1' >> /build/var/named/named.localhost && \
    echo '        AAAA    ::1' >> /build/var/named/named.localhost && \
    echo '        PTR     localhost.' >> /build/var/named/named.localhost

# Download root hints file
RUN curl -s https://www.internic.net/domain/named.root -o /build/var/named/named.ca

# Copy required BIND binaries and libraries
RUN cp /usr/sbin/named /build/usr/sbin/ && \
    cp /usr/sbin/rndc /build/usr/sbin/ && \
    cp /usr/bin/named-checkconf /build/usr/bin/ && \
    cp /usr/bin/named-checkzone /build/usr/bin/ && \
    cp /usr/bin/dig /build/usr/bin/ && \
    cp /usr/bin/nslookup /build/usr/bin/ && \
    cp /usr/bin/host /build/usr/bin/

# Find and copy all required libraries
RUN mkdir -p /build/lib64 /build/usr/lib64 && \
    for binary in /build/usr/sbin/named /build/usr/sbin/rndc /build/usr/bin/named-checkconf /build/usr/bin/named-checkzone /build/usr/bin/dig; do \
        ldd "$binary" 2>/dev/null | grep -E '^\s*/' | awk '{print $1}' | while read lib; do \
            if [ -f "$lib" ]; then \
                cp "$lib" "/build${lib}" 2>/dev/null || true; \
            fi; \
        done; \
    done

# Copy essential system files
RUN cp /etc/passwd /build/etc/ && \
    cp /etc/group /build/etc/ && \
    cp /etc/nsswitch.conf /build/etc/ && \
    cp -r /etc/named.* /build/etc/ 2>/dev/null || true

# Create named user entry in build
RUN grep '^named:' /etc/passwd > /build/etc/passwd.named || echo "named:x:25:25:Named:/var/named:/sbin/nologin" > /build/etc/passwd.named && \
    grep '^named:' /etc/group > /build/etc/group.named || echo "named:x:25:" > /build/etc/group.named

# =============================================================================
# RUNTIME STAGE - Minimal runtime environment
# =============================================================================
FROM docker.io/rockylinux:9-minimal AS runtime

# Labels for metadata
LABEL maintainer="BindCaptain"
LABEL description="BindCaptain - Take command of your DNS infrastructure"
LABEL version="2.1"
LABEL usage="Mount your named.conf to /etc/named.conf and zone files to /var/named/"
LABEL bind.compatible.versions="9.16,9.18,9.20"

# Install only essential runtime packages
RUN microdnf update -y && \
    microdnf install -y \
        glibc \
        glibc-common \
        libgcc \
        shadow-utils \
        coreutils \
        util-linux \
        procps-ng \
        iproute && \
    microdnf clean all

# Copy BIND binaries and libraries from builder
COPY --from=builder /build/usr/sbin/named /usr/sbin/
COPY --from=builder /build/usr/sbin/rndc /usr/sbin/
COPY --from=builder /build/usr/bin/named-checkconf /usr/bin/
COPY --from=builder /build/usr/bin/named-checkzone /usr/bin/
COPY --from=builder /build/usr/bin/dig /usr/bin/
COPY --from=builder /build/usr/bin/nslookup /usr/bin/
COPY --from=builder /build/usr/bin/host /usr/bin/

# Copy required libraries
COPY --from=builder /build/lib64/ /lib64/
COPY --from=builder /build/usr/lib64/ /usr/lib64/

# Copy essential system files
COPY --from=builder /build/etc/passwd.named /tmp/passwd.named
COPY --from=builder /build/etc/group.named /tmp/group.named
COPY --from=builder /build/etc/nsswitch.conf /etc/
COPY --from=builder /build/etc/named.* /etc/

# Create named user and group if they don't exist
RUN if ! getent group named >/dev/null 2>&1; then \
        cat /tmp/group.named >> /etc/group; \
    fi && \
    if ! getent passwd named >/dev/null 2>&1; then \
        cat /tmp/passwd.named >> /etc/passwd; \
    fi && \
    rm -f /tmp/passwd.named /tmp/group.named

# Copy directory structure from builder
COPY --from=builder --chown=named:named /build/var/named /var/named
COPY --from=builder --chown=named:named /build/var/log/named /var/log/named
COPY --from=builder --chown=named:named /build/var/run/named /var/run/named
COPY --from=builder --chown=named:named /build/var/backups/bind /var/backups/bind

# Set proper permissions
RUN chmod 755 /var/named && \
    chmod 750 /var/named/data && \
    chmod 750 /var/named/dynamic && \
    chmod 755 /var/named/slaves && \
    chmod 644 /var/named/named.* && \
    chown -R named:named /var/named /var/log/named /var/run/named /var/backups/bind

# Copy startup script
COPY container_start.sh /usr/local/bin/container_start.sh
RUN chmod +x /usr/local/bin/container_start.sh

# Create scripts directory (user can mount their own scripts)
RUN mkdir -p /usr/local/scripts && \
    chmod 755 /usr/local/scripts

# Create minimal log files
RUN touch /var/log/named/named.log \
          /var/log/named/security.log \
          /var/log/bind_manager.log \
          /var/log/dns_refresh.log \
          /var/log/named/container.log && \
    chown named:named /var/log/named/named.log /var/log/named/security.log /var/log/named/container.log && \
    chmod 644 /var/log/*.log /var/log/named/*.log

# Create minimal /tmp directory
RUN mkdir -p /tmp && chmod 1777 /tmp

# Environment variables for configuration
ENV BIND_USER=named
ENV BIND_CONFIG=/etc/named.conf
ENV BIND_ZONES=/var/named
ENV BIND_LOGS=/var/log/named
ENV BIND_DEBUG_LEVEL=1
ENV BIND_VERSION_CHECK=true

# Expose DNS ports
EXPOSE 53/tcp 53/udp

# Enhanced health check with modern BIND compatibility
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD /usr/local/bin/health_check.sh || exit 1

# Create enhanced health check script compatible with modern BIND
RUN echo '#!/bin/bash' > /usr/local/bin/health_check.sh && \
    echo '# Enhanced health check for modern BIND DNS' >> /usr/local/bin/health_check.sh && \
    echo 'set -e' >> /usr/local/bin/health_check.sh && \
    echo '' >> /usr/local/bin/health_check.sh && \
    echo '# Check if BIND process is running' >> /usr/local/bin/health_check.sh && \
    echo 'if ! pgrep named >/dev/null 2>&1; then' >> /usr/local/bin/health_check.sh && \
    echo '    exit 1' >> /usr/local/bin/health_check.sh && \
    echo 'fi' >> /usr/local/bin/health_check.sh && \
    echo '' >> /usr/local/bin/health_check.sh && \
    echo '# Try basic DNS query' >> /usr/local/bin/health_check.sh && \
    echo 'if /usr/bin/dig @127.0.0.1 . NS +short +time=3 >/dev/null 2>&1; then' >> /usr/local/bin/health_check.sh && \
    echo '    exit 0' >> /usr/local/bin/health_check.sh && \
    echo 'fi' >> /usr/local/bin/health_check.sh && \
    echo '' >> /usr/local/bin/health_check.sh && \
    echo '# Try to find any configured zone and query it' >> /usr/local/bin/health_check.sh && \
    echo 'if [ -f "/etc/named.conf" ]; then' >> /usr/local/bin/health_check.sh && \
    echo '    # Support both old "master" and new "primary" syntax' >> /usr/local/bin/health_check.sh && \
    echo '    zone=$(grep -E "^[[:space:]]*zone[[:space:]]+\"" /etc/named.conf | grep -E "(type[[:space:]]+(master|primary))" | head -1 | sed "s/.*zone[[:space:]]*\"\([^\"]*\)\".*/\1/")' >> /usr/local/bin/health_check.sh && \
    echo '    if [ -n "$zone" ] && [ "$zone" != "." ]; then' >> /usr/local/bin/health_check.sh && \
    echo '        /usr/bin/dig @127.0.0.1 "$zone" SOA +short +time=3 >/dev/null 2>&1' >> /usr/local/bin/health_check.sh && \
    echo '        exit $?' >> /usr/local/bin/health_check.sh && \
    echo '    fi' >> /usr/local/bin/health_check.sh && \
    echo 'fi' >> /usr/local/bin/health_check.sh && \
    echo '' >> /usr/local/bin/health_check.sh && \
    echo 'exit 1' >> /usr/local/bin/health_check.sh && \
    chmod +x /usr/local/bin/health_check.sh

# Set working directory
WORKDIR /var/named

# Run as root (required for port 53 binding)
USER root

# Start BIND
CMD ["/usr/local/bin/container_start.sh"]