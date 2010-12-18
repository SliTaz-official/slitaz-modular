#!/bin/sh
# /etc/init.d/bootopts.sh - SliTaz boot options from the cmdline.
#
# Earlier boot options are in rcS, ex: config= and modprobe=
#
. /etc/init.d/rc.functions

# Update fstab for swapon/swapoff 
add_swap_in_fstab()
{
	grep -q "$1	" /etc/fstab || cat >> /etc/fstab <<EOT
$1	swap	swap	default	0 0
EOT
}

# Default user account without password (uid=1000). In live mode the option
# user=name can be used, but user must be added before home= to have home dir.
# This option is not handled by a loop and case like others and has no
# effect on an installed system.
if ! grep -q "100[0-9]:100[0-9]" /etc/passwd; then
	if grep -q "user=" /proc/cmdline; then
		USER=`cat /proc/cmdline | sed 's/.*user=\([^ ]*\).*/\1/'`
		# Avoid usage of an existing system user or root.
		if grep -q ^$USER /etc/passwd; then
			USER=tux
		fi
	else
		USER=tux
	fi
	echo -n "Configuring user and group: $USER..."
	echo "$USER:x:1000:1000:SliTaz User,,,:/home/$USER:/bin/sh" >> /etc/passwd
	echo "$USER::14035:0:99999:7:::" >> /etc/shadow
	echo "$USER:x:1000:" >> /etc/group
	echo "$USER:!::" >> /etc/gshadow
	status
	# Audio and cdrom group.
	addgroup $USER audio
	addgroup $USER cdrom
	addgroup $USER video
	# /home/$USER files from /etc/skel.
	if [ -d /etc/skel ]; then
		cp -a /etc/skel /home/$USER
		# Path for user desktop files.
		for i in /home/$USER/.local/share/applications/*.desktop
		do
			sed -i s/"user_name"/"$USER"/g $i
		done
	else
		mkdir -p /home/$USER
	fi
	# Set permissions.
	if [ ! $(ls -l | grep "$USER      $USER" 2>/dev/null) ]; then
		chown -R $USER.$USER /home/$USER
	fi
	# Slim default user.
	if [ -f /etc/slim.conf ]; then
		sed -i s/"default_user .*"/"default_user        $USER"/\
			/etc/slim.conf
	fi
fi

# Parse /proc/cmdline for boot options.
echo "Parsing kernel cmdline for SliTaz live options... "

for opt in `cat /proc/cmdline`
do
	case $opt in
		eject)
			# Eject cdrom.
			eject /dev/cdrom ;;
		autologin)
			# Autologin option to skip first graphic login prompt.
			echo "auto_login        yes" >> /etc/slim.conf ;;
		lang=*)
			# Check for a specified locale (lang=*).
			LANG=${opt#lang=}
			echo -n "Setting system locale to: $LANG... "
			echo "LANG=$LANG" > /etc/locale.conf
			echo "LC_ALL=$LANG" >> /etc/locale.conf
			[ ! -d /usr/lib/locale/$LANG ] && localedef \
				-i $LANG -c -f UTF-8 /usr/lib/locale/$LANG &
			tazlocale link-files
			status ;;
		kmap=*)
			# Check for a specified keymap (kmap=*).
			KEYMAP=${opt#kmap=}
			echo -n "Setting system keymap to: $KEYMAP..."
			echo "$KEYMAP" > /etc/keymap.conf
			status ;;
		home=*)
			# Check for a specified home partition (home=*) and check for 
			# user home dir. Note: home=usb is a shorter and easier way to
			# have home=/dev/sda1.
			DEVICE=${opt#home=}
			[ "$DEVICE" = "usb" ] && DEVICE=sda1
			echo "Home has been specified to $DEVICE..."
			USBDELAY=`cat /sys/module/usb_storage/parameters/delay_use`
			USBDELAY=$((1+$USBDELAY))
			echo "Sleeping $USBDELAY s to let the kernel detect the device... "
			sleep $USBDELAY
			USER=`cat /etc/passwd | grep 1000 | cut -d ":" -f 1`
			DEVID=$DEVICE
			if [ -x /sbin/blkid ]; then
				# Can be a label, uuid or devname. DEVID gives us first: /dev/name.
				DEVID=`/sbin/blkid | grep $DEVICE | cut -d: -f1`
				DEVID=${DEVID##*/}
			fi
			if [ -n "$DEVID" ] && grep -q "$DEVID" /proc/partitions ; then
				echo "Mounting /home on /dev/$DEVID... "
				[ -d /home/$USER ] && mv /home/$USER /tmp/$USER-files
				mount /dev/$DEVID /home -o uid=1000,gid=1000 2>/dev/null \
					|| mount /dev/$DEVID /home
				# Check if swap file must be generated in /home: swap=size (Mb).
				# This option is only used within home=device.
				if grep -q "swap=[1-9]*" /proc/cmdline; then
					SWAP_SIZE=`cat /proc/cmdline | sed 's/.*swap=\([^ ]*\).*/\1/'`
					# DD to gen a virtual disk.
					echo "Generating swap file: /home/swap ($SWAP_SIZE)..."
					dd if=/dev/zero of=/home/swap bs=1M count=$SWAP_SIZE
					# Make the Linux swap filesystem.
					mkswap /home/swap
					add_swap_in_fstab /home/swap
				fi
			else
				echo "Unable to find $DEVICE... "
			fi
			# Move all user dir if needed.
			if [ ! -d "/home/$USER" ] ; then
				mv /tmp/$USER-files /home/$USER
				chown -R $USER.$USER /home/$USER
			else
				rm -rf /tmp/$USER-files
			fi
			# Install all packages in /home/boot/packages. In live CD and 
			# USB mode the option home= mounts the device on /home, so we 
			# already have a boot directory with the Kernel and rootfs.
			if [ -d "/home/boot/packages" ]; then
				for pkg in /home/boot/packages/*.tazpkg
				do
					tazpkg install $pkg
				done
			fi ;;
		laptop)
			# Laptop option to load related Kernel modules.
			echo "Loading laptop modules: ac, battery, fan, yenta_socket..."
			for mod in ac battery fan yenta_socket
			do
				modprobe $mod
			done
			grep -qs batt /etc/lxpanel/default/panels/panel || 
			sed -i 's/= cpu/= batt\n}\n\nPlugin {\n    type = cpu/' \
				/etc/lxpanel/default/panels/panel 2> /dev/null
			# Enable Kernel Laptop mode.
			echo "5" > /proc/sys/vm/laptop_mode ;;
		mount)
			# Mount all ext3 partitions found (opt: mount).
			# Get the list of partitions.
			DEVICES_LIST=`fdisk -l | grep 83 | cut -d " " -f 1`
			# Mount filesystems rw.
			for device in $DEVICES_LIST
			do
				name=${device#/dev/}
				# Device can be already used by home=usb.
				if ! mount | grep ^$device >/dev/null; then
					echo "Mounting partition: $name on /mnt/$name"
					mkdir /mnt/$name
					mount $device /mnt/$name
				fi
			done ;;
		mount-packages)
			# Mount and install packages-XXX.iso (useful without Internet 
			# connection).
			PKGSIGN="LABEL=\"packages-$(cat /etc/slitaz-release)\" TYPE=\"iso9660\""
			PKGDEV=$(blkid | grep "$PKGSIGN" | cut -d: -f1)
			[ -z "$PKGDEV" -a -L /dev/cdrom ] && \
				PKGDEV=$(blkid /dev/cdrom | grep "$PKGSIGN" | cut -d: -f1)
			if [ -n "$PKGDEV" ]; then
				echo -n "Mounting packages archive from $PKGDEV..."
				mkdir /packages && mount -t iso9660 -o ro $PKGDEV /packages
				status
				/packages/install.sh
			fi ;;
		wm=*)
			# Check for a Window Manager (for a flavor, default WM can be changed
			# with boot options or with an addfile in /etc/X11/wm.default.
			WM=${opt#wm=}
			mkdir -p /etc/X11
			case $WM in
				jwm)
					echo "jwm" > /etc/X11/wm.default ;;
				ob|openbox|openbox-session)
					echo "openbox" > /etc/X11/wm.default ;;
				e17|enlightenment|enlightenment_start)
					echo "enlightenment" > /etc/X11/wm.default ;;
				fluxbox|startfluxbox)
					echo "fluxbox" > /etc/X11/wm.default ;;
				awesome)
					echo "awesome" > /etc/X11/wm.default ;;
				pekwm)
					echo "pekwm" > /etc/X11/wm.default ;;
				xfce|xfce4|xfce4-session)
					echo "xfce" > /etc/X11/wm.default ;;
			esac ;;
		*)
			continue ;;
	esac
done

# If no default WM fallback to Openbox (we never know).
if [ ! -f /etc/X11/wm.default ]; then
	echo "openbox" > /etc/X11/wm.default
fi

# Activate an eventual swap file or partition.
if [ "`fdisk -l | grep swap`" ]; then
	for SWAP_DEV in `fdisk -l | grep swap | awk '{ print $1 }'`; do
		echo "Swap memory detected on: $SWAP_DEV"
		add_swap_in_fstab $SWAP_DEV
	done
fi
if grep -q swap /etc/fstab; then
	echo "Activating swap memory..."
	swapon -a
fi
