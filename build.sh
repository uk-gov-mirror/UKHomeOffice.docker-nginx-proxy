#!/usr/bin/env bash
# Script to install the openresty from source and to tidy up after...

set -eu
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
wget -qO - "$LUAROCKS_URL"     | tar xzv --strip-components 1 -C luarocks/
wget -qO - "$NAXSI_URL"        | tar xzv --strip-components 1 -C naxsi/
wget -qO - "$STATSD_URL"       | tar xzv --strip-components 1 -C nginx-statsd/
 # ...existing code...

popd
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
popd

echo "Install NAXSI default rules"
mkdir -p /usr/local/openresty/naxsi/
cp "./naxsi/naxsi_rules/naxsi_core.rules" /usr/local/openresty/naxsi/

echo "Installing luarocks"
pushd luarocks
./configure --with-lua=/usr/local/openresty/luajit \
            --lua-suffix=jit-2.1 \
            --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1
make build install
popd

echo "Installing luarocks packages"
luarocks install uuid
luarocks install luasocket
luarocks install lua-resty-openssl

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
