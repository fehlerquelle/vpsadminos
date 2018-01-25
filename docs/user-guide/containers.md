# Containers
When you have created at least one [user](users.md), you can start creating
containers. To create a container, you need an OS template. Template is
a gzipped tar archive containing the root file system. Until we get
the template machinery going, you can use one of these templates:

 - https://s.hvfn.cz/~aither/pub/tmp/templates/ubuntu-16.04-x86_64-vpsfree.tar.gz
 - https://s.hvfn.cz/~aither/pub/tmp/templates/debian-9-x86_64-vpsfree.tar.gz
 - https://s.hvfn.cz/~aither/pub/tmp/templates/centos-7.3-x86_64-vpsfree.tar.gz
 - https://s.hvfn.cz/~aither/pub/tmp/templates/alpine-3.6-x86_64-vpsfree.tar.gz

These templates are used in production at [vpsFree.cz](https://vpsfree.org),
they were generated using
[build-vpsfree-templates](https://github.com/vpsfreecz/build-vpsfree-templates)
scripts. The intent is to reuse these scripts for vpsAdminOS and have them
available on some more official server. Alternatively, you can use templates
from OpenVZ Legacy or LXC, they should be fully compatible, unless there are
some hacks for specific environments.

When you have a template ready, you can create a container:

```bash
osctl ct new --user myuser01 --template ubuntu-16.04-x86_64-vpsfree.tar.gz myct01
```

Let's see what files and directories define the container:

```
osctl ct assets myct01
TYPE        PATH                                         VALID   PURPOSE
dataset     tank/ct/myct01                               true    Container's rootfs
directory   /tank/user/myuser01/default/myct01           true    LXC configuration
file        /tank/user/myuser01/default/myct01/config    true    LXC base config
file        /tank/user/myuser01/default/myct01/network   true    LXC network config
file        /tank/user/myuser03/default/myct01/prlimits  true    LXC resource limits                      
file        /tank/user/myuser03/default/myct01/mounts    true    LXC mounts
file        /tank/user/myuser01/default/myct01/.bashrc   true    Shell configuration file for osctl ct su
file        /tank/conf/ct/myct01.yml                     true    Container config for osctld
file        /tank/log/ct/myct01.log                      true    LXC log file
```

The template is extracted into a ZFS dataset that becomes the container's rootfs.
Then there is a standard LXC configuration, followed by a config for *osctld*.
The container's existence is defined by that config. And the last entry is the
log file, where you can find errors if the container cannot be started.

To start the container, use:

```bash
osctl ct start -F myct01
```

Option `-F`, `--foreground` attaches the container's console before starting it,
so you can see the boot process and then login. Of course, the root's password
is not set yet. The console can be detached by pressing `Ctrl-a q`.

To set the password, you can use `osctl ct passwd`:

```bash
osctl ct passwd myct01 root secret
```

The command above will set root's password to `secret`. If you don't provide
the password as an argument, `osctl` will ask you for it on standard input.
You can then reopen the console and login:

```bash
osctl ct console myct01
```

The container's shell can be attached even without knowing any password with
`osctl ct attach`:

```bash
osctl ct attach myct01
```

The shell can be closed using `exit` or `Ctrl-d`.

Arbitrary commands can be executed using `osctl ct exec`:

```bash
osctl ct exec myct01 <command...>
```

You can view container states using by listing all containers:

```bash
osctl ct ls
POOL   ID       USER       GROUP     DISTRIBUTION   VERSION   STATE     INIT_PID   MEMORY   CPU_TIME 
tank   myct01   myuser01   default   ubuntu         16.04     running   7894       36.0M    1s
```

Or just one specific container, showing all container parameters:

```bash
osctl ct show myct01
          POOL:  tank
            ID:  myct01
          USER:  myuser01
         GROUP:  default
       DATASET:  tank/ct/myct01
        ROOTFS:  /tank/ct/myct01/private
      LXC_PATH:  /tank/user/myuser01/default
       LXC_DIR:  /tank/user/myuser01/default/myct01
    GROUP_PATH:  osctl/default/myuser01/myct01
  DISTRIBUTION:  ubuntu
       VERSION:  16.04
         STATE:  running
      INIT_PID:  7894
      HOSTNAME:  -
 DNS_RESOLVERS:  -
       NESTING:  -
        MEMORY:  36.0M
       KMEMORY:  3.0M
      CPU_TIME:  1s
 CPU_USER_TIME:  1s
  CPU_SYS_TIME:  0s
```

As you can see from the list above, *osctld* can also manage the container's
hostname and DNS resolvers. Hostname defaults to the container *id* and you
can manually change the hostname from within the container. If you wish to have
the hostname managed by *osctld* from the host, you can set it as:

```
osctl ct set hostname myct01 your-hostname
```

*osctld* will then configure the hostname on every container start, including
configs within the containers. Should you ever want to prevent that, you can
unset the hostname:

```
osctl ct unset hostname myct01
```

Similarly to hostname, you can configure DNS resolvers, which are written to
`/etc/resolv.conf` on every start:

```
osctl ct set dns-resolver myct01 8.8.8.8 8.8.4.4
osctl ct unset dns-resolver myct01
```

To allow LXC nesting, i.e. creating LXC containers inside the containers, you
have to enable it:

```
osctl ct set nesting myct01 enabled
```

Continue by reading more about container [networking](networking.md),
[resource management](resources.md) and [mounts](mounts.md).