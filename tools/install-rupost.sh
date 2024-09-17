#!/usr/bin/env sh
#set -e

if [ "$(whoami)" != "root" ]; then
    echo "Для запуска необходимы права суперпользователя" 1>&2
    exit 1
fi


PARSED_ARGS=$(getopt --quiet --shell sh --options d:n:g:s --longoptions distr:,nnode:,grp:,sqlip:,help:: -- "$@")
eval set -- "$PARSED_ARGS"

while true; do
    case "$1" in
        -n|--nnode)
            NNODE=$2; shift 2 ;;
        -g|--grp)
            grpNum=$2; shift 2 ;;
        -d|--distr)
            DISTR=$2; shift 2 ;;
        -s|--sqlip)
            SQLIP=$2; shift 2 ;;
        --help)
            HELP="true"; shift 2 ;;
        --)
            shift; break ;;
        *) echo "Не удалось распознать аргументы командной строки: $1 $2" 1>&2; exit 1 ;;
    esac
done

if [ -n "$HELP" ]; then
    cat <<EOF
usage: $0 -n|--nnode NodeNum -d|--distr FileName.deb/run [-s|--sqlip ipAddr] [--help]

    -n|--NODE NodeNum        Номер контейнера на который устаналиваеться дистрибутив.
    -g|--grpNum              Номер группы контейнеров
    -d|--distr fileName      Путь и имя на файл дистрибутива
    -s|--sqlip               IP адрес SQL сервера, не обязателен

EOF
    exit 0
fi

    if [ -z "$NNODE" ]; then
        echo "Не передан флаг -n|--nnode" 1>&1
        exit 1
    fi
    if [ -z "$grpNum" ]; then
        echo "Не передан флаг -g|--grpNum" 1>&1
        exit 1
    fi
    if [ -z "$DISTR" ]; then
        echo "Не передан флаг -d|--distr" 1>&1
        exit 1
    fi

    if [ -z "$SQLIP" ]; then
        echo ""
        echo "Не указан IP адрес SQL сервера, поиск локальной ноды" 1>&1

        until [ $(sudo lxc-info -n grp$grpNum-sql -iH | head -1) ]
        do
        echo "wait start sql-node"
        sleep 1
        done
        SQLIP=$(sudo lxc-info -n grp$grpNum-sql -iH | head -1)
        echo "Локальная нода найдена - адрес: "$SQLIP
    fi

echo ""

extension="${DISTR##*.}"

if [ "$extension" == "run" ]; then
    isRun=1
fi

lxc-start grp$grpNum-rupost"$NNODE"

until [ "$(sudo lxc-info -n grp$grpNum-rupost"$NNODE" -iH | head -1)" ]
do
 echo "wait start grp$grpNum-rupost$NNODE"
 sleep 1
done

lxc-ls -f | grep grp

ipNode=$(sudo lxc-info -n grp$grpNum-rupost"$NNODE" -iH | head -1)
ssh-keygen -f '/root/.ssh/known_hosts' -R '$ipNode'
sshpass -p 'astralinux' ssh -o StrictHostKeyChecking=no -l admin $ipNode 'hostname'
sshpass -p 'astralinux' scp $DISTR admin@$ipNode:/home/admin/

distrName=$(basename $DISTR)

set -e

cat << EOF | tee /tmp/run_inst.sh >/dev/null

# Запускаем процесс
sudo bash /home/admin/$distrName --  --skip-cluster-check -s  --db-host '$SQLIP' --db-port 5432 --db-user rupost --db-password rupost --db-name rupost --data-db-name rupost_data --logs-db-name rupost_logs &

# Получаем PID запущенного процесса
pid=\$!

# Определяем символы для отображения вращения
spin='-\|/'

#грязный хак пока распоковывыем пакет
sleep 5

# Получаем текущее время в секундах с начала эпохи
start_time=\$(date +%s)

# Выполняем цикл пока программа работает
i=0
while kill -0 \$pid 2>/dev/null
do
  # Отображаем текущий символ
  i=\$(( (i+1) %4 ))

  # Вычисляем прошедшее время в секундах
  end_time=\$(date +%s)
  elapsed_time=\$(( end_time - start_time ))

  # Отображаем текущий символ вместе с прошедшим временем
  printf "\r\${spin:\$i:1} Elapsed time: \${elapsed_time} seconds."

  # Приостанавливаем вращение на короткое время
  sleep .1
done
# Очищаем вывод после завершения вращения
printf "\r"

EOF

set +e

if [ -z "$isRun" ]; then
    sshpass -p 'astralinux' ssh -l admin $ipNode 'sudo apt install /home/admin/'"$distrName"''
    sshpass -p 'astralinux' ssh -l admin $ipNode 'sudo rupost-wizard --silent --db-host '"$SQLIP"' --db-port 5432 --db-user rupost --db-password rupost --db-name rupost --data-db-name rupost_data --logs-db-name rupost_logs'
else
    sshpass -p 'astralinux' scp /tmp/run_inst.sh admin@$ipNode:/home/admin/run_inst.sh
    sshpass -p 'astralinux' ssh -l admin $ipNode 'sudo bash /home/admin/run_inst.sh'
fi
