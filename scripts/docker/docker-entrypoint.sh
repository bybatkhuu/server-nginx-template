#!/usr/bin/env bash
set -euo pipefail


echo "[INFO]: Running 'nginx' docker-entrypoint.sh..."

UID=${UID:-1000}
GID=${GID:-11000}

NGINX_SSL_DIR="${NGINX_SSL_DIR:-/etc/nginx/ssl}"
NGINX_SSL_KEY_LENGTH=${NGINX_SSL_KEY_LENGTH:-2048}
NGINX_TEMPLATE_DIR="${NGINX_TEMPLATE_DIR:-/etc/nginx/templates}"
NGINX_DHPARAM_FILENAME="${NGINX_DHPARAM_FILENAME:-dhparam.pem}"
NGINX_TEMPLATE_SUFFIX="${NGINX_TEMPLATE_SUFFIX:-.template}"
NGINX_SITE_ENABLED_DIR="${NGINX_SITE_ENABLED_DIR:-/etc/nginx/sites-enabled}"


_run_nginx()
{
	echo "[INFO]: Testing nginx..."
	nginx -t || exit 2
	echo -e "[OK]: Done.\n"

	echo "[INFO]: Running nginx..."
	exec nginx
}


_generate_dh_param()
{
	local _dhparam_file_path="${NGINX_SSL_DIR}/${NGINX_DHPARAM_FILENAME}"
	if [ ! -f "${_dhparam_file_path}" ]; then
		echo "[INFO]: Generating Diffie-Hellman parameters..."
		openssl dhparam -out "${_dhparam_file_path}" "${NGINX_SSL_KEY_LENGTH}" || exit 2

		chown -c "${UID}:${GID}" "${_dhparam_file_path}" || exit 2
		chmod -c 660 "${_dhparam_file_path}" || exit 2
		echo -e "[OK]: Done.\n"
	fi
}

_https_self()
{
	_generate_dh_param

	echo "[INFO]: Preparing self-signed SSL..."
	NGINX_SSL_COUNTRY=${NGINX_SSL_COUNTRY:-KR}
	NGINX_SSL_STATE=${NGINX_SSL_STATE:-SEOUL}
	NGINX_SSL_LOC_CITY=${NGINX_SSL_LOC_CITY:-Seoul}
	NGINX_SSL_ORG_NAME=${NGINX_SSL_ORG_NAME:-Company}
	NGINX_SSL_COM_NAME=${NGINX_SSL_COM_NAME:-www.example.com}

	local _ssl_key_filename="self.key"
	local _ssl_cert_filename="self.crt"
	local _ssl_key_file_path="${NGINX_SSL_DIR}/${_ssl_key_filename}"
	local _ssl_cert_file_path="${NGINX_SSL_DIR}/${_ssl_cert_filename}"
	if [ ! -f "${_ssl_key_file_path}" ] || [ ! -f "${_ssl_cert_file_path}" ]; then
		openssl req -x509 -nodes -days 365 -newkey "rsa:${NGINX_SSL_KEY_LENGTH}" \
			-keyout "${_ssl_key_file_path}" -out "${_ssl_cert_file_path}" \
			-subj "/C=${NGINX_SSL_COUNTRY}/ST=${NGINX_SSL_STATE}/L=${NGINX_SSL_LOC_CITY}/O=${NGINX_SSL_ORG_NAME}/CN=${NGINX_SSL_COM_NAME}" || exit 2

		chown -c "${UID}:${GID}" "${_ssl_key_file_path}" "${_ssl_cert_file_path}" || exit 2
		chmod -c 660 "${_ssl_key_file_path}" "${_ssl_cert_file_path}" || exit 2
	fi
	echo -e "[OK]: Done.\n"

	_run_nginx
}

_https_lets()
{
	if [ ! -d "${NGINX_SSL_DIR}/live" ]; then
		mkdir -vp "${NGINX_SSL_DIR}/live" || exit 2
	fi

	# shellcheck disable=SC2046
	while [ $(find "${NGINX_SSL_DIR}/live" -name "*.pem" | wc -l) -le 3 ]; do
		echo "[INFO]: Waiting for certbot to obtain SSL/TLS files..."
		sleep 3
	done

	if [ ! -d "/var/www/.well-known/acme-challenge" ]; then
		mkdir -pv /var/www/.well-known/acme-challenge || exit 2
		chown -Rc "www-data:${GID}" /var/www/.well-known || exit 2
		find /var/www/.well-known -type d -exec chmod -c 775 {} + || exit 2
		find /var/www/.well-known -type f -exec chmod -c 664 {} + || exit 2
		find /var/www/.well-known -type d -exec chmod -c +s {} + || exit 2
	fi

	_generate_dh_param

	echo "[INFO]: Setting up watcher for SSL/TLS files..."
	watchman -- trigger "${NGINX_SSL_DIR}/live" cert-update "*.pem" -- /usr/local/bin/nginx-reload.sh || exit 2
	echo -e "[OK]: Done.\n"

	_run_nginx
}


main()
{
	if [ -n "${NGINX_BASIC_AUTH_USER:-}" ] && [ -n "${NGINX_BASIC_AUTH_PASS:-}" ]; then
		if [ ! -f "${NGINX_SSL_DIR}/.htpasswd" ]; then
			echo "[INFO]: Creating htpasswd file..."
			htpasswd -cb "${NGINX_SSL_DIR}/.htpasswd" "${NGINX_BASIC_AUTH_USER}" "${NGINX_BASIC_AUTH_PASS}" || exit 2
			chown -c "${UID}:${GID}" "${NGINX_SSL_DIR}/.htpasswd" || exit 2
			chmod -c 660 "${NGINX_SSL_DIR}/.htpasswd" || exit 2
			echo -e "[OK]: Done.\n"
		fi
	fi

	if [ ! -d "/var/www" ]; then
		mkdir -pv /var/www || exit 2
	fi

	if [ ! -d "/var/log/nginx" ]; then
		mkdir -pv /var/log/nginx || exit 2
	fi

	## Rendering template configs:
	find "${NGINX_TEMPLATE_DIR}" -follow -type f -name "*${NGINX_TEMPLATE_SUFFIX}" -print | while read -r _template_path; do
		local _template_filename="${_template_path#"${NGINX_TEMPLATE_DIR}"/}"
		local _output_path="${NGINX_SITE_ENABLED_DIR}/${_template_filename%"${NGINX_TEMPLATE_SUFFIX}"}"

		if [ -f "${_output_path}" ]; then
			rm -fv "${_output_path}" || exit 2
		fi

		echo "[INFO]: Rendering template -> ${_template_path} -> ${_output_path}"
		export DOLLAR="$"
		envsubst < "$_template_path" > "$_output_path" || exit 2
		unset DOLLAR
		echo -e "[OK]: Done.\n"
	done

	echo "[INFO]: Setting permissions..."
	chown -R "www-data:${GID}" /usr/share/nginx/html /var/www || exit 2
	find /usr/share/nginx/html /var/www /var/log/nginx -type d -exec chmod 775 {} + || exit 2
	find /usr/share/nginx/html /var/www /var/log/nginx -type f -exec chmod 664 {} + || exit 2
	find /usr/share/nginx/html /var/www /var/log/nginx -type d -exec chmod +s {} + || exit 2

	chown -R "${UID}:${GID}" /etc/nginx /var/lib/nginx /var/cache/nginx /var/log/nginx || exit 2
	find /etc/nginx /var/lib/nginx /var/cache/nginx -type d -exec chmod 770 {} + || exit 2
	find /etc/nginx /var/lib/nginx /var/cache/nginx -type f -exec chmod 660 {} + || exit 2
	find /etc/nginx /var/lib/nginx /var/cache/nginx -type d -exec chmod ug+s {} + || exit 2
	echo -e "[OK]: Done.\n"

	## Parsing input:
	case ${1:-} in
		"" | -n | --nginx | nginx)
			_run_nginx;;
			# shift;;
		-s=* | --https=*)
			local _https_type="${1#*=}"
			if [ "${_https_type}" = "self" ]; then
				_https_self
			elif [ "${_https_type}" = "valid" ]; then
				_generate_dh_param
				_run_nginx
			elif [ "${_https_type}" = "lets" ]; then
				_https_lets
			fi
			shift;;
		-b | --bash | bash | /bin/bash)
			shift
			if [ -z "${*:-}" ]; then
				echo "[INFO]: Starting bash..."
				exec /bin/bash
			else
				echo "[INFO]: Executing command -> ${*}"
				exec /bin/bash -c "${*}"
			fi
			exit 0;;
		*)
			echo "[ERROR]: Failed to parse input -> ${*}!"
			echo "[INFO]: USAGE: ${0} -n, --nginx, nginx | -s=*, --https=* [self | valid | lets] | -b, --bash, bash, /bin/bash"
			exit 1;;
	esac
}

main "$@"
