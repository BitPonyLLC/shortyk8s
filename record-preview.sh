#!/bin/bash

CTX=docker-for-desktop
NS=shortyk8s

if [[ "$1" = '--prepare' ]]; then
    set -x
    cp ~/.kube/config ~/.kube/config.original
    cp simple_kube_config ~/.kube/config
    kubectl --context "$CTX" delete namespace "$NS"
    while kubectl --context "$CTX" get ns | grep "$NS"; do sleep 3; done
    exit
fi

if [[ "$1" != '--play-script' ]]; then
    exec asciinema rec -t 'ShortyK8s Preview' -c "$0 --play-script" \
         --overwrite shortyk8s-preview.asc
fi

. shortyk8s.sh

CLR=$(echo -e '\033c')
CMD=$(echo -e '\033[0;35m$ ')

function c()
{
    local wc=$(awk -F' ' '{print NF}' <<< "$@")
    echo -e "${CLR}\n# ${_KOK}$*${_KNM}\n"
    sleep $(( ${wc} / 3 + 1 )) # avg reader is 200 wpm (or 3 per second)
}

function r()
{
    local w=3
    if [[ "$1" = '-w' ]]; then shift; w=$1; shift; fi
    if [[ "$1" = '-e' ]]; then
        shift
        echo -n "${CMD}"
        printf '%q ' "$@"
        echo "${_KNM}"
    else
        echo "${CMD}$*${_KNM}"
    fi
    "$@"
    echo
    sleep $w
}

set +m # silence job creation messages

echo

c "First, let's see what kubectl configuration we're currently using..."
r k u

c "Excellent! I see we have a local Kubernetes cluster. Let's use that, but in the default namespace..."
r k u docker default

c "Hmm, I wonder what nodes are hosting this cluster?"
r k no

c "And what namespaces are in here?"
r k ns

c "Hey! Where's ours? I guess no one deployed it. Let's do that and switch to the new namespace..."
r -w 0.2 k a shortyk8s-names-app.yaml
r -w 4 k u "$NS"

c "Nice! So now we should see our containers starting up. Let's watch!"
r -w 0 k po -w &
sleep 3
{ kill %1 && wait; } 2>/dev/null # silence job termination message

c "Ok, so if they're ready, let's hop in to one and peek at its processes..."
r -w 5 k repl ^names ps aux

c "And we can run asynchronous commands across all of the pods, too!"
r k each -ap .names ip addr show eth0

c "Looks good to me! How about the service? Should we take a closer look at its details?"
r k d svc names

c "Seems alright. But, just to have some fun, let's start watching the events and delete a pod!"
r -w 0 k evw &
sleep 2
r -w 8 k del po ^names <<< y
{ kill %1 && wait; } 2>/dev/null

c "Cool. So, let's look at a view of the pods with their containers..."
r k pc

c "Better look at the logs, too... but let's use Stern (an external app) for that!"
r -w 0 k ~stern names & # stern watches forever
sleep 4
{ kill %1 && wait; } 2>/dev/null

c "Alrighty. That's just a few features ShortyK8s provides. Check out \`k\` usage for more!"
sleep 3
