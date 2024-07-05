#!/usr/bin/env sh

if [ "$(whoami)" != "root" ]; then
    echo "Для запуска необходимы права суперпользователя" 1>&2
    exit 1
fi

if [[ $1 =~ ^[0-9]+$ ]]
then
 NN=$1
 lxc-stop app-$NN
 lxc-destroy app-$NN
else
NN=$(lxc-ls -f | grep app | awk -F '[^0-9]*' '$0=$2+1' | tail -1)
fi

NODE="app-$NN"

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


systemctl restart lxc-net


echo ""
echo ""
echo "Добавлен контейнер #$NN ($NODE) IP: $ipHost "

