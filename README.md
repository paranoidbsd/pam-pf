pam_pf
======

`pam_pf` is not a PAM module, but a script that can be called by the
`pam_exec` PAM module. It provides functionality roughly similar to
`authpf` via the PAM session target. Since it does not act as your
shell, it can be used to background-load `pf` rules upon successful
login while still having a normal shell.

WARNING
=======

This implementation right here is currently untested. It is published
because it is sunday evening and I want to talk with a colleague about
it tomorrow. Don't use it yet without testing.
You should always do testing, but with this, right now, you should do
even more testing.

Motiviation
===========

The initial motivation of this script was that I use draconian
connection limits on sshd via pf's state tracking and overload
facilities. But I wanted those limits to be lifted, once I made a
successful login.

The first version of this script used a single global whitelist table,
and it worked, but had horrible corner cases. This version of the
script uses anchors to hold per-user rulesets, clearly inspired by the
approach used by `authpf`. Having never actually used `authpf`, I can
not comment on any further similarities, except that I think it can do
more than this script can.

Since `authpf` is a shell, it can also take advantage of the `SSH_*`
environment variables set by sshd which are unavailable to `pam_pf`.

Since the filtering is source IP based once a ruleset has been loaded,
there can be false positive matching for shared source IPs (NAT
gateway).

Also note, `pam_exec` does not provide the source ip, but the reverse
resolution of it. Adding this into a `pf` table will forward resolve
the host name again and add all addresses it resolves to. This might
be exactly the one correct address; it might be multiple addresses,
one of which is the correct one; or it might resolve to something else
entirely.
This may be acceptable to you since it requires a valid login on top
of (sadly common) broken DNS zones to trigger. It may not be, in which
case I suggest you implement a patch to `pam_exec` to not resolve the
address and upstream it.

In any case, I strongly advise against using `pam_pf` to open up
access to unauthenticated non-public services. But I also strongly
advise against running unauthenticated non-public services in the first
place, so what do I know.

Anchor structure
================

The anchor structure loaded by `pam_pf` looks like this:

```
pam_pf/
       user1/
             regular
             extended
       user2/
             regular
             extended
       ...
```

Every user's base anchor is populated with the following:

1. a table containing the users source addresses, `<pam_pf_user>`
2. a conditional anchor statement for the regular subanchor
3. a conditional anchor statement for the extended subanchor

The anchor statements use the filter syntax `from <pam_pf_user>` and
are therefor only evaluated for packets coming from the user's source
addresses. This enables a fast cycling of not matching anchors with
minimal ruleset evaluations. At least that is the idea.

The regular anchor loads a common ruleset that is the same for all
users. The extended anchor loads a custom per-user ruleset if one is
provided for that user.

Within the rule definition files, the string `%LABEL%` can be used.
`pam_pf` will replace this prior to loading with a per-user label
`pam_pf:$username`. Upon cleanup, this label is used to kill all
states opened by rules with this label.
This applies to both the regular and the extended anchor.

If `pam_pf` becomes active for a given user or not is configured via a
whitelist.

Since / is the anchor-separator used by pf any username with / in it
is simply refused by `pam_pf`. It is possible to have anchors with
this character and not have it act as separator from how I read the
man pages, but it is a mess to escape correctly.
Just do not use / in usernames. There, easy fix.

Regular Anchor
==============

The ruleset that is loaded into the regular anchor is in
`etc/pam_pf/regular.rules`. The one shipped with this repository looks
like this:

```
table <pam_pf_ssh> persist counters
block in tag pam_pf
pass in quick proto tcp to <pam_pf_ssh> \
  port 22 flags S/SA modulate state label %LABEL%
```

Since `pam_pf` does not receive the information to which local ip
address the user has connected, a table is set up inside this anchor.
This table is then populated with addresses from a configuration file
that specifies for which sshd listening addresses the connection
should be accepted without state limits.
Not having this table or the configuration file is not supported right
now, but if the table is unused the file can simply be empty.

The regular ruleset also sets a `block in tag pam_pf` default-deny
rule that tags the packet. This can be used in the main rulset to
identify connections that come from a source with an active `pam_pf`
anchor, but no specific `quick` rule for it.

Extended Anchor
===============

The extended anchor can be filled with any valid pf configuration. The
file is simply passed to `sed` to replace any occurances of `%LABEL%`
within it. That output is then piped into `pfctl`.

Configuration files
===================

etc/pam_pf.conf
---------------

The main configuration file of `pam_pf`. It is shell syntax and
provides three variables:

1. `uid`, the uid under which this is expected to run. If your PAM
   system runs as anything other than 0, I'd be concerned but maybe
   you are not. Default: 0
2. `svc`, the PAM_SERVICE for which `pam_pf` should normally be
   called. Default: sshd
3. `wrong_svc_is_error`, which determines how `pam_pf` reacts to being
   called for the wrong service. It always stops processing, but
   depending on this setting, it will `exit 0` or `exit 1`. Default:
   yes

etc/pam_pf/regular.rules
------------------------

The ruleset that is loaded into the `regular` anchor for all users.
This file is subject to file permission checks. It has to be owned by
root/wheel with permissions 0600 and be a regular file and not at the
end of a symbolic link. These are the restrictions placed on any file
with permission checks.

etc/pam_pf/sshd_addr.conf
-------------------------

This file contains the addresses (or address ranges) to load into the
`pam_pf_ssh` table inside the regular anchor. This file is subject to
file permission checks as well.

The format is one record per line. Anything `pfctl -t snafu -T add`
recognizes is good.

etc/pam_pf/user_whitelist.conf
------------------------------

This file contains the whitelist of usernames for which `pam_pf` is
active and will create anchors. File permission checks here as well.

A user is considered whitelisted if his full username occurs on a line
of its own with no leading or trailing whitespace or other characters
exactly once. In other words, this command needs to return 1:
`grep -c '^username$' whitelist`

etc/pam_pf/rules.d/${username}.rules
---------------------------------

These are the per-user ruleset files that will be loaded into the
extended rules if one exist for a user. Again, file permission checks.

Additionally, for these files it is checked if they are still under
`${base}/etc/pam_pf/rules.d` after realpath fully resolved them, to
avoid asshatery with creative usernames.
Go buy yourself a proper username.

How do I use this thing?
========================

After installing and configuring, add the following line to the
appropriate PAM configuration file:

```
session   optional   pam_exec.so    /usr/local/libexec/pam_pf
```

Look into `pam_exec` options and stricter requirements if you want to
fail session setup on `pam_pf` errors.

For this to work, your system needs to provide a `pam_exec` module.
This module also needs to set the following environment variables:

1. PAM_USER
2. PAM_SERVICE
3. PAM_RHOST
4. PAM_SM_FUNC (values pam_sm_open_session, pam_sm_close_session)

It also helps tremendously to actually use pf. In your `pf.conf`, add
the following line:

```
anchor "pam_pf/*"
```

Since the ruleset loaded by `pam_pf` contains a default block rule, it
is advisable to have this line rather early within your ruleset.

Supported Systems
=================

Well, it is written for FreeBSD. On OpenBSD it will very likely not
work, since OpenBSD has a different pf rule syntax. DragonFlyBSD and
NetBSD I am not sure, but I think they as well still use the old syntax.

Apart from rule syntax adaptions, there is nothing fancy going on
inside the script, so that part should work.

Any system based on FreeBSD is likely to work, depending on how
customized and how recent its FreeBSD base is.

Security
========

Well, it is:
* a shellscript downloaded from the internet
* written by a dude you do not know
* executed as root
* as part of your authentication system

If this does not ring all your bells, nothing ever will. Go back to
sleep. All is well.

Seriously, read the code. It is not intentionally obfuscated.

License
=======

2-Clause BSD
