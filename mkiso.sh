#!/bin/bash

. /etc/slitaz/slitaz.conf 
. /etc/slitaz/tazwok.conf 

QUIET="y"
FORCE="y"
export LABEL="slitaz_$(date +%Y%m)"
PUBLISHER="Slitaz"
APPLICATION="Slitaz"
CREATE_DEFAULT="n"
BASEDIR="$(pwd)"
PROFILE="$BASEDIR/$1"
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
HG_PATH="home/slitaz/repos"
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
PACKAGES_REPOSITORY="$LOCAL_REPOSITORY/packages"
INCOMING_REPOSITORY="$LOCAL_REPOSITORY/packages-incoming"
SOURCES_REPOSITORY="$LOCAL_REPOSITORY/src"
HG_LIST="flavors flavors-stable slitaz-base-files slitaz-boot-scripts slitaz-configs slitaz-dev-tools slitaz-doc slitaz-doc-wiki-data slitaz-forge slitaz-modular slitaz-pizza slitaz-tools tazlito tazpkg tazusb tazwok website wok wok-stable wok-tiny wok-undigest"

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
	cat "$BASEDIR/initramfs/initramfs.list" | grep -v "^#" | while read pkgname; do
		if [ ! -f ${INITRAMFS}/var/lib/tazpkg/installed/${pkgname}/files.list ]; then
			tazpkg get-install $pkgname --root=$INITRAMFS | tee -a $LOG/initramfs.log
			sleep 1
		else
			info "${pkgname} installed"
		fi
	done

	if [ ! -d $ISODIR/boot ]; then
		mkdir -p $ISODIR/boot
	fi

	#if [ ! -f $ISODIR/boot/bzImage ]; then
		cp -a $INITRAMFS/boot/vmlinuz* $ISODIR/boot/bzImage
		rm -f $INITRAMFS/boot/vmlinuz*
		if [ -f $INITRAMFS/boot/gpxe ]; then
			cp -a $INITRAMFS/boot/gpxe $ISODIR/boot/gpxe
			rm -f $INITRAMFS/boot/gpxe
		fi
	#fi
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

	if [ -d ${MODULES_DIR}/${mod}/var/lib/tazpkg/installed ]; then
		echo "${mod} module exist. Moving on."
	elif [ ! -d ${MODULES_DIR}/${mod}/var/lib/tazpkg/installed ]; then
		if [ -f "$PROFILE/list/${mod}.list" ]; then
			cat "$PROFILE/list/${mod}.list" | grep -v "^#" | while read pkgname; do
				if [ ! -f ${UNION}/var/lib/tazpkg/installed/${pkgname}/files.list ]; then
					tazpkg get-install $pkgname --root=${UNION} | tee -a ${LOG}/${mod}-current.log
					sleep 1
				else
					info "${pkgname} installed"
				fi
			done
		fi

		if [ -f $PROFILE/list/${mod}.removelist ]; then
			cat "$PROFILE/list/${mod}.removelist" | grep -v "^#" | while read pkgname; do
				if [ -f ${UNION}/var/lib/tazpkg/installed/${pkgname}/files.list ]; then
					echo "y" | tazpkg remove ${pkgname} --root=${UNION} | tee -a ${LOG}/${mod}-current.log
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
		mkdir -p $PKGISO_DIR
		WOK=${HG_DIR}/wok/home/slitaz/repos/wok
		info "Making cooking list based installed packages in union"
		# this is to filter out packages build by get- 
		# packages that don't exist in repo or wok
		cat $ISODIR/packages-installed.list | while read pkg; do
			if [ ! -f $WOK/$pkg/receipt ]; then
				sed -i "s|$pkg||g" $ISODIR/packages-installed.list
			fi
		done
		tazwok gen-cooklist $ISODIR/packages-installed.list > $ISODIR/cookorder.list
		[ -f $INCOMING_REPOSITORY/wok-wanted.txt ] || tazwok gen-wok-db
		
		CACHE_REPOSITORY="$CACHE_DIR/$(cat /etc/slitaz-release)/packages"

		cat $ISODIR/cookorder.list | grep -v "^#" | while read pkg; do
			rwanted=$(grep $'\t'$pkg$ $INCOMING_REPOSITORY/wok-wanted.txt | cut -f 1)
			pkg_VERSION="$(grep -m1 -A1 ^$pkg$ $PACKAGES_REPOSITORY/packages.txt | \
				tail -1 | sed 's/ *//')"
			incoming_pkg_VERSION="$(grep -m1 -A1 ^$pkg$ $INCOMING_REPOSITORY/packages.txt | \
				tail -1 | sed 's/ *//')"
			for wanted in $rwanted; do
				if [ -f $INCOMING_REPOSITORY/$wanted-$incoming_pkg_VERSION.tazpkg ]; then
					ln -sf $INCOMING_REPOSITORY/$wanted-$incoming_pkg_VERSION.tazpkg $PKGISO_DIR/$wanted-$incoming_pkg_VERSION.tazpkg
				elif [ -f $PACKAGES_REPOSITORY/$wanted-$pkg_VERSION.tazpkg ]; then
					ln -sf $PACKAGES_REPOSITORY/$wanted-$pkg_VERSION.tazpkg $PKGISO_DIR/$wanted-$pkg_VERSION.tazpkg
				elif [ -f $CACHE_REPOSITORY/$Wanted-$pkg_VERSION.tazpkg ]; then
					ln -sf $CACHE_REPOSITORY/$wanted-$pkg_VERSION.tazpkg $PKGISO_DIR/$wanted-$pkg_VERSION.tazpkg
				fi
			done
		
			for i in $(ls $WOK/$pkg/receipt); do
				unset SOURCE TARBALL WANTED PACKAGE VERSION pkg_VERSION COOK_OPT
				source $i
				pkg_VERSION="$(grep -m1 -A1 ^$PACKAGE$ $PACKAGES_REPOSITORY/packages.txt | \
					tail -1 | sed 's/ *//')"
				incoming_pkg_VERSION="$(grep -m1 -A1 ^$pkg$ $INCOMING_REPOSITORY/packages.txt | \
					tail -1 | sed 's/ *//')"
				[ "$WGET_URL" ] || continue
				if [ -f $INCOMING_REPOSITORY/$PACKAGE-$incoming_pkg_VERSION.tazpkg ]; then
					ln -sf $INCOMING_REPOSITORY/$PACKAGE-$incoming_pkg_VERSION.tazpkg $PKGISO_DIR/$PACKAGE-$incoming_pkg_VERSION.tazpkg
				elif [ -f $PACKAGES_REPOSITORY/$PACKAGE-$pkg_VERSION.tazpkg ]; then
					ln -sf $PACKAGES_REPOSITORY/$PACKAGE-$pkg_VERSION.tazpkg $PKGISO_DIR/$PACKAGE-$pkg_VERSION.tazpkg
				elif [ -f $CACHE_REPOSITORY/$PACKAGE-$pkg_VERSION.tazpkg ]; then
					ln -sf $CACHE_REPOSITORY/$PACKAGE-$pkg_VERSION.tazpkg $PKGISO_DIR/$PACKAGE-$pkg_VERSION.tazpkg
				fi
			done
		done
		
		[ -d $PKGISO_DIR ] && tazwok gen-list $PKGISO_DIR
	fi
	
}

backup_src() {

	if [ "${BACKUP_PACKAGES}" = "yes" -a "${BACKUP_SOURCES}" = "yes" ]; then
			[ -d $SOURCES_REPOSITORY ] || mkdir -p $SOURCES_REPOSITORY
			[ -d $SRCISO_DIR ] && rm -r $SRCISO_DIR
			mkdir -p $SRCISO_DIR
			WOK=${HG_DIR}/wok/home/slitaz/repos/wok
			cat $ISODIR/cookorder.list | grep -v "^#"| while read pkg; do
				#rwanted=$(grep $'\t'$pkg$ $INCOMING_REPOSITORY/wok-wanted.txt | cut -f 1)
				for i in $(ls $WOK/$pkg/receipt); do
					unset SOURCE TARBALL WANTED PACKAGE VERSION COOK_OPT
					source $i
					{ [ ! "$TARBALL" ] || [ ! "$WGET_URL" ] ; } && continue
					if [ ! -f "$SOURCES_REPOSITORY/$TARBALL" ] && \
						[ ! -f "$SOURCES_REPOSITORY/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma" ]; then
						tazwok get-src $PACKAGE --nounpack
						if [ -f "$SOURCES_REPOSITORY/$TARBALL" ]; then
							ln -sf $SOURCES_REPOSITORY/$TARBALL $SRCISO_DIR/$TARBALL
						elif [ -f "$SOURCES_REPOSITORY/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma" ]; then
							ln -sf $SOURCES_REPOSITORY/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma $SRCISO_DIR/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma
						fi
					else
						[ -f "$SOURCES_REPOSITORY/$TARBALL" ] && ln -sf $SOURCES_REPOSITORY/$TARBALL $SRCISO_DIR/$TARBALL
						[ -f "$SOURCES_REPOSITORY/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma" ] && ln -sf $SOURCES_REPOSITORY/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma $SRCISO_DIR/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma
					fi
				done
			done
			cd $SRCISO_DIR
			info "Make md5sum file for sources"
			find * -not -type d | grep -v md5sum | xargs md5sum > md5sum
			cd $WORKING
	fi
	
}

backup_all()
{
	if [ "${BACKUP_ALL}" = "yes" ]; then
		[ -d $SRCISO_DIR ] || ln -sf $SOURCES_REPOSITORY $SRCISO_DIR
		[ -d $PKGISO_DIR ] || ln -sf $PACKAGES_REPOSITORY $PKGISO_DIR
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
			_mksquash "${MODULES_DIR}/${MOD}" "$ISODIR/$CDNAME/base" /var/lib/tazpkg/installed
		fi
	done
	
	if [ "${MODULES}" != "" ]; then
		for MOD in ${MODULES}; do
			if [ -d "${MODULES_DIR}/${MOD}" ]; then
				_mksquash "${MODULES_DIR}/${MOD}" "$ISODIR/$CDNAME/modules" /var/lib/tazpkg/installed
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

	if [ "${HG_LIST}" != "" ]; then
		for hg in ${HG_LIST}; do
			if [ -d "${MODULES_DIR}/${hg}" ]; then
				squashfs_hg $hg
			fi
		done
	fi
	
	[ -d $SRCISO_DIR ] && rm -r $SRCISO_DIR
	[ -d $PKGISO_DIR ] && rm -r $PKGISO_DIR
	
	if [ -d ${HG_DIR}/wok ]; then
		backup_pkg
		backup_src
	fi
	
	backup_all
	
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
	genisoimage -R -l -f -o $IMGNAME -b boot/isolinux/isolinux.bin \
	-c boot/isolinux/boot.cat -no-emul-boot -boot-load-size 4 \
	-uid 0 -gid 0 \
	-udf -allow-limited-size -iso-level 3 \
	-V "SliTaz" -input-charset utf-8 -boot-info-table $ISODIR
	if [ -x /usr/bin/isohybrid ]; then
		info "Creating hybrid ISO..."
		isohybrid "${IMGNAME}"
	fi
	md5sum "$IMGNAME" > $IMGMD5NAME
	sed -i "s|$PROFILE/||g" $IMGMD5NAME
}

if [ "$MODULES" != "" ]; then
	union
else
	error "MODULES was empty. exiting."
	exit 1
fi

make_iso
