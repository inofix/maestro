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
    echo "usage: $0"
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

[ ! -f "/etc/$conffile" ] || . "/etc/$conffile"
[ ! -f "/usr/etc/$conffile" ] || . "/usr/etc/$conffile"
[ ! -f "/usr/local/etc/$conffile" ] || . "/usr/local/etc/$conffile"
[ ! -f ~/"$conffile" ] || . ~/"$conffile"
[ ! -f "$conffile" ] || . "$conffile"

#*  options:
while true ; do
    case "$1" in
#*      -c |--config conffile               alternative config file
        -c|--config)
            shift
            if [ -r "$1" ] ; then
                . $1
            else
                die " config file $1 does not exist."
            fi
        ;;
#*      -h |--help                          print this help
        -h|--help)
            print_help
            exit 0
        ;;
#*      -n |--dry-run                       do not change anything
        -n|--dry-run)
            dryrun=0
        ;;
#*      -v |--version
        -v|--version)
            print_version
            exit
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
            error "Priviledges missing: use ${_sudo}."
        fi
    fi
fi

for t in ${danger_tools[@]} ; do
    export ${t}="$_pre ${sys_tools[$t]}"
done

exit 0

