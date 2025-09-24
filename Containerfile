# ⚓ BindCaptain - Single-stage Containerfile for Modern BIND DNS  
# Reliable and tested approach for your real zone deployment
# Updated for BIND 9.16+ compatibility and security best practices

FROM docker.io/rockylinux:9

# Labels for metadata
LABEL maintainer="BindCaptain"
LABEL description="BindCaptain - Take command of your DNS infrastructure"  
LABEL version="2.1"
LABEL usage="Mount your named.conf to /etc/named.conf and zone files to /var/named/"
LABEL bind.compatible.versions="9.16,9.18,9.20"

# Install BIND and required tools
RUN dnf update -y && \
    dnf install -y \
        bind \
        bind-utils \
        bind-chroot \
        hostname \
        findutils && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Verify BIND version for compatibility  
RUN named -v

# Create required directory structure
RUN mkdir -p \
        /var/named/data \
        /var/named/dynamic \
        /var/named/slaves \
        /var/log/named \
        /var/run/named \
        /usr/local/scripts \
        /var/backups/bind

# Create essential BIND zone files (if not provided by user)
RUN echo '$TTL 3H' > /var/named/named.empty && \
    echo '@       IN SOA  @ rname.invalid. (' >> /var/named/named.empty && \
    echo '                        0       ; serial' >> /var/named/named.empty && \
    echo '                        1D      ; refresh' >> /var/named/named.empty && \
    echo '                        1H      ; retry' >> /var/named/named.empty && \
    echo '                        1W      ; expire' >> /var/named/named.empty && \
    echo '                        3H )    ; minimum' >> /var/named/named.empty && \
    echo '        NS      @' >> /var/named/named.empty && \
    echo '        A       127.0.0.1' >> /var/named/named.empty

# Create named.localhost 
RUN echo '$TTL 1D' > /var/named/named.localhost && \
    echo '@       IN SOA  @ rname.invalid. (' >> /var/named/named.localhost && \
    echo '                        0       ; serial' >> /var/named/named.localhost && \
    echo '                        1D      ; refresh' >> /var/named/named.localhost && \
    echo '                        1H      ; retry' >> /var/named/named.localhost && \
    echo '                        1W      ; expire' >> /var/named/named.localhost && \
    echo '                        3H )    ; minimum' >> /var/named/named.localhost && \
    echo '        NS      @' >> /var/named/named.localhost && \
    echo '        A       127.0.0.1' >> /var/named/named.localhost && \
    echo '        AAAA    ::1' >> /var/named/named.localhost && \
    echo '        PTR     localhost.' >> /var/named/named.localhost

# Create named.loopback
RUN echo '$TTL 1D' > /var/named/named.loopback && \
    echo '@       IN SOA  @ rname.invalid. (' >> /var/named/named.loopback && \
    echo '                        0       ; serial' >> /var/named/named.loopback && \
    echo '                        1D      ; refresh' >> /var/named/named.loopback && \
    echo '                        1H      ; retry' >> /var/named/named.loopback && \
    echo '                        1W      ; expire' >> /var/named/named.loopback && \
    echo '                        3H )    ; minimum' >> /var/named/named.loopback && \
    echo '        NS      @' >> /var/named/named.loopback && \
    echo '        PTR     localhost.' >> /var/named/named.loopback

# Download root hints file  
RUN curl -s https://www.internic.net/domain/named.root -o /var/named/named.ca || \
    echo '; Root servers list' > /var/named/named.ca

# Set proper ownership and permissions
RUN chown -R named:named /var/named /var/log/named /var/run/named && \
    chmod 755 /var/named /var/log/named /var/run/named && \
    chmod 644 /var/named/* && \
    chmod 755 /usr/local/scripts

# Create rndc key if not exists
RUN rndc-confgen -a || true

# Copy container startup script
COPY tools/container_start.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/container_start.sh

# Expose DNS ports
EXPOSE 53/udp 53/tcp 953/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD dig @127.0.0.1 . || exit 1

# Set working directory
WORKDIR /var/named

# Run as root (required for port 53)
USER root

# Start BIND
ENTRYPOINT ["/usr/local/bin/container_start.sh"]
CMD ["named", "-g", "-u", "named"]