# shortyk8s

> Shortyk8s, shortyk8s, kubectl fan?<br/>
> Make me a command-line as fast as you can!

_**<groan!>**_

Shortyk8s provides simplified kubectl command lines through abbreviations and expansions of
containers, pods, nodes, namespaces, and contexts. Most commands shortyk8s builds up are reported to
help you understand the full kubectl command being executed. The guiding premise is that it should
only require the most basic of Unix tooling (e.g. bash, awk, sed, tr, etc.) and should not rely on
GNU-based options (i.e. should work on BSD flavors like OS X just as well as Ubuntu).

* [Preview](#preview)
* [Installing and Updating](#installing-and-updating)
* [Working with Contexts and Namespaces](#working-with-contexts-and-namespaces)
   * [Set Independent Context Terminal Sessions](#set-independent-context-terminal-sessions)
* [Working with Nodes and Pods](#working-with-nodes-and-pods)
   * [Executing Remote Actions](#executing-remote-actions)
* [Watching Events](#watching-events)
* [Executing Other Kubernetes Applications](#executing-other-kubernetes-applications)
* [Shell Prompt](#shell-prompt)
* [Everything Else](#everything-else)

---
## Preview

[![asciicast](https://asciinema.org/a/207788.png)](https://asciinema.org/a/207788?loop=1&autoplay=1)

---
## Installing and Updating

Because shorty8s only depends on Bash (v3 or greater) and standard Unix tools (awk, grep, sed,
etc.), installation is a simple matter of downloading and sourcing:

``` shell
$ curl https://raw.githubusercontent.com/bradrf/shortyk8s/master/shortyk8s.sh | bash -s -- install

$ source ~/.bash_profile
```

*Note:* Always read through scripts before executing them! In the above case, shortyk8s'
`kupdate --install` function will be invoked by the bottom portion of the script:

  * https://raw.githubusercontent.com/bradrf/shortyk8s/master/shortyk8s.sh

To get the latest version of shortyk8s, it provides a helper to automate that process for you:

``` shell
$ kupdate
```

---
## Working with Contexts and Namespaces

To begin, let shortyk8s show you what contexts you have configured in addition to highlighting the
one currently selected:

``` shell
$ k u

   NAME        CLUSTER     AUTHINFO    NAMESPACE
*  prod-apse1  prod-apse1  prod-apse1
   prod-euc1   prod-euc1   prod-euc1   api
   prod-usw1   prod-usw1   prod-usw1   database
```

Use partial matches to quickly switch into any other context or namespace:

``` shell
$ k u us web

   NAME        CLUSTER     AUTHINFO    NAMESPACE
   prod-apse1  prod-apse1  prod-apse1
   prod-euc1   prod-euc1   prod-euc1   api
*  prod-usw1   prod-usw1   prod-usw1   web

$ k u database

   NAME        CLUSTER     AUTHINFO    NAMESPACE
   prod-apse1  prod-apse1  prod-apse1
   prod-euc1   prod-euc1   prod-euc1   api
*  prod-usw1   prod-usw1   prod-usw1   database
```

### Set Independent Context Terminal Sessions

When working with several contexts, it's often frustrating to be constantly switching back and forth
or, worse, remembering to set the context option for each call. Shortyk8s simplifies this by allowing
you to leverage temporary "sessions" to switch the context only in the current terminal (without
affecting other terminals or shells). All `k` invocations will honor the current context and will
ensure the kubectl command is using the right cluster:

``` shell
$ k u -s eu api

   NAME        CLUSTER     AUTHINFO    NAMESPACE
   prod-apse1  prod-apse1  prod-apse1
*  prod-euc1   prod-euc1   prod-euc1   api        [temporary]
   prod-usw1   prod-usw1   prod-usw1   database

$ k u reset

   NAME        CLUSTER     AUTHINFO    NAMESPACE
   prod-apse1  prod-apse1  prod-apse1
   prod-euc1   prod-euc1   prod-euc1   api
*  prod-usw1   prod-usw1   prod-usw1   database
```

See also: [showing the current context in your shell prompt](#shell-prompt).

---
## Working with Nodes and Pods

To get "the lay of the land" in a context, try listing out all the pods grouped by their hosting
nodes:

``` shell
$ k ap .

NAMESPACE    NAME                      host-2 READY  STATUS   RESTARTS  AGE  IP           NODE
---                                    host-2
kube-system  node-exporter-4wz74       host-2 1/1    Running  0         4d   10.1.5.20  gke-host-1
kube-system  statsd-exporter-5ftz5     host-2 1/1    Running  0         8m   10.1.5.20  gke-host-1
twistlock    twistlock-defender-66mmc  host-2 1/1    Running  0         4d   10.1.5.20  gke-host-1
---                                    host-2
kube-system  node-exporter-smvxd       host-2 1/1    Running  0         4d   10.1.5.19  gke-host-2
kube-system  statsd-exporter-54csb     host-2 1/1    Running  0         3h   10.1.5.19  gke-host-2
twistlock    twistlock-defender-szxf5  host-2 1/1    Running  0         4d   10.1.5.19  gke-host-2
```

In most cases, when you're ready to inspect resources, it's usually a `get` of some kind. With
shortyk8s, that's unnecessary. For example, here's how you'd list out the running pods and the
images of the containers:

``` shell
$ k pi

kubectl get pods -ocustom-columns=NAME:.metadata.name\,STATUS:.status.phase\,IMAGES:.status.containerStatuses\[\*\].image
NAME                   STATUS   IMAGES
names-bcc8779b4-dtjl4  Running  tomdesinto/name-generator:latest
names-bcc8779b4-g9wv2  Running  tomdesinto/name-generator:latest
names-bcc8779b4-k8nlb  Running  tomdesinto/name-generator:latest
```

### Executing Remote Actions

Often, things just aren't that simple. Sometimes when debugging or evaluating problems in the field,
you need to inspect the state of the running containers. With shortyk8s, hopping in to one or
running the same command across all is easy and only requires knowledge of how to match the pods and
containers, no need to get the full names. Shortyk8s does that work for you!

To launch a REPL (read-eval-print-loop, aka a shell or a console) on a container, use shortyk8s'
caret matching to select a single pod. In the following case, we're using the default repl where
shortyk8s tries to find a good shell and sets up a simple prompt so we know what container we're in:

``` shell
$ k repl ^name
kubectl exec -ti names-bcc8779b4-dtjl4 -c names -- sh -c KREPL=brad\;TERM=xterm\;PS1=\"\$\(hostname\ -s\)\ \$\ \"\;export\ TERM\ PS1\;\ bash\ \|\|\ ash\ \|\|\ sh
root@names-bcc8779b4-dtjl4:/usr/src/app#
```

Note shortyk8s "marks" your process with your username ("brad" in this case). This is to allow
multiple repls in to the same container to know who "owns" others as shown in the process listing on
that container.

Once you know what kind of command to run remotely, it's common to want to execute the same thing
across the fleet of pods. In many cases, there is also a desire to run them concurrently but still
disambiguate any output that results so it's clear which pod is issuing the report. Shortyk8s makes
that trivial using its period matching along with asking for "-a" (asynchronous exec), "-p" (prefix
with container name), and "-v" (verbose reporting of the command lines):

``` shell
$ k each -apv .name ip addr show eth0

kubectl exec names-bcc8779b4-dtjl4 -c names -- sh -c ( ip addr show eth0) | awk -v h=`hostname -f`": " "{print h \$0}"
kubectl exec names-bcc8779b4-g9wv2 -c names -- sh -c ( ip addr show eth0) | awk -v h=`hostname -f`": " "{print h \$0}"
kubectl exec names-bcc8779b4-k8nlb -c names -- sh -c ( ip addr show eth0) | awk -v h=`hostname -f`": " "{print h \$0}"

names-bcc8779b4-dtjl4: 5: eth0@if62: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
names-bcc8779b4-dtjl4:     link/ether 16:3a:5b:55:79:78 brd ff:ff:ff:ff:ff:ff
names-bcc8779b4-dtjl4:     inet 10.1.0.57/16 scope global eth0
names-bcc8779b4-dtjl4:        valid_lft forever preferred_lft forever
names-bcc8779b4-k8nlb: 5: eth0@if60: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
names-bcc8779b4-k8nlb:     link/ether d6:92:1e:87:c2:ca brd ff:ff:ff:ff:ff:ff
names-bcc8779b4-k8nlb:     inet 10.1.0.55/16 scope global eth0
names-bcc8779b4-k8nlb:        valid_lft forever preferred_lft forever
names-bcc8779b4-g9wv2: 5: eth0@if59: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
names-bcc8779b4-g9wv2:     link/ether 96:ea:d5:ca:16:b8 brd ff:ff:ff:ff:ff:ff
names-bcc8779b4-g9wv2:     inet 10.1.0.54/16 scope global eth0
names-bcc8779b4-g9wv2:        valid_lft forever preferred_lft forever
```

---
## Watching Events

Kubernetes events can be a critical resource to help uncover why something changed or isn't working
properly. To that end, shortyk8s has some convenience wrappers around "tailing" the events in a
namespace both for general review but also for monitoring a deployment's progress.

Use the "evw" abbreviation to start watching all events. Note how shortyk8s will sort the events by
the most recently seen, both to show the historical events still in kubernetes as well as watching
for new ones:

``` shell
$ k evw

kubectl get ev --no-headers --sort-by=.lastTimestamp -ocustom-columns=TIMESTAMP:.lastTimestamp\,COUNT:.count\,KIND:.involvedObject.kind\,NAME:.involvedObject.name\,MESSAGE:.message
kubectl get ev --no-headers --sort-by=.lastTimestamp -ocustom-columns=TIMESTAMP:.lastTimestamp\,COUNT:.count\,KIND:.involvedObject.kind\,NAME:.involvedObject.name\,MESSAGE:.message --watch-on
ly

...
```

During a deployment, however, shortyk8s provides "kwatch" which will start watching events,
reporting changes to the pods and containers, as well as a periodic timestamp to show when "nothing"
is happening:

``` shell
$ kwatch
kubectl get ev --no-headers --sort-by=.lastTimestamp -ocustom-columns=TIMESTAMP:.lastTimestamp\,COUNT:.count\,KIND:.involvedObject.kind\,NAME:.involvedObject.name\,MESSAGE:.message --watch-on
ly
kubectl get pods -ocustom-columns=NAME:.metadata.name\,CONTAINERS:.status.containerStatuses\[\*\].name\,STATUS:.status.phase\,RESTARTS:.status.containerStatuses\[\*\].restartCount\,HOST_IP:.s
tatus.hostIP -w
NAME CONTAINERS STATUS RESTARTS HOST_IP
names-bcc8779b4-dtjl4 names Running 0 192.168.65.3
names-bcc8779b4-g9wv2 names Running 0 192.168.65.3
names-bcc8779b4-k8nlb names Running 0 192.168.65.3

>>> Sun Oct 28 10:57:28 PDT 2018 <<<
```

---
## Executing Other Kubernetes Applications

There are a lot of excellent tools to assist with a Kubernetes cluster. To ensure the tool is
running against the current context selected by shortyk8s--especially when using [temporary
sessions](#working-with-contexts-and-namespaces)--run it from shortyk8s' tilde marker:

``` shell
$ k ~stern job --tail 5
stern --context production -n web job --tail 1
...
```

Notice that shortyk8s is running the [stern](https://github.com/wercker/stern) logging helper with
the currently configured context and namespace. This expansion _assumes_ that the called application
supports these options (`--context` and `-n`). If you come across a tool that has different options,
please [open an issue](https://github.com/bradrf/shortyk8s/issues/new) and we'll add special
handling. For example, shortyk8s already does this for invoking
[helm](https://github.com/helm/helm):

``` shell
$ k ~helm list
helm --kube-context production list
NAME                            REVISION        UPDATED                         STATUS          CHART                                   APP VERSION     NAMESPACE
cluster-bootstrap               11              Fri Nov  9 16:18:13 2018        DEPLOYED        kubernetes-addons-0.1.11                1.0             default
```

---
## Shell Prompt

When working with many different kubernetes clusters, it's helpful to always represent the current
context in your shell prompt. This is especially true if you're making use of shortyk8s'
[sessions](#working-with-contexts-and-namespaces) to temporarily change a context for only one
terminal session. To that end, you can use the "kprompt" function in your bashrc file to highlight
the current context. Here's a simple illustration:

``` shell
$ PROMPT_COMMAND=kprompt

docker-for-desktop/shortyk8s
$ k u -s minikube
Temporarily switching to context "minikube" using namespace ""

minikube/shortyk8s[tmp]
$ k u reset

docker-for-desktop/shortyk8s
$
```

## Everything Else

Shortyk8s is capable of much more. To see the full list of commands and expansions available, refer
to usage reported for `k`:

``` shell
$ k
...
```

Notice there are helpers for applying configuration, showing wide or yaml output, in addition to
more details around various types of expansions.

---

Please don't hesitate to contact the author about any issues, questions, or requests for
enhancements:

[Brad Robel-Forrest \<brad+shortyk8s@bitpony.com\>](mailto:brad+shortyk8s@bitpony.com)
