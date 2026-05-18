# syntax=docker/dockerfile:1

# ARG BASE_IMAGE=ubuntu:24.04
ARG BASE_IMAGE=ubuntu:26.04

ARG DEBIAN_FRONTEND=noninteractive
ARG NGINX_VERSION=1.30.1


# Here is the builder image
FROM ${BASE_IMAGE} AS builder

ARG DEBIAN_FRONTEND
ARG NGINX_VERSION

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /usr/src/nginx

RUN rm -rfv /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /root/.cache/* && \
	apt-get clean -y && \
	apt-get update --fix-missing -o Acquire::CompressionTypes::Order::=gz && \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		build-essential \
		wget \
		tar \
		# libpcre3 \
		# libpcre3-dev \
		libpcre2-dev \
		zlib1g \
		zlib1g-dev \
		libssl-dev \
		openssl \
		libgeoip-dev

COPY --chown="www-data:11000" --chmod=775 ./src/html ./html
RUN wget -nv --show-progress --progress=bar:force:noscroll "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O nginx.tar.gz && \
	tar -xzf nginx.tar.gz && \
	cd nginx-${NGINX_VERSION} && \
	cat /usr/src/nginx/html/index.html > ./html/index.html && \
	cat /usr/src/nginx/html/50x.html > ./html/50x.html && \
	./configure \
		--sbin-path=/usr/bin/nginx \
		--conf-path=/etc/nginx/nginx.conf \
		--error-log-path=/dev/stderr \
		--http-log-path=/dev/stdout \
		--pid-path=/run/nginx.pid \
		--lock-path=/var/lock/nginx.lock \
		--http-client-body-temp-path=/var/cache/nginx/body \
		--http-proxy-temp-path=/var/cache/nginx/proxy \
		--http-fastcgi-temp-path=/var/cache/nginx/fastcgi \
		--http-uwsgi-temp-path=/var/cache/nginx/uwsgi \
		--http-scgi-temp-path=/var/cache/nginx/scgi \
		--with-debug \
		--with-compat \
		--with-pcre-jit \
		--with-http_ssl_module \
		--with-http_stub_status_module \
		--with-http_realip_module \
		--with-http_auth_request_module \
		--with-http_v2_module \
		--with-http_v3_module \
		--with-http_slice_module \
		--with-threads \
		--with-http_addition_module \
		--with-http_gunzip_module \
		--with-http_gzip_static_module \
		--with-http_sub_module \
		--with-stream \
		--with-stream_ssl_module \
		--with-http_mp4_module \
		--with-http_geoip_module=dynamic \
		--without-mail_pop3_module \
		--without-mail_imap_module \
		--without-mail_smtp_module && \
	make && \
	rm -rf auto contrib CHANGE* LICENSE README configure


# Here is the base image
FROM ${BASE_IMAGE} AS base

ARG DEBIAN_FRONTEND
ARG NGINX_VERSION

ARG UID=1000
ARG USER=nginx-user
ARG GID=11000
ARG GROUP=www-group

ENV UID=${UID} \
	USER=${USER} \
	GID=${GID} \
	GROUP=${GROUP} \
	NGINX_VERSION=${NGINX_VERSION}

WORKDIR /usr/src/nginx

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Installing system dependencies
RUN rm -rfv /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /root/.cache/* && \
	apt-get clean -y && \
	apt-get update --fix-missing -o Acquire::CompressionTypes::Order::=gz && \
	apt-get install -y --no-install-recommends \
		# sudo \
		locales \
		tzdata \
		procps \
		iputils-ping \
		iproute2 \
		curl \
		nano \
		make \
		openssl \
		watchman \
		gettext-base \
		apache2-utils \
		libgeoip-dev && \
	apt-get clean -y && \
	sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
	sed -i -e 's/# en_AU.UTF-8 UTF-8/en_AU.UTF-8 UTF-8/' /etc/locale.gen && \
	sed -i -e 's/# ko_KR.UTF-8 UTF-8/ko_KR.UTF-8 UTF-8/' /etc/locale.gen && \
	dpkg-reconfigure --frontend=noninteractive locales && \
	update-locale LANG=en_US.UTF-8 && \
	echo "LANGUAGE=en_US.UTF-8" >> /etc/default/locale && \
	echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale && \
	groupadd --gid "${GID}" "${GROUP}" && \
	# useradd -lmN -d "/home/${USER}" -s /bin/bash -g "${GROUP}" -G sudo -u "${UID}" "${USER}" && \
	echo -e "\nalias ls='ls -aF --group-directories-first --color=auto'" >> /root/.bashrc && \
	echo -e "alias ll='ls -alhF --group-directories-first --color=auto'\n" >> /root/.bashrc && \
	rm -rfv /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /root/.cache/* && \
	mkdir -pv /var/lib/nginx /var/cache/nginx /usr/share/nginx/html /etc/nginx/ssl /etc/nginx/modules-enabled /etc/nginx/sites-enabled /var/log/nginx /var/www/.well-known/acme-challenge && \
	chown -Rc "www-data:${GROUP}" /var/www /usr/share/nginx/html && \
	find /var/www /usr/share/nginx/html /var/log/nginx -type d -exec chmod -c 775 {} + && \
	find /var/www /usr/share/nginx/html /var/log/nginx -type d -exec chmod -c +s {} + && \
	chown -Rc "1000:${GROUP}" /etc/nginx /var/lib/nginx /var/cache/nginx /var/log/nginx && \
	find /etc/nginx /var/lib/nginx /var/cache/nginx -type d -exec chmod -c 770 {} + && \
	find /etc/nginx /var/lib/nginx /var/cache/nginx -type d -exec chmod -c ug+s {} +

ENV	LANG=en_US.UTF-8 \
	LANGUAGE=en_US.UTF-8 \
	LC_ALL=en_US.UTF-8

# COPY --from=builder --chown=root:root /usr/src/nginx/nginx-${NGINX_VERSION} /usr/src/nginx
RUN --mount=type=bind,from=builder,source=/usr/src/nginx/nginx-${NGINX_VERSION},target=/usr/src/nginx \
	make install


# Here is the production image
FROM base AS app

WORKDIR /etc/nginx
COPY --chown=root:root --chmod=770 ./scripts/docker/*.sh /usr/local/bin/
COPY --chown="www-data:${GROUP}" --chmod=775 ./src/html/ /usr/share/nginx/html/
COPY --chown="1000:${GROUP}" --chmod=770 ./src/configs/ /etc/nginx/

# VOLUME ["/etc/nginx/ssl"]
# EXPOSE 80 443
# HEALTHCHECK --start-period=20s --start-interval=1s --interval=5m --timeout=5s --retries=3 \
# 	CMD curl -f http://localhost:80 || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
