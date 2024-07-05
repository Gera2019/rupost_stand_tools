#!/usr/bin/env bash
if [ "$(whoami)" != "root" ]; then
    echo "Для запуска необходимы права суперпользователя" 1>&2
    exit 1
fi


mkdir -p /srv/nfs/IndexFiles
chown 420:420 -R /srv/nfs

if [ -z "$(grep '/srv/nfs/IndexFiles' /etc/exports | cut -f1 -d: | head -1)" ]
then
  cat << EOF | tee --append /etc/exports
/srv/nfs/IndexFiles 10.20.30.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF
fi

exportfs -ra
