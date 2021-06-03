#!/bin/bash

cd $(dirname $0)/..
. .env

set -x -e -o pipefail -o errexit

usermod -aG $SACLOUD_ADMIN_USER apache
cp -f /root/.ssh/id_rsa_admin /home/$SACLOUD_ADMIN_USER/.ssh/id_rsa
cp -f /root/.ssh/id_rsa_admin.pub /home/$SACLOUD_ADMIN_USER/.ssh/id_rsa.pub
cp -f /root/.ssh/authorized_keys /home/$SACLOUD_ADMIN_USER/.ssh/authorized_keys
cat /home/$SACLOUD_ADMIN_USER/.ssh/id_rsa.pub >> /home/$SACLOUD_ADMIN_USER/.ssh/authorized_keys

md5sum /home/$SACLOUD_ADMIN_USER/.ssh/id_rsa | passwd --stdin $SACLOUD_ADMIN_USER

cp -fr /root/.sacloud-api/sacloudb/html /home/$SACLOUD_ADMIN_USER/.
cat <<_EOF > /home/$SACLOUD_ADMIN_USER/html/sacloud-api/.htaccess

SetEnv SACLOUDB_ADMIN_USER $SACLOUDB_ADMIN_USER
SetEnv SACLOUDB_ADMIN_PASS $SACLOUDB_ADMIN_PASS
SetEnv SACLOUDB_VIP_ADDRESS $SERVER_VIP

RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ index.php [QSA,L]

_EOF

chmod 710 /home/$SACLOUD_ADMIN_USER /home/$SACLOUD_ADMIN_USER/.ssh
chmod 640 /home/$SACLOUD_ADMIN_USER/.ssh/authorized_keys
chown -R $SACLOUD_ADMIN_USER:$SACLOUD_ADMIN_USER /home/$SACLOUD_ADMIN_USER

cat <<_EOF > /etc/httpd/conf.d/sacloud-admin.conf
#
# When we also provide SSL we have to listen to the
# the HTTPS port in addition.
#
Listen 8443 https
<VirtualHost $SERVER_GLOBALIP:8443>

DocumentRoot "/home/$SACLOUD_ADMIN_USER/html"
#ServerName www.example.com:443

ErrorLog logs/ssl_error_log
TransferLog logs/ssl_access_log
LogLevel warn

SSLEngine on
SSLProtocol all -SSLv2 -SSLv3
SSLCipherSuite HIGH:3DES:!aNULL:!MD5:!SEED:!IDEA

#SSLCipherSuite RC4-SHA:AES128-SHA:HIGH:MEDIUM:!aNULL:!MD5
#SSLHonorCipherOrder on

SSLCertificateFile /etc/pki/tls/certs/localhost.crt
SSLCertificateKeyFile /etc/pki/tls/private/localhost.key
#SSLCertificateChainFile /etc/pki/tls/certs/server-chain.crt

#SSLCACertificateFile /etc/pki/tls/certs/ca-bundle.crt

#SSLVerifyClient require
#SSLVerifyDepth  10

BrowserMatch "MSIE [2-5]" \
         nokeepalive ssl-unclean-shutdown \
         downgrade-1.0 force-response-1.0

CustomLog logs/ssl_request_log \
          "%t %h %{SSL_PROTOCOL}x %{SSL_CIPHER}x \"%r\" %b"

<Directory "/home/$SACLOUD_ADMIN_USER/html">
    Options Indexes FollowSymLinks

    AllowOverride All
    Require all granted

    AuthUserFile /etc/httpd/.htpasswd-secure
    AuthGroupFile /dev/null
    AuthName "Basic Auth"
    AuthType Basic
    Require valid-user
</Directory>

</VirtualHost>
_EOF

sed -i /usr/lib/systemd/system/httpd.service -e 's/^PrivateTmp=.*/PrivateTmp=false/g'
systemctl daemon-reload
apachectl restart

