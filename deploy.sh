#!/bin/bash
#
# To run: curl -L https://raw.githubusercontent.com/mrakitin/sirepo_config/master/deploy.sh | bash
#
set -e

#
# Assertions
#
if (( $UID != 0 )); then
    echo 'Must run as root' 1>&2
    exit 1
fi
if ! grep '^8\.' /etc/debian_version >& /dev/null; then
    echo 'Incorrect debian version (not 8.x) or not Debian' 1>&2
    exit 1
fi

prev_dir=$PWD
export TMPDIR=/var/tmp/sirepo_config-$$-$RANDOM
umask 027
mkdir -p "$TMPDIR"
cd "$TMPDIR"

#
# Prerequisites
#
if ! id vagrant >& /dev/null; then
    echo Adding user vagrant
    useradd vagrant
fi
for f in git nginx; do
    if ! dpkg -s "$f" >& /dev/null; then
        # Work around an nginx install problem
        rm -f /etc/nginx/sites-enabled/sirepo.conf
        apt-get -y install "$f"
    fi
done

#
# Install
#
git clone https://github.com/mrakitin/sirepo_config
cd sirepo_config
if ! service docker status >& /dev/null; then
    echo Installing Docker
    . ./jessie-docker.sh
fi

cd cpu-001
tar cf - * | (cd /; tar xf -)
. /etc/default/bivio-service
. /etc/default/sirepo

#
# Permissions
#
services=( rabbitmq celery-sirepo sirepo )
dirs=( $sirepo_db_dir )
mkdir -p "$sirepo_db_dir/beaker"
for f in "${services[@]}"; do
    chmod u+x /etc/init.d/"$s"
    mkdir -p "$bivio_service_base_dir/$s"
    dirs+=( "$bivio_service_base_dir/$s" )
done
chown -R vagrant:vagrant "${dirs[@]}"

#
# Beaker
#
if [[  -f $sirepo_beaker_secret ]]; then
    # Generate random secret
    echo "Generating: $sirepo_beaker_secret"
    python > "$sirepo_beaker_secret" <<'EOF'
import random, string, sys
y = string.digits + string.letters + string.punctuation
x = ''.join(random.choice(y) for _ in range(64))
sys.stdout.write(x)
EOF
    chgrp vagrant "$sirepo_beaker_secret"
    chmod 640 "$sirepo_beaker_secret"
fi

#
# Nginx
#
rm -f /etc/nginx/sites-enabled/default
x=/var/www/empty
if [[ ! -d $x ]]; then
    mkdir "$x"
    chmod 555 "$x"
fi

#
# Services
#
docker pull "$bivio_service_image:$bivio_service_channel"
systemctl daemon-reload
for s in "${services[@]}" nginx; do
    if ! systemctl status "$s" >& /dev/null; then
        systemctl enable "$s"
    fi
    service "$s" restart
done

cd "$prev_dir"
rm -rf "$TMPDIR"

cat <<'EOF'
To restart services:
for f in ${services[*]}; do service \$f update_and_restart; done
EOF
