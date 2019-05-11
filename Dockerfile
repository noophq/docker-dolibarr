FROM php:7.3-apache

RUN a2enmod rewrite

# install the PHP extensions we need
ENV HOST_USER_ID 33
ENV PHP_INI_DATE_TIMEZONE 'UTC'

RUN apt-get update && apt-get install -y libpng-dev libjpeg-dev libldap2-dev \
	&& rm -rf /var/lib/apt/lists/* \
	&& docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr \
	&& docker-php-ext-install gd \
	&& docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu/ \
        && docker-php-ext-install ldap \
        && docker-php-ext-install mysqli \
        && apt-get purge -y libpng-dev libjpeg-dev libldap2-dev

VOLUME /var/www/html

ENV DOLIBARR_VERSION 9.0.3
ENV DOLIBARR_SHA1 05955949b893c5346477de7f2f4fff2427ea6e2c

# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
RUN curl -o dolibarr.tar.gz -SL https://github.com/Dolibarr/dolibarr/archive/${DOLIBARR_VERSION}.tar.gz \
	&& echo "$DOLIBARR_SHA1 *dolibarr.tar.gz" | sha1sum -c - \
	&& tar -xzf dolibarr.tar.gz -C /usr/src/ \
	&& rm dolibarr.tar.gz \
    && mv /usr/src/dolibarr-${DOLIBARR_VERSION} /usr/src/dolibarr \
	&& chown -R www-data:www-data /usr/src/dolibarr

COPY docker-entrypoint.sh /entrypoint.sh

# grr, ENTRYPOINT resets CMD now
ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
