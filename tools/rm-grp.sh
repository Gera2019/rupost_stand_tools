#!/usr/bin/env bash
## Скрипт ожидает числовой параметр, номер группы, которую необходимо удалить
## Скрипт удаляет группу, для этого контейнеры группы останавливаются и затем удаляются
## Подчищаются записи DNS-сервера и в файле hosts

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
 echo "Эти контейнеры будут удалены:" 
 echo "$(lxc-ls -1 | grep grp$NN)"
 sleep 5

 # Подчищаем DNS и hosts
 sed -i "/mail$NN/,$ d" /etc/dnsmasq.d/$HOSTDOMAIN
 sed -i "/grp$NN/,$ d" /etc/hosts
 for node in ${nodesList[*]};
 do
    lxc-stop $node
    lxc-destroy $node
 done
fi
