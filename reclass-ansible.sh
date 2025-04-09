#!/bin/bash
#*  This is a wrapper connecting Ansible and reclass as
#* changes in Ansible caused the upstream solution by
#* reclass to break.
#*  The script is used as an inventory file from ansible
#* and will be placed at, resp. linked to, `.invenory/hosts`.
#*  It can be tested as follows, either directly or via
#* Ansible:
#* `./.inventory/hosts --list`
#* `./.inventory/hosts --host <hostname>`
#* `ansible-inventory --list`
#* `ansible-inventory --host <hostname>`
#* ...

base=""
action=""

while true ; do
    case $1 in
        -b|--inventory-base-uri)
            shift
            base="-b $1"
        ;;
        --inventory-base-uri=*)
            base=${1/=/ }
        ;;
        --list)
            action="-i"
        ;;
        --host=*)
            action="-n ${1#*=}"
        ;;
        -t|--host)
            shift
            action="-n $1"
        ;;
        "")
            break
        ;;
    esac
    shift
done

if [ -z "$base" ] ; then
    if [ -d "$PWD/.inventory" ] ; then
        base="-b $PWD/.inventory"
    else
        echo "Error: No inventory dir was specified."
        exit 1
    fi
fi

if [[ "$action" == "-n "* ]]; then
    reclass $action $base -o json | jq -r '.parameters | del(._reclass_, .__reclass__)'
elif [ "$action" == "-i" ] ; then
    reclass $action $base -o json | jq -r '.classes'
fi

