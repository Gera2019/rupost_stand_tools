#!/usr/bin/env sh

if [ "$(whoami)" != "root" ]; then
    echo "Для запуска необходимы права суперпользователя" 1>&2
    exit 1
fi

ipSQL=$(sudo lxc-info -n node-sql -iH | head -1)

#sql
cat << EOF | sudo tee /tmp/sql.sh
sudo su - postgres -c "psql -c \"DROP DATABASE rupost;\""
sudo su - postgres -c "psql -c \"DROP DATABASE rupost_data;\""
sudo su - postgres -c "psql -c \"DROP DATABASE rupost_logs;\""
sudo su - postgres -c "psql -c \"CREATE DATABASE rupost WITH ENCODING 'UTF8' OWNER rupost;\""
sudo su - postgres -c "psql -c \"CREATE DATABASE rupost_data WITH ENCODING 'UTF8' OWNER rupost;\""
sudo su - postgres -c "psql -c \"CREATE DATABASE rupost_logs WITH ENCODING 'UTF8' OWNER rupost;\""
EOF

sshpass -p 'astralinux' ssh -o StrictHostKeyChecking=no -l admin "$ipSQL" 'bash -s' < /tmp/sql.sh
rm /tmp/sql.sh

