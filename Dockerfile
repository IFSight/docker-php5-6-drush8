FROM alpine:3.5
MAINTAINER IF Fulcrum "fulcrum@ifsight.net"

RUN echo "#################### Setup Preflight variables ####################"                           && \
PHPMAJVER=5                                                                                              && \
PHPMNRVER=6                                                                                              && \
PHPCHGURL=http://php.net/ChangeLog-$PHPMAJVER.php                                                        && \
PGKDIR_C=/home/abuild/packages/community/x86_64                                                          && \
PGKDIR_M=/home/abuild/packages/main/x86_64                                                               && \
PGKDIR_T=/home/abuild/packages/testing/x86_64                                                            && \
PKGS1="cli common ctype curl dom fpm ftp gd gettext imap json ldap mcrypt mysql mysqli opcache"          && \
PKGS2="openssl pdo pdo_mysql pdo_pgsql pgsql soap sockets xml xmlreader zip zlib"                        && \
PKGS="$PKGS1 $PKGS2"                                                                                     && \
BLACKFURL=https://blackfire.io/api/v1/releases/probe/php/alpine/amd64/$PHPMAJVER$PHPMNRVER               && \
echo "#################### Add Packages ####################"                                            && \
apk update --no-cache && apk upgrade --no-cache                                                          && \
apk add --no-cache --virtual build-dependencies alpine-sdk autoconf binutils m4 libbz2 perl                 \
    php$PHPMAJVER-dev php$PHPMAJVER-phar                                                                 && \
apk add --no-cache curl curl-dev mysql-client postfix                                                    && \
echo "#################### Get PHP point upgrade ####################"                                   && \
PHPPNTVER=$(curl -s $PHPCHGURL|grep -Eo "$PHPMAJVER\.$PHPMNRVER\.\d+"|cut -d\. -f3|sort -n|tail -1)      && \
PHPVER=$PHPMAJVER.$PHPMNRVER.$PHPPNTVER                                                                  && \
echo "#################### Setup build environment ####################"                                 && \
adduser -D abuild -G abuild -s /bin/sh                                                                   && \
mkdir -p /var/cache/distfiles                                                                            && \
chmod a+w /var/cache/distfiles                                                                           && \
echo "abuild ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/abuild                                            && \
su - abuild -c "git clone -v https://github.com/alpinelinux/aports.git aports"                           && \
su - abuild -c "cd aports && git checkout 3.5-stable"                                                    && \
su - abuild -c "cd aports && git pull"                                                                   && \
su - abuild -c "cd aports/main/php$PHPMAJVER && abuild -r deps"                                          && \
su - abuild -c "git config --global user.name \"IF Fulcrum\""                                            && \
su - abuild -c "git config --global user.email \"fulcrum@ifsight.net\""                                  && \
su - abuild -c "echo ''|abuild-keygen -a -i"                                                             && \
echo "#################### Fix Alpine PHP 5.6 bug ####################"                                  && \
sed -i 's:/etc/php:$_confdir:' /home/abuild/aports/main/php$PHPMAJVER/APKBUILD                           && \
echo "#################### Use Alpine's bump command ####################"                               && \
su - abuild -c "cd aports/main/php$PHPMAJVER && abump -k php$PHPMAJVER-$PHPVER"                          && \
echo "#################### Build ancillary PHP packages ####################"                            && \
su - abuild -c "cd aports/main/php$PHPMAJVER-memcache && abuild checksum && abuild -r"                   && \
su - abuild -c "cd aports/testing/php$PHPMAJVER-redis && abuild checksum && abuild -r"                   && \
su - abuild -c "cd aports/community/php-xdebug        && abuild checksum && abuild -r"                   && \
echo "#################### Install PHP packages ####################"                                    && \
apk add --allow-untrusted $PGKDIR_M/php$PHPMAJVER-$PHPVER-r0.apk $PGKDIR_M/php$PHPMAJVER-memcache*.apk      \
    $PGKDIR_T/php$PHPMAJVER-redis*.apk $PGKDIR_C/php$PHPMAJVER-xdebug*.apk                               && \
for EXT in $PKGS;do apk add --allow-untrusted $PGKDIR_M/php$PHPMAJVER-$EXT-$PHPVER-r0.apk;done           && \
echo "#################### Setup Fulcrum Env ####################"                                       && \
adduser -h /var/www/html -s /sbin/nologin -D -H -u 1971 php                                              && \
chown -R postfix  /var/spool/postfix                                                                     && \
chgrp -R postdrop /var/spool/postfix/public /var/spool/postfix/maildrop                                  && \
chown -R root     /var/spool/postfix/pid                                                                 && \
chown    root     /var/spool/postfix                                                                     && \
echo smtputf8_enable = no >> /etc/postfix/main.cf                                                        && \
echo "#################### Install Blackfire ####################"                                       && \
curl -A "Docker" -o /blackfire-probe.tar.gz -D - -L -s $BLACKFURL                                        && \
tar zxpf /blackfire-probe.tar.gz -C /                                                                    && \
mv /blackfire-*.so $(php -r "echo ini_get('extension_dir');")/blackfire.so                               && \
printf "extension=blackfire.so\nblackfire.agent_socket=tcp://blackfire:8707\n"                            | \
tee /etc/php$PHPMAJVER/conf.d/90-blackfire.ini                                                           && \
echo "#################### Install Drush ####################"                                           && \
cd /usr/local                                                                                            && \
curl -sS https://getcomposer.org/installer|php                                                           && \
/bin/mv composer.phar bin/composer                                                                       && \
deluser php                                                                                              && \
adduser -h /phphome -s /bin/sh -D -H -u 1971 php                                                         && \
mkdir -p /usr/share/drush/commands /phphome drush8                                                       && \
chown php.php /phphome drush8                                                                            && \
su - php -c "cd /usr/local/drush8 && composer require drush/drush:8.*"                                   && \
ln -s /usr/local/drush8/vendor/drush/drush/drush /usr/local/bin/drush                                    && \
su - php -c "/usr/local/bin/drush @none dl registry_rebuild-7.x"                                         && \
mv /phphome/.drush/registry_rebuild /usr/share/drush/commands/                                           && \
echo "#################### Reset php user for fulcrum ####################"                              && \
deluser php                                                                                              && \
adduser -h /var/www/html -s /bin/sh -D -H -u 1971 php                                                    && \
echo "#################### Clean up container/put on a diet ####################"                        && \
find /bin /lib /sbin /usr/bin /usr/lib /usr/sbin -type f -exec strip -v {} \;                            && \
apk del build-dependencies php$PHPMAJVER-dev pcre-dev                                                    && \
deluser --remove-home abuild                                                                             && \
cd /usr/bin                                                                                              && \
rm -rf /blackfire* /var/cache/apk/* /var/cache/distfiles/* /phphome /usr/local/bin/composer                 \
    mysql_waitpid mysqlimport mysqlshow mysqladmin mysqlcheck mysqldump myisam_ftdump

USER php

ENV COLUMNS 100

WORKDIR /var/www/html

ENTRYPOINT ["/usr/sbin/php-fpm"]

CMD ["--nodaemonize"]