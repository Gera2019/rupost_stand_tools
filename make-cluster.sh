#!/usr/bin/env bash
cd "$(dirname "$0")"

## Пути к дополнительным настройкам, пакетам и инструментам
CONFIGS_PATH="./configs"
TOOLS_PATH="./tools"
SRC_PATH="./src"

## Домен почтового сервера
HOSTDOMAIN=$(sed -n '/^\s*#/!{p;q}' $CONFIGS_PATH/ldap-domains)
HOSTNAME=mail.$HOSTDOMAIN


#####################################################################################

if [ "$(whoami)" != "root" ]; then
    echo "Для запуска необходимы права суперпользователя" 1>&2
    exit 1
fi

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            HELP="true"; shift ;;
        -n|--nodes)
            nodesNum=$2; shift ;;
        -i|--init)
            newClusterGroup="true"
            grpNum=$2; shift ;;
        *) echo "Неверные аргументы командной строки: $1"; exit 1 ;;
    esac
    shift
done

## Проверяем введенные параметры
if [ -n "$HELP" ]; then
    cat <<EOF
usage: $0 [-n|--nodes NUM][-i|--init][--h|--help]
    -n|--nodes NUM количество узлов; если параметр не указан, то NUM=2.
    -i|--init [NUM] инициируется развертывание новой группы
EOF
    exit 0
fi

if [ -z "$nodesNum" ]; then
    nodesNum=2
fi

checkPackage=$(apt list lxc | grep installed)
if [[ -z $checkPackage ]]; then
    sed -i 's/.*uu.*//g' /etc/apt/sources.list
    sed -i 's/\.*deb cdrom/\# deb cdrom/g' /etc/apt/sources.list
    sed -i 's/\#.*deb https/deb https/g' /etc/apt/sources.list
    ## Устанавливаем необходимые пакеты для развертывания среды LXC
    apt update
    apt install lxc lxc-astra libvirt-daemon-driver-lxc sshpass nfs-kernel-server memcached dnsutils -y
    systemctl restart libvirtd

    mkdir -p /etc/dnsmasq.d
    
    if [ -f /etc/dnsmasq.conf ]
    then
    sed -i -e '$aconf-dir=\/etc\/dnsmasq\.d' -e '/conf-dir=\/etc\/dnsmasq\.d/d' /etc/dnsmasq.conf
    else
      echo 'conf-dir=/etc/dnsmasq.d' | tee -a /etc/dnsmasq.conf
    fi

    ## Настраиваем конфигурацию lxc-net
    cat << EOF | sudo tee /etc/default/lxc-net
USE_LXC_BRIDGE="true"
LXC_BRIDGE="lxcbr0"
LXC_ADDR="10.20.30.1"
LXC_NETMASK="255.255.255.0"
LXC_NETWORK="10.20.30.0/24"
LXC_DHCP_RANGE="10.20.30.100,10.20.30.250"
LXC_DHCP_MAX="150"
LXC_DHCP_CONFILE="/etc/dnsmasq.conf"
LXC_DOMAIN=""
EOF
    
    systemctl restart lxc-net.service
fi

grp=$(lxc-ls -1 | grep ^grp | cut -d '-' -f 1 | tr -d [:alpha:] | sort -nr | head -1)
if [[ $newClusterGroup ]]; then
    if [ $grpNum ]; then
        grp=$grpNum
    else
        grp=1
        grpNum=$grp
    bash $TOOLS_PATH/rm-grp.sh $grp
    echo "Удаление завершено"
    fi
elif [ $(lxc-ls -1 | grep ^grp | cut -d '-' -f 1 | tr -d [:alpha:] | sort -nr | head -1) ]; then
    grpNum=$(($grp+1))
else
    grpNum=1
fi

echo "Имя почтового сервера: $HOSTNAME"
echo "Будет создана группа $grpNum"
echo "В группе будет создано $nodesNum экземпляра сервера РуПост"
sleep 3
    
echo "Настройка контейнеров с внутреней сетью 10.20.30.0/24" 1>&1
sleep 2

sed -i -e '$a10\.20\.30\.1\t'"$HOSTNAME" -e '/'"$HOSTNAME"'/d' /etc/hosts

#####################################################################################

## Если мы не находим родительского контейнера astra-se, то считаем, что установка "чистая" с нуля


if [ -z "$(lxc-ls -1 | grep 'astra-se')" ]
then
    echo "Создаём родительский контейнер astra-se"
    
    sed -i 's/.*uu.*//g' /etc/apt/sources.list
    sed -i 's/\.*deb cdrom/\# deb cdrom/g' /etc/apt/sources.list
    sed -i 's/\#.*deb https/deb https/g' /etc/apt/sources.list
    
## Устанавливаем необходимые пакеты для развертывания среды LXC
    apt update
    apt install lxc lxc-astra libvirt-daemon-driver-lxc sshpass nfs-kernel-server memcached dnsutils -y
    systemctl restart libvirtd

## Создаём родительский контейнер astra-se на основе шаблона astralinux-se  
    lxc-create -t astralinux-se -n astra-se
    
    if [[ $? != 0 ]]
    then
      echo ""
      echo "Контейнер не создан, устраните ошибку и перезапустите скрипт"
      sleep 0
      exit 1
    fi
	
## Сетевые настройки
## Выключаем сервис dnsmasq TODO проверка, что сервис есть вообще
    systemctl stop dnsmasq.service
    systemctl disable dnsmasq.service

## Проверяем нет ли сервиса bind

    if [ "$(fuser 53/udp)" ] || [ "$(fuser 53/tcp)" ]
        then
            echo "У Вас еще все запущен сервис на 53 порту (возможно bind)"
            echo "отключите сервис :"
            echo "53/udp " $(ps axuc | grep $(sudo fuser -n udp 53 2> /dev/null) | awk '{print $1}')
            echo "53/udp " $(ps axuc | grep $(sudo fuser -n tcp 53 2> /dev/null) | awk '{print $1}')
            echo "и перезапустите установку"
            exit 1
    fi

    systemctl stop lxc-net.service
	
	## Записи зон, определенных в файле ldap-domains
	sed 's/#.*$//;/^$/d' $CONFIGS_PATH/ldap-domains | while read d
	do
    cat <<EOF | tee /etc/dnsmasq.d/$d
address=/$d/10.20.30.1
ptr-record=1.30.20.10.in-addr.arpa.,$HOSTNAME
txt-record=$d,"v=spf1 a ~all"
mx-host=$d,$HOSTNAME,10
cname=autoconfig.$d,$HOSTNAME
cname=autodiscover.$d,$HOSTNAME
#srv-host=<_service>.<_prot>.[<domain>],[<target>[,<port>[,<priority>[,<weight>]]]]
srv-host=_carddavs._tcp.$d,$HOSTNAME,443,1,0
srv-host=_caldavs._tcp.$d,$HOSTNAME,443,1,0
EOF
    echo ""
	done
	echo 'nameserver 10.20.30.1' | tee /etc/resolv.conf
	
	# при переподключении интерфейса сново замкнем на себя
	cat <<EOF | tee /etc/network/if-up.d/resolv
#!/bin/sh
echo 'nameserver 10.20.30.1' > /etc/resolv.conf
exit 0
EOF

	chmod +x  /etc/network/if-up.d/resolv
	
	## Проброс dns-запросов

    cat $CONFIGS_PATH/dns-forwards | tee /etc/dnsmasq.d/forwards 

	systemctl start lxc-net.service
	
## Настроем сервер NFS и каталоги, необходимые для работы кластера RuPost
	mkdir -p /srv/nfs/MailStorage
	mkdir -p /srv/nfs/MailQueues
	mkdir -p /srv/nfs/MailArchive
	mkdir -p /srv/nfs/MailRecord
	mkdir -p /srv/nfs/IndexFiles
	chown 420:420 -R /srv/nfs

	if [ -z "$(grep '/srv/nfs/MailQueues' /etc/exports | cut -f1 -d: | head -1)" ]
	then
    cat << EOF | tee --append /etc/exports
/srv/nfs/MailQueues 10.20.30.0/24(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/MailStorage 10.20.30.0/24(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/MailArchive 10.20.30.0/24(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/MailRecord 10.20.30.0/24(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/IndexFiles 10.20.30.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF
	fi

	exportfs -ra
	
	## Создаем контейнеры-заготовки для БД Postgre и будущих RuPost-узлов
	echo 1 | sudo tee /parsecfs/unsecure_setxattr
	sudo execaps -c 0x1000 -- lxc-copy -n astra-se -N node-sql
	sudo execaps -c 0x1000 -- lxc-copy -n astra-se -N node-clean
	echo 0 | sudo tee /parsecfs/unsecure_setxattr
	
	nodesList=(node-sql node-clean)
	
	for node in ${nodesList[@]};
	do
		echo "Стартую $node"
		lxc-start $node
		until [ "$(sudo lxc-info -n $node -iH | head -1)" ]
		do
			printf "."
			sleep 1
		done
		echo""
	done
	
	ipSQL=$(sudo lxc-info -n node-sql -iH | head -1)
	ipHost=$(sudo lxc-info -n node-clean -iH | head -1)
	
	cat << EOF | sudo tee /tmp/sql.sh
sudo apt install postgresql syslog-ng -y
sudo su - postgres -c "psql -c \"alter user postgres with password 'rupost'\""
sudo su - postgres -c "psql -c \"CREATE ROLE rupost WITH NOSUPERUSER CREATEDB NOCREATEROLE LOGIN ENCRYPTED PASSWORD 'rupost';\""
sudo su - postgres -c "psql -c \"CREATE DATABASE rupost WITH ENCODING 'UTF8' OWNER rupost;\""
sudo su - postgres -c "psql -c \"CREATE DATABASE rupost_data WITH ENCODING 'UTF8' OWNER rupost;\""
sudo su - postgres -c "psql -c \"CREATE DATABASE rupost_logs WITH ENCODING 'UTF8' OWNER rupost;\""
EOF

	sshpass -p 'astralinux' ssh -o StrictHostKeyChecking=no -l admin "$ipSQL" 'bash -s' < /tmp/sql.sh
	rm /tmp/sql.sh
	
	sshpass -p 'astralinux' ssh -o StrictHostKeyChecking=no -l admin "$ipHost" 'sudo apt install python3 perl dialog syslog-ng -y'
	sshpass -p 'astralinux' ssh -o StrictHostKeyChecking=no -l admin "$ipHost" 'sudo ln -f -s /bin/bash /bin/sh'
	sshpass -p 'astralinux' ssh -o StrictHostKeyChecking=no -l admin "$ipHost" 'sudo ln -sf '"$(readlink /etc/localtime)"' /etc/localtime'
	sshpass -p 'astralinux' ssh -o StrictHostKeyChecking=no -l admin "$ipHost" 'echo '"$(cat /etc/timezone)"' | sudo tee /etc/timezone'
	
	lxc-stop node-sql
	lxc-stop node-clean
fi


## Создаем контейнеры для указанной группы с БД Postgre и экземплярами RuPost 
echo ""
echo "Создаем контейнер с БД Postgre и указанным количеством экземпляров RuPost"

nodesList=(grp$grpNum-sql)

echo 1 | sudo tee /parsecfs/unsecure_setxattr
sudo execaps -c 0x1000 -- lxc-copy -n node-sql -N grp$grpNum-sql
for ((i=1; i<=$nodesNum; i++))
do
	echo "Создаем grp$grpNum-rupost$i"
	sudo execaps -c 0x1000 -- lxc-copy -n node-clean -N grp$grpNum-rupost$i
	nodesList+=(grp$grpNum-rupost$i)
done
echo 0 | sudo tee /parsecfs/unsecure_setxattr

## Запускаем все экземпляры установки
echo ""
echo "Запускаем следующие контейнеры: ${nodesList[@]}"
echo ""
#hostDomain=$(echo $HOSTNAME | sed 's/mail\.//')
for node in ${nodesList[@]};
do
echo "стартую $node"
  lxc-start $node
  until [ "$(sudo lxc-info -n $node -iH | head -1)" ]
  do
    printf "."
    sleep 2
  done
  ipHost=$(sudo lxc-info -n $node -iH | head -1)
  x=$(echo $node | tr -d -c [:digit:])
  sed -i -e '$a'"$ipHost"'\t'"$node"'' -e '/'"$node"'/d' /etc/hosts

  if [ -z "$(grep 'lxc.start.auto' /var/lib/lxc/$node/config | cut -f1 -d: | head -1)" ]
  then
	## Установим параметры автозапуска для sql
	if [ "$node" = "grp$grpNum-sql" ]; then
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
lxc.signal.halt = SIGRTMIN+4
EOF
    sed -i -e '$aaddress=\/mail'"$x"'\.'"$HOSTDOMAIN"'\/'"$ipHost"'' -e '/mail"$x"/d' /etc/dnsmasq.d/$HOSTDOMAIN
	fi
  fi
done

## Пропишем в hosts доменные имена каждого экземпляра RuPost

for ((i=1; i<=$nodesNum; i++))
do
  ipHost=$(sudo lxc-info -n grp$grpNum-rupost$i -iH | head -1)
  sed -i -e '$aaddress=\/mail'"`echo $node | tr -d -c [:digit:]`"'\.'"$HOSTDOMAIN"'\/'"$ipHost"'' -e '/mail"$i"/d' /etc/dnsmasq.d/$HOSTDOMAIN
done

systemctl restart lxc-net

## Настраиваем memcached
sed -i -e '$a-l 0\.0\.0\.0' -e '/-l/d' /etc/memcached.conf
systemctl restart memcached


## Настраиваем haproxy если используем локальную сеть контейнеров

systemctl stop haproxy
rm /etc/haproxy/haproxy.cfg

apt install $SRC_PATH/libcrypt1_4.4.18-4_amd64.deb -y
apt install $SRC_PATH/haproxy_2.4.18-1~bpo11+1_amd64.deb -y

`which python3` ./$TOOLS_PATH/get_haproxy_conf.py $nodesNum $grpNum > /etc/haproxy/haproxy.cfg

systemctl enable haproxy
systemctl start haproxy


echo ""
echo "Контейнеры созданы и готовы к установке."
lxc-ls -f | grep grp
echo ""

#####################################################################################
## Установка сервера РуПост на подготовленные ноды кластера

while [[ ! "$beginSetupIsTrue" =~ "no" ]] && [[ ! "$beginSetupIsTrue" =~ "yes" ]] 
do
    echo "Установить сервер Рупост во все экземпляры? (наберите yes или no)"
    read beginSetupIsTrue
done

distNum=$(ls -1 $SRC_PATH | sed -n '/^rupost-[0-9]/ p' | wc -l)
declare -A rupostDistr

for ((i=1; i<=$distNum; i++))
    do
        rupostDistr[$i]=$(ls -1 src | sed -n '/^rupost-[0-9]/ p' | cut -d$'\n' -f $i)
    done

if [ $beginSetupIsTrue = "yes" ]; then
    
    while [ -z $distNum ] 
    do
        echo "Не было найдено ни одного установочного файла РуПост в папке $SRC_PATH"
        sleep 2
    
        while [[ ! "$answer" =~ "no" ]] && [[ ! "$answer" =~ "yes" ]] 
        do
            echo "Скопируйте в $SRC_PATH установочный файл РуПост и наберите yes для продолжения или no для завершения программы"
            read answer
        done
        if [ $answer = "no" ]; then 
            echo "Программа завершена"
            exit 0 
        fi
        distNum=$(ls -1 $SRC_PATH | sed -n '/^rupost-[0-9]/ p' | wc -l)
    done
fi

if [[ $distNum -gt 0 ]]; then
    echo "Были найдены следующие версии:"
    
    for version in "${!rupostDistr[@]}"
    do
        echo "$version) ${rupostDistr[$version]}"
    done
    
    echo "Наберите цифру, соответствующую нужной версии"
    read d
    rupostInstall=${rupostDistr[$d]}
fi

echo "Будет установлена версия РуПост - ${rupostDistr[$d]}"

for ((i=1; i<=$nodesNum; i++))
    do
        bash $TOOLS_PATH/install-rupost.sh -n $i -g $grpNum -d $SRC_PATH/${rupostDistr[$d]}
    done


echo "Используйте $TOOLS_PATH/install-rupost.sh -n НомерКонтейнера -g Номер группы -d имя deb пакета дистрибутива RuPost'а"
echo 'Для добавления нового узла используйте add_node.sh из директории $TOOLD_PATH'
sleep 4
echo "Готово"
