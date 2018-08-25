#  -*- mode: shell-script -*-

#
# Make kubectl friendlier
#

# report brief info for display in a prompt
function kprompt()
{
    echo "$*$(kctx)/$(kns)"
}

# list all interesting context names
function kctxs()
{
    kubectl config get-contexts -oname
}

# exec args for each interesting context
# TODO: add async and prefix options
function keachctx()
{
    local ctx
    if [[ $# -lt 1 ]]; then
        cat <<EOF >&2
usage: keachctx <command> [<arg> ....]
[ NOTE: command is eval'd with a \$cxt variable available ]
EOF
        return 1
    fi
    for ctx in $(kctxs); do
        eval "$@"
    done
}

# get the current context
function kctx()
{
    if [[ -n "${_K8S_CTX}" ]]; then
        echo "${_K8S_CTX}"
    else
        kubectl config current-context
    fi
}

# list all internal node IPs
function knodeips()
{
    $_KUBECTL "$@" get nodes \
            -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
}

# run a command on each node async
function keachnode()
{
    local esc cmd ip line
    if [[ "$1" = '--no-escape' ]]; then
        shift; esc=false
    else
        esc=true
    fi
    if [[ $# -lt 1 ]]; then
        echo "usage: keachnode [--no-escape] <cmd> [<args>...]" >&2
        return 1
    fi
    if $esc; then
        cmd=$(shellwords "$@")
    else
        cmd="$*"
    fi
    for ip in $(knodeips "$@"); do
        pgrep -qf "ssh: .*@${ip}" || ssh "$ip" : # start background ssh control session
        ( ( ssh "$ip" $cmd 2>&1 | while read -r line; do printf '%-15s %s\n' "${ip}:" "${line}"; done ) & )
    done
    sleep 1
    wait
}

# get uptimes for all nodes sorted by descending load (highest load at top)
function kuptime()
{
    keachnode "$@" uptime | sort -rnk 11
}

# get memory usage for all nodes sorted by ascending free memory (smallest memory available at top)
function kmem()
{
    printf '%15s %s\n' '[megabytes]' '             total       used       free     shared    buffers     cached'
    keachnode "$@" sh -c 'free -m | grep ^Mem' | sort -nk 5
}

# get file system usage for all nodes sorted by percent used (smallest space available at top)
function kdf()
{
    printf '%-15s %s\n' 'Host' 'Filesystem              Size  Used Avail Use% Mounted on'
    keachnode "$@" sh -c 'df -h / /var/lib/docker | sed 1d' | sort -rnk 6
}

# get the current namespace
function kns()
{
    if [[ -n "${_K8S_NS}" ]]; then
        echo "${_K8S_NS}"
    else
        kubectl config get-contexts | awk '$1 == "*" {print $5}'
    fi
}

function _ku_usage()
{
    cat <<EOF >&2
usage: ku [-s] <namespace>
       ku [-s] <context> <namespace>
       ku reset

  Use "-s" to start a "session" that only changes context or namespace for this terminal.  The
  session is "sticky" until a "reset" is invoked in the same terminal to revert back to using the
  current configured context.

EOF
}

# switch to a new default namespace (and optionally a new context) with partial matching
function ku()
{
    local ctx ns code session=false

    if [[ $# -lt 1 ]]; then
        ctx=$(kctx)
        # remove first column...
        code+='sub(/^CURRENT *|^\*? */,"",$0);'
        # optionally replace the namespace...
        [[ -n "${_K8S_NS}" ]] && code+='if($1=="'"${ctx}"'"){$4="'"${_K8S_NS}"'";$5="[temporary]"};'
        # print highlighted if "selected"...
        kubectl config get-contexts | awk "{${code};print}" | column -xt | \
            awk '{if($1=="'"${ctx}"'"){print "\033[30m\033[43m" $0 "\033[0m"}else{print}}'
        return
    fi

    if [[ "$1" =~ ^--?h ]]; then
        _ku_usage
        return 1
    fi

    if [[ "$1" = 'reset' ]]; then
        unset _K8S_CTX _K8S_NS
        _KUBECTL='kubectl'
        [[ "$2" = '-q' ]] || ku
        return
    fi

    if [[ "$1" = '-s' ]]; then
        session=true
        shift
    fi

    [[ -n "${_K8S_NS}" ]] && session=true

    if [[ $# -eq 2 ]]; then
        ctx=$(kctxs | sort -r | grep -m1 "$1")
        if [[ -z "$ctx" ]]; then
            echo 'no match found' >&2
            return 2
        fi
        shift
        $session || kubectl config use-context "$ctx"
    elif [[ $# -eq 1 ]]; then
        ctx=$(kctx)
    else
        _ku_usage
        return 1
    fi

    ns=$(kubectl --context "${ctx}" get ns -oname | cut -d/ -f2 | sort | grep -m1 "$1")
    if [[ -z "$ns" ]]; then
        echo 'no match found' >&2
        return 3
    fi

    if $session; then
        _K8S_CTX=$ctx
        _K8S_NS=$ns
        _KUBECTL="kubectl --context ${_K8S_CTX} -n ${_K8S_NS}"
    else
        ku reset -q
        kubectl config set-context "$ctx" --namespace "$ns" | \
            sed 's/\.$/ using namespace "'"${ns}"'"./'
    fi

    ku
}

# list matching pod names
function knamegrep()
{
    local cmd t
    if [[ "$1" = '-s' ]]; then
        shift; cmd='s|^[^/]*/||'
    fi
    if [[ $# -lt 2 ]]; then
        echo 'usage: knamegrep [-s] { pods | nodes } <grep_args>....' >&2
        return 1
    fi
    t=$1; shift
    $_KUBECTL get $t -oname | grep "$@" | sed "${cmd}"
}

# list matching container names for a given pod
function kcongrep()
{
    local pod=$1; shift
    $_KUBECTL get pod "${pod}" -oyaml -o'jsonpath={.spec.containers[*].name}' | tr ' ' '\n' | grep "$@"
}

# execute an interactive REPL on a container
function krepl()
{
    local opt raw=false

    while getopts 'r' opt; do
        case $opt in
            r) raw=true;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                return 2
                ;;
        esac
    done

    shift $((OPTIND-1))

    if [[ $# -lt 1 ]]; then
        cat <<EOF >&2
usage: krepl [OPTIONS] <pod_match> [@<container_match>] [<command> [<args>...]]

  Default command will try to determine the best shell available (bash || ash || sh).

  Options:

    -r    do not escape the command and arguments (i.e. "raw")

EOF
        return 1
    fi

    local cmd pod con e_args=('exec' -ti) pod_match=$1; shift

    if [[ "${pod_match::1}" = '^' ]] || [[ "${pod_match::1}" = '.' ]]; then
        pod_match="${pod_match:1}"
    fi

    pod=$(knamegrep -s pods -m1 "${pod_match}")
    if [[ -z "${pod}" ]]; then
        echo 'no match found' >&2
        return 2
    fi

    e_args+=("${pod}")

    if [[ "${1::1}" = '@' ]]; then
        con="$(kcongrep "${pod}" -m1 "${1:1}")"
        if [[ -z "${con}" ]]; then
            echo 'no match found' >&2
            return 3
        fi
        e_args+=(-c "${con}")
        shift
    else
        # try finding a matching container based on the pod
        con="$(kcongrep "${pod}" -m1 "${pod_match}")"
        [[ -n "${con}" ]] && e_args+=(-c "${con}")
    fi

    if [[ $# -eq 0 ]]; then
        cmd=' bash || ash || sh'
    elif $raw; then
        cmd=" $*"
    else
        cmd=$(printf ' %q' "$@")
    fi

    e_args+=(-- sh -c "KREPL=${USER};TERM=xterm;PS1=\"\$(hostname -s) $ \";export TERM PS1;${cmd}")

    echo "${_KUBECTL}$(printf ' %q' "${e_args[@]}")" >&2
    $_KUBECTL "${e_args[@]}"
}

# run commands on one or more containers
function keach()
{
    local opt async=false interactive=false prefix=false raw=false verbose=false

    while getopts 'aiprv' opt; do
        case $opt in
            a) async=true;;
            i) interactive=true;;
            p) prefix=true;;
            r) raw=true;;
            v) verbose=true;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                return 2
                ;;
        esac
    done

    shift $((OPTIND-1))

    if [[ $# -lt 2 ]]; then
        cat <<EOF >&2
usage: keach [OPTIONS] <pod_match> [@<container_name>] <command> [<arguments>...]

  Options:

    -a    run the command asynchronously for all matching pods
    -i    run the command interactive with a TTY allocated
    -p    prefix the command output with the name of the pod
    -r    do not escape the command and arguments (i.e. "raw")
    -v    show the kubectl command line used

EOF
        return 1
    fi

    local pod cmd x_args=() e_args=('{}') pod_match=$1; shift

    if [[ "${1::1}" = '@' ]]; then
        e_args+=(-c "${1:1}")
        shift
    fi

    if $interactive; then
        cmd+='TERM=term'
        e_args+=(-ti)
    fi

    if $raw; then
        cmd+=" $*"
    else
        cmd+=$(printf ' %q' "$@")
    fi

    $prefix && cmd+=" | sed -e \"s/^/\`hostname -f\`: /\""
    $verbose && x_args+=(-t)

    pods=($(knamegrep -s pods "${pod_match}"))
    $async && x_args+=(-P ${#pods[@]})

    xargs "${x_args[@]}" -I'{}' -n1 -- \
          ${_KUBECTL} exec "${e_args[@]}" -- sh -c "${cmd}" <<< "${pods[@]}"
}

# simplify kubectl commands with abbreviations
# TODO: consider how best to add krepl or k repl
function k()
{
    if [[ $# -lt 1 ]]; then
        cat <<EOF >&2

  Expansions:

    a <f>    apply --filename=<f>
    g        get
    d        describe
    del      delete
    ex       exec
    exi      exec -ti
    l        logs
    s <r>    scale --replicas=<r>

${_KGCMDS_HELP}    pc       get pods and containers

    tn       top node
    tp       top pod --containers

    all      --all-namespaces
    any      --all-namespaces
    w        -owide
    y        -oyaml

    .<pod_match>        replace with matching pods (will include "kind" prefix)
    ^<pod_match>        replace with FIRST matching pod
    @<container_match>  replace with FIRST matching container in pod (requires ^<pod_match>)
    ,<node_match>       replace with matching nodes

  Examples:

    k po                       # => kubectl get pods
    k g .odd y                 # => kubectl get pod/oddjob-2231453331-sj56r -oyaml
    k exi ^collab @nginx ash   # => kubectl exec -ti collab-3928615836-37fv4 -c nginx ash
    k l ^back @back --tail=5   # => kubectl logs backburner-1444197888-7xsgk -c backburner --tail=5
    k s 8 dep collab           # => kubectl scale --replicas=8 deployments collab

EOF
        return 1
    fi

    local a pod res args=()

    while [[ $# -gt 0 ]]; do
        a=$1; shift
        case "$a" in
            a)
                if ! [[ -f "$1" ]]; then
                    echo "\"apply\" requires a path to a YAML file (tried \"$1\")" >&2
                    return 2
                fi
                args+=(apply --filename="$1"); shift
                ;;
            any|all)
                if [[ $# -eq 0 ]]; then
                    _kget args all # simple request to get all... let it thru
                else
                    args+=(--all-namespaces)
                fi
                ;;
            d) args+=(describe);;
            del) args+=(delete);;
            ex) args+=('exec');;
            exi) args+=('exec' -ti);;
            g) args+=(get);;
            l) args+=(logs);;
            pc)
                _kget args pods;
                args+=('-ocustom-columns=NAME:.metadata.name,CONTAINERS:.spec.containers[*].name,'`
                `'STATUS:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount')
                ;;
            s)
                if ! [[ "$1" =~ ^[[:digit:]]+$ ]]; then
                    echo "\"scale\" requires replicas (\"$1\" is not a number)" >&2
                    return 3
                fi
                args+=(scale --replicas=$1); shift
                ;;
            tn) args+=(top node);;
            tp) args+=(top pod --containers);;
            w) args+=(-owide);;
            y) args+=(-oyaml);;
            ,*) args+=($(knamegrep nodes "${a:1}"));;
            .*) args+=($(knamegrep pods "${a:1}"));;
            ^*)
                pod=$(knamegrep -s pods -m1 "${a:1}")
                if [[ $? -ne 0 ]]; then
                    echo "no pods matched \"${a:1}\"" >&2
                    return 4
                fi
                args+=("${pod}")
                ;;
            @*)
                if [[ -z "${pod}" ]]; then
                    echo 'must select a pod with ^' >&2
                    return 5
                fi
                args+=(-c $(kcongrep "${pod}" -m1 "${a:1}"))
                if [[ $? -ne 0 ]]; then
                    echo "no containers matched \"${a:1}\" for the \"${pod}\" pod" >&2
                    return 6
                fi
                ;;
            *)
                found=false
                for i in ${!_KGCMDS_AKA[@]}; do
                    if [[ $a = ${_KGCMDS_AKA[$i]} ]]; then
                        found=true
                        _kget args ${_KGCMDS[$i]}
                        break
                    fi
                done
                $found || args+=("$a")
        esac
    done

    echo "${_KUBECTL}$(printf ' %q' "${args[@]}")" >&2
    if [[ " ${args[@]} " =~ ' delete ' ]]; then
        read -r -p 'Are you sure? [y/N] ' res
        case "$res" in
            [yY][eE][sS]|[yY]) : ;;
            *) return 7
        esac
    fi

    $_KUBECTL "${args[@]}"
}

# report all pods grouped by nodes
function kallpods()
{
    if [[ $# -lt 1 ]]; then
        echo 'usage: kallpods <node_match> [<namespace_match> [<pod_match>]]' >&2
        return 1
    fi
    local match='$8 ~ /'"$1"'/'
    [[ $# -gt 1 ]] && match+=' && $1 ~ /'"$2"'/'
    [[ $# -gt 2 ]] && match+=' && $2 ~ /'"$3"'/'
    # sort by node then by namespace then by name
    $_KUBECTL get --all-namespaces pods -owide | awk "${match} {print}" | sort -b -k8 -k1 -k2 | \
        awk '{ x[$8]++; if (x[$8] == 1) print "---"; print}'
}

# report _ALL_ interesting k8s info (more than `get all` provides, but much slower)
function kall()
{
    local rsc res ns=$(kns)
    local ign='all|events|clusterroles|clusterrolebindings|customresourcedefinition|namespaces|'`
             `'nodes|persistentvolumeclaims|storageclasses'
    for rsc in $($_KUBECTL get 2>&1 | awk '/^  \* /{if (!($2 ~ /^('"${ign}"')$/)) print $2}'); do
        if [[ "${rsc}" = 'persistentvolumes' ]]; then
            res=$($_KUBECTL get "${rsc}" | awk 'NR==1{print};$6 ~ /^'"${ns}"'/{print}')
        else
            res=$($_KUBECTL get "${rsc}" 2>&1)
        fi
        [[ $? -eq 0 ]] || continue
        [[ $(echo "$res" | wc -l ) -lt 2 ]] && continue
        cat <<EOF

----------------------------------------------------------------------
$(upcase "$rsc")

${res}
EOF
    done
}

# download the latest version of shortyk8s
function kupdate()
{
    if ! which curl >/dev/null 2>&1; then
        echo 'Curl is required for updating' 2>&1
        return 1
    fi

    local url='https://raw.githubusercontent.com/bradrf/shortyk8s/master/shortyk8s.sh'
    local hfn="${HOME}/.shortyk8s_hdr"

    local tf=$(mktemp)
    local cargs=(-sSfo "${tf}" -D "${hfn}")

    local etag=$(sed -n 's/^ETag: *\([^[:space:]]*\).*$/\1/p' "${hfn}" 2>/dev/null)
    [[ -n "${etag}" ]] && cargs+=(-H "If-None-Match: ${etag}")

    curl "${cargs[@]}" "${url}"

    local rc=0
    local dstd dstf
    if [[ $? -ne 0 ]]; then
        echo 'Unable to check for updates' 2>&1
        rc=$?
    elif [[ -s "${tf}" ]]; then
        # use `cp` to enable automatic following of any symbolic references...
        cp -f "${tf}" "${BASH_SOURCE[0]}" && source "${BASH_SOURCE[0]}"
        rc=$?
        echo 'Updated to the latest version'
    else
        echo "No updates available (${etag})"
    fi

    rm -f "${tf}"

    return $rc
}

######################################################################
# PRIVATE - internal helpers

# internal helper to provide get unless another action has already been requested
function _kget()
{
    local -n a=$1
    shift
    if [[ " ${a[@]} " =~ ' get ' ]] || \
           [[ " ${a[@]} " =~ ' describe ' ]] || \
           [[ " ${a[@]} " =~ ' delete ' ]] || \
           [[ " ${a[@]} " =~ ' scale ' ]]; then
        a+=("$@")
    else
        a+=(get "$@")
    fi
}

# preload the list of known kubectl get commands
_KGCMDS=()
_KGCMDS_AKA=()
_KGCMDS_HELP=''
str='s/^.*\* ([^ ]+) \(aka ([^\)]+).*$/c=\1;a=\2/p; s/^.*\* ([^ ]+) *$/c=\1;a=""/p'
for vals in $(kubectl get 2>&1 | sed -nE "$str"); do
    eval "$vals"
    [[ "$a" = 'deploy' ]] && a='dep'
    [[ "$a" = 'limits' ]] && a='lim'
    [[ "$a" = 'netpol' ]] && a='net'
    _KGCMDS+=("$c")
    _KGCMDS_AKA+=("${a:-$c}")
    _KGCMDS_HELP+=$(printf '    %-8s get %s' "$a" "$c")$'\n'
done
unset str vals c a

ku reset -q
