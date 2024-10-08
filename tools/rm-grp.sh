#!/usr/bin/env bash
## Скрипт ожидает числовой параметр, номер группы, которую необходимо удалить
## Скрипт удаляет группу, для этого контейнеры группы останавливаются и затем удаляются
## Подчищаются записи DNS-сервера и в файле hosts

cd "$(dirname "$0")"
CONFIGS_PATH="../configs"
HOSTDOMAIN=$(sed -n '/^\s*#/!{p;q}' $CONFIGS_PATH/ldap-domains)

OS_VERSION=$(cat /etc/os-release | grep VERSION_ID | cut -f2 -d=)

if [ "$(whoami)" != "root" ]; then
    echo "Для запуска необходимы права суперпользователя" 1>&2
    exit 1
fi

if [[ $1 =~ ^[0-9]+$ ]] ## проверяем, передан ли параметр (номер группы)
then
 NN=$1
 nodesList=$(lxc-ls -1 | grep grp$NN)
 echo "Эти контейнеры будут удалены:" 
 echo "$(lxc-ls -1 | grep grp$NN)"
 sleep 5
 for node in ${nodesList[@]};
   do
      ipHost=$(sudo lxc-info -n $node -iH | head -1)
      ssh-keygen -f "/root/.ssh/known_hosts" -R "$ipHost"
      if [[ "$(lxc-info -n $node -sH)" != "STOPPED" ]]; then
         echo "Узел $node будет остановлен"
         sshpass -p 'astralinux' ssh -o StrictHostKeyChecking=no -l admin "$ipHost" 'sudo poweroff'
      
         while [[ "$(lxc-info -n $node -sH)" != "STOPPED" ]]
         do
            printf "."
            sleep 1
         done
         echo""
      fi
      [[ "$node" =~ "sql" ]] &&  [[ "$OS_VERSION" =~ "1.8" ]] && chattr -a /var/lib/lxc/$node/rootfs/parsec/log/astra/events
      lxc-destroy $node
   done

 # Подчищаем DNS и hosts
 sed -i "/mail$NN/,$ d" /etc/dnsmasq.d/$HOSTDOMAIN
 sed -i "/grp$NN/,$ d" /etc/hosts
fi
