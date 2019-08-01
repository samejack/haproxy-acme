# vim:set ft=dockerfile:
FROM debian:stretch-slim
MAINTAINER SJ Chou <sj@toright.com>

ENV HAPROXY_VERSION 1.9.8
ENV HAPROXY_URL https://www.haproxy.org/download/1.9/src/haproxy-1.9.8.tar.gz
ENV HAPROXY_SHA256 2d9a3300dbd871bc35b743a83caaf50fecfbf06290610231ca2d334fd04c2aee

# see https://sources.debian.net/src/haproxy/jessie/debian/rules/ for some helpful navigation of the possible "make" arguments
RUN set -x \
	\
	&& savedAptMark="$(apt-mark showmanual)" \
	&& apt-get update && apt-get install -y --no-install-recommends \
		ca-certificates \
		gcc \
		libc6-dev \
		liblua5.3-dev \
		libpcre3-dev \
		libssl-dev \
		make \
		wget \
		zlib1g-dev \
	&& rm -rf /var/lib/apt/lists/* \
	\
	&& wget -O haproxy.tar.gz "$HAPROXY_URL" \
	&& echo "$HAPROXY_SHA256 *haproxy.tar.gz" | sha256sum -c \
	&& mkdir -p /usr/src/haproxy \
	&& tar -xzf haproxy.tar.gz -C /usr/src/haproxy --strip-components=1 \
	&& rm haproxy.tar.gz \
	\
	&& makeOpts=' \
		TARGET=linux2628 \
		USE_LUA=1 LUA_INC=/usr/include/lua5.3 \
		USE_GETADDRINFO=1 \
		USE_OPENSSL=1 \
		USE_PCRE=1 PCREDIR= \
		USE_ZLIB=1 \
	' \
	&& make -C /usr/src/haproxy -j "$(nproc)" all $makeOpts \
	&& make -C /usr/src/haproxy install-bin $makeOpts \
	\
	&& mkdir -p /usr/local/etc/haproxy \
	&& cp -R /usr/src/haproxy/examples/errorfiles /usr/local/etc/haproxy/errors \
	&& rm -rf /usr/src/haproxy \
	\
	&& apt-mark auto '.*' > /dev/null \
	&& { [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; } \
	&& find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual

# https://www.haproxy.org/download/1.8/doc/management.txt
# "4. Stopping and restarting HAProxy"
# "when the SIGTERM signal is sent to the haproxy process, it immediately quits and all established connections are closed"
# "graceful stop is triggered when the SIGUSR1 signal is sent to the haproxy process"
STOPSIGNAL SIGUSR1

# Install package
RUN apt-get -y update && \
    apt-get -y install supervisor curl openssl cron

# Install confd and supervisord config
RUN curl -qL https://github.com/kelseyhightower/confd/releases/download/v0.16.0/confd-0.16.0-linux-amd64 -o /confd && \
    chmod +x /confd && \
    mv /confd /usr/sbin && \
    mkdir -p /etc/confd/conf.d && \
    mkdir -p /etc/confd/templates

# Install acme.sh
RUN curl https://get.acme.sh -o /tmp/acme.sh && chmod 755 /tmp/acme.sh && /tmp/acme.sh --install
RUN ~/.acme.sh/acme.sh --install-cronjob

# Install etcd
RUN wget https://github.com/coreos/etcd/releases/download/v2.0.10/etcd-v2.0.10-linux-amd64.tar.gz && \
    tar xzvf etcd-v2.0.10-linux-amd64.tar.gz && \
    mv etcd-v2.0.10-linux-amd64/etcd* /bin/ && \
    rm -Rf etcd-v2.0.10-linux-amd64*
ADD ./etcd/run-etcd.sh /bin/

# Install lighttp
RUN apt-get -y install lighttpd
RUN useradd lighttpd
COPY ./lighttpd/* /etc/lighttpd/

# Clear APT cache
RUN apt-get remove --purge -y software-properties-common && \
    apt-get autoremove -y  -o APT::AutoRemove::RecommendsImportant=false && \
    apt-get clean && \
    apt-get autoclean && \
    echo -n > /var/lib/apt/extended_states && \
    rm -rf /usr/share/man/?? && \
    rm -rf /usr/share/man/??_* && \
	rm -rf /var/cache/apk/*

# Init script and config file
ADD ./docker-entrypoint.sh /
ADD ./haproxy/supervisord.conf     /etc/supervisor/supervisord.conf
ADD ./haproxy/default.pem          /usr/local/etc/haproxy/default.pem
ADD ./haproxy/haproxy.cfg          /etc/haproxy/haproxy.cfg
ADD ./haproxy/haproxy.cfg.toml     /etc/confd/conf.d/haproxy.cfg.toml
ADD ./haproxy/haproxy.cfg.tmpl     /etc/confd/templates/haproxy.cfg.tmpl
ADD ./haproxy/acme-issue.sh.toml   /etc/confd/conf.d/acme-issue.sh.toml
ADD ./haproxy/acme-issue.sh.tmpl   /etc/confd/templates/acme-issue.sh.tmpl

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
