#!/bin/bash -e
########################################################################
#** Version: v1.3-57-g45a7492
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
conffile=maestro
### {{{

# some "sane" ansible default values
ansible_managed="Ansible managed. All local changes will be lost!"
ansible_timeout="60"
ansible_scp_if_ssh="True"
ansible_galaxy_roles=".ansible-galaxy-roles"

# whether to ask or not before applying changes..
force=1

# for status mode concentrate on this ip protocol
ipprot="-4"

# whether to take action
dryrun=1
# whether we must run as root
needsroot=1

# rsync mode - read the code here first (rsync is used both for single files
# and recursively!)
rsync_options="-a -m --exclude=.keep"

merge_only_this_subdir=""
merge_mode="dir"

# maestro's git repo - if not the current project dir (e.g. define in
# global ~/.maestro for access to one main repo)
maestrodir="$PWD"

# usually inside the local dir
workdir="./workdir"

# the reclass sources will constitute the knowledge base for the meta data
inventorydirs=(
    ["main"]="./inventory"
)

# ansible/debops instructions
playbookdirs=(
    ["common_playbooks"]=""
)

# file name of the galaxy role definition (relative to the playbookdirs)
galaxyroles="galaxy/roles.yml"

# further directories/repos that can be used
localdirs=(
    ["any_confix"]=""
    ["packer_templates"]=""
    ["vagrant_boxes"]=""
)

# this is the hosts link. If the file doesn't exists we try to get it from the PATH.
ansible_connect="/usr/share/reclass/reclass-ansible"

# options to pass to ansible (see also -A/--ansible-options)
ansibleoptions=""

# how much feedback to give
verbose="1"

# what files are to be ignored on 'unmerge'
unmerge_ignore=(
    "_packages.wiki"
)

# variable name of the host resources in the reclass knowledge base
knowledge_base_parameter_resources="host:resource"

### }}}

# Unsetting this helper variables (sane defaults)
_pre=""
classfilter=""
nodefilter=""
projectfilter=""

ansible_root=""
parser_dryrun=1
pass_ask_pass=""
ansible_verbose=""

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=(
            ["_ansible"]="/usr/bin/ansible"
            ["_ansible_playbook"]="/usr/bin/ansible-playbook"
            ["_ansible_galaxy"]="/usr/bin/ansible-galaxy"
            ["_awk"]="/usr/bin/gawk"
            ["_basename"]="/usr/bin/basename"
            ["_cat"]="/bin/cat"
            ["_diff"]="/usr/bin/diff"
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
            ["_wc"]="/usr/bin/wc"
            ["_xargs"]="/usr/bin/xargs"
)
# this tools get disabled in dry-run and sudo-ed for needsroot
danger_tools=(
            "_ansible"
            "_ansible_playbook"
            "_ansible_galaxy"
            "_cat"
            "_dd"
            "_ln"
            "_mkdir"
            "_mv"
            "_rm"
            "_rmdir"
            "_rsync"
            "_sed"
)
# special case sudo (not mandatory)
_sudo="/usr/bin/sudo"


#check if ansible_connect exists
[ -f $ansible_connect ] || ansible_connect="$(command -v reclass-ansible)"

#display error if it still doesn't exist
[ -f $ansible_connect ] || echo "Path to reclass-ansible is missing!"; exit 0;



## functions ##

print_usage()
{
    echo "usage: $0 [options] action"
    echo "use '$0 help' to get a list of available commands"
}

print_help()
{
    echo "usage: $0 [options] action"
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

#* config file hierarchy (default $conffile=maestro):
#*  * first try to source the systemwide config in /etc/maestro
[ ! -f "/etc/$conffile" ] || . "/etc/$conffile"
#*  * overwrite it with global config /usr/etc/maestro
[ ! -f "/usr/etc/$conffile" ] || . "/usr/etc/$conffile"
#*  * overwrite it with global config installed locally /usr/local/etc/maestro
[ ! -f "/usr/local/etc/$conffile" ] || . "/usr/local/etc/$conffile"
#*  * then prefer the user config if available ~/.maestro
[ ! -f ~/."$conffile" ] || . ~/."$conffile"
#*  * finally test for the config in the path specified - default value is the
#*    current directory: ./maestro or ./.maestro
if [ -f "$conffile" ] ; then
    . "$conffile"
elif [ -f ".$conffile" ] ; then
    . ".$conffile"
fi

## first set the system tools
fail=1
for t in ${!sys_tools[@]} ; do
    # check if sys tool exists and is executable
    if [ -x "${sys_tools[$t]##* }" ] ; then
        export ${t}="${sys_tools[$t]}"
    # If not: Check if it exists in PATH
    elif [ -x "$(command -v ansible-playbook)" ]; then
        export ${t}="$(command -v $(basename ${sys_tools[$t]}))"
    else
        fail=0
        echo "Missing system tool: '${sys_tools[$t]##* }' must be installed."
    fi
done
if [ $fail -eq 0 ] ; then
    die "Please install the above mentioned tools first.."
fi

# the merge of the above inventories will be stored here
inventorydir="$maestrodir/.inventory"

#* options:
while true ; do
    case "$1" in
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
            if [ -n "$classfilter" ] ; then
                classfilter="$1,$classfilter"
            else
                classfilter="$1"
            fi
        ;;
#*  --force|-f                      do not ask before changing anything (!-i)
        -f|--force)
            force=0
        ;;
#*  --dry-run|-n                    do not change anything (see the un-/merge
#*                                  aka rsync, and the ansible actions for their
#*                                  resp. dry-run/check mode)
        -n|--dry-run)
            dryrun=0
        ;;
##*  --dry-run-ansible               do all but on ansible just pretend
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
#*  --interactive|-i                do ask before changing anything (!-f)
        -i|--interactive)
            force=1
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
            if [ -n "$projectfilter" ] ; then
                error "Only one projectfilter is supported, please use the classfilter (-C) instead"
            fi
            projectfilter="$1"
        ;;
#*  --quiet                         equal to '--verbose 0'
        -q|--quiet)
            verbose="0"
        ;;
#*  --version|-V                    print version information and exit
        -V|--version)
            print_version
            exit
        ;;
#TODO actually fix all functions to respect the verbose parameter..
#*  --verbose|-v [level]            print out what is done ([0]:quiet [1..])
        -v*|--v*)
            if [ -z "$2" ] || [ "${2:0:1}" == "-" ] ; then
                verbosity="1"
            elif [ -z "${2/[0-9]*/}" ] ; then
                shift
                verbose=$1
            fi
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

if [ $verbose -eq 0 ] ; then
    ansible_verbose=""
elif [ $verbose -eq 2 ] ; then
    ansible_verbose="-v"
elif [ $verbose -gt 2 ] ; then
    ansible_verbose="-vvv"
    rsync_options="$rsync_options -v"
fi

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

reclass_parameter_parser='BEGIN {
                mode="none"
            }
            /^parameters:$/ {
                mode="param"
                next
            }
            {
                if ( mode == "param" ) {
                    print $0
                }
            }'

reclass_custom_parameter_parser='BEGIN {
                mode="none"
                split(target_var, target_vars, ":")
                spaces="  "
                i=1
                target="^"spaces""target_vars[i]":"
                deeper="^"spaces"[ -] "
            }
            /^parameters:$/ {
                mode="param"
                next
            }
            /^\w.*$/ {
                next
                mode="none"
                next
            }
            {
                if ( mode == "none" ) {
                    next
                }
            }
            $0 ~ target {
                sub("^\\s*", "")
                if ( i == length(target_vars) ) {
                    mode="target"
                    answer=answer"  "target_string""$0"\n"
                } else {
                    i++
                    spaces=spaces"  "
                    target="^"spaces""target_vars[i]":"
                    target_string=""target_string""$0
                    deeper="^"spaces"[ -] "
                }
                next
            }
            $0 !~ deeper {
                mode="param"
                next
            }
            {
                if ( mode == "target" ) {
                    answer=answer $0"\n"
                }
            }
            END {
                print answer
            }'

reclass_parser='BEGIN {
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
                for (var in projects) {
                    gsub("{{ "var" }}", projects[var])
                }
            }
            !/^ *- / {
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
            /^  host__hypervisor:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  l=length($1)
                  print "hosthypervisor=\""substr($0, l+4)"\""
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
            /^  host__virt-type:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  l=length($1)
                  print "hostvtype=\""substr($0, l+4)"\""
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
            /^  host__type_human_readable:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  l=length($1)
                  print "hosttypeh=\""substr($0, l+4)"\""
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
#            /^  debops:$/ {
#print "debops_="metamode
#                if ( metamode == "parameters" ) {
#                    metamode=metamode":debops"
#                    mode="debops"
#                }
#                next
#            }
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
#            /^      .*$/ {
#                if ( metamode == "parameters:debops" ) {
#print "debops___="metamode
#                    gsub("'"'"'", "")
#                    list=list "\n'"'"'" $0 "'"'"'"
#                    next
#                }
#            }
            /^    .*$/ {
#                if ( metamode == "parameters:debops" ) {
#print "debops__="metamode
#                    next
#                } else
                if ( metamode == "parameters:ansible" ) {
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
#                if (( mode != "none") && ( mode != "debops" )) {
                if ( mode != "none") {
                    gsub("'"'"'", "")
                    sub(" *- *", "")
                    list=list "\n'"'"'"$0"'"'"'"
                }
                next
            }
            {
                mode="none"
            }
            END {
            }'

print_warning()
{
    if [ $verbose -ge 1 ] ; then
        printf "\e[1;33mWarning: "
        printf "\e[1;39m$n \e[0m$1\n"
    fi
}

# Not all projects use the same access policy - try to give some hints
ansible_connection_test()
{
    for o in ${!ansible_meta[@]} ; do
        case $o in
            ask_pass)
                if [ ${ansible_meta[$o]} == "true" ] ; then
                    print_warning "has ansible:ask_pass set to 'true'. You probably want to use the '-k' flag."
                fi
            ;;
            ask_become_pass)
                if [ ${ansible_meta[$o]} == "true" ] ; then
                    print_warning "has ansible:ask_become_pass set to 'true'. You probably want to use something like '--become --become-user root -K' as flags."
                fi
            ;;
            connect_timeout)
                if [ ${ansible_meta[$o]} -gt $ansible_timeout ] ; then
                    print_warning ""
                fi
            ;;
            ssh_common_args)
                print_warning "has ansible:ssh_common_args set to '${ansible_meta['ssh_common_args']}'. Please check your ssh configs for that host if you encounter problems."
            ;;
            scp_if_ssh)
                if [ ${ansible_meta[$o]} == "true" ] ; then
                    print_warning "has ansible:$o set to '${ansible_meta[$o]}'. Please control your (.)ansible.cfg if you encounter problems."
                fi
            ;;
            become_user)
                if [ -n "${ansible_meta[$o]}" ] ; then
                    print_warning "has set a certain user to be required to switch to after connecting. You might want to set '--become --become-user ${ansible_meta[$o]}'. Usually this is already set in the backend via the 'ansible_become_user' parameter"
                fi
            ;;
            user)
                if [ -n "${ansible_meta[$o]}" ] ; then
                    print_warning "has set a certain user to be required for connecting. You might want to set '-u ${ansible_meta[$o]}'. Usually this is already set in the backend via the 'ansible_user' parameter"
                fi
            ;;
            *)
            ;;
        esac
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
    if [ ${#remote_os[@]} -gt 5 ]; then
        remote_os_codename="${remote_os_codename} ${remote_os[5]}"
    fi
    answer0="${remote_os_distro} ${remote_os_name} ${remote_os_release} ${remote_os_codename}"
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
    if [ $verbose -gt 1 ] ; then
        printf "    \e[1;36m$1\e[0;39m -> \e[1;35m$2\e[0;39m\n"
    fi
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
###*** Array:                 parameters.debops
#    debops=()
#*** String:                parameters.host__hypervisor
    hosthypervisor=""
#*** String:                parameters.host__infrastructure
    hostinfrastructure=""
#*** String:                parameters.host__virt-type
    hostvtype=""
#*** String:                parameters.host__locations
    hostlocation=""
#*** String:                parameters.host__type
    hosttype=""
#*** String:                parameters.host__type_human_readable
    hosttypeh=""
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

parse_node_whole_reclass_list()
{
    list_node $0
    $_reclass -b $inventorydir -n $1 | $_awk "$reclass_parameter_parser"
}

parse_node_custom_var_list()
{
    list_node $n
    parse_node_custom_var $n
}

parse_node_custom_var()
{
    $_reclass -b $inventorydir -n $1 |
        $_awk -v target_var="$target_var" "$reclass_custom_parameter_parser"
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

#TODO handle bug with AND filters '&classname'
    if [ -n "$classfilter" ] ; then
        process_nodes process_classes ${nodes[@]}
        nodes=()
        for c in ${classfilter//,/ } ; do
            for a in ${classes_dict[$c]//:/ } ; do
                nodes=( ${nodes[@]} $a )
            done
        done
        classes_dict=()
    fi
}

# List all applications for all hosts
list_applications()
{
    list_node $n
    for a in ${applications[@]} ; do
        printf "\e[0;36m - $a\n"
    done | $_sort
    printf "\e[0;39m"
}

# List all classes for all hosts
list_classes()
{
    list_node $n
    for c in ${classes[@]} ; do
        printf "\e[0;35m - $c\n"
    done | $_sort_or_not_sort
    printf "\e[0;39m"
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
    printf "\e[0;33m This host is a \e[1;33m${hosttypeh} (${hosttype})\e[0;33m.\n"
    if [ -n "$hostinfrastructure" ] ; then
        if [ -n "$hostvtype" ] && [ "$n" == "$hosthypervisor" ] ; then
            printf " It runs \e[1;33m${hostvtype}\e[0;33m.\n"
        else
            printf " It is running on \e[1;33m${hostinfrastructure}\e[0;33m.\n"
        fi
    fi
    [ -n "$hostlocation" ] &&
        printf " The ${hosttypeh} is located at "
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
            if [ $verbose -gt 2 ] ; then
                printf "\e[1;31mNo match for $n\n\e[0;39m"
            fi
            continue
        elif [ $verbose -gt 2 ] ; then
            printf "\e[1;32mMached node: $n\n\e[0;39m"
        fi
        hostname="${n%%.*}"
        domainname="${n#*.}"
        parse_node $n
        $command $n
    done
}

re_merge_custom()
{
    #better safe than sorry
    [ -n "$1" ] || error "ERROR: Source directory was empty!"
    [ "${1/*$n*/XXX}" == "XXX" ] || error "ERROR: Source directory was $1"
    for m in ${!remergecustomsrc[@]} ; do
        if [ $verbose -gt 0 ] ; then
            printf "\e[0;39m Merging $1/${remergecustomsrc[$m]} to ${remergecustomdest[$m]}\n"
        fi
        if [ -e "$1/${remergecustomsrc[$m]}" ] ; then
            $_mkdir -p ${remergecustomdest[$m]%/*}
            $_rsync $rsync_options $1/${remergecustomsrc[$m]} ${remergecustomdest[$m]}
        elif [ $verbose -gt 0 ] ; then
            printf "\e[0:31m  Skipping $1/${remergecustomsrc[$m]} as it does not exist..\n\e[0;39m"
        fi
    done
}

merge_all()
{
    if [ $verbose -gt 0 ] ; then
        printf "\e[1;39m  - $1\e[0;39m\n"
    fi
    if [ ! -d "$workdir" ] ; then
        die "Target directory '$workdir' does not exist!"
    fi
    src=""
    trgt=""
    if [ -n "$merge_only_this_subdir" ] ; then
        if [ $verbose -gt 1 ] ; then
            printf "    - focus on '$merge_only_this_subdir' only\n"
        fi
        src="$merge_only_this_subdir"
        trgt="$merge_only_this_subdir"
    fi
    case "$merge_mode" in
        dir|custom)
            for d in ${storagedirs[@]} ; do
                do_sync "$d/$src/" "$workdir/$n/$trgt/"
            done
        ;;&
        dir)
        ;;
        custom)
            re_merge_custom $workdir/$n/
        ;;
        *)
            die "merge mode '$merge_mode' is not supported.."
        ;;
    esac
}

print_plain_reclass()
{
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
}

unfold_all()
{
    if [ $verbose -gt 0 ] ; then
        printf "\e[1;39m  - $1\e[0;39m\n"
    fi
    if [ ! -d "$workdir" ] ; then
        die "Source directory '$workdir' does not exist!"
    fi
    src=""
    trgt=""
    if [ -n "$merge_only_this_subdir" ] ; then
        if [ $verbose -gt 1 ] ; then
            printf "    - focus on '$merge_only_this_subdir' only\n"
        fi
        src="$merge_only_this_subdir"
        trgt="$merge_only_this_subdir"
    fi
    case "$merge_mode" in
        dir|custom)
            ignore_these=""
            for f in ${unmerge_ignore[@]} ; do
                ignore_these="$ignore_these -not -name $f"
            done
            for f in $($_find "$workdir/$n/$src/" -type f $ignore_these) ; do
                if [ $verbose -gt 1 ] ; then
                    printf "    processing $f\n"
                fi
                t="$merge_only_this_subdir${merge_only_this_subdir:+/}${f/$workdir\/$n\/$trgt/}"
                let i=${#storagedirs[@]}-1
                if [ -f "${storagedirs[$i]}/$t" ] ; then
                    rv=0
                    $_diff -q "$f" "${storagedirs[$i]}/$t" 2>&1 >/dev/null || rv=$?
                    if [ 0 -eq $rv ] ; then
                        if [ $verbose -gt 2 ] ; then
                            printf "    No changes found at ${storagedirs[$i]}/$t\n"
                        fi
                        continue
                    elif [ 1 -eq $rv ] ; then
                        printf "      found '$f' in last/host storage dir "
                        printf " '${storagedirs[$i]}/$t', merging!\n"
                        $_rsync $rsync_options "$f" "${storagedirs[$i]}/$t"
                        continue
                    fi
                else
                    answer=n
                    unmerge_done=1
                    for (( j=i-1 ; j>=0 ; j-- )) ; do
                        if [ -f "${storagedirs[$j]}/$t" ] ; then
                            rv=0
                            $_diff -q "$f" "${storagedirs[$j]}/$t" 2>&1 >/dev/null || rv=$?
                            if [ 0 -eq $rv ] ; then
                                if [ $verbose -gt 2 ] ; then
                                    printf "    No changes found at ${storagedirs[$j]}/$t\n"
                                fi
                                unmerge_done=0
                                break
                            elif [ 1 -eq $rv ] ; then
                                printf "      found '$f' in storage dir "
                                printf " '${storagedirs[$j]}/$t'"
                                if [ 0 -eq "$force" ] ; then
                                    printf ", merging (--force)!\n"
                                    answer=0
                                else
                                    printf ", do you want to merge? [yN] "
                                    read answer
                                fi
                            fi
                            case $answer in
                                y*|Y*)
                                    $_rsync $rsync_options "$f" "${storagedirs[$j]}/$t"
                                    unmerge_done=0
                                    break
                                ;;
                                *)
                                    printf "      .. not merging.\n"
                                ;;
                            esac
                        fi
                    done
                    if [ 0 -ne "$unmerge_done" ] ; then
                        if [ 0 -eq "$force" ] ; then
                            printf "No target found, use '-i' for interactive"
                            printf " mode.\n"
                            continue
                        fi
                        printf "File \e[1m'$f'\e[0m is not persisted yet.\n"
                        printf "Which directory do you prefer for storage?\n"
                        printf "  0) none\n"
                        for (( i=0 ; i<${#storagedirs[@]} ; i++ )) ; do
                            let j=i+1
                            printf "  $j) ${storagedirs[$i]}\n"
                        done
                        read answer
                        if [ -z "$answer" ] || [ $answer -eq 0 ] ; then
                            noop
                            continue
                        else
                            let answer--
                            $_mkdir -p "${storagedirs[$answer]}/${t%/*}"
                            $_rsync $rsync_options "$f" "${storagedirs[$answer]}/$t"
                        fi
                    fi
                fi
            done
        ;;&
        dir)
        ;;
        custom)
            re_merge_custom $workdir/$n/
        ;;
        *)
            die "merge mode '$merge_mode' is not supported.."
        ;;
    esac
}

# gets filled in get_nodes
nodes=()

#* actions:
case $1 in
    ansible*|play|playloop|ploop)
        shift
        ansibleaction="$1"
        shift
        get_nodes
        [ -n "$_ansible" ] || error "Missing system tool: ansible."
        [ -n "$_ansible_playbook" ] ||
                        error "Missing system tool: ansible-playbook."

        # check for some connection settings in config or for -k option
        process_nodes ansible_connection_test ${nodes[@]}
        if [ -n "$nodefilter" ] && [ -n "${nodefilter//*\.*/}" ] ; then
            nodefilter="${nodefilter}*"
        fi
        if [ -n "$projectfilter" ] && [ -n "$classfilter" ] && [ -n "$nodefilter" ] ; then
            hostpattern="&project.$projectfilter,$classfilter,$nodefilter"
        elif [ -n "$projectfilter" ] && [ -n "$classfilter" ] ; then
            hostpattern="&project.$projectfilter,$classfilter"
        elif [ -n "$projectfilter" ] && [ -n "$nodefilter" ] ; then
            hostpattern="&project.$projectfilter,$nodefilter"
        elif [ -n "$classfilter" ] && [ -n "$nodefilter" ] ; then
            hostpattern="$classfilter,$nodefilter"
        elif [ -n "$projectfilter" ] ; then
            hostpattern="$projectfilter"
        elif [ -n "$classfilter" ] ; then
            hostpattern="$classfilter"
        elif [ -n "$nodefilter" ] ; then
            hostpattern="$nodefilter"
        else
            error "No class or node was specified.."
        fi
        for d in ${!localdirs[@]} ; do
            ansibleextravars="$ansibleextravars $d=${localdirs[$d]}"
        done
        if [ -z "$ANSIBLE_CONFIG" ] ; then
            ANSIBLE_CONFIG="$maestrodir/ansible.cfg"
            export ANSIBLE_CONFIG
        fi
    ;;&
#*  ansible-module module '[ansible-module-arguments]' '[ansible-extra-vars] ..'\
#*   [ansible-option]..             execute an ansible module. (E.g.
#*                                  `debug 'msg="{{ certificate.main }}"'`)
    ansible|ansible-module)
        if [ "$1" != "" ] && [ "${1:0:1}" != "-" ] ; then
            ansiblemoduleargs="$1"
            shift
        fi
        if [ "$1" != "" ] && [ "${1:0:1}" != "-" ] ; then
            ansibleextravars="$ansibleextravars $1"
            shift
        fi
        ansibleoptions="$ansibleoptions $@"
        $_ansible ${ansible_verbose} "$hostpattern" -m $ansibleaction -a "$ansiblemoduleargs" -e "workdir='$workdir' $ansibleextravars" $ansibleoptions
    ;;
#*  ansible-plays-list [play]       list all available playbooks (see
#*                                  'playbookdir') in your config, or print
#*                                  the details of the one play specified.
    ansible-plays-list|apls|pls)
        shift
        o=$1
        if [ -n "$o" ] ; then
            p="$($_find -L ${playbookdirs[@]} -maxdepth 1 -name "$o.yml" )"
            if [ -f "$p" ] ; then
                printf "\e[1;39m - ${o##*/}: \e[0;32m $p\e[0;35m\n"
                $_grep "^#\* " $p | $_sed 's;^#\*;  ;'
                printf "\e[0;39m"
            else
                die "No such play found $o: $p"
            fi
        else
            foundplays=( $($_find -L ${playbookdirs[@]} -maxdepth 1 -name "*.yml" | $_sort -u) )
            for p in ${foundplays[@]} ; do
                o=${p%.yml}
                printf "\e[1;39m - ${o##*/}: \e[0;32m $p\e[0;39m\n"
            done
        fi
    ;;
#*  ansible-play play '[ansible-extra-vars] ..' [ansible-option]..
#*                                  wrapper to ansible which also includes
#*                                  custom plays stored in the config
#*                                  file as '$playbookdir'.
#*                                  'play' name of the play
    ansible-play|ansible-playbook|play)
        if [ "$1" != "" ] && [ "${1:0:1}" != "-" ] ; then
            ansibleextravars="$ansibleextravars $1"
            shift
        fi
        ansibleoptions="$ansibleoptions $@"
        p="$($_find -L ${playbookdirs[@]} -maxdepth 1 -name ${ansibleaction}.yml)"
        [ -n "$p" ] ||
            error "There is no play called ${ansibleaction}.yml in ${playbookdirs[@]}"
        echo "wrapping $_ansible_playbook ${ansible_verbose} -l $hostpattern $pass_ask_pass $ansible_root -e 'workdir="$workdir" $ansibleextravars' $ansibleoptions $p"
        if [ 0 -ne "$force" ] ; then
            echo "Press <Enter> to continue <Ctrl-C> to quit"
            read
        fi
        $_ansible_playbook ${ansible_verbose} -l "$hostpattern" $pass_ask_pass $ansible_root -e "workdir='$workdir' $ansibleextravars" $ansibleoptions $@ $p
    ;;
#*  ansible-play-loop play itemkey=itemval0:.. '[ansible-extra-vars] ..' \
#*  [ansible-option]..
#*                                  wrapper to ansible which also includes
#*                                  custom plays stored in the config
#*                                  file as '$playbookdir'. Unlike 'play'
#*                                  above it will be run multiple times, for
#*                                  every 'itemsparameter' as 'itemname' passed
#*                                  on to 'play', name of the play
    ansible-play-loop|playloop|ploop)
        itemname="${1%=*}"
        itemparams="${1##*=}"
        shift
        if [ "$1" != "" ] && [ "${1:0:1}" != "-" ] ; then
            ansibleextravars="$ansibleextravars $1"
            shift
        fi
        ansibleoptions="$ansibleoptions $@"
        p="$($_find -L ${playbookdirs[@]} -maxdepth 1 -name ${ansibleaction}.yml)"
        [ -n "$p" ] ||
            error "There is no play called ${ansibleaction}.yml in ${playbookdirs[@]}"
        for iparam in ${itemparams//:/ } ; do

            echo "wrapping $_ansible_playbook ${ansible_verbose} -l $hostpattern $pass_ask_pass $ansible_root -e 'workdir="$workdir" $itemname="{{ $iparam }}" $ansibleextravars' $ansibleoptions $p"
            if [ 0 -ne "$force" ] ; then
                echo "Press <Enter> to continue <Ctrl-C> to quit"
                read
            fi
            $_ansible_playbook ${ansible_verbose} -l $hostpattern $pass_ask_pass $ansible_root -e "workdir='$workdir' $itemname='{{ $iparam }}' $ansibleextravars" $ansibleoptions $p
        done
    ;;
#*  applications-list [app]         list hosts sorted by applications
    als|app*)
        get_nodes
        process_nodes process_applications ${nodes[@]}
        shift
        if [ -n "$1" ] ; then
            if [ -n "${applications_dict[$1]}" ] ; then
                hs="${applications_dict[$1]}"
                applications_dict=()
                applications_dict[$1]="$hs"
            else
                die "Application '$1' not found in knowledge base"
            fi
        fi
        for a in $( echo ${!applications_dict[@]} | $_tr " " "\n" | $_sort ) ; do
            printf "\e[1;34m[$a]\n"
            for h in $(echo -e ${applications_dict[$a]//:/ \\n} | $_sort -u); do
                printf "\e[0;32m$h\n"
            done
        done
        printf "\e[0;39m"
    ;;
#*  classes-list [class]            list hosts sorted by class
    cls|class*)
        get_nodes
        process_nodes process_classes ${nodes[@]}
        shift
        if [ -n "$1" ] ; then
            if [ -n "${classes_dict[$1]}" ] ; then
                hs="${classes_dict[$1]}"
                classes_dict=()
                classes_dict[$1]="$hs"
            else
                die "Class '$1' not found in knowledge base"
            fi
        fi
        for a in $( echo ${!classes_dict[@]} | $_tr " " "\n" | $_sort ) ; do
            printf "\e[1;35m[$a]\n"
            for h in $( echo -e ${classes_dict[$a]//:/ \\n} | $_sort -u ) ; do
                printf "\e[0;32m$h\n"
            done
        done
        printf "\e[0;39m"
    ;;
#*  help                            print this help
    help)
        print_help
        exit 0
    ;;
#*  init                            create an environemnt with all the
#*                                  repos defined in the config, in order
#*                                  to get a running knowledge base
#*  reinit                          update reclass environment without
#*                                  pulling repos
    init|reinit)
        $_mkdir -p "$workdir"
        if [ "$1" == init ] ; then
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
        fi
        shift
        echo "Re-create the inventory. Note: there will be warnings for "
        echo "duplicates, etc. "
        $_mkdir -p $inventorydir/{nodes,classes}
        $_rm -rf $inventorydir/{nodes,classes}/*
        for d in ${inventorydirs[@]} ; do
            $_find "$d/nodes/" -type d |
                $_sed 's;'$d'/nodes/;'$inventorydir'/nodes/;' |
                $_xargs --no-run-if-empty $_mkdir -p
            $_find "$d/classes/" -type d |
                $_sed 's;'$d'/classes/;'$inventorydir'/classes/;' |
                $_xargs --no-run-if-empty $_mkdir -p
            $_find "$d/nodes/" -name "*.yml" |
                $_sed \
                  's;\('$d'/nodes/\)\(.*\);\1\2 '$inventorydir'/nodes/\2;' |
                $_xargs --no-run-if-empty --max-args 2 $_ln -s || true
            $_find "$d/classes/" -name "*.yml" |
                $_sed \
                  's;\('$d'/classes/\)\(.*\);\1\2 '$inventorydir'/classes/\2;' |
                $_xargs --no-run-if-empty --max-args 2 $_ln -s || true
        done
        echo "Re-connect ansible to our reclass inventory"
        # remove hosts file if it exists
        [ -f "$inventorydir/hosts" ] && $_rm "$inventorydir/hosts"
        # remove reclass config if it exists
        [ -f "$inventorydir/reclass-config.yml" ] && $_rm "$inventorydir/reclass-config.yml"
        # create symlink to reclass-ansible
        $_ln -s $ansible_connect "$inventorydir/hosts"
        if [ -z "$_pre" ] ; then
            $_cat > "$inventorydir/reclass-config.yml" << EOF
storage_type: yaml_fs
inventory_base_uri: $inventorydir
EOF
            $_cat > "$maestrodir/ansible.cfg" << EOF
[defaults]
hostfile    = $inventorydir/hosts
timeout     = $ansible_timeout
ansible_managed = "$ansible_managed"
roles_path  = $maestrodir/$ansible_galaxy_roles
#allow_world_readable_tmpfiles = true

[ssh_connection]
#scp_if_ssh = $ansible_scp_if_ssh
EOF
        else
            echo "write config file $inventorydir/reclass-config.yml"
            echo "  storage_type: yaml_fs"
            echo "  inventory_base_uri: $inventorydir"
            echo "-EOF-"
            echo "write config file $maestrodir/ansible.cfg"
            echo "  [defaults]"
            echo "  hostfile    = $inventorydir/hosts"
            echo "  timeout     = $ansible_timeout"
            echo "  ansible_managed = '$ansible_managed'"
            echo ""
            echo "  [ssh_connection]"
            echo "  scp_if_ssh = $Ansible_scp_if_ssh"
            echo "-EOF-"

        fi
        if [ -z "$ANSIBLE_CONFIG" ] ; then
            ANSIBLE_CONFIG="$maestrodir/ansible.cfg"
            export ANSIBLE_CONFIG
        fi
        echo "Installing all necessary ansible-galaxy roles"
        for f in ${playbookdirs[@]}/${galaxyroles} ; do
            if [ -f "${f}" ] ; then
                echo "found ${f}"
                if $_grep "^- src:" $f ; then
                    if $_ansible_galaxy install -r $f ; then
                        echo "done."
                    else
                        error "ansible-galaxy failed to perform the" \
                                "installation. Please make sure all the" \
                                "roles do exist and that you have" \
                                "write access to the ansible 'roles_path'," \
                                "it can be controled in ansible.cfg in" \
                                "the [defaults] section."
                    fi
                else
                    echo ".. but it was empty, ignoring.."
                fi
            fi
        done
    ;;
#*  shortlist                       list nodes - but just the hostname
    l|shortlist)
        get_nodes
        process_nodes list_node_short ${nodes[@]}
    ;;
#*  list                            list nodes
    ls|list*)
        get_nodes
        process_nodes list_node ${nodes[@]}
    ;;
#*  list-applications               list applications sorted by hosts
    lsa|list-a*)
        get_nodes
        process_nodes list_applications ${nodes[@]}
    ;;
#*  list-classes [option]           list classes sorted by hosts
#*                                  options:
#*                                    --alphabetical do not sort in order of
#*                                                   processing but alpha-
#*                                                   betically
    lsc|list-c*)
        get_nodes
        shift
        _sort_or_not_sort="cat"
        case $1 in
            -a|--alph*)
                _sort_or_not_sort="$_sort"
            ;;
            "")
            ;;
            *)
                die "option '$1' not supported"
            ;;
        esac
        process_nodes list_classes ${nodes[@]}
    ;;
#*  list-distro-packages            list app package names for the hosts distro
    lsp|list-distro-packages)
        get_nodes
        process_nodes list_distro_packages ${nodes[@]}
    ;;
#*  list-merge-customs              show custom storage merge rules
    lsmc|list-merge-c*)
        get_nodes
        process_nodes list_node_re_merge_custom ${nodes[@]}
    ;;
#*  list-storage                    show storage directories (for merging)
    lss|list-storage)
        get_nodes
        process_nodes list_node_stores ${nodes[@]}
    ;;
#*  list-types                      show maschine type and location
    lst|list-types)
        get_nodes
        process_nodes list_node_type ${nodes[@]}
    ;;
#*  list-resources                  show the machines resource config
    lsr|list-resources)
        target_var=$knowledge_base_parameter_resources
        get_nodes
        process_nodes parse_node_custom_var_list ${nodes[@]}
    ;;
####TODO rename to fold/unfold ??
#*  merge [subdir] [rsync-option].. just merge all storage directories
#*                                  (only under subdir if specified)
#*                                  flat to $workdir with rsync
    merge|merge-a*|mg)
        shift
        if [ "$1" != "" ] && [ "${1:0:1}" != "-" ] ; then
            merge_only_this_subdir="$1"
            shift
        fi
        rsync_options="$rsync_options $@"
        get_nodes
        if [ $verbose -gt 0 ] ; then
            printf "\e[1;39mSynchronizing storage dirs \e[0m(rsync options: "
            printf "\e[1;34m'$rsync_options'\e[0;39m)\n"
        fi
        process_nodes merge_all ${nodes[@]}
    ;;
#*  merge-custom [subdir] [rsync-option]..
#*                                  merge after custom rules defined in reclass
#*                                  in $workdir (just subdir if specified),
#*                                  then move to its target destination
    merge-cu*|mc)
        shift
        if [ "$1" != "" ] && [ "${1:0:1}" != "-" ] ; then
            merge_only_this_subdir="$1"
            shift
        fi
        rsync_options="$rsync_options $@"
        get_nodes
        merge_mode="custom"
        process_nodes merge_all ${nodes[@]}
    ;;
#*  reclass                         just wrap reclass
    rec|reclass)
        print_plain_reclass
    ;;
#*  reclass-show-parameters         print all parameters set in reclass
    reclass-show*|rsh)
        get_nodes
        process_nodes parse_node_whole_reclass_list ${nodes[@]}
    ;;
#*  reclass-search-parameter        print a certain parameter set in reclass
    reclass-search*|rs)
        shift
        target_var="${1}"
        get_nodes
        process_nodes parse_node_custom_var_list ${nodes[@]}
    ;;
#*  show-summary                    show variables used here from the config and reclass
    show-sum*)
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
#*  search pattern                  show in which file a variable is defined
#*                                  or used
    search)
        shift
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${$1}" -e "{{ *$1 *}}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${$1}" -e "{{ *$1 *}}" $inventorydir/classes || true
    ;;
#*  search-class classpattern       show which class or node refers to a given
#*                                  class
    search-class)
        shift
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "^  - $1$" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "^  - $1$" $inventorydir/classes || true
    ;;
#*  search-in-playbooks pattern     search the common-playbooks for a certain
#*                                  parameter as they overlap
    search-in-playbooks|search-play*)
        shift
        for d in ${playbookdirs[@]} $maestrodir/$ansible_galaxy_roles/* ; do
            printf "\e[1;33mIn $d we found the string here:\e[0m\n"
            $_grep --color -Hn -R \
                    -e "{{ *${1} *}}" \
                    -e "{{ *[][a-zA-Z0-9_+\.]*[[\.]${1}[]\.][][a-zA-Z0-9_+\.]* *}}" \
                    -e "{{ *[][a-zA-Z0-9_+\.]*[]\.]${1} *}}" \
                    -e "{{ *${1}[[\.][][a-zA-Z0-9_+\.]* *}}" \
                    -e "^ *${1}:$" $d || true
        done
    ;;
#*  search-external pattern         show in which file an 'external' (maestro)
#*                                  {{ variable }} is used
    search-external)
        shift
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "{{ *$1 *}}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "{{ *$1 *}}" $inventorydir/classes || true
    ;;
#*  search-reclass pattern          show in which file a ${variable} is
#*                                  defined or used
    search-reclass)
        shift
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${$1}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${$1}" $inventorydir/classes || true
    ;;
#*  status                          test host by ssh and print distro and ip(s)
    ss|status)
        get_nodes
        process_nodes connect_node ${nodes[@]}
    ;;
####TODO rename to fold/unfold ??
#*  unmerge [rsync-option]..        copy the content of $workdir back to the
#*                                  storage directories - guess or ask..
    unmerge|umg)
        shift
        if [ "$1" != "" ] && [ "${1:0:1}" != "-" ] ; then
            merge_only_this_subdir="$1"
            shift
        fi
        rsync_options="$rsync_options $@"
        get_nodes
        if [ $verbose -gt 0 ] ; then
            printf "\e[1;39mSynchronizing back to storage dirs\e[0m\n"
        fi
        process_nodes unfold_all ${nodes[@]}
    ;;
    *)
        print_usage
    ;;
esac

