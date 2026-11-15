# syntax=docker/dockerfile:1

###############################################################################
# Stage 1 — vendor
# Composer deps are resolved in a throwaway image so the runtime image stays slim
# and never carries composer itself.
###############################################################################
FROM composer:2 AS vendor

WORKDIR /app

# Only the manifest is needed to install dependencies. Copying these first
# keeps the layer cache warm when only source code changes.
COPY composer.json composer.lock ./

# The composer image does not carry Moodle's required extensions (ext-intl,
# ext-gd, ext-mysqli, ...). Installing them there would bloat a stage that is
# thrown away, so platform checks are skipped. The runtime stage installs and
# provides every extension for real — that is what actually serves requests.
RUN --mount=type=cache,target=/tmp/composer-cache \
    COMPOSER_CACHE_DIR=/tmp/composer-cache composer install \
        --no-dev \
        --no-scripts \
        --no-interaction \
        --prefer-dist \
        --optimize-autoloader \
        --no-progress \
        --ignore-platform-reqs

###############################################################################
# Stage 2 — runtime (php-fpm + Moodle source)
###############################################################################
FROM php:8.3-fpm-alpine AS runtime

LABEL org.opencontainers.image.title="Moodle" \
      org.opencontainers.image.version="5.3.1" \
      org.opencontainers.image.source="https://github.com/diconic-dev/moodle"

# Build deps for PHP extensions are removed in the same layer to avoid bloat.
RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        libpng-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        libzip-dev \
        libxml2-dev \
        icu-dev \
        oniguruma-dev \
    ; \
    apk add --no-cache \
        libpng \
        libjpeg-turbo \
        freetype \
        libzip \
        libxml2 \
        icu-libs \
        oniguruma \
        fcgi \
        curl \
        tzdata \
    ; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
        gd \
        intl \
        mbstring \
        mysqli \
        pdo_mysql \
        soap \
        zip \
        exif \
        opcache \
    ; \
    apk del --no-network .build-deps; \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/*
# Not installed explicitly because php:8.3 already ships them compiled in:
#   xmlreader, simplexml, sodium, ctype, curl, dom, fileinfo, hash, iconv,
#   json, libxml, mbstring, openssl, pcre, tokenizer.
# Asking docker-php-ext-install for a builtin extension fails the build.

# PHP configuration (opcache, upload limits, session handling)
COPY docker/php.ini /usr/local/etc/php/conf.d/zz-moodle.ini

WORKDIR /var/www/moodle

# Application source. Ownership: php-fpm runs as www-data, and Moodle needs to
# be able to write into its own tree for a few runtime paths.
COPY --chown=www-data:www-data . .

# Composer dependencies from stage 1
COPY --from=vendor --chown=www-data:www-data /app/vendor ./vendor

# Entrypoint waits for the DB, renders config.php from env, then execs php-fpm.
COPY docker/entrypoint.sh /usr/local/bin/moodle-entrypoint
COPY docker/healthcheck.sh /usr/local/bin/moodle-healthcheck
RUN chmod +x /usr/local/bin/moodle-entrypoint /usr/local/bin/moodle-healthcheck

# Moodledata lives on a volume; create the mountpoint with correct ownership.
RUN mkdir -p /var/www/moodledata \
    && chown www-data:www-data /var/www/moodledata

ENV MOODLE_DATAROOT=/var/www/moodledata \
    MOODLE_DB_TYPE=mariadb \
    MOODLE_DB_HOST=db \
    MOODLE_DB_PORT=3306 \
    MOODLE_DB_NAME=moodle \
    MOODLE_DB_USER=moodle \
    MOODLE_WWWROOT=http://localhost:8080 \
    MOODLE_SITE_LANG=en \
    MOODLE_REVERSEPROXY=0 \
    MOODLE_SSLPROXY=0

EXPOSE 9000
STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["/usr/local/bin/moodle-healthcheck"]

ENTRYPOINT ["/usr/local/bin/moodle-entrypoint"]
CMD ["php-fpm", "-F"]

###############################################################################
# Stage 3 — web (nginx static assets)
###############################################################################
FROM nginx:1.27-alpine AS web

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=runtime /var/www/moodle/public /var/www/moodle/public