#!/usr/bin/env bash

set -e

. /defaults.sh

# TODO have an identifier to resolve all variables if present:

function download() {

    file_url=$1
    file_md5=$2
    download_path=$3

    file_path=${download_path}/$(basename ${file_url})
    error=0

    for i in {1..5}; do
        if [ ${i} -gt 1 ]; then
            echo "About to retry download for ${file_url}..."
            sleep 1
        fi
        wget -q -O ${file_path} ${file_url}
        md5=$(md5sum ${file_path} | cut -d' ' -f1)
        if [ "${md5}" == "${file_md5}" ] ; then
            echo "File downloaded & OK:${file_url}"
            error=0
            break
        else
            echo "Error: MD5 expecting '${file_md5}' but got '${md5}' for ${file_url}"
            error=1
        fi
    done
    return ${error}
}

function get_id_var() {
    LOCATION_ID=$1
    VAR_NAME=$2
    NEW_VAR_NAME="${VAR_NAME}_${LOCATION_ID}"
    if [ "${!NEW_VAR_NAME}" == "" ]; then
        NEW_VAR_NAME=${VAR_NAME}
    fi
    echo ${!NEW_VAR_NAME}
}

LOCATION_ID=$1
LOCATION=$2
NAXSI_LOCATION_RULES=/usr/local/openresty/naxsi/location/${LOCATION_ID}
mkdir -p ${NAXSI_LOCATION_RULES}

# Resolve any variable names here:
PROXY_SERVICE_HOST=$(get_id_var ${LOCATION_ID} PROXY_SERVICE_HOST)
PROXY_SERVICE_PORT=$(get_id_var ${LOCATION_ID} PROXY_SERVICE_PORT)
NAXSI_RULES_URL_CSV=$(get_id_var ${LOCATION_ID} NAXSI_RULES_URL_CSV)
NAXSI_RULES_MD5_CSV=$(get_id_var ${LOCATION_ID} NAXSI_RULES_MD5_CSV)
NAXSI_USE_DEFAULT_RULES=$(get_id_var ${LOCATION_ID} NAXSI_USE_DEFAULT_RULES)
EXTRA_NAXSI_RULES=$(get_id_var ${LOCATION_ID} EXTRA_NAXSI_RULES)

echo "Setting up location '${LOCATION}' to be proxied to http://${PROXY_SERVICE_HOST}:${PROXY_SERVICE_PORT}"

eval PROXY_HOST=$(eval "echo $PROXY_SERVICE_HOST")
export PROXY_SERVICE_PORT=$(eval "echo $PROXY_SERVICE_PORT")

# Detect default configuration...
md5sum ${NGIX_CONF_DIR}/nginx.conf | cut -d' ' -f 1 >/tmp/nginx_new
if diff /container_default_ngx /tmp/nginx_new ; then
    if [ "$PROXY_SERVICE_HOST" == "" ] || [ "$PROXY_SERVICE_PORT" == "" ] || [ "$PROXY_HOST" == "" ]; then
        echo "Default config requires PROXY_SERVICE_HOST and PROXY_SERVICE_PORT to be set."
        echo "PROXY_SERVICE_HOST=$PROXY_HOST"
        echo "PROXY_SERVICE_PORT=$PROXY_SERVICE_PORT"
        exit 1
    fi
    if [ "$NAME_RESOLVE" == "BAD" ] ; then
        echo "Name specified for default config can't be resolved:$PROXY_SERVICE_HOST"
        exit 1
    fi
    echo "Proxying to : http://$PROXY_SERVICE_HOST:$PROXY_SERVICE_PORT"
fi

if [ "${NAXSI_RULES_URL_CSV}" != "" ]; then
    if [ "${NAXSI_RULES_MD5_CSV}" == "" ]; then
        echo "Error, must specify NAXSI_RULES_MD5_CSV if NAXSI_RULES_URL_CSV is specified"
        exit 1
    fi
    IFS=',' read -a NAXSI_RULES_URL_ARRAY <<< "$NAXSI_RULES_URL_CSV"
    IFS=',' read -a NAXSI_RULES_MD5_ARRAY <<< "$NAXSI_RULES_MD5_CSV"
    if [ ${#NAXSI_RULES_URL_ARRAY[@]} -ne ${#NAXSI_RULES_MD5_ARRAY[@]} ]; then
        echo "Must specify the same number of items in \$NAXSI_RULES_URL_CSV and \$NAXSI_RULES_MD5_CSV"
        exit 1
    fi
    for i in "${!NAXSI_RULES_URL_ARRAY[@]}"; do
        download ${NAXSI_RULES_URL_ARRAY[$i]} ${NAXSI_RULES_MD5_ARRAY[$i]} ${NAXSI_LOCATION_RULES}
    done
fi
if [ "${NAXSI_USE_DEFAULT_RULES}" == "FALSE" ]; then
    echo "Deleting core rules..."
    rm -f /usr/local/openresty/naxsi/naxsi_core.rules
    rm -f ${NAXSI_LOCATION_RULES}/location.rules
else
    echo "Core NAXSI rules enabled @ /usr/local/openresty/naxsi/naxsi_core.rules"
    echo "Core NAXSI location rules enabled @ ${NAXSI_LOCATION_RULES}/location.rules"
    if [ "${EXTRA_NAXSI_RULES}" != "" ]; then
        echo "Adding extra NAXSI rules from environment"
        echo ''>>${NAXSI_LOCATION_RULES}/location.rules
        echo ${EXTRA_NAXSI_RULES}>>${NAXSI_LOCATION_RULES}/location.rules
    fi
fi

# Now create the location specific include file.
mkdir -p /usr/local/openresty/nginx/locations
cat > /usr/local/openresty/nginx/conf/locations/${LOCATION_ID}.conf <<- EOF_LOCATION_CONF
location ${LOCATION} {
    set \$proxy_address "${PROXY_SERVICE_HOST}:${PROXY_SERVICE_PORT}";

    include  ${NAXSI_LOCATION_RULES}/*.rules ;

    $(cat /location_template.conf)
}
EOF_LOCATION_CONF
