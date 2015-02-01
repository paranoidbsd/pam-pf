# vim: set ft=make ffs=unix fenc=utf8:
# vim: set noet ts=4 sw=4 tw=72 list:

LOCALBASE=/usr/local

all:

install: files

directory:
	install -d -o root -g wheel $(LOCALBASE)/lib/pam_pf
	install -d -o root -g wheel $(LOCALBASE)/etc/pam_pf/rules.d

files: directory
	install -C -S -o root -g wheel -m 0644 lib/pam_pf/pam_pf.sub $(LOCALBASE)/lib/pam_pf/pam_pf.subr
	install -C -S -o root -g wheel -m 0644 libexec/pam_pf $(LOCALBASE)/libexec/pam_pf
	install -C -S -o root -g wheel -m 0644 etc/pam_pf.conf $(LOCALBASE)/etc/pam_pf.conf
	install -C -S -o root -g wheel -m 0600 etc/pam_pf/regular.rules $(LOCALBASE)/etc/pam_pf/regular.rules
	install -C -S -o root -g wheel -m 0600 etc/pam_pf/sshd_addr.conf $(LOCALBASE)/etc/pam_pf/sshd_addr.conf
	install -C -S -o root -g wheel -m 0600 etc/pam_pf/user_whitelist.conf $(LOCALBASE)/etc/pam_pf/user_whitelist.conf
