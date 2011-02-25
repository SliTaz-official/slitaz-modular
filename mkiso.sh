#!/bin/bash

. /etc/slitaz/slitaz.conf 

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
MODULES=""
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
BACKUP_ALL="no"
CLEAN_MODULES_DIR="no"
CLEAN_INITRAMFS="no"
PACKAGES_REPOSITORY="$LOCAL_REPOSITORY/packages"
SOURCES_REPOSITORY="$LOCAL_REPOSITORY/src"
HG_LIST="flavors flavors-stable slitaz-base-files slitaz-boot-scripts slitaz-configs slitaz-dev-tools slitaz-doc slitaz-forge slitaz-pizza slitaz-tools tazlito tazpkg tazusb tazwok website wok wok-stable wok-tiny wok-undigest"

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
	else
		cp -rf ${PROFILE}/overlay ${MODULES_DIR}
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
		cp -f $INITRAMFS/boot/vmlinuz* $ISODIR/boot/bzImage
		rm -f $INITRAMFS/boot/vmlinuz*
	#fi

	if [ -d $BASEDIR/initramfs ]; then
		cp -af $BASEDIR/initramfs/* $INITRAMFS
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
	for mod in $MODULES; do

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
		find ${UNION}/${INSTALLED} -type d | sort > $ISODIR/packages-installed.list
		sed -i "s|${UNION}/${INSTALLED}/||g" $ISODIR/packages-installed.list
	fi
	
	info "Unmounting union"
	umount -l "${UNION}"

	info "Removing unionfs .wh. files."
	find ${MODULES_DIR} -type f -name ".wh.*" -exec rm {} \;
	find ${MODULES_DIR} -type d -name ".wh.*" -exec rm -rf {} \;
}

backup_pkg() {
	if [ "${BACKUP_PACKAGES}" = "yes" ]; then
		[ -d $ISODIR/boot/packages ] && rm -r $ISODIR/boot/packages
		mkdir -p $ISODIR/boot/packages
		info "Making cooking list based installed packages in union"
		tazwok gen-cooklist $ISODIR/packages-installed.list > $ISODIR/cookorder.list
		#[ -f $INCOMING_REPOSITORY/wok-wanted.txt ] || tazwok gen-wok-db
		
		info "Linking all installed packages to $ISODIR/boot/packages"
		cat $ISODIR/packages-installed.list | while read PACKAGE; do
			VERSION=$(grep ^VERSION= ${HG_DIR}/wok/${PACKAGE}/receipt | cut -d "=" -f2 | sed -e 's/"//g')
			CACHE_PACKAGE=$(find $CACHE_DIR/$(cat /etc/slitaz-release)/packages -type f -name "$PACKAGE-$VERSION.tazpkg")	
			if [ -f $CACHE_PACKAGE ]; then
				info "Copying $CACHE_PACKAGE to $ISODIR/boot/packages"
				ln -sf $CACHE_PACKAGE $ISODIR/boot/packages
			#elif [ ! -f $CACHE_PACKAGE ]; then
			#	info "$CACHE_PACKAGE doesn't exist. Downloading it."
			#	cd $CACHE_DIR/$(cat /etc/slitaz-release)/packgages
			#	tazpkg get $PACKAGE
			#	cd $WORKING
			#	if [ -f $CACHE_PACKAGE ]; then
			#		ln -sf $CACHE_PACKAGE $ISODIR/packages
			#	fi
			fi
		done
		
		cat $ISODIR/cookorder.list | while read PACKAGE; do
			rwanted=$(grep $'\t'$PACKAGE$ $INCOMING_REPOSITORY/wok-wanted.txt | cut -f 1)
			echo $rwanted | while read WANTED_PKG; do
				VERSION=$(grep  ^VERSION= ${HG_DIR}/wok/${WANTED_PKG}/receipt | cut -d "=" -f2 | sed -e 's/"//g')
				CACHE_PACKAGE=$(find $CACHE_DIR/$(cat /etc/slitaz-release)/packages -type f -name "$WANTED_PKG-$VERSION.tazpkg")
				if [ -f $CACHE_PACKAGE ]; then
					info "Copying $CACHE_PACKAGE to $ISODIR/boot/packages"
					ln -sf $CACHE_PACKAGE $ISODIR/boot/packages
				#elif [ ! -f $CACHE_PACKAGE ]; then
				#	info "$CACHE_PACKAGE doesn't exist. Downloading it."
				#	cd $CACHE_DIR/$(cat /etc/slitaz-release)/packgages &>/dev/null
				#	tazpkg get $PACKAGE
				#	cd $WORKING
				#	if [ -f $CACHE_PACKAGE ]; then
				#		ln -sf $CACHE_PACKAGE $ISODIR/packages
				#	fi
				fi
			done
		done
		
		[ -d $ISODIR/boot/packages ] && tazwok gen-list $ISODIR/boot/packages
	fi
	
}

backup_src() {

	if [ "${BACKUP_PACKAGES}" = "yes" -a "${BACKUP_SOURCES}" = "yes" ]; then
			[ -d $SOURCES_REPOSITORY ] || mkdir -p $SOURCES_REPOSITORY
			[ -d $ISODIR/boot/src ] || mkdir -p $ISODIR/boot/src
			
			cat $ISODIR/cookorder.list | while read PACKAGE; do
				WGET_URL=$(grep  ^WGET_URL= ${HG_DIR}/wok/${PACKAGE}/receipt | cut -d "=" -f2 | sed -e 's/"//g' | head -n 1)
				VERSION=$(grep  ^VERSION= ${HG_DIR}/wok/${PACKAGE}/receipt | cut -d "=" -f2 | sed -e 's/"//g' | head -n 1)
				TARBALL=$(grep  ^TARBALL= ${HG_DIR}/wok/${PACKAGE}/receipt | cut -d "=" -f2 | sed -e 's/"//g' | head -n 1)
				
				if [ ! -f "$SOURCES_REPOSITORY/$TARBALL" ] && \
					[ ! -f "$SOURCES_REPOSITORY/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma" ]; then
					tazwok get-src $PACKAGE --nounpack
					if [ -f "$SOURCES_REPOSITORY/$TARBALL" ]; then
						ln -sf $SOURCES_REPOSITORY/$TARBALL $ISODIR/sources/$TARBALL
					elif [ -f "$SOURCES_REPOSITORY/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma" ]; then
						ln -sf $SOURCES_REPOSITORY/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma $ISODIR/sources/${SOURCE:-$PACKAGE}-$VERSION.tar.lzma
					fi
				else
					[  -f "$SOURCES_REPOSITORY/$TARBALL" ] && ln -sf $SOURCES_REPOSITORY/$TARBALL $ISODIR/sources/$TARBALL
				fi
			done
			cd $ISODIR/boot/src
			info "Make md5sum file for sources"
			find * -not -type d | grep -v md5sum | xargs md5sum > md5sum
			cd $WORKING
	fi
	
}

backup_all()
{
	if [ "${BACKUP_ALL}" = "yes" ]; then
		[ -d $ISODIR/boot/src ] || ln -sf $SOURCES_REPOSITORY $ISODIR/boot/src
		[ -d $ISODIR/boot/packages ] || ln -sf $PACKAGES_REPOSITORY $ISODIR/boot/packages
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
	if [ "${MODULES}" != "" ]; then
		for MOD in ${MODULES}; do
			if [ -d "${MODULES_DIR}/${MOD}" ]; then
				_mksquash "${MODULES_DIR}/${MOD}" "$ISODIR/$CDNAME/base" /var/lib/tazpkg/installed
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
	genisoimage -R -J -f -o $IMGNAME -b boot/isolinux/isolinux.bin \
	-c boot/isolinux/boot.cat -no-emul-boot -boot-load-size 4 \
	-V "SliTaz" -input-charset iso8859-1 -boot-info-table $ISODIR
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
