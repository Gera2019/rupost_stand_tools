#!/usr/bin/env sh

if [ "$(whoami)" != "root" ]; then
    echo "Для запуска необходимы права суперпользователя" 1>&2
    exit 1
fi

if [[ $1 =~ ^[0-9]+$ ]] ## проверяем, передан ли параметр (номер группы)
then
 NN=$1
 nodesList=$(lxc-ls -1 | grep grp$NN)
fi

NEW=$(( $(lxc-ls -1 | grep grp$NN-rupost | cut -d '-' -f 2 | tr -d [:alpha:] | sort -nr | head -1)+1 ))
NODE="grp$NN-rupost$NEW"

echo "Копирование собраного контейнера"
echo 1 | sudo tee /parsecfs/unsecure_setxattr
sudo execaps -c 0x1000 -- lxc-copy -n node-clean -N $NODE
echo 0 | sudo tee /parsecfs/unsecure_setxattr


if [ -z "$(grep 'lxc.start.auto' /var/lib/lxc/$NODE/config | cut -f1 -d: | head -1)" ]
then
 cat << EOF | sudo tee -a /var/lib/lxc/$NODE/config
lxc.start.auto = 1
lxc.start.delay = 5
lxc.start.order = 5
EOF
fi

echo "Start new node ..."
 
lxc-start $NODE
until [ $(sudo lxc-info -n $NODE -iH | head -1) ]
do
  echo "wait start $NODE"
  sleep 3
done


ipHost=$(sudo lxc-info -n $NODE -iH | head -1)

#host file
sed -i -e '$a'"$ipHost"'\t'"$NODE"'' -e '/'"$NODE"'/d' /etc/hosts

if [ $(sudo lxc-info -n $NODE -iH | head -1 | grep 10.20.30.) ]
then
    sed -i -e '$aaddress=\/mail0'"$NN"'\.rupost\.local\/'$ipHost'' -e '/'mail0"$NN"'/d' /etc/dnsmasq.d/rupost.local

    #haproxy
    #sed -i 's/NODE_'"$NN"'/'"$ipHost"'/g' /etc/haproxy/haproxy.cfg
    sed -i 's/\#server node'"$NN"'/  server node'"$NN"'/g' /etc/haproxy/haproxy.cfg
    systemctl restart haproxy
fi

systemctl restart lxc-net


echo ""
echo ""
echo "Добавлен контейнер #$NN ($NODE) IP: $ipHost "

