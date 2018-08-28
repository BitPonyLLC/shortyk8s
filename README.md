# shortyk8s

> Shortyk8s, shortyk8s, kubectl fan?
> Make me a command-line as fast as you can!

_**<groan!>**_

Shortyk8s provides simplified kubectl command lines through abbreviations and expansions of
containers, pods, nodes, namespaces, and contexts. Most commands shortyk8s builds up are reported to
help you understand exactly what is being invoked.

* [Installing and Updating](#installing-and-updating)
* [Working with Contexts and Namespaces](#working-with-contexts-and-namespaces)
* [Working with Nodes and Pods](#working-with-nodes-and-pods)

---
## Installing and Updating

Because shorty8s only depends on Bash (v4.3 or greater) and standard Unix tools (awk, grep, sed,
etc.), installation should be a simple matter of downloading, saving, and sourcing:

``` shell
$ curl -o ~/.bashrc_shortyk8s https://raw.githubusercontent.com/bradrf/shortyk8s/master/shortyk8s.sh
$ echo 'source "${HOME}/.bashrc_shortyk8s"' >> ~/.bashrc
```

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

Leverage temporary "sessions" to switch the context only in the current terminal (without affecting
other terminals or shells):

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
