#!/bin/sh
# /etc/init.d/local.sh - Local startup commands.
#
# All commands here will be executed at boot time.
#
. /etc/init.d/rc.functions
. /etc/slitaz/slitaz.conf

echo "Starting local startup commands... "

[ -d /etc/pango ] || mkdir -p /etc/pango
[ -d /etc/gtk-2.0 ] || mkdir -p /etc/gtk-2.0
[ -x /usr/bin/pango-querymodules ] && /usr/bin/pango-querymodules > /etc/pango/pango.modules
[ -x /usr/bin/gdk-pixbuf-query-loaders ] && /usr/bin/gdk-pixbuf-query-loaders > /etc/gtk-2.0/gdk-pixbuf.loaders
[ -x /usr/bin/update-mime-database ] && update-mime-database /usr/share/mime

list_udev_group()
{
    object=$1
    [ -n "$object" ] || object=GROUP
    grep $object /etc/udev/rules.d/* | \
        sed "s/.*GROUP=\"\\([a-zA-Z0-9]*\\)\".*/\1/" | sort | uniq
}

if [ -f $INSTALLED/udev/receipt ]; then
	# Sanity check for udev+ldap boot
	list_udev_group GROUP | while read x ; do
		grep -q ^$x: /etc/group || addgroup -S $x
	done
	list_udev_group OWNER | while read x ; do
		grep -q ^$x: /etc/passwd || adduser -S -D -H $x
	done
fi

if [ -f $INSTALLED/slim/receipt -o -f $INSTALLED/slim-pam/receipt ]; then
	USER=$(awk -F: '/:1000:100:/ ' < /etc/passwd)
	[ -n "$USER" ] &&
	sed -i s/"default_user .*"/"default_user        $USER"/ /etc/slim.conf
	unset USER
fi

PKG_ORDER="$(find /mnt/live/mnt/* -name "packages-order.txt" -maxdepth 1)"
if [ -f $PKG_ORDER ]; then
	for i in $(cat $PKG_ORDER); do
		if [ -f $INSTALLED/$i/pkgmd5 ]; then
			unset PACKAGE VERSION EXTRAVERSION
			[ -f $INSTALLED/$i/receipt ] && source $INSTALLED/$i/receipt
			if [ $(cat $LOCALSTATE/installed.md5 | grep -i " ${PACKAGE}-${VERSION}${EXTRAVERSION}.tazpkg") ]; then
				sed -i "/ $PACKAGE-$VERSION${EXTRAVERSION}.tazpkg/d" $LOCALSTATE/installed.md5
				cat $INSTALLED/$i/pkgmd5 >> $LOCALSTATE/installed.md5
			else
				cat $INSTALLED/$i/pkgmd5 >> $LOCALSTATE/installed.md5
			fi
		fi
	done
fi
#[ -x /usr/bin/setup-live ] && /usr/bin/setup-live
