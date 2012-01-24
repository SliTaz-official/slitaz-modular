#!/bin/bash

. /etc/slitaz/slitaz.conf
. /etc/slitaz/cook.conf

QUIET="y"
FORCE="y"
PUBLISHER="Slitaz"
APPLICATION="Slitaz"
CREATE_DEFAULT="n"
BASEDIR="$(pwd)"
PROFILE="$BASEDIR/$1"
export LABEL="slitaz_$1_$(date +%F)"
VOLUME_ID="$LABEL"
ver=""
CDNAME="slitaz"
RMSTUFF=n
MVSTUFF=n
UNGZIP=n
EXT="xz"
COMPRESSION="xz -Xbcj x86"
MKOPTION="-b 256k"
BASE_MODULES=""
MODULES=""
UNION_MODULES=""
WORKING="$PROFILE/working"
INITRAMFS="$WORKING/initramfs"
UNION="$WORKING/union"
LOG="$WORKING/log"
ISODIR="$WORKING/iso"
IMGNAME="$PROFILE/$CDNAME-$1-$(date +%F).iso"
IMGMD5NAME="$IMGNAME.md5"
LASTBR="$INITRAMFS"
SGNFILE="$ISODIR/$CDNAME/livecd.sgn"
MODULES_DIR="$WORKING/modules"
HG_DIR="$WORKING/hg"
HG_URL="http://hg.slitaz.org"
HG_PATH="repos"
DONT_UPDATE_MIRROR="no"
COPY_HG="no"
UPDATE_HG="no"
BACKUP_SOURCES="no"
BACKUP_PACKAGES="no"
MIRROR_DIR="mirror"
PKGISO_DIR="$ISODIR/$MIRROR_DIR/packages"
SRCISO_DIR="$ISODIR/$MIRROR_DIR/src"
BACKUP_ALL="no"
KEY_FILES="init liblinuxlive linuxrc"
CLEAN_MODULES_DIR="no"
CLEAN_INITRAMFS="no"
LOCAL_REPOSITORY="$SLITAZ"
PACKAGES_REPOSITORY="$PKGS"
INCOMING_REPOSITORY="$INCOMING"
SOURCES_REPOSITORY="$SRC"
HG_LIST="cookutils flavors flavors-stable slitaz-base-files slitaz-configs slitaz-doc slitaz-forge slitaz-modular slitaz-pizza slitaz-tools slitaz-vz ssfs tazlito tazpanel tazpkg tazusb tazweb tazwok wok wok-stable wok-tiny wok-undigest"
MY_HG_LIST="piratebox slitaz-cloud slitaz-dev-tools tazpkg-tank slitaz-doc-wiki-data slitaz-boot-scripts my-cookutils wok-tank website"
MY_HG_URL="https://bitbucket.org/godane"

error () { echo -e "\033[1;31;40m!!! \033[1;37;40m$@\033[1;0m"; }
warn ()  { echo -e "\033[1;33;40m*** \033[1;37;40m$@\033[1;0m"; }
info () { echo -e "\033[1;32;40m>>> \033[1;37;40m$@\033[1;0m"; }

# do UID checking here so someone can at least get usage instructions
#if [ "$EUID" != "0" ]; then
#    error "error: This script must be run as root."
#    exit 1
#fi
if [ ! -d $PROFILE -o "$1" = "" ]; then
	echo "$0 profile-name"
	echo "ex $0 core"
	exit 1
fi

ROOT_MOD="$(ls -1 ${PROFILE}/list | head -1)"
INST_ROOT="${MODULES_DIR}/$(basename ${ROOT_MOD} .list)"

if [ -f ${PROFILE}/config ]; then
	source ${PROFILE}/config
fi

_overlay()
{
	if [ -d ${MODULES_DIR}/overlay ]; then
		rm -rf ${MODULES_DIR}/overlay
		cp -rf ${PROFILE}/overlay ${MODULES_DIR}
		cp -af ${BASEDIR}/initramfs/* ${MODULES_DIR}/overlay
	else
		cp -rf ${PROFILE}/overlay ${MODULES_DIR}
		cp -af ${BASEDIR}/initramfs/* ${MODULES_DIR}/overlay
	fi

	if [ -f ${MODULES_DIR}/overlay/etc/local-mirror.conf ]; then
		sed -i "s|^#PKGDIR|PKGDIR=/packages|g" ${MODULES_DIR}/overlay/etc/local-mirror.conf
		sed -i "s|^#SRCDIR|SRCDIR=/src|g" ${MODULES_DIR}/overlay/etc/local-mirror.conf
	fi

	if [ "${QUIET}" = "y" ]; then
		mksquashfs "${MODULES_DIR}/overlay" "${ISODIR}/${CDNAME}/modules/zzz.overlay.${EXT}" -comp ${COMPRESSION} -noappend ${MKOPTION} >/dev/null
	else
		mksquashfs "${MODULES_DIR}/overlay" "${ISODIR}/${CDNAME}/modules/zzz.overlay.${EXT}" -comp ${COMPRESSION} -noappend ${MKOPTION}
	fi
}

lzma_switches()
{
	echo "-d$(echo 24) -mt$(grep ^processor < /proc/cpuinfo | wc -l)"
}

# Pack rootfs
pack_rootfs()
{
	( cd $1 ; find . -print | cpio -o -H newc ) | \
	if [ -x /usr/bin/lzma ]; then
		info "Generating lzma'ed initramfs... "
		lzma e -si -so $(lzma_switches $1) > $2
	else
		info "Generating gziped initramfs... "
		gzip -9 > $2
	fi
	echo 1 > /tmp/rootfs
}

download()
{
	for file in $@; do
		wget -q $file && break
	done
}

initramfs () {

	if [ ! -e "$BASEDIR/initramfs/initramfs.list" ]; then
		error "error: $BASEDIR/initramfs/initramfs.list doesn't exist, aborting."
		exit 1
	fi

	if [ "$CLEAN_INITRAMFS" = "yes" ]; then
		if [ -d ${INITRAMFS} ]; then
			rm -Rf ${INITRAMFS}
		fi
	fi

	if [ ! -d ${INITRAMFS} ]; then
		mkdir -p $INITRAMFS
	fi

	info "Making bootable image"
	[ -f $LOG/initramfs.log ] && rm -f $LOG/initramfs.log
	cat "$BASEDIR/initramfs/initramfs.list" | grep -v "^#" | while read pkgname; do
		if [ ! -f ${INITRAMFS}${INSTALLED}/${pkgname}/files.list ]; then
			tazpkg get-install $pkgname --root=$INITRAMFS 2>&1 | tee -a $LOG/initramfs.log
			sleep 1
		else
			info "${pkgname} installed" | tee -a $LOG/initramfs.log
		fi
	done

	if [ ! -d $ISODIR/boot ]; then
		mkdir -p $ISODIR/boot
	fi

	#if [ ! -f $ISODIR/boot/bzImage ]; then
	if [ -f $INITRAMFS/boot/vmlinuz* ]; then
		cp -a $INITRAMFS/boot/vmlinuz* $ISODIR/boot/bzImage
		rm -f $INITRAMFS/boot/vmlinuz*
	fi
	
	if [ -f $INITRAMFS/boot/gpxe ]; then
		cp -a $INITRAMFS/boot/gpxe $ISODIR/boot/gpxe
		rm -f $INITRAMFS/boot/gpxe
	fi
	
	if [ -d $BASEDIR/initramfs ]; then
		for i in $KEY_FILES; do
			if [ -f $BASEDIR/initramfs/$i ]; then
				cp -af $BASEDIR/initramfs/$i $INITRAMFS
			fi
		done
	fi
	
	if [ -f $INITRAMFS/liblinuxlive ]; then
		sed -i "s|^#MIRROR|MIRROR=$MIRROR_DIR|g" $INITRAMFS/liblinuxlive
	fi

}

copy_hg() {
	if [ ! -d ${HG_DIR}/${1}/${HG_PATH}/${1} ]; then
		info "Cloning $1 repo ..."
		hg clone $HG_URL/${1} ${HG_DIR}/${1}/${HG_PATH}/${1}
		if [ $(grep -l "^HG_URL=$HG_URL" $PROFILE/config) ]; then
			if [ ! $(grep -l "$HG_URL" ${HG_DIR}/${1}/${HG_PATH}/${1}/.hg/hgrc) ]; then
				echo "mirror = $HG_URL/$1" >> ${HG_DIR}/${1}/${HG_PATH}/${1}/.hg/hgrc
			fi
		fi
	elif [ -d ${HG_DIR}/${1}/${HG_PATH}/${1} -a ${UPDATE_HG} = "yes" ]; then
		info "Updating $1 repo ..."
		cd ${HG_DIR}/${1}/${HG_PATH}/${1}
		hg pull $HG_URL/${1} -u
		if [ $(grep -l "^HG_URL=$HG_URL" $PROFILE/config) ]; then
			if [ ! $(grep -l "$HG_URL" ${HG_DIR}/${1}/${HG_PATH}/${1}/.hg/hgrc) ]; then
				echo "mirror = $HG_URL/$1" >> ${HG_DIR}/${1}/${HG_PATH}/${1}/.hg/hgrc
			fi
		fi
		cd $PROFILE
	fi
}

squashfs_hg() {
	if [ ! -d "$ISODIR/$CDNAME/modules/hg" ]; then
		mkdir -p "$ISODIR/$CDNAME/modules/hg"
	fi
	if [ -d ${HG_DIR}/${1}/ ]; then
		_mksquash ${HG_DIR}/${1} "$ISODIR/$CDNAME/modules/hg/" /${HG_PATH}/${1}
	fi
}

slitaz_union () {

	if [ -d ${MODULES_DIR}/${mod}${INSTALLED} ]; then
		echo "${mod} module exist. Moving on."
	elif [ ! -d ${MODULES_DIR}/${mod}${INSTALLED} ]; then
		if [ -f "$PROFILE/list/${mod}.list" ]; then
			[ -f ${LOG}/${mod}-current.log ] && rm -f ${LOG}/${mod}-current.log
			cat "$PROFILE/list/${mod}.list" | grep -v "^#" | while read pkgname; do
				if [ ! -f ${UNION}${INSTALLED}/${pkgname}/files.list ]; then
					tazpkg get-install $pkgname --root=${UNION} 2>&1 | tee -a ${LOG}/${mod}-current.log
					sleep 1
				else
					info "${pkgname} installed" | tee -a ${LOG}/${mod}-current.log
				fi
			done
		fi

		if [ -f $PROFILE/list/${mod}.removelist ]; then
			[ -f ${LOG}/${mod}-current-removelist.log ] && rm -f ${LOG}/${mod}-current-removelist.log
			cat "$PROFILE/list/${mod}.removelist" | grep -v "^#" | while read pkgname; do
				if [ -f ${UNION}${INSTALLED}/${pkgname}/files.list ]; then
					echo "y" | tazpkg remove ${pkgname} --root=${UNION} 2>&1 | tee -a ${LOG}/${mod}-current-removelist.log
					sleep 1
				else
					info "${pkgname} removed"
				fi
			done
		fi
	fi		
}

union () {
	if [ "$BASE_MODULES" != "" ]; then
		UNION_MODULES="$BASE_MODULES $MODULES"
	elif [ "$MODULES" != "" ]; then
		UNION_MODULES="$MODULES"
	else
		error "Error: no modules assigned in config for profile."
		exit 1
	fi
	
	mkdir -p $WORKING
	mkdir -p $UNION
	mkdir -p $LOG
	mkdir -p $ISODIR/${CDNAME}/base
	mkdir -p $ISODIR/${CDNAME}/modules
	mkdir -p $ISODIR/${CDNAME}/optional
	mkdir -p $ISODIR/${CDNAME}/rootcopy
	mkdir -p $ISODIR/${CDNAME}/tmp
	mkdir -p $LASTBR
	
	touch $SGNFILE

	modprobe aufs
	if [ $? -ne 0 ]; then
		error "Error loading Union filesystem module. (aufs)"
		exit 1
	fi
	
	# $INITRAMFS is now $LASTBR
	# This will be copyed to /mnt/memory/changes on boot
	initramfs

	mount -t aufs -o br:${LASTBR}=rw aufs ${UNION}
	if [ $? -ne 0 ]; then 
		error "Error mounting $union."
		exit 1
	fi
	
	info "====> Installing packages to '$UNION'"
	for mod in $UNION_MODULES; do

		if [ "$CLEAN_MODULES_DIR" = "yes" ]; then
			if [ -d $MODULES_DIR/$mod ]; then
				rm -Rf $MODULES_DIR/$mod
			fi
		fi

		if [ ! -d $MODULES_DIR/$mod ]; then
			mkdir -p $MODULES_DIR/$mod
		fi
		info "Adding $MODULES_DIR/$mod as top branch of union."
		mount -t aufs -o remount,add:0:${MODULES_DIR}/${mod}=rw aufs $UNION
		info "Adding $LASTBR as lower branch of union."
		mount -t aufs -o remount,mod:${LASTBR}=rr+wh aufs $UNION
		LASTBR="$MODULES_DIR/${mod}"

		slitaz_union
	done
	
	if [ -d ${UNION}/${INSTALLED} ]; then
		ls ${UNION}/${INSTALLED} | sort > $ISODIR/packages-installed.list
	fi
	
	info "Unmounting union"
	umount -l "${UNION}"

	info "Removing unionfs .wh. files."
	find ${MODULES_DIR} -type f -name ".wh.*" -exec rm {} \;
	find ${MODULES_DIR} -type d -name ".wh.*" -exec rm -rf {} \;
}

backup_pkg() {
	if [ "${BACKUP_PACKAGES}" = "yes" ]; then
		[ -d $PKGISO_DIR ] && rm -r $PKGISO_DIR
		[ -f $LOG/backup_pkg.log ] && rm -rf $LOG/backup_pkg.log
		mkdir -p $PKGISO_DIR
		info "Making cooking list based installed packages in union"
		# this is to filter out packages build by get- 
		# packages that don't exist in repo or wok
		cat $ISODIR/packages-installed.list | while read pkg; do
			if [ ! -f $WOK/$pkg/receipt ]; then
				sed -i "s|$pkg||g" $ISODIR/packages-installed.list
			fi
		done
		local pkg wanted rwanted pkg_VERSION incoming_pkg_VERSION cache_pkg_VERSION
		cook gen-cooklist $ISODIR/packages-installed.list > $ISODIR/cookorder.list
		[ -f $PKGS/fullco.txt ] || cook gen-wok-db $WOKHG
		cookorder=$ISODIR/cookorder.list
		[ "$BACKUP_ALL" = "yes" ] && cookorder=$PKGS/fullco.txt
		[ "$BACKUP_ALL" = "yes" ] && cp -a $cookorder $PKGISO_DIR/fullco.txt
		CACHE_REPOSITORY="$CACHE_DIR/$(cat /etc/slitaz-release)/packages"
		[ -f $PROFILE/list/backupall.banned ] && cp -a $PROFILE/list/backupall.banned $ISODIR/blocked
		
		cat $cookorder | grep -v "^#" | while read pkg; do
			[ -f "$WOK/$pkg/receipt" ] || continue
			unset rwanted pkg_VERSION incoming_pkg_VERSION cache_pkg_VERSION
			rwanted=$(grep $'\t'$pkg$ $PKGS/wanted.txt | cut -f 1)
			pkg_VERSION="$(grep -m1 -A1 ^$pkg$ $PACKAGES_REPOSITORY/packages.txt | \
				tail -1 | sed 's/ *//')"
			incoming_pkg_VERSION="$(grep -m1 -A1 ^$pkg$ $INCOMING_REPOSITORY/packages.txt | \
				tail -1 | sed 's/ *//')"
			cache_pkg_VERSION="$(grep -m1 -A1 ^$pkg$ $LOCALSTATE/packages.txt | \
					tail -1 | sed 's/ *//')"
			for wanted in $rwanted; do
				if [ -f $PROFILE/list/backupall.banned ]; then
					if [ "$BACKUP_ALL" = "yes" ]; then
						[ $(grep -l "^$wanted$" $PROFILE/list/backupall.banned) ] && continue
					fi
				fi

				if [ -f $INCOMING_REPOSITORY/$wanted-$incoming_pkg_VERSION.tazpkg ]; then
					info "Backing up $INCOMING_REPOSITORY/$wanted-$incoming_pkg_VERSION.tazpkg" | tee -a $LOG/backup_pkg.log
					ln -sf $INCOMING_REPOSITORY/$wanted-$incoming_pkg_VERSION.tazpkg $PKGISO_DIR/$wanted-$incoming_pkg_VERSION.tazpkg
				elif [ -f $PACKAGES_REPOSITORY/$wanted-$pkg_VERSION.tazpkg ]; then
					info "Backing up $PACKAGES_REPOSITORY/$wanted-$pkg_VERSION.tazpkg" | tee -a $LOG/backup_pkg.log
					ln -sf $PACKAGES_REPOSITORY/$wanted-$pkg_VERSION.tazpkg $PKGISO_DIR/$wanted-$pkg_VERSION.tazpkg
				elif [ -f $CACHE_REPOSITORY/$Wanted-$cache_pkg_VERSION.tazpkg ]; then
					info "Backing up $CACHE_REPOSITORY/$wanted-$cache_pkg_VERSION.tazpkg" | tee -a $LOG/backup_pkg.log
					ln -sf $CACHE_REPOSITORY/$wanted-$cache_pkg_VERSION.tazpkg $PKGISO_DIR/$wanted-$cache_pkg_VERSION.tazpkg
				fi
			done
			
			if [ -f $PROFILE/list/backupall.banned ]; then
				if [ "$BACKUP_ALL" = "yes" ]; then
					[ $(grep -l "^$pkg$" $PROFILE/list/backupall.banned) ] && continue
				fi
			fi
			
			if [ -f $INCOMING_REPOSITORY/$pkg-$incoming_pkg_VERSION.tazpkg ]; then
				info "Backing up $INCOMING_REPOSITORY/$pkg-$incoming_pkg_VERSION.tazpkg" | tee -a $LOG/backup_pkg.log
				ln -sf $INCOMING_REPOSITORY/$pkg-$incoming_pkg_VERSION.tazpkg $PKGISO_DIR/$pkg-$incoming_pkg_VERSION.tazpkg
			elif [ -f $PACKAGES_REPOSITORY/$pkg-$pkg_VERSION.tazpkg ]; then
				info "Backing up $PACKAGES_REPOSITORY/$pkg-$pkg_VERSION.tazpkg" | tee -a $LOG/backup_pkg.log
				ln -sf $PACKAGES_REPOSITORY/$pkg-$pkg_VERSION.tazpkg $PKGISO_DIR/$pkg-$pkg_VERSION.tazpkg
			elif [ -f $CACHE_REPOSITORY/$pkg-$cache_pkg_VERSION.tazpkg ]; then
				info "Backing up $CACHE_REPOSITORY/$pkg-$cache_pkg_VERSION.tazpkg" | tee -a $LOG/backup_pkg.log
				ln -sf $CACHE_REPOSITORY/$pkg-$cache_pkg_VERSION.tazpkg $PKGISO_DIR/$pkg-$cache_pkg_VERSION.tazpkg
			fi
		done
		
		if [ "$SRC_PKG" = "yes" ]; then
			cat $cookorder | grep -v "^#" | while read pkg; do
				[ -f "$WOK/$pkg/receipt" ] || continue
				[ $(grep ^$pkg$ $PROFILE/list/srcpkg.banned) ] && continue
				for i in $(grep -l "^SOURCE=\"$pkg\"" $WOK/*/receipt); do
					unset SOURCE TARBALL WANTED PACKAGE VERSION COOK_OPT WGET_URL
					unset pkg_VERSION incoming_pkg_VERSION cache_pkg_VERSION src_pkg src_ver 
					#source $i
					src_pkg=$(grep ^PACKAGE= $WOK/$pkg/receipt | cut -d "=" -f 2 | sed -e 's/"//g')
					src_ver=$(grep ^VERSION= $WOK/$pkg/receipt | cut -d "=" -f 2 | sed -e 's/"//g')
					[ "$VERSION" = "$src_ver" ] || continue
					pkg_VERSION="$(grep -m1 -A1 ^$src_pkg$ $PACKAGES_REPOSITORY/packages.txt | \
						tail -1 | sed 's/ *//')"
					incoming_pkg_VERSION="$(grep -m1 -A1 ^$src_pkg$ $INCOMING_REPOSITORY/packages.txt | \
						tail -1 | sed 's/ *//')"
					cache_pkg_VERSION="$(grep -m1 -A1 ^$src_pkg$ $LOCALSTATE/packages.txt | \
						tail -1 | sed 's/ *//')"
					rwanted=$(grep $'\t'$src_pkg$ $PKGS/wanted.txt | cut -f 1)
					
					for wanted in $rwanted; do
						if [ -f $INCOMING_REPOSITORY/$wanted-$incoming_pkg_VERSION.tazpkg ]; then
							ln -sf $INCOMING_REPOSITORY/$wanted-$incoming_pkg_VERSION.tazpkg $PKGISO_DIR/$wanted-$incoming_pkg_VERSION.tazpkg
						elif [ -f $PACKAGES_REPOSITORY/$wanted-$pkg_VERSION.tazpkg ]; then
							ln -sf $PACKAGES_REPOSITORY/$wanted-$pkg_VERSION.tazpkg $PKGISO_DIR/$wanted-$pkg_VERSION.tazpkg
						elif [ -f $CACHE_REPOSITORY/$Wanted-$pkg_VERSION.tazpkg ]; then
							ln -sf $CACHE_REPOSITORY/$wanted-$pkg_VERSION.tazpkg $PKGISO_DIR/$wanted-$pkg_VERSION.tazpkg
						fi
					done
					
					if [ -f $INCOMING_REPOSITORY/$PACKAGE-$incoming_pkg_VERSION.tazpkg ]; then
						ln -sf $INCOMING_REPOSITORY/$PACKAGE-$incoming_pkg_VERSION.tazpkg $PKGISO_DIR/$PACKAGE-$incoming_pkg_VERSION.tazpkg
					elif [ -f $PACKAGES_REPOSITORY/$PACKAGE-$pkg_VERSION.tazpkg ]; then
						ln -sf $PACKAGES_REPOSITORY/$PACKAGE-$pkg_VERSION.tazpkg $PKGISO_DIR/$PACKAGE-$pkg_VERSION.tazpkg
					elif [ -f $CACHE_REPOSITORY/$PACKAGE-$cache_pkg_VERSION.tazpkg ]; then
						ln -sf $CACHE_REPOSITORY/$PACKAGE-$cache_pkg_VERSION.tazpkg $PKGISO_DIR/$PACKAGE-$cache_pkg_VERSION.tazpkg
					fi
				done
			done
		fi
		
		[ -f $LOG/packages-gen-list.log ] && rm -f $LOG/packages-gen-list.log
		[ -d $PKGISO_DIR ] && cook pkgdb $PKGISO_DIR | tee -a $LOG/packages-gen-list.log
	fi
	
}

backup_src() {

	if [ "${BACKUP_PACKAGES}" = "yes" -a "${BACKUP_SOURCES}" = "yes" ]; then
		[ -d $SOURCES_REPOSITORY ] || mkdir -p $SOURCES_REPOSITORY
		[ -d $SRCISO_DIR ] && rm -r $SRCISO_DIR
		mkdir -p $SRCISO_DIR
		local pkg cookorder pkg_VERSION
		cookorder=$ISODIR/cookorder.list
		[ "$BACKUP_ALL" = "yes" ] && cookorder=$PKGS/fullco.txt
		[ -f $LOG/cook-getsrc.log ] && rm -rf $LOG/cook-getsrc.log
		[ -f $LOG/backup_src.log ] && rm -rf $LOG/backup_src.log
		cat $cookorder | grep -v "^#" | while read pkg; do
			if [ -f $PROFILE/list/backupall.banned ]; then
				if [ "$BACKUP_ALL" = "yes" ]; then
					[ $(grep -l "^$pkg$" $PROFILE/list/backupall.banned) ] && continue
				fi
			fi
			unset PATCH SOURCE TARBALL WANTED PACKAGE VERSION COOK_OPT WGET_URL KBASEVER
			unset pkg_VERSION
			[ -f $WOK/$pkg/receipt ] || continue
			source $WOK/$pkg/receipt
			[ "$WGET_URL" ] || continue
			[ "$TARBALL" ] || continue
			pkg_VERSION="$(grep -m1 -A1 ^$pkg$ $PKGISO_DIR/packages.txt | \
				tail -1 | sed 's/ *//')"
			[ -f "$PKGISO_DIR/$PACKAGE-$pkg_VERSION.tazpkg" ] || continue
			#{ [ ! "$TARBALL" ] || [ ! "$WGET_URL" ] ; } && continue
			LZMA_TARBALL="${SOURCE:-$PACKAGE}-${KBASEVER:-$VERSION}.tar.lzma"
			if [ "$PATCH" ]; then
				if [ -f "$SOURCES_REPOSITORY/$(basename $PATCH)" ]; then
					info "Backing up $SOURCES_REPOSITORY/$(basename $PATCH)" | tee -a $LOG/backup_src.log
					ln -sf $SOURCES_REPOSITORY/$(basename $PATCH) $SRCISO_DIR/$(basename $PATCH)
				else
					cook $PACKAGE --getsrc | tee -a $LOG/cook-getsrc.log
					if [ -f "$SOURCES_REPOSITORY/$(basename $PATCH)" ]; then
						info "Backing up $SOURCES_REPOSITORY/$(basename $PATCH)" | tee -a $LOG/backup_src.log
						ln -sf $SOURCES_REPOSITORY/$(basename $PATCH) $SRCISO_DIR/$(basename $PATCH)
					fi
				fi
			fi
			if [ -f "$SOURCES_REPOSITORY/$LZMA_TARBALL" ]; then
				info "Backing up $SOURCES_REPOSITORY/$LZMA_TARBALL" | tee -a $LOG/backup_src.log
				ln -sf $SOURCES_REPOSITORY/$LZMA_TARBALL $SRCISO_DIR/$LZMA_TARBALL
			elif [ -f "$SOURCES_REPOSITORY/$TARBALL" ]; then
				info "Backing up $SOURCES_REPOSITORY/$TARBALL" | tee -a $LOG/backup_src.log
				ln -sf $SOURCES_REPOSITORY/$TARBALL $SRCISO_DIR/$TARBALL
			else
				cook $PACKAGE --getsrc | tee -a $LOG/cook-getsrc.log
				if [ -f "$SOURCES_REPOSITORY/$TARBALL" ]; then
					info "Backing up $SOURCES_REPOSITORY/$TARBALL" | tee -a $LOG/backup_src.log
					ln -sf $SOURCES_REPOSITORY/$TARBALL $SRCISO_DIR/$TARBALL
				elif [ -f "$SOURCES_REPOSITORY/$LZMA_TARBALL" ]; then
					info "Backing up $SOURCES_REPOSITORY/$LZMA_TARBALL" | tee -a $LOG/backup_src.log
					ln -sf $SOURCES_REPOSITORY/$LZMA_TARBALL $SRCISO_DIR/$LZMA_TARBALL
				fi
			fi
		done
		cd $SRCISO_DIR
		info "Make md5sum file for sources"
		find * -not -type d | grep -v md5sum | xargs md5sum > md5sum
		cd $WORKING
	fi
	
}

# _mksquash dirname
_mksquash () {
    if [ ! -d "$1" ]; then
        error "Error: '$1' is not a directory"
        return 1
    fi

    if [ ! -d "$2" ]; then
        error "Error: '$2' is not a directory"
        return 1
    fi

    if [ ! -d "${1}${3}" ]; then
        error "Error: '${1}${3}' is not a directory"
        return 1
    fi

    time_dir="${3}"
    sqimg="${2}/$(basename ${1}).${EXT}"
    info "====> Generating SquashFS image for '${1}'"
    if [ -e "${sqimg}" ]; then
        dirhaschanged=$(find ${1}${time_dir} -newer ${sqimg})
        if [ "${dirhaschanged}" != "" ]; then
            info "SquashFS image '${sqimg}' is not up to date, rebuilding..."
            rm "${sqimg}"
        else
            info "SquashFS image '${sqimg}' is up to date, skipping."
            return
        fi
    fi

    info "Creating SquashFS image. This may take some time..."
    start=$(date +%s)
    if [ "${QUIET}" = "y" ]; then
        mksquashfs "${1}" "${sqimg}" -noappend ${MKOPTION} -comp ${COMPRESSION} >/dev/null
    else
        mksquashfs "${1}" "${sqimg}" -noappend ${MKOPTION} -comp ${COMPRESSION}
    fi
    minutes=$(echo $start $(date +%s) | awk '{ printf "%0.2f",($2-$1)/60 }')
    info "Image creation done in $minutes minutes."
}

imgcommon () {
	for MOD in ${BASE_MODULES}; do
		if [ -d "${MODULES_DIR}/${MOD}" ]; then
			_mksquash "${MODULES_DIR}/${MOD}" "$ISODIR/$CDNAME/base" $INSTALLED
		fi
	done
	
	if [ "${MODULES}" != "" ]; then
		for MOD in ${MODULES}; do
			if [ -d "${MODULES_DIR}/${MOD}" ]; then
				_mksquash "${MODULES_DIR}/${MOD}" "$ISODIR/$CDNAME/modules" $INSTALLED
			fi
		done
	fi
	
	if [ "$HG_LIST" != "" ]; then
		if [ "$COPY_HG" = "yes" ]; then
			for hg in $HG_LIST; do
				copy_hg $hg
				squashfs_hg $hg
			done
		fi
	fi
	
	if [ "$MY_HG_LIST" != "" ]; then
		if [ "$COPY_HG" = "yes" ]; then
			for my_hg in $MY_HG_LIST; do
				HG_URL="$MY_HG_URL"
				copy_hg $my_hg
				WOK=${HG_DIR}/wok-tank/repos/wok-tank
				if [ -d $WOK/.hg ]; then
					cd $WOK
					if [ "$(hg branch)" != "cooking" ]; then
						hg update cooking
					fi
					cd $PROFILE
				fi
				squashfs_hg $my_hg
			done
		fi
	fi

	if [ "$DONT_UPDATE_MIRROR" = "no" ]; then
		[ -d $SRCISO_DIR ] && rm -r $SRCISO_DIR
		[ -d $PKGISO_DIR ] && rm -r $PKGISO_DIR	
		if [ -d ${HG_DIR}/wok-tank/repos/wok-tank/.hg ]; then
			WOK=${HG_DIR}/wok-tank/repos/wok-tank
			backup_pkg
			backup_src
		elif [ -d ${HG_DIR}/wok/repos/wok/.hg ]; then
			WOK=${HG_DIR}/wok/repos/wok
			backup_pkg
			backup_src
		fi
	fi
	
	info "====> Making bootable image"

	# Sanity checks
	if [ ! -d "${ISODIR}" ]; then
		error "Error: '${ISODIR}' doesn't exist. What did you do?!"
		exit 1
	fi

	if [ ! -f "${SGNFILE}" ]; then
 		error "Error: the ${SGNFILE} file doesn't exist. This image won't do anything"
		error "  Protecting you from yourself and erroring out here..."
		exit 1
	fi


	if [ -e "${IMGNAME}" ]; then
		if [ "${FORCE}" = "y" ]; then
			info "Removing existing bootable image..."
			rm -rf "${IMGNAME}"
		else
			error "Error: Image '${IMGNAME}' already exists, aborting."
			exit 1
		fi
	fi
   
}

make_iso () {
	imgcommon

	info "Creating rootfs.gz"
	pack_rootfs $INITRAMFS $ISODIR/boot/rootfs.gz

	if [ -d $PROFILE/rootcd ]; then
		cp -af $PROFILE/rootcd/* $ISODIR/
	fi

	info "Copying isolinux files..."
	if [ -d $INITRAMFS/boot/isolinux ]; then
		cp -a $INITRAMFS/boot/isolinux $ISODIR/boot
	fi

	if [ -d ${PROFILE}/overlay ]; then
		_overlay
	fi

	info "Creating ISO image..."
	genisoimage -R -l -f -V $VOLUME_ID -o $IMGNAME -b boot/isolinux/isolinux.bin \
	-c boot/isolinux/boot.cat -no-emul-boot -boot-load-size 4 \
	-uid 0 -gid 0 \
	-udf -allow-limited-size -iso-level 3 \
	-P $PUBLISHER -input-charset utf-8 -boot-info-table $ISODIR
	if [ -x /usr/bin/isohybrid ]; then
		info "Creating hybrid ISO..."
		isohybrid "${IMGNAME}"
	fi
	md5sum "$IMGNAME" > $IMGMD5NAME
	sed -i "s|$PROFILE/||g" $IMGMD5NAME
}

if [ "$BASE_MODULES" != "" ]; then
	union
else
	error "BASE_MODULES was empty. exiting."
	exit 1
fi

make_iso
