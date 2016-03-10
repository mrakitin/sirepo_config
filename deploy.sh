#!/bin/bash
set -e
prev_dir=$PWD
export TMPDIR=/var/tmp/sirepo_config-$$-$RANDOM
mkdir -p "$TMPDIR"
cd "$TMPDIR"
umask 027

if ! service docker status >& /dev/null; then
    echo 'docker not running, please install and start' 1>&2
    exit 1
fi

#
# Run user
#
if ! id vagrant >& /dev/null; then
    echo Adding user vagrant
    useradd vagrant
fi

#
# Install
#
git clone https://github.com/mrakitin/sirepo_config
cd sirepo_config/cpu-001
. /etc/default/bivio-service
rsync -a * /
chown -R vagrant:vagrant "$sirepo_db_dir" "$bivio_service_base_dir"/{celery-sirepo,sirepo,rabbitmq}
chmod u+x /etc/init.d/{celery-sirepo,sirepo,rabbitmq}

#
# Beaker
#
if [[ ! -f $sirepo_beaker_secret ]]; then
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
systemctl daemon-reload
for s in rabbitmq celery-sirepo sirepo nginx; do
    if ! systemctl status "$s" >& /dev/null; then
        systemctl enable "$s"
    fi
    service "$s" restart
done

cd "$prev_dir"
rm -rf "$TMPDIR"
