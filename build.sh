#!/usr/bin/env bash
# Script to install the openresty from source and to tidy up after...

set -euo pipefail

# ----------------------
# Configurable URLs
# ----------------------
OPEN_RESTY_URL=${OPEN_RESTY_URL:-http://openresty.org/download/openresty-1.27.1.2.tar.gz}
LUAROCKS_URL=${LUAROCKS_URL:-https://luarocks.github.io/luarocks/releases/luarocks-3.12.0.tar.gz}
NAXSI_URL=${NAXSI_URL:-https://github.com/wargio/naxsi/releases/download/1.7/naxsi-1.7-src-with-deps.tar.gz}
DRUPAL_RULES_URL=${DRUPAL_RULES_URL:-https://raw.githubusercontent.com/nbs-system/naxsi-rules/master/drupal.rules}
STATSD_URL=${STATSD_URL:-https://github.com/UKHomeOffice/nginx-statsd/archive/0.0.1-ngxpatch.tar.gz}

WORKDIR="$PWD"
OPENRESTY_DIR="$WORKDIR/openresty"
LUAROCKS_DIR="$WORKDIR/luarocks"
NAXSI_DIR="$WORKDIR/naxsi"
STATSD_DIR="$WORKDIR/nginx-statsd"

# ----------------------
# Install build dependencies
# ----------------------
echo "Installing build dependencies..."
dnf -y install gcc-c++ gcc git make libcurl-devel openssl-devel openssl \
               perl pcre-devel pcre readline-devel tar unzip wget zlib-devel

# ----------------------
# Create directories
# ----------------------
mkdir -p "$OPENRESTY_DIR" "$LUAROCKS_DIR" "$NAXSI_DIR" "$STATSD_DIR"

# ----------------------
# Download and extract OpenResty
# ----------------------
echo "Downloading and extracting OpenResty..."
wget -qO - "$OPEN_RESTY_URL" | tar xzf - --strip-components=1 -C "$OPENRESTY_DIR"

# ----------------------
# Download and extract LuaRocks
# ----------------------
echo "Downloading and extracting LuaRocks..."
wget -O luarocks.tar.gz "$LUAROCKS_URL"
tar xzf luarocks.tar.gz
rm luarocks.tar.gz
mv luarocks-3.12.0/* "$LUAROCKS_DIR"/
rm -rf luarocks-3.12.0

# Sanity check
if [ -z "$(ls -A "$LUAROCKS_DIR")" ]; then
    echo "ERROR: luarocks directory is empty after extraction."
    exit 1
fi

# ----------------------
# Download NAXSI and StatsD
# ----------------------
echo "Downloading and extracting NAXSI..."
wget -qO - "$NAXSI_URL" | tar xzf - --strip-components=1 -C "$NAXSI_DIR"

echo "Downloading and extracting nginx-statsd..."
wget -qO - "$STATSD_URL" | tar xzf - --strip-components=1 -C "$STATSD_DIR"

# ----------------------
# Build and install OpenResty
# ----------------------
echo "Building and installing OpenResty..."
pushd "$OPENRESTY_DIR"
./configure \
    --add-module="$NAXSI_DIR/naxsi_src" \
    --add-module="$STATSD_DIR" \
    --with-http_realip_module \
    --with-http_v2_module \
    --with-http_stub_status_module
make -j"$(nproc)" install
popd

# ----------------------
# Install NAXSI core rules
# ----------------------
echo "Installing NAXSI default rules..."
mkdir -p /usr/local/openresty/naxsi/
CORE_RULES_PATHS=( "$NAXSI_DIR/naxsi_rules/naxsi_core.rules" "$NAXSI_DIR/naxsi_core.rules" )
for path in "${CORE_RULES_PATHS[@]}"; do
    if [ -f "$path" ]; then
        cp "$path" /usr/local/openresty/naxsi/
        break
    fi
done
# fallback download
if [ ! -f /usr/local/openresty/naxsi/naxsi_core.rules ]; then
    wget -O /usr/local/openresty/naxsi/naxsi_core.rules \
        https://raw.githubusercontent.com/nbs-system/naxsi/master/naxsi_config/naxsi_core.rules
fi

# ----------------------
# Install Drupal-specific NAXSI rules
# ----------------------
echo "Installing Drupal NAXSI rules..."
wget -O /usr/local/openresty/naxsi/drupal.rules "$DRUPAL_RULES_URL"

# ----------------------
# Build and install LuaRocks
# ----------------------
echo "Building and installing LuaRocks..."
pushd "$LUAROCKS_DIR"
./configure --with-lua=/usr/local/openresty/luajit \
            --lua-suffix=jit-2.1 \
            --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1
make build install
popd

# Verify LuaRocks installation
if ! command -v luarocks >/dev/null 2>&1; then
    echo "ERROR: luarocks binary not found after installation."
    exit 1
fi

# ----------------------
# Install LuaRocks packages
# ----------------------
echo "Installing LuaRocks packages..."
LUA_PACKAGES=( uuid luasocket lua-resty-openssl )
for pkg in "${LUA_PACKAGES[@]}"; do
    luarocks install "$pkg" || { echo "ERROR: Failed to install $pkg."; exit 1; }
done

# ----------------------
# Cleanup
# ----------------------
echo "Cleaning up unnecessary tooling..."
rm -fr "$OPENRESTY_DIR" "$LUAROCKS_DIR" "$NAXSI_DIR" "$STATSD_DIR"
dnf -y remove gcc-c++ gcc git make openssl-devel libcurl-devel perl pcre-devel readline-devel
dnf clean all

echo "Build and installation completed successfully."
