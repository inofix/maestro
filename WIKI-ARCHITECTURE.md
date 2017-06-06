# The Basic Concepts #

## Overview ##

The central part of our host management solution is [maestro](https://github.com/inofix/maestro)[^1](https://github.com/inofix/maestro/wiki/Architecture/#footnote) (maestro.sh for the moment, but will probably be maestro.py one day).

Maestro gets parameterized by one or more [reclass](http://reclass.pantsfullofunix.net/)[^2](https://github.com/inofix/maestro/wiki/Architecture/#footnote) backends.

It supports a second backend type, which simply consists of plain config files, that can be stored in a repository (e.g. VCS). (See Pic. 1 for a visualization.)

To get the parameters set, actions taken or config files copied to the respective host(s), maestro uses a third party configuration management solution.

>> So why bother with this extra layer, as everything could also be done without maestro and/or reclass?

> Well, the solution here provides a common interface to multi project, heterogenous, situations: even if more than one configuration management solution is at place or when several projects have to be managed, with the little extra effort done once, many details can be managed quickly with one interface and on top the projects/hosts become comparable and sharable!


            BACKEND0 (meta-data):              BACKEND1 (concrete-data):
                ,---------.                         ,---------.
               |`----------'--.                    |`----------'--.
               |  reclass0 |---'--.                |  confix0  |---'--.
               |           |s1 |---'               |           |1  |---'<--.
                `---------'    |.. |                `---------'    |.. |   |
                    `---------'    |                    `---------'    |   |
                        \---------'                     /   `---------'    |
                          \| _______________________  |/                   |
                           ,'                       `.                     |
           CONNECTOR:     (       m a e s t r o       )                    |
                           `._______________________,'\                    |
                              /     /      |   _        \                  |
                             V     V   _   V  |C| ____    \                |
                         __________   | | ___ |F||Temp|     \              |
                        (=========='  |d||   ||E||late|       \            |
       CONFIGURATION    |\ Ansible |  |e|| S ||n||    |        |(plain     |
       MANAGEMENT:      || \       |  |b|| a ||g|| j2 | _____  | files)   /
                        ||  |~~~~~ |  |o|| l ||i|| .. || ... | |        /
                        ||  |~~~~~ |  |p|| t ||n||    || ... | |      /
                        ||  |~~~~~ |  |s||   ||e||    || ... | |    /
                        (|  |______| .|_||___||_||____||_____| |  /
                         \  |                                /  /
                           \| |      |      |  |   |       /  /
                              |      |      |  |   |     /  /
                              V      V      V  V   V    V /
        MACHINES:         [ host0 ][ host1 ] ... [ hostN ]

**Pic. 1:** A visualization of how the elements fit together

We plan to provide yaml and json interfaces to maestro, which will then be visualized on the web-browser by javascript and html.


## Parameters in Classes and Nodes ##

[Maestro](https://github.com/inofix/maestro)[^1](https://github.com/inofix/maestro/wiki/Architecture/#footnote) uses [Reclass](http://reclass.pantsfullofunix.net/)[^2](https://github.com/inofix/maestro/wiki/Architecture/#footnote) to store the host parameters.

Reclass is organized in classes and nodes, where nodes may reference classes and classes may reference other classes. Classes can be seen as groups of nodes.

Please find here a simple overview of how the classes can be structured with reusability in mind -- this is pretty much the way they are structured in all of our projects. In fact we are using a public repo called [commo-inv](https://github.com/inofix/common-inv/)[^3](https://github.com/inofix/maestro/wiki/Architecture/#footnote) both to show an example structure of a backend and for all the meta data that is not confidentail and generic (for example the application classes).


                  C L A S S   O R G A N I Z A T I O N
                  ===================================


                      admin
            location
                        ^
               ^ ^      |                 service -----> app (application)
               |  \     |
               |   \    |                   ^
               |                           /
               |     project
               |                       role
               |           ^
               |            \          ^
               |             \       /

              host <--------- (Node)

                                  |
                                  |
                                  v

                               manager

**Pic. 2:** Top-level classes and their relation to each other and to the 'node'

Ideally the actual parameters are namespaced, i.e. preceeded with the class tree names they are initially defined in, either stored as dictionaries or in flat form, e.g.:
* app[apache][config_files]
* app__apache__config_files

As the parameters will often be overwritten in other classes, it is not always easy to find them. Maestro has several search options for this case. But to render life less complex, there is more one can do.

There are two ways how the classes themselfes can be grouped. The first, and explicit one, is by the directory hierarchy in the file system (resp. in the repository). The second, and only implicit one, is by usage.

The explicit hierarchy can be seen in the example of the different applications in the app directory, where a certain version of an application relies on the application class etc., e.g. (the later relies on the earlier):
* classes/app/java/init.yml
* classes/app/java/jre/init.yml
* classes/app/java/jre/8.yml

Pic. 2 shows the ideal usage and thus the implicit relation of the classes. As mentioned, this is only an ideological, implicit, concept, without any final structure -- a recommended split into "inner" and "outer" classes, where the inner classes make use of the outer classes and not vice versa.

With other words: wherever possible, use the classes in such a way that inner and outer classes emerge, i.e. by reference and by letting the outer classes define parameters and the inner classes consume resp. overwrite them. Thus the outer classes become more generic and can easily be shared between projects or even publicly.

As these "outer"-parameters have a better visibility, they are the first ones you want to use in your configuration management engine tasks -- while you might want to avoid the parameters defined (and used) in the inner classes altogether in your tasks, as those might not be available in your next project.



# Configuration Management #

## Integration ##

[Maestro](https://github.com/inofix/maestro)[^1](https://github.com/inofix/maestro/wiki/Architecture/#footnote) primarily uses [Ansible](https://www.ansible.com/)[^4](https://github.com/inofix/maestro/wiki/Architecture/#footnote) to get tasks done. Ansible is very simple and has a minimum of requirements on the client side.

Maestro has Ansible fully integrated with the [common-playbooks](https://github.com/inofix/common-playbooks)[^5](https://github.com/inofix/maestro/wiki/Architecture/#footnote) repository. This repository is actually thought to just store the plain playbooks which can then include whatever role you want (e.g. some third-party [debops](https://debops.org/)[^6](https://github.com/inofix/maestro/wiki/Architecture/#footnote) roles are already used).

It is also possible to use more than one playbook repository at the same time, just by adding the working directory to the maestro config.

On some of our projects we have integrated [salt](https://saltstack.com/)[^7](https://github.com/inofix/maestro/wiki/Architecture/#footnote) too, this is not a direct integration yet though. Currently we defined transformation rules, but as salt is able to use a reclass backend, it would not be too hard to support an alternative CM.

An old project that was started with [cfengine2](https://cfengine.com/)[^8](https://github.com/inofix/maestro/wiki/Architecture/#footnote) was also integrated with maestro, here just the config files are organized via maestro the old code continues to work with them..

## Ansible Playbooks ##

For the moment we have this interface between maestro and some ansible roles ready for the public eye: [common-playbooks](https://github.com/inofix/common-playbooks)[^5](https://github.com/inofix/maestro/wiki/Architecture/#footnote).

The maestro classes become ansible groups and can be used in the playbooks. It is recommended to only use the groups in the playbooks and base tests in the roles on parameters.

Further, as mentioned above, the ideal would be to only use parameters defined in [commo-inv](https://github.com/inofix/common-inv/)[^3](https://github.com/inofix/maestro/wiki/Architecture/#footnote) (i.e. admin, app, host, location, and manager) in the playbooks. Those parameters can then be mapped to the parameters used in the roles.

A bit more translation work for the sake of interchangeability, reusability, and comparability. 

# Visualization #

The json/yaml interface can easily be consumed (and even written) with the web-browser. We actually plan to provide a portlet for [liferay](https:www.liferay.com)[^9](https://github.com/inofix/maestro/wiki/Architecture/#footnote), as the portal already provides the permission management and it is one of our core services already. The web-view would also allow for nice graphs an for integration with other services, such as backup or monitoring.

----
##### footnote #####
[[1] https://github.com/inofix/maestro](https://github.com/inofix/maestro)

[[2] http://reclass.pantsfullofunix.net/](http://reclass.pantsfullofunix.net/)

[[3] https://github.com/inofix/common-inv/](https://github.com/inofix/common-inv/)

[[4] https://www.ansible.com/](https://www.ansible.com/)

[[5] https://github.com/inofix/common-playbooks](https://github.com/inofix/common-playbooks)

[[6] https://debops.org/](https://debops.org/)

[[7] https://saltstack.com/](https://saltstack.com/)

[[8] https://cfengine.com/](https://cfengine.com/)

[[9] https:www.liferay.com](https:www.liferay.com)
