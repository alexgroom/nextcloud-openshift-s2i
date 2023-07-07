#!/bin/sh
set -ux

# version_greater A B returns whether A > B
version_greater() {
    [ "$(printf '%s\n' "$@" | sort -t '.' -n -k1,1 -k2,2 -k3,3 -k4,4 | head -n 1)" != "$1" ]
}

# return true if specified directory is empty
directory_empty() {
    [ -z "$(ls -A "$1/")" ]
}


# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    local varValue=$(env | grep -E "^${var}=" | sed -E -e "s/^${var}=//")
    local fileVarValue=$(env | grep -E "^${fileVar}=" | sed -E -e "s/^${fileVar}=//")
    if [ -n "${varValue}" ] && [ -n "${fileVarValue}" ]; then
        echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    if [ -n "${varValue}" ]; then
        export "$var"="${varValue}"
    elif [ -n "${fileVarValue}" ]; then
        export "$var"="$(cat "${fileVarValue}")"
    elif [ -n "${def}" ]; then
        export "$var"="$def"
    fi
    unset "$fileVar"
}

#echo "Patch up master config before starting"
#sed -i "s%^<Directory \"${APP_DATA}\"%<Directory \"${HTTPD_DATA_ORIG_PATH}/html\"%" ${HTTPD_MAIN_CONF_PATH}/httpd.conf

export PHP_MEMORY_LIMIT=512M
export OPCACHE_REVALIDATE_FREQ=1
export OPCACHE_MAX_FILES=10000
export PHP_OPCACHE_REVALIDATE_FREQ=1
export PHP_OPCACHE_MAX_ACCELERATED_FILES=10000

fix-permissions /var/www/

installed_version="0.0.0.0"
if [ -f /var/www/html/version.php ]; then
    # shellcheck disable=SC2016
    installed_version="$(php -r 'require "/var/www/html/version.php"; echo implode(".", $OC_Version);')"
fi
# shellcheck disable=SC2016
image_version="$(php -r 'require "/opt/app-root/src/version.php"; echo implode(".", $OC_Version);')"

if version_greater "$installed_version" "$image_version"; then
    echo "Can't start Nextcloud because the version of the data ($installed_version) is higher than the container image version ($image_version) and downgrading is not supported. Are you sure you have pulled the newest image version?"
    exit 1
fi

if version_greater "$image_version" "$installed_version"; then
    echo "Initializing nextcloud $image_version ..."
    if [ "$installed_version" != "0.0.0.0" ]; then
        echo "Upgrading nextcloud from $installed_version ..."
        php /var/www/html/occ app:list | sed -n "/Enabled:/,/Disabled:/p" > /tmp/list_before
    fi
    if [ "$(id -u)" = 0 ]; then
        rsync_options="-rlDog --chown 1001:root"
    else
        rsync_options="-rlD"
    fi
    rsync $rsync_options --delete --exclude-from=/upgrade.exclude /opt/app-root/src/ /var/www/html/
    for dir in config data custom_apps themes; do
        if [ ! -d "/var/www/html/$dir" ] || directory_empty "/var/www/html/$dir"; then
            rsync $rsync_options --include "/$dir/" --exclude '/*' /opt/app-root/src/ /var/www/html/
        fi
    done
    rsync $rsync_options --include 'version.php' --exclude '*' /opt/app-root/src/ /var/www/html/
    echo "Initializing finished"

    #install
    install=false
    if [ "$installed_version" = "0.0.0.0" ]; then
        echo "New nextcloud instance"

        file_env NEXTCLOUD_ADMIN_PASSWORD
        file_env NEXTCLOUD_ADMIN_USER

        if [ -n "${NEXTCLOUD_ADMIN_USER+x}" ] && [ -n "${NEXTCLOUD_ADMIN_PASSWORD+x}" ]; then
            # shellcheck disable=SC2016
            install_options="-n --admin-user ${NEXTCLOUD_ADMIN_USER} --admin-pass ${NEXTCLOUD_ADMIN_PASSWORD}"
            if [ -n "${NEXTCLOUD_DATA_DIR+x}" ]; then
                # shellcheck disable=SC2016
                install_options=$install_options" --data-dir ${NEXTCLOUD_DATA_DIR}"
            fi

            file_env MYSQL_DATABASE
            file_env MYSQL_PASSWORD
            file_env MYSQL_USER
            file_env POSTGRES_DB
            file_env POSTGRES_PASSWORD
            file_env POSTGRES_USER

            if [ -n "${SQLITE_DATABASE+x}" ]; then
                echo "Installing with SQLite database"
                # shellcheck disable=SC2016
                install_options=$install_options" --database-name ${SQLITE_DATABASE}"
                install=true
            elif [ -n "${MYSQL_DATABASE+x}" ] && [ -n "${MYSQL_USER+x}" ] && [ -n "${MYSQL_PASSWORD+x}" ] && [ -n "${MYSQL_HOST+x}" ]; then
                echo "Installing with MySQL database"
                # shellcheck disable=SC2016
                install_options=$install_options" --database mysql --database-name ${MYSQL_DATABASE} --database-user ${MYSQL_USER} --database-pass ${MYSQL_PASSWORD} --database-host ${MYSQL_HOST}"
                install=true
            elif [ -n "${POSTGRES_DB+x}" ] && [ -n "${POSTGRES_USER+x}" ] && [ -n "${POSTGRES_PASSWORD+x}" ] && [ -n "${POSTGRES_HOST+x}" ]; then
                echo "Installing with PostgreSQL database"
                # shellcheck disable=SC2016
                install_options=$install_options" --database pgsql --database-name ${POSTGRES_DB} --database-user ${POSTGRES_USER} --database-pass ${POSTGRES_PASSWORD} --database-host ${POSTGRES_HOST}"
                install=true
            fi

            if [ "$install" = true ]; then
                echo "starting nextcloud installation"
                max_retries=10
                try=0
                echo "Install options" ${install_options}
                until php /var/www/html/occ maintenance:install $install_options || [ "$try" -gt "$max_retries" ]
                do
                    echo "retrying install..."
                    try=$((try+1))
                    sleep 10s
                done
                if [ "$try" -gt "$max_retries" ]; then
                    echo "installing of nextcloud failed!"
                    env
                    exit 1
                fi
                if [ -n "${NEXTCLOUD_TRUSTED_DOMAINS+x}" ]; then
                    echo "setting trusted domains…"
                    NC_TRUSTED_DOMAIN_IDX=1
                    for DOMAIN in $NEXTCLOUD_TRUSTED_DOMAINS ; do
                        DOMAIN=$(echo "$DOMAIN" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                        php /var/www/html/occ config:system:set trusted_domains $NC_TRUSTED_DOMAIN_IDX --value=$DOMAIN
                        NC_TRUSTED_DOMAIN_IDX=$(($NC_TRUSTED_DOMAIN_IDX+1))
                    done
                fi
            else
                echo "running web-based installer on first connect!"
            fi
        fi
    #upgrade
    else
        php /var/www/html/occ upgrade

        php /var/www/html/occ app:list | sed -n "/Enabled:/,/Disabled:/p" > /tmp/list_after
        echo "The following apps have been disabled:"
        diff /tmp/list_before /tmp/list_after | grep '<' | cut -d- -f2 | cut -d: -f1
        rm -f /tmp/list_before /tmp/list_after

    fi
fi

#source ${STI_SCRIPTS_PATH}/run

source /common.sh

export_vars=$(cgroup-limits); export $export_vars
export DOCUMENTROOT=${DOCUMENTROOT:-/}

# Default php.ini configuration values, all taken
# from php defaults.
export ERROR_REPORTING=${ERROR_REPORTING:-E_ALL & ~E_NOTICE}
export DISPLAY_ERRORS=${DISPLAY_ERRORS:-ON}
export DISPLAY_STARTUP_ERRORS=${DISPLAY_STARTUP_ERRORS:-OFF}
export TRACK_ERRORS=${TRACK_ERRORS:-OFF}
export HTML_ERRORS=${HTML_ERRORS:-ON}
export INCLUDE_PATH=${INCLUDE_PATH:-.:/opt/app-root/src:${PHP_DEFAULT_INCLUDE_PATH}}
export PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-128M}
export SESSION_NAME=${SESSION_NAME:-PHPSESSID}
export SESSION_HANDLER=${SESSION_HANDLER:-files}
export SESSION_PATH=${SESSION_PATH:-/tmp/sessions}
export SESSION_COOKIE_DOMAIN=${SESSION_COOKIE_DOMAIN:-}
export SESSION_COOKIE_HTTPONLY=${SESSION_COOKIE_HTTPONLY:-}
export SESSION_COOKIE_SECURE=${SESSION_COOKIE_SECURE:-0}
export SHORT_OPEN_TAG=${SHORT_OPEN_TAG:-OFF}

# TODO should be dynamically calculated based on container memory limit/16
export OPCACHE_MEMORY_CONSUMPTION=${OPCACHE_MEMORY_CONSUMPTION:-128}

export OPCACHE_REVALIDATE_FREQ=${OPCACHE_REVALIDATE_FREQ:-2}
export OPCACHE_MAX_FILES=${OPCACHE_MAX_FILES:-4000}

export PHPRC=${PHPRC:-${PHP_SYSCONF_PATH}/php.ini}
export PHP_INI_SCAN_DIR=${PHP_INI_SCAN_DIR:-${PHP_SYSCONF_PATH}/php.d}

envsubst < /opt/app-root/etc/php.ini.template > ${PHP_SYSCONF_PATH}/php.ini
envsubst < /opt/app-root/etc/php.d/10-opcache.ini.template > ${PHP_SYSCONF_PATH}/php.d/10-opcache.ini

# add values needed for nextcloud
echo "apc.enable_cli=1" >>  ${PHP_SYSCONF_PATH}/php.ini
echo "opcache.enable_cli=1" >>  ${PHP_SYSCONF_PATH}/php.ini

export HTTPD_START_SERVERS=${HTTPD_START_SERVERS:-8}
export HTTPD_MAX_SPARE_SERVERS=$((HTTPD_START_SERVERS+10))
export HTTPD_MAX_REQUESTS_PER_CHILD=${HTTPD_MAX_REQUESTS_PER_CHILD:-4000}
export HTTPD_MAX_KEEPALIVE_REQUESTS=${HTTPD_MAX_KEEPALIVE_REQUESTS:-100}

if [ -n "${NO_MEMORY_LIMIT:-}" -o -z "${MEMORY_LIMIT_IN_BYTES:-}" ]; then
  #
  export HTTPD_MAX_REQUEST_WORKERS=${HTTPD_MAX_REQUEST_WORKERS:-256}
else
  # A simple calculation for MaxRequestWorkers would be: Total Memory / Size Per Apache process.
  # The total memory is determined from the Cgroups and the average size for the
  # Apache process is estimated to 15MB.
  max_clients_computed=$((MEMORY_LIMIT_IN_BYTES/1024/1024/15))
  # The MaxClients should never be lower than StartServers, which is set to 5.
  # In case the container has memory limit set to <64M we pin the MaxClients to 4.
  [[ $max_clients_computed -le 4 ]] && max_clients_computed=4
  export HTTPD_MAX_REQUEST_WORKERS=${HTTPD_MAX_REQUEST_WORKERS:-$max_clients_computed}
  echo "-> Cgroups memory limit is set, using HTTPD_MAX_REQUEST_WORKERS=${HTTPD_MAX_REQUEST_WORKERS}"
fi


#Config fixups
sed -i "s%^#DocumentRoot \"${APP_DATA}\"%DocumentRoot \"${HTTPD_DATA_ORIG_PATH}/html\"%" ${HTTPD_MAIN_CONF_PATH}/httpd.conf
sed -i "s%^<Directory \"${APP_DATA}\"%<Directory \"${HTTPD_DATA_ORIG_PATH}/html\"%" ${HTTPD_MAIN_CONF_PATH}/httpd.conf
sed -i "s%IncludeOptional ${APP_ROOT}%IncludeOptional ${HTTPD_DATA_ORIG_PATH}%" ${HTTPD_MAIN_CONF_PATH}/httpd.conf


#if [ "x$PLATFORM" == "xel9" ] || [ "x$PLATFORM" == "xfedora" ]; then
#  if [ -n "${PHP_FPM_RUN_DIR:-}" ]; then
#    /bin/ln -s /dev/stderr ${PHP_FPM_LOG_PATH}/error.log
#    mkdir -p ${PHP_FPM_RUN_DIR}
#    chmod -R a+rwx ${PHP_FPM_RUN_DIR}
#    chown -R 1001:0 ${PHP_FPM_RUN_DIR}
#    mkdir -p ${PHP_FPM_LOG_PATH}
#    chmod -R a+rwx ${PHP_FPM_LOG_PATH}
#    chown -R 1001:0 ${PHP_FPM_LOG_PATH}
#  fi
#fi


# pre-start files
process_extending_files ${APP_DATA}/php-pre-start/ ${PHP_CONTAINER_SCRIPTS_PATH}/pre-start/

if [ "$install" = true ]; then
    echo "Finishing nextcloud installation"
    if [ -n "${NEXTCLOUD_TRUSTED_DOMAINS+x}" ]; then
        echo "setting trusted domains…"
        NC_TRUSTED_DOMAIN_IDX=1
        for DOMAIN in $NEXTCLOUD_TRUSTED_DOMAINS ; do
            DOMAIN=$(echo "$DOMAIN" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            php /var/www/html/occ config:system:set trusted_domains $NC_TRUSTED_DOMAIN_IDX --value=$DOMAIN
            NC_TRUSTED_DOMAIN_IDX=$(($NC_TRUSTED_DOMAIN_IDX+1))
        done
    fi
fi


exec httpd -D FOREGROUND
