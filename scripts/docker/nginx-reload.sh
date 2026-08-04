#!/usr/bin/env bash
set -euo pipefail


echo "[INFO]: Running nginx-reload.sh..."
sleep 2
nginx -s reload || exit 2

if [ ! -d "/var/log/nginx" ]; then
	mkdir -pv "/var/log/nginx" || exit 2
fi

echo -e "reloaded_dtime: $(date "+%Y-%m-%dT%H:%M:%S%z")" >> /var/log/nginx/nginx_reload.log || exit 2
echo -e "[OK]: Done.\n"

exit 0
