#!/bin/bash

if [ -z "${BASH_VERSINFO}" ] || [ -z "${BASH_VERSINFO[0]}" ] || [ ${BASH_VERSINFO[0]} -lt 3 ]; then
    cat <<EOF

**********************************************************************
               Shortyk8s requires Bash version >= 3
**********************************************************************

EOF
fi

eval $(kubectl version --client -ojson | \
           awk -F\" '/major/{print "_kubectl_majver="$4} /minor/{print "_kubectl_minver="$4}')
if [[ $_kubectl_majver -lt 1 ]] || [[ $_kubectl_majver -eq 1 && $_kubectl_minver -lt 11 ]]; then
    cat <<EOF

**********************************************************************
               Shortyk8s requires Kubectl version >= 1.11
**********************************************************************

EOF
fi

# show only the names (different than -oname which includes the kind of resource as a prefix)
knames='--no-headers -ocustom-columns=:metadata.name'

_KPUB=()

# main entry point for all shortyk8s commands
function k()
{
    if [[ $# -lt 1 ]]; then
        local of=2
        [[ -t 1 ]] || of=1 # allow redirect into a pipe
        cat <<EOF >&$of

  Expansions:

    a <f>    apply --filename=<f>
    g        get
    d        describe
    del      delete
    ex       exec
    exi      exec -ti
    l        logs
    s <r>    scale --replicas=<r>
    draini   drain --delete-local-data --ignore-daemonsets
    sec [.]  get secret [<resource_name> [<secret_name>]]

${_KCMDS_HELP}
    pc       get pods and containers
    ni       get nodes and private IP addresses
    pi       get pods and container images

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
    ~<alt_command>      replace \`kubectl\` with \`<alt_command> --context $(shortyk8s_ctx) -n $(shortyk8s_kns)\`

  Examples:

    k po                       # => kubectl get pods
    k g .odd y                 # => kubectl get pods oddjob-2231453331-sj56r -oyaml
    k repl ^web @nginx ash     # => kubectl exec -ti webservice-3928615836-37fv4 -c nginx ash
    k l ^job --tail=5          # => kubectl logs bgjobs-1444197888-7xsgk --tail=5
    k s 8 dep web              # => kubectl scale --replicas=8 deployments webservice
    k ~stern ^job --tail 5     # => stern --context usw1 -n prod bgjobs-1444197888-7xsgk --tail 5
    k cp notes.txt ^web:/tmp   # => kubectl cp notes.txt web-55b79cccb9-cjv2s:/tmp -c web

EOF
        return 1
    fi

    local a c pod res caret atsign nc=false cmd=kubectl args=()
    local orig_ctx=$_K8S_CTX orig_ns=$_K8S_NS revert_ctx=false revert_ns=false

    if [[ " $@ " = ' all ' ]]; then
        # simple request to get all resources
        _kcmd kubectl get all
        return
    fi

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
            any|all) args+=(--all-namespaces);;
            d|desc) args+=(describe);;
            del) args+=(delete);;
            draini) args+=(drain --delete-local-data --ignore-daemonsets);;
            ev)
                _kget events
                nc=true
                ;;
            ex) args+=('exec');;
            exi) args+=('exec' -ti);;
            g) args+=(get);;
            l) args+=(logs);;
            ni)
                _kget nodes
                args+=('-ocustom-columns=NAME:.metadata.name,'`
                      `'CONDITIONS:.status.conditions[?(@.status=="True")].type,'`
                      `'INTERNAL_IP:.status.addresses[?(@.type=="InternalIP")].address')
                ;;
            pc)
                _kget pods
                args+=('-ocustom-columns=NAME:.metadata.name,'`
                      `'CONTAINERS:.status.containerStatuses[*].name,'`
                      `'READY:.status.containerStatuses[*].ready,'`
                      `'RESTARTS:.status.containerStatuses[*].restartCount,'`
                      `'HOST_IP:.status.hostIP')
                ;;
            pi)
                _kget pods
                args+=('-ocustom-columns=NAME:.metadata.name,STATUS:.status.phase,'`
                      `'IMAGES:.status.containerStatuses[*].image')
                ;;
            pn)
                _kget pods
                args+=('-ocustom-columns=NAME:.metadata.name,STATUS:.status.phase,'`
                      `'IMAGES:.status.containerStatuses[*].image')
                ;;
            s)
                if ! [[ "$1" =~ ^[[:digit:]]+$ ]]; then
                    echo "\"scale\" requires replicas (\"$1\" is not a number)" >&2
                    return 3
                fi
                args+=(scale --replicas=$1); shift
                ;;
            sec)
                _kgetsecret "$@"
                return
                ;;
            tn) args+=(top node);;
            tp) args+=(top pod --containers);;
            version)
                _kcmd kubectl version "$@"
                _kversioninfo "$@"
                return
                ;;
            w) args+=(-owide);;
            y) nc=true; args+=(-oyaml);;
            ,*) args+=($(_knamegrep nodes "${a:1}"));;
            .*) args+=($(_knamegrep pods "${a:1}"));;
            ^*) caret="$a";;
            @*) atsign="$a";;
            ~*)
                cmd=${a:1}
                case "$cmd" in
                    helm) _KSAFE=true; args+=(--kube-context "$(shortyk8s_ctx)");;
                    *) args+=(--context "$(shortyk8s_ctx)" -n "$(shortyk8s_kns)")
                esac
                ;;
            --context)
                # set one-time session context (so subcommands use it for lookups)
                _K8S_CTX=$1
                $revert_ns || _K8S_NS=''
                revert_ctx=true
                shift
                ;;
            -n|--namespace)
                # set one-time session namespace (so subcommands use it for lookups)
                _K8S_NS=$1
                $revert_ctx || K8S_CTX=''
                revert_ns=true
                shift
                ;;
            -w|-h*|-o*)
                args+=("$a")
                nc=true
                ;;
            *)
                found=false
                for i in ${!_KCMDS_AKA[@]}; do
                    if [[ "$a" = "${_KCMDS_AKA[$i]}" ]]; then
                        found=true
                        c="${_KCMDS[$i]}"
                        if [[ "$c" = shortyk8s_* ]]; then
                            args+=("$@")
                            if [[ -t 1 && "$a" == 'ap' ]]; then
                                "$c" "${args[@]}" | _kcolorize
                            else
                                "$c" "${args[@]}"
                            fi
                            # for now, all public helpers handle their own args...
                            return
                        fi
                        _kget "${_KCMDS[$i]}"
                        break
                    fi
                done
                $found || args+=("$a")
        esac
    done

    if [[ -n "${caret}" ]]; then
        _kgetpodcon "${caret}" "${atsign}" -m1 || return $?
        args+=("${pods[0]}")
        if [[ -n "${con}" && ! " ${args[@]} " =~ ' delete ' ]]; then
            args+=(-c "${con}")
        fi
    fi

    local fmtr argstr=" ${args[@]} "
    if [[ -t 1 && "${argstr}" =~ ' get ' ]]; then
        # stdout is a tty and using a simple get...
        fmtr='_kcolorize'
        $nc && fmtr+=' -nc'
    fi

    [[ " ${args[@]} " =~ ' delete ' || " ${args[@]} " =~ ' scale ' ]] && _KCONFIRM=true

    if [[ -n "$fmtr" ]]; then
        _kcmd "$cmd" "${args[@]}" | $fmtr
    else
        _kcmd "$cmd" "${args[@]}"
    fi
    local rc=$?

    $revert_ctx && _K8S_CTX=$orig_ctx
    $revert_ns && _K8S_NS=$orig_ns

    return $rc
}

_KPUB+=('')

_KPUB+=('a=ap;c=shortyk8s_allpods;d="report all pods grouped by nodes"')
function shortyk8s_allpods()
{
    if [[ $# -lt 1 ]]; then
        echo 'usage: allpods <node_match> [<namespace_match> [<pod_match>]]' >&2
        return 1
    fi
    local match='$8 ~ /'"$1"'/'
    [[ $# -gt 1 ]] && match+=' && $1 ~ /'"$2"'/'
    [[ $# -gt 2 ]] && match+=' && $2 ~ /'"$3"'/'
    # sort by node then by namespace then by name
    _kcmd kubectl get --all-namespaces pods -owide | \
        awk 'NR==1{print;next};'"${match}"'{print|"sort -b -k8 -k1 -k2"}' | \
        awk 'NR==1{print;next};{ x[$8]++; if (x[$8] == 1) print "---"; print}'
}

_KPUB+=('a=eachnode;c=shortyk8s_eachnode;d="run a command on each node"')
function shortyk8s_eachnode()
{
    local _keach_usage='eachnode [OPTIONS] <node_match>' _keach_resources='_knodeips'

    function _keach_prepare() {
        e_args+=(ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no '{}')
        if $interactive; then
            remote_cmd+='TERM=term'
            e_args+=(-t)
        fi
    }

    _keach "$@"
}

_KPUB+=('a=uptime;c=shortyk8s_uptime;d="get uptimes for all nodes (highest load at top)"')
function shortyk8s_uptime()
{
    shortyk8s_eachnode "$@" uptime | sort -rnk 11
}

_KPUB+=('a=mem;c=shortyk8s_mem;d="get memory usage for all nodes (smallest available at top)"')
function shortyk8s_mem()
{
    printf '%15s %s\n' '[megabytes]' '             total       used       free     shared    buffers     cached'
    shortyk8s_eachnode "$@" 'free -m | grep ^Mem' | sort -nk 5
}

_KPUB+=('a=df;c=shortyk8s_df;d="get file system usage for all nodes (smallest available at top)"')
function shortyk8s_df()
{
    printf '%-15s %s\n' 'Host' 'Filesystem              Size  Used Avail Use% Mounted on'
    shortyk8s_eachnode "$@" 'df -h / /var/lib/docker | sed 1d' | sort -rnk 6
}

_KPUB+=('')

_KPUB+=('a=u;c=shortyk8s_use;d="use a different context and/or namespace"')
function shortyk8s_use()
{
    local ctx ns code session=false

    if [[ $# -lt 1 ]]; then
        _kctxs -hl
        return
    fi

    if [[ "$1" =~ ^--?h ]]; then
        _ku_usage
        return 1
    fi

    if [[ "$1" = 'reset' ]]; then
        rm -f "$_KPROMPT_FN" "$_KSESSION_FN"
        unset _K8S_CTX _K8S_NS
        [[ "$2" = '-q' ]] || shortyk8s_use
        return
    fi

    if [[ "$1" = '-s' ]]; then
        session=true
        shift
    fi

    [[ -n "${_K8S_NS}" ]] && session=true

    if [[ $# -eq 1 ]]; then
        # try namespace match first, then context
        ns=$(_knamegrep ns -m1 "$1")
        if [[ -z "${ns}" ]]; then
            ctx=$(_kctxgrep -m1 "$1")
            if [[ -z "${ctx}" ]]; then
                echo 'no match found' >&2
                return 2
            fi
            ns=$(_kctxs | awk '$1=="'"${ctx}"'"{print $4}' )
        else
            ctx=$(shortyk8s_ctx)
        fi
    elif [[ $# -eq 2 ]]; then
        # switch to context and namespace
        ctx=$(_kctxgrep -m1 "$1")
        if [[ -z "$ctx" ]]; then
            echo 'no match found' >&2
            return 3
        fi
        ns=$(kubectl --context "$ctx" get ns $knames | egrep -m1 "$2")
        if [[ -z "$ns" ]]; then
            echo 'no match found' >&2
            return 4
        fi
    else
        _ku_usage
        return 5
    fi

    if $session; then
        rm -f "$_KPROMPT_FN"
        _K8S_CTX=$ctx
        _K8S_NS=$ns
        cat <<EOF > "$_KSESSION_FN"
_K8S_CTX='${_K8S_CTX}'
_K8S_NS='${_K8S_NS}'
EOF
    else
        shortyk8s_use reset -q
        kubectl config set-context "$ctx" --namespace "$ns" | \
            sed 's/\.$/ using namespace "'"${ns}"'"./'
        kubectl config use-context "$ctx"
    fi

    shortyk8s_use
}

_KPUB+=('a=prompt;c=shortyk8s_prompt;d="provide info for shell prompt"')
function shortyk8s_prompt()
{
    # Large configs can take hundreds of milliseconds for kubectl config to process which will cause
    # a grossly slow prompt. Using a file to store the value to allow caller to invoke in subshell.
    local prompt_ts=$(_kfilets "$_KPROMPT_FN")
    local config_ts=$(_kfilets "${KUBECONFIG:-${HOME}/.kube/config}")
    if [[ $prompt_ts -le $config_ts ]]; then
        prompt="$*$(shortyk8s_ctx)/$(shortyk8s_kns)"
        [[ -n "$_K8S_CTX" ]] && prompt+='[tmp]'
        echo "$prompt" > "$_KPROMPT_FN"
    else
        prompt="$(cat "$_KPROMPT_FN")"
    fi
    echo "$prompt"
}

_KPUB+=('a=ctx;c=shortyk8s_ctx;d="report current context"')
function shortyk8s_ctx()
{
    if [[ -n "${_K8S_CTX}" ]]; then
        echo "${_K8S_CTX}"
    else
        kubectl config current-context
    fi
}

_KPUB+=('a=kns;c=shortyk8s_kns;d="report current namespace"')
function shortyk8s_kns()
{
    if [[ -n "${_K8S_NS}" ]]; then
        echo "${_K8S_NS}"
    else
        kubectl config get-contexts | awk '$1 == "*" {print $5}'
    fi
}

_KPUB+=('a=eachctx;c=shortyk8s_eachctx;d="invoke action for matching context names"')
function shortyk8s_eachctx()
{
    local _keach_usage='eachctx [OPTIONS] <context_match>' _keach_resources='_kctxgrep'

    function _keach_prepare() {
        if $interactive; then e_args+=(bash -ic); else e_args+=(bash -c); fi
        prefix_cmd='{}'
        remote_cmd=". ${BASH_SOURCE[0]};ctx='{}';${remote_cmd}"
    }

    _keach "$@"
}

_KPUB+=('')

_KPUB+=('a=repl;c=shortyk8s_repl;d="execute an interactive REPL on a container"')
function shortyk8s_repl()
{
    if [[ $# -lt 1 ]]; then
        cat <<EOF >&2
usage: repl <pod_match> [@<container_match>] [<command> [<args>...]]

  Default container match will use the pod match.

  Default command will try to determine the best shell available (bash || ash || sh).

EOF
        return 1
    fi

    local cmd pods con cnt e_args=('exec' -ti)

    _KSTATUS=Running _kgetpodcon "$1" "$2" -m1 || return $?
    shift $cnt

    e_args+=("${pods[0]}")
    [[ -n "${con}" ]] && e_args+=(-c "${con}")

    if [[ $# -eq 0 ]]; then
        cmd=' bash || ash || sh'
    else
        cmd=" $*"
    fi

    e_args+=(-- sh -c "KREPL=${USER};TERM=xterm;PS1=\"\$(hostname -s) $ \";export TERM PS1;${cmd}")
    _kcmd kubectl "${e_args[@]}"
}

_KPUB+=('a=each;c=shortyk8s_each;d="run commands on one or more containers"')
function shortyk8s_each()
{
    local _keach_usage='each [OPTIONS] <pod_match> [@<container_name>]'
    local con

    function _keach_resources() {
        local pods
        _KSTATUS=Running _kgetpodcon "$1" "$2" || return $?
        resources=("${pods[@]}")
        match_shift=$cnt
    }

    function _keach_prepare() {
        local shell_cmd=(/bin/sh -c)
        _KNOOP=true _kcmd kubectl
        e_args+=($_KCMD exec '{}')
        [[ -n "$con" ]] && e_args+=(-c "$con")
        if $interactive; then
            shell_cmd=('TERM=term' "${shell_cmd[@]}")
            e_args+=(-ti)
        fi
        e_args+=(-- "${shell_cmd[@]}")
    }

    _keach "$@"
}

_KPUB+=('a=watch;c=shortyk8s_watch;d="watch events and pods concurrently"')
function shortyk8s_watch()
{
    ( # run in a subshell to trap control-c keyboard interrupt for cleanup of bg procs
        shortyk8s_evw --new &
        while true; do sleep 10; echo; echo ">>> $(date) <<<"; done &
        trap 'kill %1 %2' EXIT
        k pc -w
    )
}

_KPUB+=('a=evw;c=shortyk8s_evw;d="watch events sorted by most recent report"')
function shortyk8s_evw()
{
    local new=false
    if [[ "$1" = '--new' ]]; then
        shift; new=true
    fi
    local args=(get ev --no-headers --sort-by=.lastTimestamp \
        -ocustom-columns='TIMESTAMP:.lastTimestamp,COUNT:.count,KIND:.involvedObject.kind,'`
                        `'NAME:.involvedObject.name,MESSAGE:.message' "$@")
    # kubectl get ev --watch ignores `sort-by` for the first listing
    $new || _kcmd kubectl "${args[@]}"
    _kcmd kubectl "${args[@]}" --watch-only
}

_KPUB+=('a=report;c=shortyk8s_report;d="report all interesting resources"')
function shortyk8s_report()
{
    local c res ns=$(shortyk8s_kns)
    local ign='all|events|clusterroles|clusterrolebindings|customresourcedefinition|namespaces|'`
             `'nodes|persistentvolumeclaims|storageclasses'
    _kapi_resources
    for vals in "${_KAPI_RESOURCES[@]}"; do
        eval "${vals}"
        if [[ "$c" = 'persistentvolumes' ]]; then
            res=$(_kcmd kubectl get "$c" | awk 'NR==1{print};$6 ~ /^'"${ns}"'/{print}')
        else
            res=$(_kcmd kubectl get "$c" 2>&1)
        fi
        [[ $? -eq 0 ]] || continue
        [[ $(echo "$res" | wc -l ) -lt 2 ]] && continue
        cat <<EOF

----------------------------------------------------------------------
$(upcase "$c")

${res}
EOF
    done

    unset _KAPI_RESOURCES
}

_KPUB+=('')

_KPUB+=('a=update;c=shortyk8s_update;d="get the latest version of shortyk8s"')
function shortyk8s_update()
{
    if ! which git >/dev/null 2>&1; then
        echo 'Git is required for updating (or installing)' 2>&1
        return 1
    fi

    if [[ -d "${_KHOME}/.git" ]]; then
        git -C "${_KHOME}" pull || return
    else
        git clone -q https://github.com/bradrf/shortyk8s.git "${_KHOME}" || return
    fi
}

######################################################################
# PRIVATE - internal helpers

_KHOME="${HOME}/.shortyk8s"

_KSESSIONS_DIR="${_KHOME}/sessions"
[[ -d "$_KSESSIONS_DIR" ]] || mkdir -p "$_KSESSIONS_DIR"

_KHI=$(echo -e '\033[30;43m') # black fg, yellow bg
_KOK=$(echo -e '\033[01;32m') # bold green fg
_KWN=$(echo -e '\033[01;33m') # bold yellow fg
_KER=$(echo -e '\033[01;31m') # bold red fg
_KNM=$(echo -e '\033[00;00m') # normal

_KCOLORIZE='
BEGIN {
    OK = "'"${_KOK}"'"
    WN = "'"${_KWN}"'"
    ER = "'"${_KER}"'"
    NM = "'"${_KNM}"'"
}

NR == 1 {
    for (i = 1; i <= NF; ++i) {
        if (match($i, /READY/)) {
            ready_col = i
            $ready_col = NM $ready_col NM
        } else if (match($i, /STATUS/)) {
            status_col = i
            $status_col = NM $status_col NM
        } else if (match($i, /RESTART/)) {
            restart_col = i
            $restart_col = NM $restart_col NM
        }
    }
    print
}

NR > 1 {
    if (ready_col > 0) {
        n = split($ready_col, a, "/")
        if (n == 2) {
            if (a[1] == a[2]) {
                $ready_col = OK $ready_col NM
            } else {
                $ready_col = ER $ready_col NM
            }
        } else {
            $ready_col = NM $ready_col NM
        }
    }
    if (status_col > 0) {
        if (match($status_col, /Disabled|Pending|Creating|Init/)) {
            $status_col = WN $status_col NM
        } else if (match($status_col, /NotReady/)) {
            $status_col = ER $status_col NM
        } else if (match($status_col, /Running|Ready|Active|Succeeded|Completed|true/)) {
            $status_col = OK $status_col NM
        } else {
            $status_col = ER $status_col NM
        }
    }
    if (restart_col > 0) {
        # split array will not be in order, so look for anomolies and highlight whole entry
        split($restart_col, cnts, ",")
        cnt = 0
        for (k in cnts) {
            v = cnts[k]
            if (v > cnt) cnt = v
        }
        if (cnt > 10)
            $restart_col = ER $restart_col NM
        else if (cnt > 0)
            $restart_col = WN $restart_col NM
        else
            $restart_col = NM $restart_col NM
    }
    print
}
'

function _kcolorize()
{
    if [[ "$1" = '-nc' ]]; then
        awk "${_KCOLORIZE}"
    else
        awk "${_KCOLORIZE}" | column -xt
    fi
}

# load these at source time to reflect running state in memory, not state of the repo
_KMAJVER=1
_KMINVER=0
_KPATVER=$(TZ=UTC git -C "${_KHOME}" log -1 --format=%cd --date='format-local:%Y%m%d%H%M')
_KGITSTS=$(git -C "${_KHOME}" status --porcelain --untracked-files=no 2>/dev/null)
_KGITCMT=$(git -C "${_KHOME}" log -1 --format=%H)

function _kversion()
{
    echo "v${_KMAJVER}.${_KMINVER}.${_KPATVER}"
}

function _kversioninfo()
{
    local state
    if [[ " $@ " =~ ' --short' ]]; then
        echo "Shortyk8s Version: $(_kversion)"
    else
        if [[ -z "$_KGITSTS" ]]; then state='clean'; else state='dirty'; fi
        cat <<EOF
Shortyk8s Version: version.Info{Major:"${_KMAJVER}", Minor:"${_KMINVER}", \
GitVersion:"$(_kversion)", GitCommit:"${_KGITCMT}", GitTreeState:"${state}", \
BashVersion:"${BASH_VERSION}", Platform:"$(uname -s -m)"}
EOF
    fi
}

function _kapi_resources()
{
    # use cached version of api-resources as this requires a query to the cluster
    local fn="${_KSESSIONS_DIR}/api_resources.${_kubectl_majver}_${_kubectl_minver}"
    if [[ -s "${fn}" ]]; then
        _KAPI_RESOURCES=($(cat "${fn}"))
    else
        local str='NR==1{i=index($0,"SHORTNAMES")}; NR>1{a=substr($0,i,1);if(a!=" "){a=$2};print "c="$1";a="a}'
        _KAPI_RESOURCES=($(kubectl api-resources --cached=true | awk "$str" | tee "${fn}"))
    fi
}

function _ksessions_set()
{
    _KPID=$1
    _KSESSION_FN="${_KSESSIONS_DIR}/${_KPID}_session.sh"
    [[ -r "$_KSESSION_FN" ]] && source "$_KSESSION_FN"
    _KPROMPT_TS=0
    _KPROMPT_FN="${_KSESSIONS_DIR}/${_KPID}_prompt.sh"
}

function _ksessions_clean()
{
    local fn pid
    for fn in "${_KSESSIONS_DIR}/"*_prompt.sh; do
        pid=$(basename "${fn}" | tr -dC '[:digit:]')
        [[ -z "${pid}" ]] || kill -0 "${pid}" 2>/dev/null || \rm -f "${fn}"
    done
}

function _kfilets()
{
    date -r "$1" +%s 2>/dev/null || echo 0
}

function _kjointmpl()
{
    echo '{{range $i, $e := '"${1}"'}}{{if $i}},{{end}}{{$e.'"${2}"'}}{{end}}'
}

function _ktabletmpl()
{
    local tmpl q s=''
    tmpl='{{println "'"${1}"'"}}{{range .items}}'; shift
    for q in "$@"; do
        [[ "$q" = '{{'* ]] || q="{{${q}}}"
        tmpl+="${s}${q}"
        s=$'\t'
    done
    tmpl+='{{println}}{{end}}'
    echo "-ogo-template=$tmpl"
}

# internal helper to support lookup of item or items as a go-template
function _kitemtmpl()
{
    echo "-ogo-template={{if .items}}{{range .items}}$1{{end}}{{end}}{{if not .items}}$1{{end}}"
}

# internal helper to list all internal node IPs
function _knodeips()
{
    local names=()
    [[ $# -gt 0 ]] && \
        names=($(_KQUIET=true _kcmd kubectl get nodes --show-labels --no-headers | \
                     awk "/$*/{print \$1}"))
    _kcmd kubectl get nodes "${names[@]}" \
          "$(_kitemtmpl '{{range .status.addresses}}{{if eq .type "InternalIP"}}{{.address}} {{end}}{{end}}')"
}

# internal helper to show contexts without the first column, indicating session changes, optionally
# highlighting current context
function _kctxs()
{
    local hl='1' ctx=$(shortyk8s_ctx)
    if [[ "$1" = '-hl' ]]; then
        shift
        # print highlighted if "selected"...
        hl="{if(\$1==\"${ctx}\"){print \"${_KHI}\" \$0 \"${_KNM}\"}else{print}}"
    fi
    # remove first column...
    code+='sub(/^CURRENT *|^\*? */,"",$0);'
    # optionally replace the namespace...
    [[ -n "${_K8S_NS}" ]] && code+='if($1=="'"${ctx}"'"){$4="'"${_K8S_NS}"'";$5="[temporary]"};'
    kubectl config get-contexts | awk "{${code};print}" | column -xt | awk "${hl}"
}

function _ku_usage()
{
    cat <<EOF >&2
usage: use [-s] <namespace>
       use [-s] <context> <namespace>
       use reset

  Use "-s" to start a "session" that only changes context or namespace for this terminal.  The
  session is "sticky" until a "reset" is invoked in the same terminal to revert back to using the
  current configured context.

EOF
}

# internal helper to match a pod and optionally a container
# (intentionally exposes `pod`, `con`, `cnt` variables for caller;
#  status value is number of args to shift for caller)
function _kgetpodcon()
{
    local pod_match=$1; shift
    local container_match=$1; shift
    local grep_args=($@)

    if [[ "${pod_match::1}" = '^' ]] || [[ "${pod_match::1}" = '.' ]]; then
        pod_match="${pod_match:1}"
    fi

    # split on colon to allow POD:PATH variables (for logs)
    local pod_match_a
    IFS=: read -ra pod_match_a <<< "${pod_match}"
    pod_match="${pod_match_a[0]}"

    # expose the `pods` array to caller
    pods=($(_knamegrep pods "${grep_args[@]}" "${pod_match}"))
    if [[ ${#pods[@]} -lt 1 ]]; then
        echo 'no match found' >&2
        return 11
    fi

    if [[ "${container_match::1}" = '@' ]]; then
        # expose the `con` value to caller
        con="$(_kcongrep "${pods[0]}" -m1 "${container_match:1}")"
        if [[ -z "${con}" ]]; then
            echo 'no match found' >&2
            return 22
        fi
        # expose the `cnt` value to caller (for argument shifting)
        cnt=2
    else
        # try finding a matching container based on the first pod
        con="$(_kcongrep "${pods[0]}" -m1 "${pod_match%%-*}")"
        cnt=1
    fi

    if [[ ${#pod_match_a[@]} -gt 1 ]]; then
        # append the path to the pods found
        local pod orig_pods=("${pods[@]}")
        pods=()
        for pod in "${orig_pods[@]}"; do
            pods+=("${pod}:${pod_match_a[1]}")
        done
    fi
}

# internal helper to list matching context names
function _kctxgrep()
{
    kubectl config get-contexts -oname | egrep "$@"
}

# internal helper to list matching pod names
function _knamegrep()
{
    local res=$1; shift
    local args=(kubectl get $knames)
    if [[ "$res" = po* && -n "$_KSTATUS" ]]; then
       args+=("--field-selector=status.phase=${_KSTATUS}")
    fi
    _KQUIET=true _kcmd "${args[@]}" "$res" | egrep "$@"
}

# internal helper to list matching container names for a given pod
function _kcongrep()
{
    local pod=$1; shift
    _KQUIET=true _kcmd kubectl get pod "${pod}" -oyaml -o'jsonpath={.spec.containers[*].name}' \
        | tr ' ' '\n' | egrep "$@"
}

# internal helper to provide get unless another action has already been requested
function _kget()
{
    # FIXME: once Bash 4 is more widely in use (*cough*OS X*cough*) leverage local -n
    if [[ " ${args[@]} " =~ ' get '      || \
          " ${args[@]} " =~ ' create '   || \
          " ${args[@]} " =~ ' describe ' || \
          " ${args[@]} " =~ ' edit '     || \
          " ${args[@]} " =~ ' delete '   || \
          " ${args[@]} " =~ ' scale ' ]]; then
        args+=("$@")
    else
        args+=(get "$@")
    fi
}

# internal helper to list secrets available or decode one
function _kgetsecret()
{
    local args=(_kcmd kubectl get secret)
    if [[ $# -lt 1 ]]; then
        ${args[@]} -ogo-template='{{range .items}}{{$n := .metadata.name}}{{range $k, $v := .data}}{{println $n $k}}{{end}}{{end}}'
    elif [[ $# -eq 1 ]]; then
        ${args[@]} "$1" -ogo-template='{{range $k, $v := .data}}{{println $k}}{{end}}'
    elif [[ $# -eq 2 ]]; then
        ${args[@]} "$1" -ogo-template='{{index .data "'"$2"'"}}' | base64 -D
    else
        return 1
    fi
}

# internal helper to execute "each" commands using common options and behavior
function _keach()
{
    local opt async=false interactive=false prefix=false quiet=true

    OPTIND=1

    while getopts 'aipv' opt; do
        case $opt in
            a) async=true;;
            i) interactive=true;;
            p) prefix=true;;
            v) quiet=false;;
            \?) return 2;;
        esac
    done

    shift "$((OPTIND-1))"

    if [[ $# -gt 1 ]]; then
        local match_shift=1
        local resources
        if declare -F _keach_resources >/dev/null; then
            # caller defined "closure" to get the resources
            _keach_resources "$@"
        else
            resources=($(_KQUIET=$quiet "${_keach_resources}" "$1"))
        fi
        shift $match_shift
    fi

    if [[ $# -lt 1 ]]; then
        cat <<EOF >&2

usage: ${_keach_usage} <command> [<arguments>...]

        -a    run the command asynchronously
        -i    run the command interactive with a TTY allocated
        -p    prefix the command output with a name
        -v    show the command line used

EOF
        return 1
    fi

    local remote_cmd="$*" prefix_cmd='`hostname -s`' x_args=() e_args=()

    _keach_prepare

    unset _keach_usage _keach_resources _keach_prepare # remove "closures"

    $prefix && remote_cmd="( ${remote_cmd} ) 2>&1 | awk -v h=\"${prefix_cmd}:\" '{print h,\$0}'"
    $quiet || x_args+=(-t)
    $async && x_args+=(-P ${#resources[@]})
    x_args+=(-I'{}' -n1)

    xargs "${x_args[@]}" -- "${e_args[@]}" -- "$remote_cmd" <<< "${resources[@]}"
}

# internal helper to build a command line (setting context/namespace when appropriate)
function _kcmd()
{
    local cmd=$1; shift
    local args=("$@")
    local rc

    if ! $_KSAFE && [[ ! " ${args[@]} " =~ ' --context' ]]; then
        if [[ ! " ${args[@]} " =~ ' --namespace' && \
                  ! " ${args[@]} " =~ ' -n ' && \
                  ! " ${args[@]} " =~ ' --all-namespaces ' ]]; then
            [[ -n "${_K8S_NS}" ]] && args=(-n "${_K8S_NS}" "${args[@]}")
        fi
        [[ -n "${_K8S_CTX}" ]] && args=(--context "${_K8S_CTX}" "${args[@]}")
    fi

    if [[ ${#args[@]} -gt 0 ]]; then
        _KCMD="${cmd}$(printf ' %q' "${args[@]}")"
    else
        _KCMD=$cmd
    fi

    $_KNOOP && return
    $_KQUIET || echo "${_KCMD}" >&2

    if $_KCONFIRM; then
        read -r -p 'Are you sure? [y/N] ' res
        case "$res" in
            [yY][eE][sS]|[yY]) : ;;
            *) return 11
        esac
    fi

    "$cmd" "${args[@]}"
    _kcmd_reset $?
}

# internal helper to reset temporary overrides for _kcmd()
function _kcmd_reset()
{
    _KNOOP=false
    _KQUIET=false
    _KCONFIRM=false
    _KSAFE=false
    _KSTATUS=''
    return $1
}

_kcmd_reset 0

# first, preload the list of known kubectl get commands
_KCMDS=()
_KCMDS_AKA=()
_KCMDS_HELP=''
_kapi_resources
for vals in "${_KAPI_RESOURCES[@]}"; do
    eval "$vals"
    a=${a/%,*/} # use only first option in a comma list
    [[ "$a" = 'deploy' ]] && a='dep'
    [[ "$a" = 'limits' ]] && a='lim'
    [[ "$a" = 'netpol' ]] && a='net'
    _KCMDS+=("$c")
    _KCMDS_AKA+=("${a:-$c}")
    _KCMDS_HELP+=$(printf '    %-8s get %s' "$a" "$c")$'\n'
done

# then, add our own "public" helpers
for vals in "${_KPUB[@]}"; do
    if [[ -z "$vals" ]]; then
        _KCMDS_HELP+=$'\n' # add a spacer
        continue
    fi
    eval "$vals"
    _KCMDS+=("$c")
    _KCMDS_AKA+=("${a:-$c}")
    _KCMDS_HELP+=$(printf '    %-8s %s' "$a" "$d")$'\n'
done

unset vals c a d _KPUB _KAPI_RESOURCES

################################################################################
# handle when script is executed

if [[ "$(basename -- "$0")" = 'shortyk8s.sh' ]]; then
    if [[ "$1" = 'install' ]]; then
        shortyk8s_update --install || exit
        cat <<EOF

Shortyk8s has been downloaded and is ready for use.

If you're a Bash user, have shortyk8s sourced from your init file like this:

  $ echo ". '${_KHOME}/shortyk8s.sh'" >> "${HOME}/.bashrc"
  $ source "${HOME}/.bashrc"

If you use any other shell (e.g. fish, ksh, tcsh, zsh, etc.), or if you don't want to have shortyk8s
pollute your shell namespace, it can be run as a script:

  $ ${_KHOME}/shortyk8s.sh

And then try this to show the current kubectl configuration contexts:

  $ k u

...or...

  $ ${_KHOME}/shortyk8s.sh u

EOF
    else
        _ksessions_set $PPID
        k "$@"
        exit $!
    fi
elif [[ "$0" = "bash" && "$1" == 'install' ]]; then
    # invoked from curl piped to bash (README instructions)
    shortyk8s_update --install
fi

[[ -z "$_KSESSION_FN" ]] && _ksessions_set $$
_ksessions_clean

:
