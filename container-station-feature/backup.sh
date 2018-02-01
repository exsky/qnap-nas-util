#!/bin/sh -e

mode=$1
package=$2

case $1 in
    backup)
        directory="./backup_tmp"
        if [ ! -d "$directory" ]; then
            echo "Generating tempory directory ..."
            mkdir "$directory"
        else
            echo "Cleaning tempory directory ..."
            rm -rf "$directory"/*
        fi

        file="./$directory/mapping"
        if [ -f "$file" ]; then
            echo "Removing the mapping file ..."
            rm "$file"
        fi

        i=1
        while [ -n "$3" ]; do
            # container="$3"
            var=`docker inspect --format='{{range .Mounts}} {{.Source}} {{.Destination}} ,{{end}}' "$3"`
            echo $var | while IFS=" " read -d ',' volume mounted; do
                echo "$3":"$3"_${i}.tbz:${mounted} >> $file
                tar -jc -f ./"$directory"/"$3"_${i}.tbz -C ${volume}/../ `basename ${volume}`
                ((i++))
            done
            shift 1
        done

        tar -jcv -f "$package" "$directory"
        rm -rf "$directory"
    ;;
    restore)
        directory="./backup_tmp"
        if [ -d "$directory" ]; then
            echo "Cleaning tempory directory ..."
            rm -rf "$directory"/*
        #else
            #echo "Generating tempory directory ..."
            #mkdir "$directory"
        fi

		if [ -e "$package" ]; then
            tar -jxv -f "$package"
        else
            echo "No such file: $package"
        fi

        map=`cat ./backup_tmp/mapping`
        echo "$map" | while IFS='' read -r line || [[ -n "$line" ]]; do
            var1=`echo "$line" | sed -E 's/(.*):(.*):(.*)/\1/'`
            var2=`echo "$line" | sed -E 's/(.*):(.*):(.*)/\2/'`
            var3=`echo "$line" | sed -E 's/(.*):(.*):(.*)/\3/'`
            retr=`docker inspect "$var1"`
            retv=`echo $?`
            if [ $retv -eq "0" ]; then
                echo "Starting mounting volume ... "
                var=`docker inspect --format='{{range .Mounts}} {{.Source}} {{.Destination}} ,{{end}}' "$var1"`
                echo $var | while IFS=" " read -d ',' volume mounted; do
                    if [ "$mounted" = "$var3" ]; then
                        echo "MOUNT: Stopping the container $var1"
                        docker stop $var1                       
                        echo "MOUNT: Mounting the volume $var2 to container $var1, $var3"
                        rm -rf `basename ${volume}`
                        echo "MOUNT: Replacing $dictionary/$var2 to ${volume}"
                        tar -jx -f ./"$directory"/"$var2" -C ${volume}/../ 
                        echo "MOUNT: Starting the container $var1"
                        # docker start $var1
                        res="$res $var1"
                    fi
                done
            elif [ -v $retv && $retv -eq "1" ]; then
                echo "No such container named as $var1"
            else
                echo "Command failed: docker inspect $var1"
                echo $retv
            fi
        done
        rm -rf "$directory"
    ;;
esac
exit 0
