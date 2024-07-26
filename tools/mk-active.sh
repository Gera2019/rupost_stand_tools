#!/usr/bin/env sh

TOOLS_PATH="./tools"
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
	for node in ${nodesList[*]};
		do
			lxc-stop $node
		done
else
	for node in ${nodesList[*]};
		do
			status=$(lxc-info -s $node | cut -d " " -f 11)
			[[ "$status" =~ "STOPPED" ]] && lxc-start $node
		done
	`which python3` $TOOLS_PATH/get_haproxy_conf.py $nodesCount $NN > /etc/haproxy/haproxy.cfg
	systemctl restart haproxy
fi