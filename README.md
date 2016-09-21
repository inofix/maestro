# maestro
Orchestrate any number of orchestras (i.e. config management environements).

![Maestro Logo](maestro.png "A thumbsketch of what this is all about..")

We started with cfengine to automate our server landscape,
we even configured and administrated a mesh network based on
embedded boxes based on linux/ulibc-busybox and cfengine
at the time it was the only automation solution
out there.

Today we have several customers with different configuration
management systems already in use. There is ansible, salt, and
even some homebrew solution, we currently use in different
projects on different customer sites and we also have debops
and cfengine for our servers in place. So we started to read
about reclass..

The central idea behind maestro is to build a knowledge
base (CMDB) that can be used by several configuration management
tools. It must be flexible enough to be split up as needed
and simple enough such that one can work on several projects
without having to think to much.

