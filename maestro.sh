#!/bin/bash -e
########################################################################
#** Version: 0.1
#* This script connects meta data about host projects and concrete
#* configuration files and even configuration management solutions.
#*
#* This way all the meta data can be stored at a single place and
#* in a uniform way but still be used for the actual work with the
#* hosts in question.
#*
#* The meta data is stored with reclass[1], the actual work on the
#* hosts is done via ansible[2] playbooks, the core can be found
#* under common-playbooks[3], but is easily extensible. This connector
#* supports also simple merging of plain config files and other little
#* tricks..
#*
#* It is currently written in bash and gawk (see [4]), but will probably
#* be rewritten in python[5] soon.
#*
#* [1] http://reclass.pantsfullofunix.net/
#* [2] https://www.ansible.com/
#* [3] https://github.com/zwischenloesung/common-playbooks
#* [4] https://www.gnu.org/
#* [5] https://www.python.org/
#
# note: the frame for this script was auto-created with
# *https://github.com/inofix/admin-toolbox/blob/master/makebashscript.sh*
########################################################################
#
#  This is Free Software; feel free to redistribute and/or modify it
#  under the terms of the GNU General Public License as published by
#  the Free Software Foundation; version 3 of the License.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  Copyright 2016, Michael Lustenberger <mic@inofix.ch>
#
########################################################################
[ "$1" == "debug" ] && shift && set -x

## variables ##
# important directories
declare -A inventorydirs
declare -A playbookdirs
declare -A storagedirs
declare -A localdirs

### you may copy the following variables into this file for having your own
### local config ...
conffile=.maestro
### {{{

# for status mode concentrate on this ip protocol
ipprot="-4"

# whether to take action
dryrun=1
# whether we must run as root
needsroot=1

# rsync mode
rsync_options="-a -m --exclude=.keep"

merge_only_this_subdir=""
merge_mode="dir"

# maestro's git repo
maestrodir=""

# usually the local dir
workdir="./workdir"

# the reclass sources will constitute the knowledge base for the meta data
inventorydirs=(
    ["main"]="./inventory"
)

# ansible/debops instructions
playbookdirs=(
    ["common_playbooks"]=""
)

# the plain config files, either as a source or target (or both)
storagedirs=(
    ["any_confix"]=""
)

# further directories/repos that can be used
localdirs=(
    ["packer_templates"]=""
    ["vagrant_boxes"]=""
)

# this is the hosts link
ansible_connect=/usr/share/reclass/reclass-ansible

# options to pass to ansible (see also -A/--ansible-options)
ansibleoptions=""

### }}}

# Unsetting this helper variables (sane defaults)
_pre=""
classfilter=""
nodefilter=""
projectfilter=""

ansible_root=""
force=1
parser_dryrun=1
pass_ask_pass=""
ansible_verbose=""

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_awk"]="/usr/bin/gawk"
            ["_basename"]="/usr/bin/basename"
            ["_cat"]="/bin/cat"
            ["_cp"]="/bin/cp"
            ["_dirname"]="/usr/bin/dirname"
            ["_find"]="/usr/bin/find"
            ["_grep"]="/bin/grep"
            ["_id"]="/usr/bin/id"
            ["_ip"]="/bin/ip"
            ["_ln"]="/bin/ln"
            ["_lsb_release"]="/usr/bin/lsb_release"
            ["_mkdir"]="/bin/mkdir"
            ["_mv"]="/bin/mv"
            ["_pwd"]="/bin/pwd"
            ["_rm"]="/bin/rm"
            ["_rmdir"]="/bin/rmdir"
            ["_reclass"]="/usr/bin/reclass"
            ["_rsync"]="/usr/bin/rsync"
            ["_sed"]="/bin/sed"
            ["_sed_forced"]="/bin/sed"
            ["_sort"]="/usr/bin/sort"
            ["_ssh"]="/usr/bin/ssh"
            ["_tr"]="/usr/bin/tr"
            ["_wc"]="/usr/bin/wc" )
# this tools get disabled in dry-run and sudo-ed for needsroot
danger_tools=( "_cp" "_cat" "_dd" "_ln" "_mkdir" "_mv"
               "_rm" "_rmdir" "_rsync" "_sed" )
# special case sudo (not mandatory)
_sudo="/usr/bin/sudo"

declare -A opt_sys_tools
opt_sys_tools=( ["_ansible"]="/usr/bin/ansible"
                ["_ansible_playbook"]="/usr/bin/ansible-playbook" )
opt_danger_tools=( "_ansible" "_ansible_playbook" )

## functions ##

print_usage()
{
    echo "usage: $0 [options] action"
}

print_help()
{
    print_usage
    $_grep "^#\* " $0 | $_sed_forced 's;^#\*;;'
}

print_version()
{
    $_grep "^#\*\* " $0 | $_sed 's;^#\*\*;;'
}

die()
{
    echo "$@"
    exit 1
}

error()
{
    print_usage
    echo ""
    die "Error: $@"
}

## logic ##

## first set the system tools
for t in ${!sys_tools[@]} ; do
    if [ -x "${sys_tools[$t]##* }" ] ; then
        export ${t}="${sys_tools[$t]}"
    else
        error "Missing system tool: ${sys_tools[$t]##* } must be installed."
    fi
done

for t in ${!opt_sys_tools[@]} ; do
    if [ -x "${opt_sys_tools[$t]##* }" ] ; then
        export ${t}="${opt_sys_tools[$t]}"
    else
        echo "Warning! Missing system tool: ${opt_sys_tools[$t]##* }."
    fi
done

[ ! -f "/etc/$conffile" ] || . "/etc/$conffile"
[ ! -f "/usr/etc/$conffile" ] || . "/usr/etc/$conffile"
[ ! -f "/usr/local/etc/$conffile" ] || . "/usr/local/etc/$conffile"
[ ! -f ~/"$conffile" ] || . ~/"$conffile"
[ ! -f "$conffile" ] || . "$conffile"

#* options:
while true ; do
    case "$1" in
#*  --ansible-become-root|-b        Ansible: Use --become-user root -K
        --ansible-become-root)
            ansible_root="--become-user root -K"
        ;;
#*  --ansible-become-su-root|-B     Ansible: Use --become-method su \
#*                                              --become-user root -K
        --ansible-become-su)
            ansible_root="--become-method su --become-user root -K"
        ;;
#*  --ansible-ask-password|-k       ask for the connection pw (see ansible -k)
        -k|--ask-pass)
            pass_ask_pass="-k"
        ;;
#*  --ansible-extra-vars|-a 'vars'  variables to pass to ansible
        -a|--ansible-extra-vars)
            shift
            ansibleextravars="$1"
        ;;
#*  --ansible-options|-A 'options'  options to pass to ansible or
#*                                  ansible_playbook resp.
        -A|--ansible-options)
            shift
            ansibleoptions="$1"
        ;;
#*  --config|-c conffile            alternative config file
        -c|--config)
            shift
            if [ -r "$1" ] ; then
                . $1
            else
                die " config file $1 does not exist."
            fi
        ;;
#*  --class|-C class                only process member nodes of this class
#*                                  (see reclass classes)
        -C|--class)
            shift
            classfilter="$1"
        ;;
#*  --force|-f                      do not ask before changing anything
        -f|--force)
            force=0
        ;;
#*  --dry-run|-n                    do not change anything
        -n|--dry-run)
            dryrun=0
        ;;
#*  --dry-run-rsync                 do all but on rsync just pretend
        --dry-run-rsync|--rsync-dry-run)
            rsync_options="$rsync_options -n"
        ;;
#*  --dry-run-ansible               do all but on ansible just pretend
        --dry-run-ansible|--ansible-dry-run)
            ansibleoptions="$ansibleoptions -C"
        ;;
#*  --help|-h                       print this help
        -h|--help)
            print_help
            exit 0
        ;;
#*  --host|-H host                  only process a certain host
        -H|--host|-N|--node)
            shift
            nodefilter="$1"
        ;;
#*  --merge|-m mode                 specify how to merge, available modes:
#*                                    custom    based on "re-merge-custom"
#*                                    dir       nodename based dirs (default)
#*                                    in        nodename infixed files
#*                                    pre       nodename prefixed files
#*                                    post      nodename postfixed files
        -m|--merge)
            shift
            merge_mode=$1
        ;;
#*  --parser-test|-p                only output what would be fed to script
        -p|--parser-test)
            parser_dryrun=0
        ;;
#*  --project|-P project            only process nodes from this project,
#*                                  which practically is the node namespace
#*                                  from reclass (directory hierarchy)
        -P|--project)
            shift
            projectfilter="$1"
            classfilter="project.$1"
        ;;
#*  --subdir-only-merge|-s          concentrate on this subdir only
        -s|--subdir-only-merge)
            shift
            merge_only_this_subdir=$1
        ;;
#*  --verbose|-v                    print out what is done
        -v|--verbose)
            if [ -z "$ansible_verbose" ] ; then
                ansible_verbose="-v"
            else
                ansible_verbose="-vvv"
            fi
            rsync_options="$rsync_options -v"
        ;;
#*  --version|-V                    print version information and exit
        -V|--version)
            print_version
            exit
        ;;
#*  --workdir|-w directory          manually specify a temporary workdir
        -w|--workdir)
            shift
            workdir=$1
            $_mkdir -p $workdir
        ;;
        -*|--*)
            error "option $1 not supported"
        ;;
        *)
            break
        ;;
    esac
    shift
done

if [ $dryrun -eq 0 ] ; then
    _pre="echo "
fi

if [ $needsroot -eq 0 ] ; then

    iam=$($_id -u)
    if [ $iam -ne 0 ] ; then
        if [ -x "$_sudo" ] ; then

            _pre="$_pre $_sudo"
        else
            error "Missing system tool: $_sudo must be installed."
        fi
    fi
fi

for t in ${danger_tools[@]} ; do
    export ${t}="$_pre ${sys_tools[$t]}"
done

for t in ${opt_danger_tools[@]} ; do
    [ -z "${!t}" ] || export ${t}="$_pre ${opt_sys_tools[$t]}"
done

exit 0

init()
{
    cdir="$1"
    f="$2"
    [ -f "$cdir/hosts" ] && error "a file '$cdir/hosts' already exists, please remove manually first.."
    [ -f "$cdir/reclass-config.yml" ] && error "a file '$cdir/reclass-config.yml' already exists, please remove manually first.."
    [ -d "$cdir/reclass-env" ] && error "a directory '$cdir/reclass-env' already exists, please remove manually first.."
    $_ln -s $ansible_connect "$cdir/hosts"
    if [ -z "$_pre" ] ; then
        $_cat > "$cdir/reclass-config.yml" << EOF
storage_type: yaml_fs
inventory_base_uri: $cdir/reclass-env
EOF
    else
        echo "write config file $cdir/reclass-config.yml"
        echo "  storage_type: yaml_fs"
        echo "  inventory_base_uri: $cdir/reclass-env"
    fi
    $_mkdir -p "$cdir/reclass-env/nodes" "$cdir/reclass-env/classes"
    if [ -z "$f" ] ; then
        l="$_ln -s"
    else
        l="$_cp -r"
    fi
    $l $inventorydir/classes/* "$cdir/reclass-env/classes/"
    if [ -z "$projectfilter" ] ; then
        $l $inventorydir/nodes/* "$cdir/reclass-env/nodes/"
    else
        $l $inventorydir/nodes/$projectfilter "$cdir/reclass-env/nodes/"
    fi

}

