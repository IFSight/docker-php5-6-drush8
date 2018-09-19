FROM alpine:3.5
MAINTAINER IF Fulcrum "fulcrum@ifsight.net"

RUN STARTTIME=$(date "+%s")                                                                    && \
PHPV0=5                                                                                        && \
PHPV1=6                                                                                        && \
echo "################## [$(date)] Setup PHP $PHPV0.$PHPV1 Preflight vars ##################"  && \
PHPCHGURL=http://php.net/ChangeLog-$PHPV0.php                                                  && \
PGKDIR=/home/abuild/packages                                                                   && \
PKGS1="cli|common|ctype|curl|dom|fpm|ftp|gd|gettext|iconv|imap|json|ldap|mcrypt|memcache"      && \
PKGS2="mysql|mysqli|opcache|openssl|pdo|pdo_mysql|pdo_pgsql|pgsql|redis|soap|sockets"          && \
PKGS3="xdebug|xml|xmlreader|zip|zlib"                                                          && \
PKGS="$PKGS1|$PKGS2|$PKGS3"                                                                    && \
BLACKFURL=https://blackfire.io/api/v1/releases/probe/php/alpine/amd64/$PHPV0$PHPV1             && \
echo "################## [$(date)] Add Packages ##################"                            && \
apk update --no-cache && apk upgrade --no-cache                                                && \
apk add --no-cache curl curl-dev mysql-client postfix                                          && \
apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing gnu-libiconv && \
apk add --no-cache --virtual gen-deps alpine-sdk autoconf binutils libbz2 libpcre16 libpcre32     \
  libpcrecpp m4 pcre-dev perl                                                                  && \
echo "################## [$(date)] Get PHP $PHPV0.$PHPV1 point upgrade ##################"     && \
PHPV2=$(curl -s $PHPCHGURL|grep -Eo "$PHPV0\.$PHPV1\.\d+"|cut -d\. -f3|sort -n|tail -1)        && \
PHPVER=$PHPV0.$PHPV1.$PHPV2                                                                    && \
echo "################## [$(date)] Setup PHP $PHPVER build environment ##################"     && \
adduser -D abuild -G abuild -s /bin/sh                                                         && \
mkdir -p /var/cache/distfiles                                                                  && \
chmod a+w /var/cache/distfiles                                                                 && \
echo "abuild ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/abuild                                  && \
su - abuild -c "git clone -v https://github.com/alpinelinux/aports.git aports"                 && \
su - abuild -c "cd aports && git checkout 3.5-stable"                                          && \
su - abuild -c "cd aports && git pull"                                                         && \
su - abuild -c "cd aports/main/php$PHPV0 && abuild -r deps"                                    && \
su - abuild -c "git config --global user.name \"IF Fulcrum\""                                  && \
su - abuild -c "git config --global user.email \"fulcrum@ifsight.net\""                        && \
su - abuild -c "echo ''|abuild-keygen -a -i"                                                   && \
echo "################## [$(date)] Fix Alpine PHP 5.6 bug ##################"                  && \
sed -i 's:/etc/php:$_confdir:' /home/abuild/aports/main/php$PHPV0/APKBUILD                     && \
echo "################## [$(date)] Use Alpine's bump command ##################"               && \
su - abuild -c "cd aports/main/php$PHPV0 && abump -k php$PHPV0-$PHPVER"                        && \
echo "################## [$(date)] Install initial and dev PHP packages ##################"    && \
apk add --allow-untrusted $(find $PGKDIR|egrep "php$PHPV0-((common|session)-)?$PHPV0")         && \
apk add --allow-untrusted --no-cache --virtual php-deps                                           \
  $(find $PGKDIR|egrep "php$PHPV0-(dev|phar)-$PHPV0")                                          && \
echo "################## [$(date)] Build ancillary PHP packages ##################"            && \
su - abuild -c "cd aports/main/php$PHPV0-memcache && abuild checksum && abuild -r"             && \
su - abuild -c "cd aports/testing/php$PHPV0-redis && abuild checksum && abuild -r"             && \
su - abuild -c "cd aports/community/php-xdebug    && abuild checksum && abuild -r"             && \
echo "################## [$(date)] Install PHP packages ##################"                    && \
apk add --allow-untrusted $(find $PGKDIR|egrep "php$PHPV0-($PKGS)-.*.apk")                     && \
echo "################## [$(date)] Setup Fulcrum Env ##################"                       && \
adduser -h /var/www/html -s /sbin/nologin -D -H -u 1971 php                                    && \
chown -R postfix  /var/spool/postfix                                                           && \
chgrp -R postdrop /var/spool/postfix/public /var/spool/postfix/maildrop                        && \
chown -R root     /var/spool/postfix/pid                                                       && \
chown    root     /var/spool/postfix                                                           && \
echo smtputf8_enable = no >> /etc/postfix/main.cf                                              && \
echo "################## [$(date)] Install Blackfire ##################"                       && \
curl -A "Docker" -o /blackfire-probe.tar.gz -D - -L -s $BLACKFURL                              && \
tar zxpf /blackfire-probe.tar.gz -C /                                                          && \
mv /blackfire-*.so $(php -r "echo ini_get('extension_dir');")/blackfire.so                     && \
printf "extension=blackfire.so\nblackfire.agent_socket=tcp://blackfire:8707\n"                  | \
    tee /etc/php$PHPV0/conf.d/90-blackfire.ini                                                 && \
echo "################## [$(date)] Install Composer ##################"                        && \
cd /usr/local                                                                                  && \
curl -sS https://getcomposer.org/installer|php                                                 && \
/bin/mv composer.phar bin/composer                                                             && \
echo "################## [$(date)] Install Drush ##################"                           && \
deluser php                                                                                    && \
adduser -h /phphome -s /bin/sh -D -H -u 1971 php                                               && \
mkdir -p /usr/share/drush/commands /phphome drush8                                             && \
chown php.php /phphome drush8                                                                  && \
su - php -c "cd /usr/local/drush8 && composer require drush/drush:8.*"                         && \
ln -s /usr/local/drush8/vendor/drush/drush/drush /usr/local/bin/drush                          && \
su - php -c "/usr/local/bin/drush @none dl registry_rebuild-7.x"                               && \
mv /phphome/.drush/registry_rebuild /usr/share/drush/commands/                                 && \
echo "################## [$(date)] Reset php user for fulcrum ##################"              && \
deluser php                                                                                    && \
adduser -h /var/www/html -s /bin/sh -D -H -u 1971 php                                          && \
echo "################## [$(date)] Clean up container/put on a diet ##################"        && \
find /bin /lib /sbin /usr/bin /usr/lib /usr/sbin -type f -exec strip -v {} \;                  && \
apk del php-deps gen-deps                                                                      && \
deluser --remove-home abuild                                                                   && \
cd /usr/bin                                                                                    && \
rm -vrf /blackfire* /var/cache/apk/* /var/cache/distfiles/* /phphome /usr/local/bin/composer      \
    mysql_waitpid mysqlimport mysqlshow mysqladmin mysqlcheck mysqldump myisam_ftdump          && \
echo "################## [$(date)] Done ##################"                                    && \
echo "################## Elapsed: $(expr $(date "+%s") - $STARTTIME) seconds ##################"

USER php

ENV COLUMNS 100
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php-fpm

WORKDIR /var/www/html

ENTRYPOINT ["/usr/bin/php-fpm"]

CMD ["--nodaemonize"]
