#!/bin/bash
set -e

if [ -n "$MYSQL_PORT_3306_TCP" ]; then
	if [ -z "$DOLIBARR_DB_HOST" ]; then
		DOLIBARR_DB_HOST='mysql'
	else
		echo >&2 'warning: both WORDPRESS_DB_HOST and MYSQL_PORT_3306_TCP found'
		echo >&2 "  Connecting to WORDPRESS_DB_HOST ($DOLIBARR_DB_HOST)"
		echo >&2 '  instead of the linked mysql container'
	fi
fi

if [ -z "$DOLIBARR_DB_HOST" ]; then
	echo >&2 'error: missing DOLIBARR_DB_HOST and MYSQL_PORT_3306_TCP environment variables'
	echo >&2 '  Did you forget to --link some_mysql_container:mysql or set an external db'
	echo >&2 '  with -e DOLIBARR_DB_HOST=hostname?'
	exit 1
fi

# if we're linked to MySQL, and we're using the root user, and our linked
# container has a default "root" password set up and passed through... :)
: ${DOLIBARR_DB_USER:=root}
: ${DOLIBARR_DB_PORT:=3306}
if [ "$DOLIBARR_DB_USER" = 'root' ]; then
	: ${DOLIBARR_DB_PASSWORD:=$MYSQL_ENV_MYSQL_ROOT_PASSWORD}
fi
: ${DOLIBARR_DB_NAME:=dolibarr}

if [ -z "$DOLIBARR_DB_PASSWORD" ]; then
	echo >&2 'error: missing required DOLIBARR_DB_PASSWORD environment variable'
	echo >&2 '  Did you forget to -e DOLIBARR_DB_PASSWORD=... ?'
	echo >&2
	echo >&2 '  (Also of interest might be DOLIBARR_DB_USER and DOLIBARR_DB_NAME.)'
	exit 1
fi

if ! [ -e index.php ]; then
	echo >&2 "Dolibarr not found in $(pwd) - copying now..."
	if [ "$(ls -A)" ]; then
		echo >&2 "WARNING: $(pwd) is not empty - press Ctrl+C now if this is an error!"
		( set -x; ls -A; sleep 10 )
	fi
	tar cf - --one-file-system -C /usr/src/dolibarr/htdocs . | tar xf -
    cp ./conf/conf.php.example ./conf/conf.php
    chown www-data:www-data ./conf/conf.php
	echo >&2 "Complete! Dolibarr has been successfully copied to $(pwd)"
fi

sed_escape_lhs() {
	echo "$@" | sed 's/[]\/$*.^|[]/\\&/g'
}
sed_escape_rhs() {
	echo "$@" | sed 's/[\/&]/\\&/g'
}
php_escape() {
	php -r 'var_export((string) $argv[1]);' "$1"
}
set_config() {
	key="$1"
	value="$2"
	regex="(['\"])$(sed_escape_lhs "$key")\2\s*,"
	if [ "${key:0:1}" = '$' ]; then
		regex="^(\s*)$(sed_escape_lhs "$key")\s*="
	fi
	sed -ri "s/($regex\s*)(['\"]).*\3/\1$(sed_escape_rhs "$(php_escape "$value")")/" ./conf/conf.php
}

set_config '$dolibarr_main_db_type' "mysqli"
set_config '$dolibarr_main_document_root' "/var/www/html"
set_config '$dolibarr_main_data_root' "/var/www/html/documents"
set_config '$dolibarr_main_url_root' "$DOLIBARR_URL"
set_config '$dolibarr_main_db_host' "$DOLIBARR_DB_HOST"
set_config '$dolibarr_main_db_port' "$DOLIBARR_DB_PORT"
set_config '$dolibarr_main_db_name' "$DOLIBARR_DB_NAME"
set_config '$dolibarr_main_db_user' "$DOLIBARR_DB_USER"
set_config '$dolibarr_main_db_pass' "$DOLIBARR_DB_PASSWORD"

TERM=dumb php -- "$DOLIBARR_DB_HOST" "$DOLIBARR_DB_PORT" "$DOLIBARR_DB_USER" "$DOLIBARR_DB_PASSWORD" "$DOLIBARR_DB_NAME" <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)
$stderr = fopen('php://stderr', 'w');
$maxTries = 10;
do {
	$mysql = new mysqli($argv[1], $argv[3], $argv[4], '', (int)$argv[2]);
	if ($mysql->connect_error) {
		fwrite($stderr, "\n" . 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
		--$maxTries;
		if ($maxTries <= 0) {
			exit(1);
		}
		sleep(3);
	}
} while ($mysql->connect_error);
if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($argv[5]) . '` DEFAULT CHARACTER SET utf8
  DEFAULT COLLATE utf8_general_ci;')) {
	fwrite($stderr, "\n" . 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
	$mysql->close();
	exit(1);
}
$mysql->close();
EOPHP

exec "$@"
