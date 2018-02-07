#!/bin/sh -e

function stop()
{
    while true; do
        read -rep $'\nStop backup script?(y/n)' yn
        case $yn in
            [Yy]* ) echo "Teminating the process ...";
                    ## SIGINT when backup/restore
                    map=`cat ./mapping`
                    str=""
                    while IFS='' read -r line || [[ -n "$line" ]]; do
                        var2=`echo "$line" | sed -E 's/(.*):(.*):(.*)/\2/'`
                        echo "Removing file ... $var2"
                        str="${var2} ${str}"
                    done <<<"$(echo "$map")"
                    echo "Removing temp files ... $str"
                    rm -rf $str
                    rm -rf ./mapping 
                    exit 1;;
            [Nn]* ) echo break;;
            * ) echo "Please answer (y/n)";;
        esac
    done
}

function restore_container_status()
{
    container="$1"
    echo "STATUS: $state"
    if [[ -z "$state" ]]; then
        echo "state is empty"
        echo "Default to DOWN STATE"
    else
        if [[ $state -eq "0" ]]; then
            echo "$container should return to DOWN STATE"
            ret=`docker stop $container`
            echo "$ret"
        elif [[ $state -eq "1" ]]; then
            echo "$container should return to UP STATE"
            ret=`docker start $container`
            echo "$ret"
        else
            echo "Oooooops~~"
        fi
    fi
}

function set_container_status()
{
    container="$1"
    stat=`docker ps -a --filter name=$1 --format {{.Status}}`
    if [[ "$stat" =~ "Up" ]]; then
        state=1
    elif [[ "$stat" =~ "Exited" ]]; then
        state=0
    else
        echo "Oops~ STATE: $stat , CONTAINER: $container .........."
    fi
}

trap 'stop' SIGINT

mode=$1
package=$2

case $1 in
    backup )
        file="./mapping"
        if [ -f "$file" ]; then
            echo "Removing the mapping file ..."
            rm "$file"
        fi

        i=1
        while [ -n "$3" ]; do
            set_container_status "$3"
            var=`docker inspect --format='{{range .Mounts}} {{.Source}} {{.Destination}} ,{{end}}' "$3"`
            echo $var | while IFS=" " read -d ',' volume mounted; do
                echo "Writing log into mapping file ..."
                echo "$3":"$3"_${i}.tbz:${mounted} >> $file
                echo "PACKING: Stopping container -- $3 ..."
                docker stop $3
                echo "Packing container ... $3 ... $volume ..."
                tar -jc -f ./"$3"_${i}.tbz -C ${volume}/../ `basename ${volume}`
                ((i++))
            done
            restore_container_status "$3"
            shift 1
        done

        map=`cat ./mapping`
        str=""
        while IFS='' read -r line || [[ -n "$line" ]]; do
            var2=`echo "$line" | sed -E 's/(.*):(.*):(.*)/\2/'`
            str="${var2} ${str}"
        done <<<"$(echo "$map")"
        echo "MERGING ..."
        tar -jcv -f "$package" -C ./ mapping $str

        # Clean
        while IFS='' read -r line || [[ -n "$line" ]]; do
            var2=`echo "$line" | sed -E 's/(.*):(.*):(.*)/\2/'`
            echo "Removing file ... $var2"
            rm $var2
        done <<<"$(echo "$map")"
        echo "Removing file ... mapping"
        rm $file
    ;;

    restore )
        if [ -e "$package" ]; then
            tar -jxv -f "$package"
        else
            echo "No such file: $package"
        fi

        map=`cat ./mapping`
        echo "$map" | while IFS='' read -r line || [[ -n "$line" ]]; do
            var1=`echo "$line" | sed -E 's/(.*):(.*):(.*)/\1/'`
            var2=`echo "$line" | sed -E 's/(.*):(.*):(.*)/\2/'`
            var3=`echo "$line" | sed -E 's/(.*):(.*):(.*)/\3/'`
            retr=`docker inspect "$var1"`
            retv=`echo $?`
            if [ $retv -eq "0" ]; then
                set_container_status "$var1"
                echo "Starting mounting volume ... "
                var=`docker inspect --format='{{range .Mounts}} {{.Source}} {{.Destination}} ,{{end}}' "$var1"`
                echo $var | while IFS=" " read -d ',' volume mounted; do
                    if [ "$mounted" = "$var3" ]; then
                        echo "RESTORE: Stopping the container $var1"
                        docker stop $var1                       
                        echo "MOUNT: Mounting the volume $var2 to container $var1, $var3"
                        rm -rf `basename ${volume}`
                        echo "RESTORE: Replacing $dictionary/$var2 to ${volume}"
                        tar -jx -f ./"$var2" -C ${volume}/../ 
                        echo "RESTORE: Removing $var2 ..."
                        rm -rf ./"$var2"
                    fi
                done
                restore_container_status "$var1"
            elif [ -v $retv && $retv -eq "1" ]; then
                echo "No such container named as $var1"
            else
                echo "Command failed: docker inspect $var1"
                echo $retv
            fi
        done
        echo "Removing file ... mapping"
        rm -rf ./mapping
    ;;

    --h | -help | help )
        echo "Usage: "
        echo "    ./backup.sh backup <target_packed_name> <container_name>"
        echo "    ./backup.sh restore <package_name>"
    ;;

    * ) break ;;
esac
exit 0
