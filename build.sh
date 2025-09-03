#!/usr/bin/env bash
# Script to install the openresty from source and to tidy up after...

set -eu

OPEN_RESTY_URL=${OPEN_RESTY_URL:-http://openresty.org/download/openresty-1.27.1.2.tar.gz}
LUAROCKS_URL=${LUAROCKS_URL:-https://luarocks.github.io/luarocks/releases/luarocks-3.12.0.tar.gz}
NAXSI_URL=${NAXSI_URL:-https://github.com/wargio/naxsi/releases/download/1.7/naxsi-1.7-src-with-deps.tar.gz}
STATSD_URL=${STATSD_URL:-https://github.com/UKHomeOffice/nginx-statsd/archive/0.0.1-ngxpatch.tar.gz}
set -o pipefail

# ...existing code...
# LUAROCKS_URL='https://luarocks.github.io/luarocks/releases/luarocks-3.12.0.tar.gz'
# NAXSI_URL='https://github.com/wargio/naxsi/releases/download/1.7/naxsi-1.7-src-with-deps.tar.gz'
# OPEN_RESTY_URL='http://openresty.org/download/openresty-1.27.1.2.tar.gz'
# STATSD_URL='https://github.com/UKHomeOffice/nginx-statsd/archive/0.0.1-ngxpatch.tar.gz'

 # ...existing code...

# Install dependencies to build from source
dnf -y install \
    gcc-c++ \
    gcc \
    git \
    make \
    libcurl-devel \
    openssl-devel \
    openssl \
    perl \
    pcre-devel \
    pcre \
    readline-devel \
    tar \
    unzip \
    wget \
    zlib-devel

mkdir -p openresty luarocks naxsi nginx-statsd

# Prepare
wget -qO - "$OPEN_RESTY_URL"   | tar xzv --strip-components 1 -C openresty/
echo "Downloading and extracting LuaRocks..."
wget -O luarocks.tar.gz "$LUAROCKS_URL"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to download LuaRocks from $LUAROCKS_URL"
    exit 1
fi
tar xzvf luarocks.tar.gz
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to extract LuaRocks archive."
    exit 1
fi
rm luarocks.tar.gz
# Move all extracted files except luarocks/ and luarocks.tar.gz into luarocks/
find . -maxdepth 1 ! -name 'luarocks' ! -name 'luarocks.tar.gz' ! -name '.' -exec mv {} luarocks/ \;
rm -rf luarocks-3.12.0
if [ ! -d "luarocks" ] || [ -z "$(ls -A luarocks)" ]; then
    echo "ERROR: luarocks directory not created or is empty. Download or extraction failed."
    exit 1
fi
wget -qO - "$NAXSI_URL"        | tar xzv --strip-components 1 -C naxsi/
wget -qO - "$STATSD_URL"       | tar xzv --strip-components 1 -C nginx-statsd/
 # ...existing code...


 # ...existing code...

 # ...existing code...

 # ...existing code...

echo "Install openresty"
pushd openresty
./configure \
            --add-module="../naxsi/naxsi_src" \
            --add-module="../nginx-statsd" \
            --with-http_realip_module \
            --with-http_v2_module \
            --with-http_stub_status_module
make install


echo "Install NAXSI default rules"
mkdir -p /usr/local/openresty/naxsi/
if [ -f "./naxsi/naxsi_rules/naxsi_core.rules" ]; then
    cp "./naxsi/naxsi_rules/naxsi_core.rules" /usr/local/openresty/naxsi/
elif [ -f "./naxsi/naxsi_core.rules" ]; then
    cp "./naxsi/naxsi_core.rules" /usr/local/openresty/naxsi/
else
    wget -O /usr/local/openresty/naxsi/naxsi_core.rules https://raw.githubusercontent.com/nbs-system/naxsi/master/naxsi_config/naxsi_core.rules
fi

echo "Installing LuaRocks..."
if [ ! -d "luarocks" ] || [ -z "$(ls -A luarocks)" ]; then
    echo "ERROR: luarocks directory not created or is empty before pushd. Download or extraction failed."
    echo "Current directory contents:"
    ls -l
    exit 1
fi
pushd luarocks
./configure --with-lua=/usr/local/openresty/luajit \
                        --lua-suffix=jit-2.1 \
                        --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1
make build install
if ! command -v luarocks >/dev/null 2>&1; then
    echo "ERROR: luarocks binary not found after installation."
    exit 1
fi
popd

echo "Installing LuaRocks packages..."
if ! command -v luarocks >/dev/null 2>&1; then
    echo "ERROR: luarocks binary not found. Lua packages cannot be installed."
    exit 1
fi
luarocks install uuid || { echo "ERROR: Failed to install uuid."; exit 1; }
luarocks install luasocket || { echo "ERROR: Failed to install luasocket."; exit 1; }
luarocks install lua-resty-openssl || { echo "ERROR: Failed to install lua-resty-openssl."; exit 1; }

echo "Removing unnecessary developer tooling"
rm -fr openresty naxsi nginx-statsd luarocks
dnf -y remove \
    gcc-c++ \
    gcc \
    git \
    make \
    openssl-devel \
    libcurl-devel \
    perl \
    pcre-devel \
    readline-devel

dnf clean all
