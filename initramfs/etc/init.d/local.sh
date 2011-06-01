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

if [ -f /etc/local-mirror.conf ]; then
	. /etc/local-mirror.conf
	if [ ! $(grep -l "$PKGDIR" $LOCALSTATE/mirror) ]; then
		[ -d $PKGDIR ] && echo "$PKGDIR" > $LOCALSTATE/mirror
	fi
fi
#[ -x /usr/bin/setup-live ] && /usr/bin/setup-live
