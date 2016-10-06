#!/bin/bash -e
########################################################################
#** Version: 0.2
#* This script connects meta data about host projects with concrete
#* configuration files and even configuration management solutions.
#*
#* This way all the meta data can be stored at a single place and
#* in a uniform way but still be used for the actual work with the
#* hosts in question.
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

# get these repos
declare -A toclone

# important directories
declare -A inventorydirs
declare -A playbookdirs
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
maestrodir="$PWD"

# usually the local dir
workdir="./workdir"

# the reclass sources will constitute the knowledge base for the meta data
inventorydirs=(
    ["main"]="./inventory"
)

# the merge of the above inventories will be stored here
inventorydir="$maestrodir/.inventory"

# ansible/debops instructions
playbookdirs=(
    ["common_playbooks"]=""
)

# further directories/repos that can be used
localdirs=(
    ["any_confix"]=""
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
            ["_git"]="/usr/bin/git"
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
        -b|--ansible-become-root)
            ansible_root="--become-user root -K"
        ;;
#*  --ansible-become-su-root|-B     Ansible: Use --become-method su \
#*                                              --become-user root -K
        -B|--ansible-become-su)
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

reclass_parser='BEGIN {
                hostname="'$hostname'"
                domainname="'$domainname'"
                fqdn="'$n'"
                split(p_keys, project_keys, ";")
                split(p_vals, project_vals, ";")
                for (i=1;i<=p_len;i++) {
                    projects[project_keys[i]]=project_vals[i]
                }
                metamode="reclass"
                mode="none"
                rckey=""
                list=""
            }
            #sanitize input a little
            /<|>|\$|\|`/ {
                next
            }
            /{{ .* }}/ {
                gsub("{{ hostname }}", hostname)
                gsub("{{ domainname }}", domainname)
                gsub("{{ fqdn }}", fqdn)
                for (var in projects) {
                    gsub("{{ "var" }}", projects[var])
                }
            }
            !/^ *- / {
#print "we_are_here="metamode"-"mode
                tmp=$0
                # compare the number of leading spaces divided by 2 to
                # the number of colons in metamode to decide if we are
                # still in the same context
                sub("\\S.*", "", tmp)
                numspaces=length(tmp)
                tmp=metamode
                numcolons=gsub(":", "", tmp)
                doprint="f"
                if (( numcolons == 0 ) && ( numspaces == 2 )) {
                    doprint=""
                } else {
                    while ( numcolons >= numspaces/2 ) {
                        sub(":\\w*$", "", metamode)
                        numcolons--
                        doprint=""
                    }
                }
                if (( doprint == "" ) && ( mode != "none" ) && ( list != "" )) {
                    print mode"=( "list" )"
                    mode="none"
                    list=""
                    doprint="f"
                }
            }
            /^  node:/ {
                if ( metamode == "reclass" ) {
                  sub("/.*", "", $2)
                  print "project="$2
                  next
                }
            }
            /^applications:$/ {
                metamode="none"
                mode="applications"
                next
            }
            /^classes:$/ {
                metamode="none"
                mode="classes"
                next
            }
            /^environment:/ {
                metamode="none"
                mode="none"
                print "environement="$2
                next
            }
            /^parameters:/ {
                metamode="parameters"
                mode="none"
            }
            /^  os:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_name="$2
                }
                next
            }
            /^  os__distro:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_distro="$2
                }
                next
            }
            /^  os__codename:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_codename="$2
                }
                next
            }
            /^  os__release:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_release="$2
                }
                next
            }
            /^  os__package-selections:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_package_selections="$2
                }
                next
            }
            /^  host__infrastructure:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  l=length($1)
                  print "hostinfrastructure=\""substr($0, l+4)"\""
                }
                next
            }
            /^  location:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  l=length($1)
                  print "hostlocation=\""substr($0, l+4)"\""
                }
                next
            }
            /^  host__type:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  l=length($1)
                  print "hosttype=\""substr($0, l+4)"\""
                }
                next
            }
            /^  role:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "role="$2
                }
                next
            }
            /^  debian-.*-packages:$/ {
                if ( metamode == "parameters" ) {
                  gsub("-", "_")
                  mode=substr($1, 0, length($1)-1)
                }
                next
            }
            /^  storage_dirs:$/ {
                if ( metamode == "parameters" ) {
                  mode="storagedirs"
                }
                next
            }
            /^  debops:$/ {
#print "debops_="metamode
                if ( metamode == "parameters" ) {
                    metamode=metamode":debops"
                    mode="debops"
                }
                next
            }
            /^  ansible:$/ {
                if ( metamode == "parameters" ) {
                    metamode=metamode":ansible"
                    mode="ansible"
                }
            }
            /^  re-merge:$/ {
                if ( metamode == "parameters" ) {
                    metamode=metamode":remerge"
                }
            }
            /^    direct:$/ {
                if ( metamode == "parameters:remerge" ) {
                  mode="remergedirect"
                }
                next
            }
            /^    custom:$/ {
                if ( metamode == "parameters:remerge" ) {
                    metamode=metamode":custom"
                    mode="remergecustom"
                }
                next
            }
            /^      .*:$/ {
                if ( mode == "remergecustom" ) {
                    rckey=$1
                    sub(":", "", rckey)
                    next
                }
            }
            /^        file: .*$/ {
                if (( mode == "remergecustom" ) && ( rckey != "" )) {
                    gsub("\047", "");
                    print "remergecustomsrc[\""rckey"\"]=\""$2"\""
                }
                next
            }
            /^        dest: .*$/ {
                if (( mode == "remergecustom" ) && ( rckey != "" )) {
                    gsub("\047", "");
                    print "remergecustomdest[\""rckey"\"]=\""$2"\""
                }
                next
            }
            /^      .*$/ {
                if ( metamode == "parameters:debops" ) {
#print "debops___="metamode
                    gsub("'"'"'", "")
                    list=list "\n'"'"'" $0 "'"'"'"
                    next
                }
            }
            /^    .*$/ {
                if ( metamode == "parameters:debops" ) {
#print "debops__="metamode
                    next
                } else if ( metamode == "parameters:ansible" ) {
                    gsub("\"", "\x22")
                    gsub(":", "\x3A")
                    # pure trial and error as I just dont get it..
                    gsub("%", "%%")
                    a=$1
                    sub(":", "", a)
                    b=$0
                    sub(" *"$1" ", "", b)
                    print "ansible_meta[\""a"\"]='"'"'" b "'"'"'"
                    next
                }
            }
            /^ *- / {
                if (( mode != "none") && ( mode != "debops" )) {
                    gsub("'"'"'", "")
                    sub("- ", "")
                    list=list "\n'"'"'" $0 "'"'"'"
                }
                next
            }
            {
                mode="none"
            }
            END {
            }'

# Not all projects use the same access policy - try to give some hints
ansible_connection_test()
{
    if [ "${ansible_meta['prompt_password']}" == "true" ] ; then
        printf "\e[1;33mWarning: "
        printf "\e[1;39m$n\e[0m has ansible:prompt_password set to 'true'.\n"
        printf "         You probably want to use the '-k' flag.\n"
    fi
    if [ -n "${ansible_meta['ssh_common_args']}" ] ; then
        printf "\e[1;33mWarning: "
        printf "\e[1;39m$n\e[0m has ansible:ssh_common_args set to '${ansible_meta['ssh_common_args']}'.\n"
        printf "         Please check your ssh configs for that host if you encounter problems.\n"
    fi
    for l in connect_timeout use_scp ; do
        if [ -n "${ansible_meta[$l]}" ] ; then
            printf "\e[1;33mWarning: "
            printf "\e[1;39m$n\e[0m has ansible:$l set to '${ansible_meta[$l]}'.\n"
            printf "         Please control your (.)ansible.cfg if you encounter problems.\n"
        fi
    done
}

# Try to connect to a host an compare some metadata to facts
connect_node()
{
    list_node $n
    retval=0
    remote_os=( $( $_ssh $1 $_lsb_release -d 2>/dev/null) ) || retval=$?
    remote_os_distro=${remote_os[1]}
    remote_os_name=${remote_os[2]}
    remote_os_release=${remote_os[3]}
    remote_os_codename=${remote_os[4]}
    answer0="${remote_os[1]} ${remote_os[2]} ${remote_os[3]} ${remote_os[4]}"
    if [ $retval -gt 127 ] ; then
        printf " \e[1;31m${answer0}\n"
    elif [ $retval -gt 0 ] ; then
        printf " \e[1;33m${answer0}\n"
    else
        distro_color="\e[0;32m"
        os_color="\e[0;32m"
        release_color="\e[0;32m"
        codename_color="\e[0;32m"
        if [ -n "$os_distro" ] ; then
            comp0=$( echo $remote_os_distro | $_sed 's;.*;\L&;' )
            comp1=$( echo $os_distro | $_sed 's;.*;\L&;' )
            if [ "$comp0" == "$comp1" ] ; then
                distro_color="\e[1;32m"
            else
                distro_color="\e[1;31m"
            fi
        fi
        if [ -n "$os_release" ] ; then
            comp0=$( echo $remote_os_release | $_sed 's;.*;\L&;' )
            comp1=$( echo $os_release | $_sed 's;.*;\L&;' )
            if [ "$comp0" == "$comp1" ] ; then
                release_color="\e[1;32m"
            else
                release_color="\e[1;31m"
            fi
        fi
        if [ -n "$os_codename" ] ; then
            comp0=$( echo $remote_os_codename | $_sed 's;.*;\L&;' )
            comp1=$( echo $os_codename | $_sed 's;.*;\L&;' )
            if [ "$comp0" == "($comp1)" ] ; then
                codename_color="\e[1;32m"
            else
                codename_color="\e[1;31m"
            fi
        fi
        printf "  $distro_color$remote_os_distro\e[0;39m"
        printf " $os_color$remote_os_name\e[0;39m"
        printf " $release_color$remote_os_release\e[0;39m"
        printf " $codename_color$remote_os_codename\n\e[0;39m"
        answer1=$( $_ssh $1 $_ip $ipprot address show eth0 | $_grep inet)
        printf "\e[0;32m$answer1\n\e[0;39m"
    fi
}

#
do_sync()
{
    if [ -d "$1" ] ; then
        $_mkdir -p $2
        $_rsync $rsync_options $1 $2
    fi
}

## define these in parse_node()
re_define_parsed_variables()
{
#*** Associative Array:     ansible_meta
    declare -g -A ansible_meta
    ansible_meta=()
#*** Array:                 applications
    applications=()
#*** Array:                 classes
    classes=()
#*** String:                environemnt
    environement=""
#*** Array:                 parameters.debops
    debops=()
#*** String:                parameters.host__infrastructure
    hostinfrastructure=""
#*** String:                parameters.host__locations
    hostlocation=""
#*** String:                parameters.host__type
    hosttype=""
#*** String:                parameters.os__codename
    os_codename=""
#*** String:                parameters.os__distro
    os_distro=""
#*** String:                parameters.os__name
    os_name=""
#*** String:                parameters.os__package-selections
    os_package_selections=""
#*** String:                parameters.os__release
    os_release=""
#*** String                 parameters.project
    project=""
#*** Array:                 parameters.storage_dirs
    storagedirs=()
#*** Array:                 parameters.re-merge.direct
    remergedirect=()
#*** Associative array:     parameters.re-merge.custom.src
    declare -g -A remergecustomsrc
    remergecustomsrc=()
#*** Associative array:     parameters.re-merge.custom.dest
    declare -g -A remergecustomdest
    remergecustomdest=()
}
re_define_parsed_variables

parse_node()
{
    # make sure they are empty
    re_define_parsed_variables

    awk_var_p_keys=";"
    awk_var_p_vals=";"
    for k in ${!localdirs[@]} ; do
        awk_var_p_keys="$k;$awk_var_p_keys"
        awk_var_p_vals="${localdirs[$k]};$awk_var_p_vals"
    done
    if [ $parser_dryrun -eq 0 ] ; then
        $_reclass -b $inventorydir -n $1 |\
            $_awk -v p_len=${#localdirs[@]} -v p_keys=$awk_var_p_keys \
                  -v p_vals=$awk_var_p_vals "$reclass_parser"
    else
        eval $(\
            $_reclass -b $inventorydir -n $1 |\
            $_awk -v p_len=${#localdirs[@]} -v p_keys=$awk_var_p_keys \
                  -v p_vals=$awk_var_p_vals "$reclass_parser"
        )
    fi
}

# First call to reclass to get an overview of the hosts available
get_nodes()
{
    [ -d "$inventorydir/nodes" ] || error "reclass environment not found at $inventorydir/nodes"
    reclass_filter=""
    if [ -n "$projectfilter" ] ; then
        if [ -d "$inventorydir/nodes/$projectfilter" ] ; then
            reclass_filter="-u nodes/$projectfilter"
        else
            die "This project does not exist in $inventorydir"
        fi
    fi
    nodes=( $($_reclass -b $inventorydir $reclass_filter -i |\
            $_awk 'BEGIN {node=1}; \
                   /^nodes:/ {node=0};\
                   /^  \w/ {if (node == 0) {print now $0}}' |\
            $_tr -d ":" | $_sort -r ) )
}

# List all applications for all hosts
list_applications()
{
    list_node $n
    for a in ${applications[@]} ; do
        printf "\e[0;36m - $a\n"
    done
    printf "\e[0;39m"
}

# List all classes for all hosts
list_classes()
{
    list_node $n
    for c in ${classes[@]} ; do
        printf "\e[0;35m - $c\n"
    done
    printf "\e[0;39m"
}

#
list_debops()
{
    list_node $n
    for (( i=0 ; i < ${#debops[@]} ; i++ )) ; do
        echo "${debops[i]}"
    done
}

# List packages installed
list_distro_packages()
{
    list_node $n
    ps=()
    psi=0
    l=$(eval 'echo ${#'${os_distro}'__packages[@]}')
    for (( i=0 ; i<l ; i++ )) ; do
        ps[$psi]=$(eval 'echo ${'${os_distro}'__packages['$i']}')
        let ++psi
    done
    l=$(eval 'echo ${'${os_distro}'_'${os_codename}'_packages[@]}')
    for (( i=0 ; i<l ; i++ )) ; do
        ps[$psi]=$(eval 'echo ${'${os_distro}'_'${os_codename}'_packages['$i']}')
        let ++psi
    done

    OLDIFS=$IFS
    IFS="
"
    ps=( $(
        for (( i=0 ; i<${#ps[@]} ; i++ )); do
            echo "${ps[$i]}"
        done | $_sort -u
    ) )
    IFS=$OLDIFS

    for (( i=0 ; i<${#ps[@]} ; i++ )); do
        printf "\e[0;33m - ${ps[$i]}\n"
    done
}

# Print out info about a host
list_node()
{
    output="\e[1;39m$n \e[1;36m($environement:$project)"
    if [ "$role" == "development" ] ; then
         output="$output \e[1;32m$role"
    elif [ "$role" == "fallback" ] ; then
         output="$output \e[1;33m$role"
    elif [ "$role" == "productive" ] ; then
         output="$output \e[1;31m$role"
    else
         output="$output \e[1;39m$role"
    fi
    if [ -n "$os_distro" ] && [ -n "$os_codename" ] &&
            [ -n "$os_release" ] ; then
        os_output="\e[1;34m($os_distro-$os_codename $os_release)"
    elif [ -n "$os_distro" ] && [ -n "$os_codename" ] ; then
        os_output="\e[1;34m($os_distro-$os_codename)"
    elif [ -n "$os_distro" ] && [ -n "$os_release" ] ; then
        os_output="\e[1;34m($os_distro $os_release)"
    fi
    output="$output $os_output"
    printf "$output\e[0;39m\n"
}

# Print out info about a host - the short form
list_node_short()
{
    printf "$n\n"
}

# List all the storage (config) directories) per host
list_node_stores()
{
    list_node $n
    list_node_arrays ${storagedirs[@]}
}

# List the merge mappings
list_node_re_merge_exceptions()
{
    list_node $n
    list_node_arrays ${remergedirect[@]}
}

# List the merge mappings
list_node_re_merge_custom()
{
    list_node $n
    list_re_merge_custom
}

# List meta info about the hosts type and location
list_node_type()
{
    list_node $n
    printf "\e[0;33m This host is a \e[1;33m${hosttype}\e[0;33m.\n"
    [ -n "$hostinfrastructure" ] &&
        printf " It is running on \e[1;33m${hostinfrastructure}\e[0;33m.\n" ||
        true
    [ -n "$hostlocation" ] &&
        printf " The ${hosttype} is located at "
        printf "\e[1;33m$hostlocation\e[0;33m.\n" ||
        true
}

# List the merge mappings
list_re_merge_custom()
{
    for m in ${!remergecustomsrc[@]} ; do
        printf "\e[1;33m - $m\n"
        printf "\e[0;33m   file: \e[0;35m${remergecustomsrc[$m]}\n"
        printf "\e[0;33m   dest: \e[0;36m${remergecustomdest[$m]}\n"
    done
    printf "\e[0;39m"
}

# List directories
list_node_arrays()
{
    for d in $@ ; do
        if [ -d "$d" ] ; then
            printf "\e[0;32m - $d\n"
        else
            printf "\e[0;33m ! $d \n"
        fi
    done
}

# do nothing..
noop()
{
    echo -n ""
}

# Gather application info for a host
declare -A applications_dict
process_applications()
{
    for a in ${applications[@]} ; do
        applications_dict[$a]=$n:${applications_dict[$a]}
    done
}

# Gather class info for a node
declare -A classes_dict
process_classes()
{
    for c in ${classes[@]} ; do
        classes_dict[$c]=$n:${classes_dict[$c]}
    done
}

# Collect all the info about a host
process_nodes()
{
    command=$1
    shift
    for n in $@ ; do
        if [ -n "$nodefilter" ] && [ "$nodefilter" != "$n" ] &&
                [ "$nodefilter" != "${n%%.*}" ]  ; then
            continue
        fi
        hostname="${n%%.*}"
        domainname="${n#*.}"
        parse_node $n
        $command $n
    done
}

# gets filled in get_nodes
nodes=()

#* actions:
case $1 in
#
#


#*  init [directory]                create an environemnt with all the
#*                                  repos defined in the config, in order
#*                                  to get a running knowledge base.
    init|reinit)
        shift
        [ -f "$conffile" ] || error "Please provide a config file."
        for g in ${!toclone[@]} ; do
            git_dest=""
            if [ -n "${inventorydirs[$g]}" ] ; then
                git_dest="${inventorydirs[$g]}"
            elif [ -n "${playbookdirs[$g]}" ] ; then
                git_dest="${playbookdirs[$g]}"
            elif [ -n "${localdirs[$g]}" ] ; then
                git_dest="${localdirs[$g]}"
            else
                error "there is no corresponding directory defined" \
                      "in your config for $g"
            fi
            if [ -d "$git_dest/.git" ] ; then
                echo "update repository $g"
                $_git -C "$git_dest" pull
            else
                $_mkdir -p $git_dest
                [ -n "${toclone[$g]}" ] || continue
                $_git clone "${toclone[$g]}" "$git_dest"
            fi
        done
        echo "Re-create the inventory. Note: there will be warnings for duplicates"
        echo "etc. "
        $_mkdir -p $inventorydir/{nodes,classes}
        $_rm -f $inventorydir/{nodes,classes}/*
        for d in ${inventorydirs[@]} ; do
            $_find "$d/nodes/" -mindepth 1 -maxdepth 1 -type d -exec $_ln -s \{} $inventorydir/nodes/ \;
            $_find "$d/nodes/" -mindepth 1 -maxdepth 1 -name "*.yml" -exec $_ln -s \{} $inventorydir/nodes/ \;
            $_find "$d/classes/" -mindepth 1 -maxdepth 1 -type d -exec $_ln -s \{} $inventorydir/classes/ \;
            $_find "$d/classes/" -mindepth 1 -maxdepth 1 -name "*.yml" -exec $_ln -s \{} $inventorydir/classes/ \;
        done
        echo "Re-connect ansible to our reclass inventory"
        [ ! -f "$inventorydir/hosts" ] || $_rm "$inventorydir/hosts"
        [ ! -f "$inventorydir/reclass-config.yml" ] || $_rm "$inventorydir/reclass-config.yml"
        $_ln -s $ansible_connect "$inventorydir/hosts"
        if [ -z "$_pre" ] ; then
            $_cat > "$inventorydir/reclass-config.yml" << EOF
storage_type: yaml_fs
inventory_base_uri: $inventorydir
EOF
        else
            echo "write config file $inventorydir/reclass-config.yml"
            echo "  storage_type: yaml_fs"
            echo "  inventory_base_uri: $inventorydir"
        fi
    ;;
#*  list (ls)                       list nodes
    ls|list*)
        get_nodes
        process_nodes list_node ${nodes[@]}
    ;;
##*  re-merge                        remerge as specified in '--merge mode'
#    rem|re-merge*)
#        process_nodes re-merge ${nodes[@]}
#    ;;
#*  reclass                         just wrap reclass
    rec*)
        if [ -n "$nodefilter" ] ; then
            nodefilter=$($_find -L $inventorydir/nodes/ -name "$nodefilter" -o -name "${nodefilter}\.*" | $_sed -e 's;.yml;;' -e 's;.*/;;')

            if [ -n "$nodefilter" ] ; then
                reclassmode="-n $nodefilter"
            else
                error "The node does not seem to exist: $nodefilter"
            fi
        else
            reclassmode="-i"
        fi
        if [ -n "$projectfilter" ] ; then
            nodes_uri="$inventorydir/nodes/$projectfilter"
            if [ ! -d "$nodes_uri" ] ; then
                error "No such project dir: $nodes_uri"
            fi
        elif [ -n "$classfilter" ] ; then
            error "Classes are not supported here, use project filter instead."
        fi
        if [ -z "$nodes_uri" ] ; then
            $_reclass -b $inventorydir $nodes_uri $reclassmode
        else
            $_reclass -b $inventorydir -u $nodes_uri $reclassmode
        fi
    ;;
#*  show-reclass-summary            show variables used in reclass that are
#*                                  interpreted here
    show-rec*)
        printf "The following variables can be used in reclass and will\n"
        printf "be interpreted (and potentially used) by this script.\n"
        printf "\n"
        printf "\e[1mNote:\e[0m Of course you can use other variables as well,\n"
        printf "this is just a list of what $0\n"
        printf "is directly aware of.\n"
        printf "\n"
        printf " \e[1mType                   Variable\e[0m\n"
        $_grep "^#\*\*\* " $0 | $_sed_forced 's;^#\*\*\*;;'
        printf "\n"
        printf "Furthermore these variables are needed in $conffile\n"
        printf " Where to search for reclass:         inventorydirs (merged to inventorydir)\n"
        printf " Where to put (temp.) results:        workdir\n"
        printf " Local directories to replace:        localdirs\n"
        printf " Ansible playbooks:                   playbookdirs\n"
        printf "\n"
        printf "Currently these contain the following values:\n"
        printf " 'inventorydir':    $inventorydir\n"
        printf " 'workdir':         $workdir\n"
        printf "\n"
        printf " The 'inventorydirs' (see above) gets internally merged to 'inventorydir'\n"
        printf " and is used as the input to reclass. Currently these sources\n"
        printf " are used in your config:\n"
        for d in ${!inventorydirs[@]} ; do
            printf "  $d: ${inventorydirs[$d]}\n"
        done
        printf "\n"
        printf " The 'playbookdirs' (see above) are used as a source for ansible playbooks.\n"
        printf " Currently these sources are used in your config:\n"
        for d in ${!playbookdirs[@]} ; do
            printf "  $d: ${playbookdirs[$d]}\n"
        done
        printf "\n"
        printf " The 'localdirs' (see above) can be used in reclass like any other\n"
        printf " external variable, i.e. '{{ name }}'. Currently these names\n"
        printf " are used in your config:\n"
        for d in ${!localdirs[@]} ; do
            printf "  $d: ${localdirs[$d]}\n"
        done
    ;;
#*  status (ss)                     test host by ssh and print distro and ip(s)
    ss|status)
        get_nodes
        process_nodes connect_node ${nodes[@]}
    ;;
    *)
        print_usage
    ;;
esac

