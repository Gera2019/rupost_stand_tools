#!/usr/bin/env sh
cd "$(dirname "$0")"

TOOLS_PATH="./tools"
CONFIGS_PATH="./configs"

## Домен почтового сервера
HOSTDOMAIN=$(sed -n '/^\s*#/!{p;q}' ../$CONFIGS_PATH/ldap-domains)

#####################################################################################

if [ "$(whoami)" != "root" ]; then
    echo "Для запуска необходимы права суперпользователя" 1>&2
    exit 1
fi

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            HELP="true"; shift ;;
        -g|--group)
            NN=$2; shift ;;
        -d|--deactivate)
        	deactivateFlag="true"; shift ;;
        *) echo "Неверные аргументы командной строки: $1"; exit 1 ;;
    esac
    shift
done

## Проверяем введенные параметры
if [ -n "$HELP" ]; then
    cat <<EOF
usage: $0 [--h|--help][-g|--group NUM][-d|--deactivate]
	-h|--help	показывает эту справку
    -g|--group NUM номер группы, которую необходимо активировать
    -d|--deactivate ключ, указывающий что группу необходимо деактивировать
EOF
    exit 0
fi

if [ -z "$NN" ]; then
    echo "Не указан номер группу, запустите команду снова с указанным номером группы"
fi

## Активируем группу
##############################

nodesList=$(lxc-ls -1 | grep grp$NN)
nodesCount=$(lxc-ls -1 | grep grp$NN | wc -l)

if [ $deactivateFlag ]; then
	echo "Остановка контейнеров может занять достаточно длительное время"
	sed -i "/grp$NN/,$ d" /etc/hosts
	for node in ${nodesList[*]};
		do
			lxc-stop $node
		done
else
	for node in ${nodesList[*]};
	do
		status=$(lxc-info -s $node | cut -d " " -f 11)
		if [[ "$status" =~ "STOPPED" ]]; then
			echo "стартую $node"
			lxc-start $node
			
			until [ "$(sudo lxc-info -n $node -iH | head -1)" ]
			do
				printf "."
				sleep 2
			done
			echo ""
			ipHost=$(sudo lxc-info -n $node -iH | head -1)
			x=$(echo $node | tr -d -c [:digit:])
		fi
		sed -i -e '$a'"$ipHost"'\t'"$node"'' -e '/'"$node"'/d' /etc/hosts
	done
	sed -i -e '$aaddress=\/mail'"$x"'\.'"$HOSTDOMAIN"'\/'"$ipHost"'' -e '/mail"$x"/d' /etc/dnsmasq.d/$HOSTDOMAIN
	`which python3` ./get_haproxy_conf.py $(($nodesCount-1)) $NN > /etc/haproxy/haproxy.cfg
	systemctl restart haproxy
fi
