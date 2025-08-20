# --- Builder stage ---
FROM almalinux:9.5 AS builder

WORKDIR /root

# Install build dependencies
RUN dnf install -y git wget tar && dnf clean all

# Install Go 1.24.6 (with SHA256 checksum verification)
ENV GO_VERSION=1.24.6
ENV GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
ENV GO_URL="https://go.dev/dl/${GO_TARBALL}"
ENV GO_SHA256="bbca37cc395c974ffa4893ee35819ad23ebb27426df87af92e93a9ec66ef8712"

RUN wget -q "$GO_URL" && \
    echo "${GO_SHA256}  ${GO_TARBALL}" | sha256sum -c - && \
    rm -rf /usr/local/go && \
    tar -C /usr/local -xzf "$GO_TARBALL" && \
    rm "$GO_TARBALL" && \
    /usr/local/go/bin/go version

ENV PATH="/usr/local/go/bin:${PATH}"

# Add build script and build geoipupdate
ADD ./build.sh /root/
ARG GEOIP_ACCOUNT_ID="${GEOIP_ACCOUNT_ID:-123456}"
ENV GEOIP_LICENSE_KEY="${GEOIP_LICENSE_KEY:-xxxxxx}"
RUN chmod +x /root/build.sh && /root/build.sh


# --- Final runtime image ---
FROM almalinux:9.5

ARG GEOIP_ACCOUNT_ID
ARG GEOIP_LICENSE_KEY

# Runtime deps
RUN dnf update -y && \
    dnf install -y openssl bind-utils dnsmasq diffutils && \
    dnf autoremove -y && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Copy geoipupdate binary from builder
COPY --from=builder /usr/local/bin/geoipupdate /usr/local/bin/geoipupdate

# Create keys for nginx
RUN mkdir -p /etc/keys && \
    openssl req -x509 -newkey rsa:2048 -keyout /etc/keys/key -out /etc/keys/crt -days 360 -nodes -subj '/CN=test' && \
    chmod 600 /etc/keys/key && \
    openssl dhparam -out /usr/local/openresty/nginx/conf/dhparam.pem 2048

# Copy configs, scripts, and HTML
ADD ./naxsi/location.rules /usr/local/openresty/naxsi/location.template
ADD ./nginx*.conf /usr/local/openresty/nginx/conf/
RUN mkdir -p /usr/local/openresty/nginx/conf/locations /usr/local/openresty/nginx/lua
ADD ./lua/* /usr/local/openresty/nginx/lua/
RUN md5sum /usr/local/openresty/nginx/conf/nginx.conf | cut -d' ' -f 1 > /container_default_ngx
ADD ./defaults.sh /
ADD ./go.sh /
ADD ./enable_location.sh /
ADD ./location_template.conf /
ADD ./logging.conf /usr/local/openresty/nginx/conf/
ADD ./security_defaults.conf /usr/local/openresty/nginx/conf/
ADD ./html/ /usr/local/openresty/nginx/html/
ADD ./readyness.sh /
ADD ./helper.sh /
ADD ./refresh_geoip.sh /

# Drop unneeded headers
RUN dnf remove -y kernel-headers && dnf clean all

# Add nginx user
RUN useradd -u 1000 nginx && \
    install -o nginx -g nginx -d \
      /usr/local/openresty/naxsi/locations \
      /usr/local/openresty/nginx/{client_body,fastcgi,proxy,scgi,uwsgi}_temp && \
    chown -R nginx:nginx /usr/local/openresty/nginx/{conf,logs} /usr/share/GeoIP /etc/keys

WORKDIR /usr/local/openresty

EXPOSE 10080 10443

USER 1000

ENTRYPOINT [ "/go.sh" ]
