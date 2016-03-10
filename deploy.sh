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
# Vagrant user
#
if ! id vagrant >& /dev/null; then
    echo Adding user vagrant
    useradd vagrant
fi

#
# Install files
#
git clone https://github.com/mrakitin/sirepo_config
cd sirepo_config/cpu-001
. /etc/default/bivio-service
rsync -a * /
chown -R vagrant:vagrant "$sirepo_db_dir" "$bivio_service_base_dir"/{celery-sirepo,sirepo,rabbitmq}
chmod u+x /etc/init.d/{celery-sirepo,sirepo,rabbitmq}

#
# Verify /etc/hosts
#
if ! grep "$rabbitmq_host" /etc/hosts >& /dev/null; then
    echo "You need to add $rabbitmq_host to /etc/hosts" 1>&2
    exit 1
fi

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
# move out dist sites-enabled, we use conf.d
#
x=/etc/nginx/sites-enabled/default
if [[ -f $x ]]; then
    mv "$x" "$x-dist"
fi

#
# Services
#
for s in rabbitmq celery-sirepo sirepo nginx; do
    if ! systemctl status "$s" >& /dev/null; then
        systemctl enable "$s"
    fi
    service "$s" restart
done

cd "$prev_dir"
rm -rf "$TMPDIR"
