#!/usr/bin/env bash
## Скрипт ожидает числовой параметр, номер группы, контейнеры в которой необходимо клонировать
## Скрипт определяет число узлов в группу, которая клонируется, а также
## Наибольший номер среди всех групп, чтобы определить с каким номером создавать клонированную группу

cd "$(dirname "$0")"

CONFIGS_PATH="../configs"
HOSTDOMAIN=$(sed -n '/^\s*#/!{p;q}' $CONFIGS_PATH/ldap-domains)

if [ "$(whoami)" != "root" ]; then
    echo "Для запуска необходимы права суперпользователя" 1>&2
    exit 1
fi

if [[ $1 =~ ^[0-9]+$ ]] ## проверяем, передан ли параметр (номер группы)
then
   NN=$1
   nodesList=$(lxc-ls -1 | grep grp$NN)
   echo "Эти контейнеры будут склонированы:" 
   echo "$(lxc-ls -1 | grep grp$NN)"
   sleep 4

   nodesNum=$(( $(lxc-ls -1 | grep grp$NN | wc -l)-1 ))
   lastGrp=$(lxc-ls -1 | grep ^grp | cut -d '-' -f 1 | tr -d [:alpha:] | sort -nr | head -1)

## Клонируем группу контейнеров
   NEW=$(( $lastGrp+1 )) ## номер клонированной группы
   nodesList=(grp$NEW-sql)

   echo 1 | sudo tee /parsecfs/unsecure_setxattr
   sudo execaps -c 0x1000 -- lxc-copy -n grp$NN-sql -N grp$NEW-sql --allowrunning
   for ((i=1; i<=$nodesNum; i++))
   do
      echo "Создаем grp$NEW-rupost$i"
      sudo execaps -c 0x1000 -- lxc-copy -n grp$NN-rupost$i -N grp$NEW-rupost$i --allowrunning
      nodesList+=(grp$NEW-rupost$i)
   done
   echo 0 | sudo tee /parsecfs/unsecure_setxattr

   for node in ${nodesList[@]};
   do
      echo "Стартую $node"
      lxc-start $node
      until [ "$(sudo lxc-info -n $node -iH | head -1)" ]
      do
         printf "."
         sleep 2
      done
      echo""
      ipHost=$(sudo lxc-info -n $node -iH | head -1)
      x=$(echo $node | tr -d -c [:digit:])
      sed -i -e '$a'"$ipHost"'\t'"$node"'' -e '/'"$node"'/d' /etc/hosts

      if [ -z "$(grep 'lxc.start.auto' /var/lib/lxc/$node/config | cut -f1 -d: | head -1)" ]
      then
## Установим параметры автозапуска для sql
      if [ "$node" = "grp$NEW-sql" ]; then
         cat << EOF | sudo tee -a /var/lib/lxc/$node/config
lxc.start.auto = 1
lxc.start.delay = 5
lxc.start.order = 100
EOF
## Установка параметра автозапуска контейнеров с сервером RuPost
      else
         cat << EOF | sudo tee -a /var/lib/lxc/$node/config
lxc.start.auto = 1
lxc.start.delay = 5
lxc.start.order = 5
EOF
         sed -i -e '$aaddress=\/mail'"$x"'\.'"$HOSTDOMAIN"'\/'"$ipHost"'' -e '/mail"$x"/d' /etc/dnsmasq.d/$HOSTDOMAIN
      fi
     fi
   done
fi
echo "Клонированная группа готова к работе:"
lxc-ls -f | grep grp$NEW
