
#========================================================================
#
# PROGRAM FUNCTIONS
#

# Clean-up tmp and lock files
#
function cleanup() {
	local retval=${EXIT_CODE:-0}
	[ "$SPINNING" = "off" ] || tput cnorm
	if [ -e $TMPDIR/error.log ]; then
		retval=1
	        echo -e "         
\n==============================================================================
WARNING!        WARNING!        WARNING!        WARNING!        WARNING!
==============================================================================
One or more errors occurred while slackpkg was running:                       
"
		cat $TMPDIR/error.log
		echo -e "
=============================================================================="
	fi    
	echo
	if [ "$DELALL" = "on" ] && [ "$NAMEPKG" != "" ]; then
		rm $CACHEPATH/$NAMEPKG &>/dev/null
	fi		
	rm -f /var/lock/slackpkg.$$
	rm -rf $TMPDIR
	exit ${retval}
}
trap 'cleanup' 2 14 15 		# trap CTRL+C and kill

# This create an spinning bar
spinning() {
	local WAITFILE
	local SPININTERVAL
	local COUNT
	
	if [ "$SPIN" = "" ]; then
		SPIN=( "|" "/" "-" "\\" )
	fi
	COUNT=${#SPIN[@]}
		
	[ -n "$1" ] && WAITFILE=$1 || WAITFILE=/tmp/waitfile
	[ -n "$2" ] && SPININTERVAL=$2 || SPININTERVAL=0.1

	count=0
	tput civis 
	while [ -e $WAITFILE ] ; do 
		count=$(( count + 1 ))
		tput sc
		echo -n ${SPIN[$(( count % COUNT ))]}
		tput rc
		sleep $SPININTERVAL
	done
	tput cnorm
}

# System setup
#
function system_setup() {

	# Create $WORKDIR just in case
	mkdir -p "${WORKDIR}"

	# Set the "current" flag if system is running Slackware Current
	if [ -n "$(echo $SLACKWARE_VERSION | sed -ne 's/.*\(+\|current\)$/\1/pi')" ] && \
	   [ ! -e ${WORKDIR}/current ]; then
		touch ${WORKDIR}/current
	fi

	# Select the command to fetch files and packages from network sources
	if [ "$DOWNLOADER" = "curl" ]; then
		DOWNLOADER="curl ${CURLFLAGS} -o"
	else
               	DOWNLOADER="wget ${WGETFLAGS} -O"
	fi

	# Set LOCAL if mirror isn't through network 
	#
	MEDIA=${SOURCE%%:*}
	if [ "$MEDIA" = "cdrom" ] || [ "$MEDIA" = "file" ] || \
	   [ "$MEDIA" = "local" ]; then
		SOURCE=/${SOURCE#${MEDIA}://}
		LOCAL=1
	else
		LOCAL=0
	fi

	# Set MORECMD, EDITCMD and check BATCH mode 
	#
	if [ "$BATCH" = "on" ] || [ "$BATCH" = "ON" ]; then
		DIALOG=off
		SPINNING=off
		MORECMD=cat
		EDITCMD=vi
		if [ "$DEFAULT_ANSWER" = "" ]; then
			DEFAULT_ANSWER=n
		fi
	else
		if [ "${PAGER}" ]; then	
			MORECMD="${PAGER}"
		else
			MORECMD=more
		fi
		if [ "${EDITOR}" ]; then	
			EDITCMD="${EDITOR}"
		else
			EDITCMD=vi
		fi
	fi

	# Set ARCH, SLACKKEY and others by slackware port
	#
	if [ "$ARCH" = "" ]; then
		ARCH=$(uname -m)
	fi
	case $ARCH in
		i386|i486|i586|i686)
			ARCH=[i]*[3456x]86[^_]*
			SLACKKEY=${SLACKKEY:-"Slackware Linux Project <security@slackware.com>"}
			PKGMAIN=${PKGMAIN:-slackware}
		;;
		x86-64|x86_64|X86-64|X86_64)
			ARCH=x86[_64]*
			SLACKKEY=${SLACKKEY:-"Slackware Linux Project <security@slackware.com>"}
			PKGMAIN=${PKGMAIN:-slackware64}
		;;
		s390)
			ARCH=s390
			# Slack390 didn't have signed packages
			CHECKGPG=off
			PKGMAIN=${PKGMAIN:-slackware}
		;;
		arm*)
			ARCH=arm[v5tel]*
			SLACKKEY=${SLACKKEY:-"Slackware ARM (Slackware ARM Linux Project) <mozes@slackware.com>"}
			PKGMAIN=${PKGMAIN:-slackware}
		;;
		aarch64)
			ARCH=aarch64
			SLACKKEY=${SLACKKEY:-"Slackware ARM (Slackware ARM Linux Project) <mozes@slackware.com>"}
			PKGMAIN=${PKGMAIN:-slackware}
		;;
		*)
			ARCH=none
		;;
	esac

	# Sub %PKGMAIN with the correct $PKGMAIN value
	#
	MAIN=$PKGMAIN
	for i in 0 1 2 3 4 ; do
		if [ "${PRIORITY[$i]}" = "%PKGMAIN" ]; then
			PRIORITY[$i]=$PKGMAIN
		fi
	done

	TEMPLATEDIR=$CONF/templates
	if [ ! -d $TEMPLATEDIR ]; then
	  mkdir $TEMPLATEDIR
	fi

	# Create initial blacklist of single package names from regexps in
	# ${CONF}/blacklist.
	[ "$CMD" != update ] && mkregex_blacklist

	if [ -z "${SLACKCFVERSION}" ]; then
		SLACKCFVERSION=$(grep "# v[0-9.]\+" $CONF/slackpkg.conf | cut -f2 -dv)
	fi
	CHECKSUMSFILE=${WORKDIR}/CHECKSUMS.md5
	KERNELMD5=$(md5sum /boot/vmlinuz 2>/dev/null)
	DIALOG_MAXARGS=${DIALOG_MAXARGS:-19500}
	echo "$0 $VERSION - Slackware Linux $SLACKWARE_VERSION" > $TMPDIR/timestamp
}

# Syntax Checking
#
function system_checkup() {

	# Check slackpkg.conf version
	#
	SLCKCFVL=$( expr length $SLACKCFVERSION )
	if [ "$SLACKCFVERSION" != "$( echo $VERSION |cut -c1-$SLCKCFVL)" ] &&\
	   [ "$CMD" != "new-config" ]; then
		echo -e "\
\nYour slackpkg.conf is outdated. Please, edit it using slackpkg.conf.new\n\
as example or overwrite it with slackpkg.conf.new.\n\
\nYou can use 'slackpkg new-config' to do that.\n"
		cleanup
	fi

	# Check if ARCH is set
	#
	if [ "$ARCH" = "none" ] && [ "$CMD" != "new-config" ]; then
		echo -e "\
\nThe ARCH values in slackpkg.conf are now different. You can remove\n\
ARCH from there, and slackpkg will use your current ARCH or you can look\n\
at slackpkg.conf.new or slackpkg.conf manual page to see the new valid\n\
ARCH values\n"
		cleanup
	fi

	# Check if the config files are updated to the new slackpkg version
	#
	if [ "${WORKDIR}" = "" ]; then
		echo -e "\
\nYou need to upgrade your slackpkg.conf.\n\
This is a new slackpkg version and many changes happened in config files.\n\
In ${CONF}/slackpkg.conf.new, there is a sample of the new configuration.\n\
\nAfter updating your configuration file, run: slackpkg update\n" 
		cleanup
	fi

	# Checking if another instance of slackpkg is running
	#
	if [ "$(ls /var/lock/slackpkg.* 2>/dev/null)" ] && \
		[ "$CMD" != "search" ] && \
		[ "$CMD" != "help" ] && \
		[ "$CMD" != "file-search" ]; then
		echo -e "\
\nAnother instance of slackpkg is running. If this is not correct, you can\n\
remove /var/lock/slackpkg.* files and run slackpkg again.\n"
		cleanup
	else        
		ls /var/lock/slackpkg.* &>/dev/null || \
			touch /var/lock/slackpkg.$$
	fi

	# Checking if the we can create TMPDIR
	#
	if [ "$TMPDIR" = "FAILED" ]; then
		echo -e "\
\nA problem was encountered writing to slackpkg's temporary dir in /tmp.\n\
Check to ensure you have permissions to write in /tmp and make sure the\n\
filesystem is not out of free space.  Run slackpkg again after correcting\n\
the problem.\n"
		cleanup
	fi

	# Checking if is the first time running slackpkg
	#                                               
	if ! [ -f ${WORKDIR}/pkglist ] && [ "$CMD" != "update" ]; then
		if [ "$SOURCE" = "" ]; then
                	echo -e "\
\nThis appears to be the first time you have run slackpkg.\n\
Before you install|upgrade|reinstall anything, you need to uncomment\n\
ONE mirror in ${CONF}/mirrors and run:\n\n\
\t# slackpkg update\n\n\
You can see more information about slackpkg functions in slackpkg manpage."
			cleanup
		elif [ "$CMD" != "new-config" ] && [ "$CMD" != "help" ]; then
			updatefilelists
			mkregex_blacklist
			UPDATED=1
		fi
	fi                                                      


	# Checking if /etc/slackpkg/mirrors are in correct syntax.
	#                                                         
	if [ "$SOURCE" = "" ] ; then
		echo -e "\
\nYou do not have any mirror selected in ${CONF}/mirrors\n\
Please edit that file and uncomment ONE mirror.  Slackpkg\n\
only works with ONE mirror selected.\n"
		cleanup
	fi
	if echo $SOURCE|grep -q " "; then
		echo "
Slackpkg only works with ONE mirror selected.  Please edit your
${CONF}/mirrors and comment all but one line - two or more
mirrors uncommented is not valid syntax.
"
		cleanup
	fi
	MIRROR_VERSION=$(echo $SOURCE|sed "s/.*-//;s/.$//") 
	if [ "$MIRROR_VERSION" = "current" ] && [ ! -f ${WORKDIR}/current ]; then
		echo -n  "
You have selected a mirror for Slackware -current in ${CONF}/mirrors,
but Slackware version $SLACKWARE_VERSION appears to be installed.

Slackware -current is the development (i.e. unstable) tree.

Is this really what you want?

To confirm your choice, press Y, else press N. Then, press Enter: "
		read current
		if [ "$current" = "Y" ] || [ "$current" = "y" ]; then
			touch ${WORKDIR}/current
			echo -n  "
Slackpkg will not show this warning again unless you remove the
${WORKDIR}/current file. 
"
			sleep 1
		else
			cleanup
		fi
	fi
	[ ! "$MIRROR_VERSION" = "current" ] &&  rm -f ${WORKDIR}/current

	# It will check if the mirror selected are ftp.slackware.com
	# if set to "ftp.slackware.com" tell the user to choose another
	#
	if echo ${SOURCE} | grep "^ftp://ftp.slackware.com" &>/dev/null ; then
		echo -e "\n\
Please use one of the mirrors.\n\
ftp.slackware.com should be reserved so that the\n\
official mirrors can be kept up-to-date.\n"
		cleanup
	fi

	# Also check if the mirror selected is ftp://mirrors.slackware.com
	# if set to "ftp://mirrors.slackware.com" tell the user to choose another
	#
	if echo ${SOURCE} | grep "^ftp://mirrors.slackware.com" &>/dev/null ; then
		echo -e "\n\
Please use http://mirrors.slackware.com instead.\n\
ftp://mirrors.slackware.com does not handle redirects \n\
to the closest mirror and is very slow.\n"
		cleanup
	fi

	# Checking if the user has the permissions to install/upgrade/update
	#                                                                    
	if [ "$(id -u)" != "0" ] && \
	   [ "$CMD" != "search" ] && \
	   [ "$CMD" != "file-search" ] && \
	   [ "$CMD" != "check-updates" ] && \
	   [ "$CMD" != "show-changelog" ] && \
	   [ "$CMD" != "help" ] && \
	   [ "$CMD" != "info" ]; then
		echo -e "\n\
Only root can install, upgrade, or remove packages.\n\
Please log in as root or contact your system administrator.\n"
		cleanup
	fi          

	# Check if the "which" command is there
	if ! which which 1>/dev/null 2>/dev/null ; then
		echo -e "\n\
No 'which' command found, please install it if you want to\n\
use slackpkg.\n"
		cleanup
	fi

	# Check if we have md5sum in the PATH. Without md5sum, disables
	# md5sum checks
	#
	if ! [ $(which md5sum 2>/dev/null) ]; then
		CHECKMD5=off
	elif ! [ -f ${WORKDIR}/CHECKSUMS.md5 ] && \
		[ "$CMD" != "update" ] && \
		[ "$CMD" != "new-config" ] && \
		[ "$CMD" != "help" ] && \
		[ "$CHECKMD5" = "on" ]; then
		echo -e "\n\
No CHECKSUMS.md5 found!  Please disable md5sums checking\n\
on your ${CONF}/slackpkg.conf or run slackpkg update\n\
to download a new CHECKSUMS.md5 file.\n"
		cleanup
	fi

	# Check if awk is installed
	#
	if ! [ "$(which awk 2>/dev/null)" ]; then
		echo -e "\n\
awk package not found! Please install awk before you run slackpkg,\n\
as slackpkg cannot function without awk.\n"
		cleanup
	fi

	# Check if tput is there
	#
	if ! which tput 1>/dev/null 2>/dev/null ; then
		SPINNING=off
	fi

	# Check if gpg is enabled but no GPG command are found.
	#
	if ! [ "$(which gpg 2>/dev/null)" ] && [ "${CHECKGPG}" = "on" ]; then
		CHECKGPG=off
		echo -e "\n\
gpg package not found!  Please disable GPG in ${CONF}/slackpkg.conf or install\n\
the gnupg package.\n\n\
To disable GPG, edit slackpkg.conf and change the value of the CHECKGPG \n\
variable to "off" - you can see an example in the original slackpkg.conf.new\n\
file distributed with slackpkg.\n"
		sleep 5
	fi 

	# Check if the Slackware GPG key are found in the system
	#                                                       
	GPGFIRSTTIME="$(gpg --list-keys \"$SLACKKEY\" 2>/dev/null \
			| grep -c "$SLACKKEY")"
	if [ "$GPGFIRSTTIME" = "0" ] && \
		[ "$CMD" != "search" ] && \
		[ "$CMD" != "file-search" ] && \
		[ "$CMD" != "info" ] && \
		[ "$CMD" != "new-config" ] && \
		[ "$CMD" != "update" ] && \
		[ "$CMD" != "check-updates" ] && \
		[ "$CHECKGPG" = "on" ]; then
		echo -e "\n\
You need the GPG key of $SLACKKEY.\n\
To download and install that key, run:\n\n\
\t# slackpkg update gpg\n\n\
You can disable GPG checking too, but it is not a good idea.\n\
To disable GPG, edit slackpkg.conf and change the value of the CHECKGPG\n\
variable to "off" - you can see an example in the original slackpkg.conf.new\n\
file distributed with slackpkg.\n"
		cleanup
	fi
	echo 
}

# Got the name of a package, without version-arch-release data
#
function cutpkg() {
	echo ${1/%.t[blxg]z/} | awk -F- -f /usr/libexec/slackpkg/cutpkg.awk
}

# The same, but reading packages from stdin
#
function batchcutpkg() {
	awk -F- -f /usr/libexec/slackpkg/cutpkg.awk
}

# Show the slackpkg usage
#
function usage() {
	echo -e "\
slackpkg - version $VERSION\n\
\nUsage:\n\
\tslackpkg [OPTIONS] {install|remove|search|file-search|
\t\t\t    download|upgrade|reinstall} {PATTERN|FILE}
\tslackpkg [OPTIONS] {generate-template|install-template|remove-template}
\t\t\t   TEMPLATENAME
\tslackpkg [OPTIONS] info PACKAGE
\tslackpkg [OPTIONS] update [gpg]
\tslackpkg [OPTIONS] {clean-system|upgrade-all|install-new}
\tslackpkg [OPTIONS] {new-config|check-updates|show-changelog|help}
\nIf you need more information try to use 'slackpkg help' or look the\n\
slackpkg's manpage.
"
	cleanup
}

function full_usage() {
	echo -e "\
slackpkg - version $VERSION\n\
\nUsage: \tslackpkg update [gpg]\t\tdownload and update files and 
\t\t\t\t\tpackage indexes
\tslackpkg check-updates\t\tcheck if there is any news on
\t\t\t\t\tSlackware's ChangeLog.txt
\tslackpkg show-changelog\t\tshow Slackware ChangeLog.txt and exit
\tslackpkg install package\tdownload and install packages 
\tslackpkg upgrade package\tdownload and upgrade packages
\tslackpkg reinstall package\tsame as install, but for packages 
\t\t\t\t\talready installed
\tslackpkg remove package\t\tremove installed packages
\tslackpkg clean-system\t\tremove all packages which are not 
\t\t\t\t\tpresent in the official Slackware 
\t\t\t\t\tpackage set. Good to keep the house
\t\t\t\t\tin order
\tslackpkg upgrade-all\t\tsync all packages installed in your 
\t\t\t\t\tmachine with the selected mirror. This
\t\t\t\t\tis the "correct" way to upgrade all of 
\t\t\t\t\tyour machine.
\tslackpkg install-new\t\tinstall packages which are added to
\t\t\t\t\tthe official Slackware package set.
\t\t\t\t\tRun this if you are upgrading to another
\t\t\t\t\tSlackware version or using "current".
\tslackpkg download\t\tOnly download (do not install) a package
\tslackpkg info package\t\tShow package information 
\t\t\t\t\t(works with only ONE package)
\tslackpkg search package\t\tSearch packages that have a
\t\t\t\t\tselected name
\tslackpkg file-search file\tSearch for a specific file in the
\t\t\t\t\tentire package collection
\tslackpkg new-config\t\tSearch for new configuration files and
\t\t\t\t\task to user what to do with them.
\tslackpkg generate-template\tCreate a template with all 
\t\t\t\t\tofficial Slackware packages installed 
\t\t\t\t\tin your machine.
\tslackpkg install-template\tInstall selected template.
\tslackpkg remove-template\tRemove selected template. Be careful.
\tslackpkg help\t\t\tShow this screen. 
\nYou can see more information about slackpkg usage and some examples
in slackpkg's manpage. You can use partial package names (such as xorg 
instead of xorg-server, xorg-docs, etc), or even Slackware series
(such as "n","ap","xap",etc) when searching for packages.
\nWhen blacklisting packages you can use extended regex on package names
(such as xorg-.* instead of xorg-server, xorg-docs, etc), and a trailing 
slash for package series ("n/", "ap/", "xap/", etc).

Note that special characters in blacklisted package names, such as '+', need
escaping: gcc-g\\+\\+"
	cleanup
}

# Verify if we have enough disk space to install selected package
#
function havespace() {
	local DSIZE
	local ASIZE
	DSIZE=$(grep "^${1}" ${TMPDIR}/tempsize | \
		awk 'BEGIN { tot=0 } { tot+=$2 } END { print int(tot/1024)+1}')
	ASIZE=$(df ${1} | awk '/% \// { print 0+$(NF-2) }')
	if [ ${DSIZE} -gt ${ASIZE} ] ; then
		ISOK=0
	fi
}

function checksize() {
	local i
	local ISOK=1
	tar -tvf ${1} | tr -s ' ' | grep -v '^[dl]' | cut -f6,3 -d\ | \
	sed 's,[^/]*$,,' | awk '
	{ size[$2]+=$1 }
	END { 
	    	for (i in size) { 
			print "/"i,size[i]
		}
	}' > ${TMPDIR}/tempsize

	for i in $(tac /proc/mounts | grep "^/dev" |cut -f2 -d\ ); do
		if grep -q "^${i}" ${TMPDIR}/tempsize ; then
			havespace ${i}
			grep -v "^${i}/" ${TMPDIR}/tempsize > ${TMPDIR}/tempsize.tmp
			mv ${TMPDIR}/tempsize.tmp ${TMPDIR}/tempsize
		fi	
	done
	echo ${ISOK}
}

# Verify if the package was corrupted by checking md5sum
#
function checkmd5() {
	local MD5ORIGINAL
	local MD5DOWNLOAD

	MD5ORIGINAL=$(	grep -v "/source/" ${CHECKSUMSFILE} |\
			grep -m1 "/$(basename $1)$" | cut -f1 -d \ )
	MD5DOWNLOAD=$(md5sum ${1} | cut -f1 -d \ )
	if [ "$MD5ORIGINAL" = "$MD5DOWNLOAD" ]; then
		echo 1 
	else
		echo 0 
	fi
}

# Verify the GPG signature of files/packages
#
function checkgpg() {
	gpg --verify ${1}.asc ${1} 2>/dev/null && echo "1" || echo "0"
}

# Fetch $SLACKKEY from a trusted source
function get_gpg_key() {
	if ping -c 1 www.slackware.com &>/dev/null; then
		if printf "$ARCH" | grep -q -e "arm" -e "aarch64" &>/dev/null ; then
			echo -e "\t\t\tGetting key from https://www.slackware.com/infra/keys/arm/GPG-KEY"
			$DOWNLOADER $TMPDIR/gpgkey https://www.slackware.com/infra/keys/arm/GPG-KEY &>/dev/null
			# Backup: https://arm.slackware.com/keys/GPG-KEY
		else
			echo -e "\t\t\tGetting key from https://www.slackware.com/infra/keys/GPG-KEY"
			$DOWNLOADER $TMPDIR/gpgkey https://www.slackware.com/infra/keys/GPG-KEY &>/dev/null
			# Backup: https://mirrors.slackware.com/slackware/slackware-current/GPG-KEY
		fi
	else
                echo -e "\
slackpkg is unable to get the Slackware GPG key from www.slackware.com\n\
If you trust the source you have configured in /etc/slackpkg/mirrors,\n\
slackpkg can import the GPG key from that source.\n\
The source currently in use is:\n\
\t ${SOURCE}\n\
Do you want to import the GPG key from this source? (YES|NO)\n"
                read ANSWER
                case "$ANSWER" in
                        YES|Y|yes|y)
                         	getfile ${SOURCE}GPG-KEY $TMPDIR/gpgkey
                        ;;
                        *)
                                echo -e "\t\tslackpkg is unable to get the Slackware GPG key."
				cleanup
                        ;;
                esac
	fi
}

# Import $SLACKKEY
function import_gpg_key() {
	mkdir -p ~/.gnupg
	gpg --yes --batch --delete-key "$SLACKKEY" &>/dev/null
	gpg --import $TMPDIR/gpgkey &>/dev/null && \
	echo -e "\t\t\tSlackware Linux Project's GPG key added"
}

# Found packages in repository. 
# This function selects the package from the higher priority
# repository directories.
#
function givepriority {
        local DIR
        local ARGUMENT=$1
	local PKGDATA

	unset NAME
        unset FULLNAME
	unset PKGDATA
	
        for DIR in ${PRIORITY[@]} ; do
		[ "$PKGDATA" ] && break
                PKGDATA=( $(grep "^${DIR} ${ARGUMENT} " ${TMPDIR}/pkglist) )
                if [ "$PKGDATA" ]; then
			NAME=${PKGDATA[1]}
                        FULLNAME=$(echo "${PKGDATA[5]}.${PKGDATA[7]}")
                fi
        done
}

# Creates files with mirror package names (spkg), local package
# names (lpkg) and packages unique to one or other file (dpkg)
#
function listpkgname() {
	cut -f2 -d\  ${TMPDIR}/pkglist | sort > ${TMPDIR}/spkg	
	cut -f2 -d\  ${TMPDIR}/tmplist | sort > ${TMPDIR}/lpkg
	cat ${TMPDIR}/pkglist ${TMPDIR}/tmplist | \
		cut -f2-6 -d\ |sort | uniq -u | \
		cut -f1 -d\  | uniq > ${TMPDIR}/dpkg
}

# Create a blacklist of single package names from regexps in original blacklist
# any sets such as kde/ are converted to single package names in the process
# the final list will be used by 'applyblacklist' later.
function mkregex_blacklist() {
	# Check that we have the files we need
	if [ ! -f ${WORKDIR}/pkglist ] || [ ! -f ${CONF}/blacklist ];then
		return 1
	fi

	# Create tmp blacklist in a more usable format
	sed -E "s,(^[[:blank:]]+|[[:blank:]]+$),,
		/(^#|^$)/d
		s,^, ,
		s,$, ,
		s,^ (extra|pasture|patches|slackware(|64)|testing)/ $,^\1 ,
		s,^ ([^/]+)/ $, \\\./$PKGMAIN/\1\$,
		" ${CONF}/blacklist > ${TMPDIR}/blacklist.tmp

	# Filter server and local package lists through blacklist
	( cat ${WORKDIR}/pkglist
		printf "%s\n" $ROOT/var/log/packages/* |
			awk -f /usr/libexec/slackpkg/pkglist.awk
	) | cut -d\  -f1-7 | grep -E -f ${TMPDIR}/blacklist.tmp |
		awk '{print $2}' | sort -u | sed "s,[+],[+],g
		s,$,-[^-]+-($ARCH|noarch|fw)-[^-]+,g" > ${TMPDIR}/blacklist
}

# Blacklist filter
#
function applyblacklist() {
	grep -vxE -f ${TMPDIR}/blacklist
}

# Function to make install/reinstall/upgrade lists
#
function makelist() {
	local ARGUMENT
	local i
	local VRFY

	INPUTLIST=$@

	printf "%s\n" $ROOT/var/log/packages/* |
		awk -f /usr/libexec/slackpkg/pkglist.awk > ${TMPDIR}/tmplist

	cat ${WORKDIR}/pkglist > ${TMPDIR}/pkglist

	touch ${TMPDIR}/waiting

	case "$CMD" in
		clean-system)
			echo -n "Looking for packages to remove. Please wait... "
		;;
		upgrade-all)
			echo -n "Looking for packages to upgrade. Please wait... "
		;;
		install-new)
			echo -n "Looking for NEW packages to install. Please wait... "
		;;
		*-template)
			echo -n "Looking for packages in \"$ARG\" template to ${CMD/%-template/}. Please wait..."
		;;
		*)
			echo -n "Looking for $(echo $INPUTLIST | tr -d '\\') in package list. Please wait... "
		;;
	esac

	[ "$SPINNING" = "off" ] || spinning ${TMPDIR}/waiting &

	case "$CMD" in
		download)
			for ARGUMENT in $(echo $INPUTLIST); do
				for i in $(grep -w -- "${ARGUMENT}" ${TMPDIR}/pkglist | cut -f2 -d\  | sort -u); do
					LIST="$LIST $(grep " ${i} " ${TMPDIR}/pkglist | cut -f6,8 -d\  --output-delimiter=.)"
				done
				LIST="$(echo -e $LIST | sort -u)"
			done
		;;
		blacklist)
			/bin/false
		;;
		install|upgrade|reinstall)
			for ARGUMENT in $(echo $INPUTLIST); do
				for i in $(grep -w -- "${ARGUMENT}" ${TMPDIR}/pkglist | cut -f2 -d\  | sort -u); do
					givepriority $i
					[ ! "$FULLNAME" ] && continue

					case $CMD in
						'upgrade')
							VRFY=$(cut -f6 -d\  ${TMPDIR}/tmplist | \
							      grep -x "${NAME}-[^-]\+-\(noarch\|fw\|${ARCH}\)-[^-]\+")
							[ "${FULLNAME/%.t[blxg]z/}" != "${VRFY}" ]  && \
										[ "${VRFY}" ] && \
								LIST="$LIST ${FULLNAME}"
						;;
						'install')
							grep -q " ${NAME} " ${TMPDIR}/tmplist || \
								LIST="$LIST ${FULLNAME}"
						;;
						'reinstall')
							grep -q " ${FULLNAME/%.t[blxg]z} " ${TMPDIR}/tmplist && \
								LIST="$LIST ${FULLNAME}"
						;;
					esac
				done
			done
		;;
		remove)
			for ARGUMENT in $(echo $INPUTLIST); do
				for i in $(cat ${TMPDIR}/pkglist ${TMPDIR}/tmplist | \
					  	grep -w -- "${ARGUMENT}" | cut -f6 -d\  | sort -u); do
					PKGDATA=( $(grep -w -- "$i" ${TMPDIR}/tmplist) )
					[ ! "$PKGDATA" ] && continue
					LIST="$LIST ${PKGDATA[5]}" 
					unset PKGDATA
				done
			done
		;;
		clean-system)
			listpkgname
			for i in $(comm -2 -3 ${TMPDIR}/lpkg ${TMPDIR}/spkg) ; do
				PKGDATA=( $(grep -- "^local $i " ${TMPDIR}/tmplist) )
				[ ! "$PKGDATA" ] && continue
				LIST="$LIST ${PKGDATA[5]}" 
				unset PKGDATA
			done				
		;;
		upgrade-all)
			listpkgname
			for i in $(comm -1 -2 ${TMPDIR}/lpkg ${TMPDIR}/dpkg | \
				   comm -1 -2 - ${TMPDIR}/spkg) ; do
	
				givepriority ${i}
				[ ! "$FULLNAME" ] && continue

				VRFY=$(cut -f6 -d\  ${TMPDIR}/tmplist | grep -x "${NAME}-[^-]\+-\(noarch\|fw\|${ARCH}\)-[^-]\+")
				[ "${FULLNAME/%.t[blxg]z}" != "${VRFY}" ]  && \
							[ "${VRFY}" ] && \
					LIST="$LIST ${FULLNAME}"
			done
		;;
		install-new)
			for i in $(awk -f /usr/libexec/slackpkg/install-new.awk ${WORKDIR}/ChangeLog.txt |\
				  sort -u ) dialog aaa_terminfo fontconfig \
				ntfs-3g ghostscript wqy-zenhei-font-ttf \
				xbacklight xf86-video-geode ; do
	
				givepriority $i
				[ ! "$FULLNAME" ] && continue
				
				grep -q " ${NAME} " ${TMPDIR}/tmplist || \
					LIST="$LIST ${FULLNAME}"
			done
		;;
		install-template)
			for i in $INPUTLIST ; do
				givepriority $i
				[ ! "$FULLNAME" ] && continue
				grep -q " ${NAME} " ${TMPDIR}/tmplist || \
					LIST="$LIST ${FULLNAME}"
			done
		;;	
		remove-template)
			for i in $INPUTLIST ; do
				givepriority $i
				[ ! "$FULLNAME" ] && continue
				grep -q " ${NAME} " ${TMPDIR}/tmplist && \
					LIST="$LIST ${FULLNAME}"
			done
		;;	
		search|file-search)
				# -- temporary file used to store the basename of selected
				#    packages.

			PKGNAMELIST=$(mktemp -p ${TMPDIR} -t slackpkg.XXXXXXXXXXXX)

			if [ "$CMD" = "file-search" ]; then
				# Search filelist.gz for possible matches
				for i in ${PRIORITY[@]}; do
					if [ -e ${WORKDIR}/${i}-filelist.gz ]; then
						PKGS="$(zegrep -w "${INPUTLIST}" ${WORKDIR}/${i}-filelist.gz | \
							cut -d\  -f 1 | awk -F'/' '{print $NF}')"
						for FULLNAME in $PKGS ; do
							NAME=$(cutpkg ${FULLNAME})
							grep -q "^${NAME}$" $PKGNAMELIST && continue
							LIST="$LIST ${FULLNAME}"
							echo "$NAME" >> $PKGNAMELIST
						done
					fi
				done
			else
				for i in ${PRIORITY[@]}; do

					PKGS=$( cut -d\  -f1-7 ${TMPDIR}/pkglist |
						grep "^${i}.*${PATTERN}" | cut -f6 -d\ )

					for FULLNAME in $PKGS ; do
						NAME=$(cutpkg ${FULLNAME})

						grep -q "^${NAME}$" $PKGNAMELIST && continue
						LIST="$LIST ${FULLNAME}"
						echo "$NAME" >> $PKGNAMELIST
					done
				done
			fi
			rm -f $PKGNAMELIST
		;;	
	esac
	LIST=$( printf "%s\n" $LIST | applyblacklist | sort | uniq )

	rm ${TMPDIR}/waiting

	echo -e "DONE\n"
}

# Function to count total of packages
#
function countpkg() {
	local COUNTPKG=$(echo -e "$1" | wc -w)

	if [ "$COUNTPKG" != "0" ]; then
		echo -e "Total package(s): $COUNTPKG\n"
	fi
}

function answer() {
	if [ "$BATCH" = "on" ]; then
		ANSWER="$DEFAULT_ANSWER"
		echo $DEFAULT_ANSWER
	else
		read ANSWER
	fi
}

function searchlist() {
	local i
	local BASENAME
	local RAWNAME
	local STATUS
	local INSTPKG

	for i in $1; do
	    if [ "$BASENAME" = "$(cutpkg ${i})" ]; then
		continue
	    fi
	    # BASENAME is base package name 
	    BASENAME="$(cutpkg ${i})"

	    # RAWNAME is Latest available version  
	    RAWNAME="${i/%.t[blxg]z/}"

	    # Default is uninstalled
	    STATUS="uninstalled"

	    # First is the package already installed?
	    # Amazing what a little sleep will do
	    # exclusion is so much nicer :)
	    INSTPKG=$(ls -1 $ROOT/var/log/packages/ | \
		grep -e "^${BASENAME}-[^-]\+-\(${ARCH}\|fw\|noarch\)-[^-]\+")

		# INSTPKG is local version
		if [ ! "${INSTPKG}" = "" ]; then

		# If installed is it uptodate?
		if [ "${INSTPKG}" = "${RAWNAME}" ]; then
		    STATUS=" installed "
		    echo "[${STATUS}] - ${INSTPKG}"
		else
		    STATUS="  upgrade  "
				INSTPKG=$( printf "$INSTPKG" | tr '\n' ' ' )

				if echo "$INSTPKG" | grep -q ' '; then
					printf "%s - %s / %s\n            --> %s\n" \
						"[${STATUS}]" ${INSTPKG} ${RAWNAME}
				else
					echo "[${STATUS}] - ${INSTPKG} --> ${RAWNAME}"
				fi
		fi
		else
		    echo "[${STATUS}] - ${RAWNAME}"
		fi
	done
}

# Show the lists and asks if the user want to proceed with that action
# Return accepted list in $SHOWLIST
#
function showlist() {
	local ANSWER
	local i

	for i in $1; do echo $i; done | $MORECMD
	echo
	countpkg "$1"
	echo -e "Do you wish to $2 selected packages (Y/n)? \c"
	answer
	if [ "$ANSWER" = "N" -o "$ANSWER" = "n" ]; then
		cleanup
	else
		SHOWLIST="$1"
	fi
}

function getfile() {
        if [ "$LOCAL" = "1" ]; then
                echo -e "\t\t\tLinking $1..."
                if [ -e $1 ]; then
			ln -s $1 $2 2>/dev/null
		else
			return 1
		fi
        else
                echo -e "\t\t\tDownloading $1..."
		$DOWNLOADER $2 $1
        fi
}

# Function to download the correct package and many "checks"
#
function getpkg() {
	local ISOK="1"
	local ERROR=""
	local PKGNAME
	local FULLPATH
	local NAMEPKG
	local CACHEPATH

	PKGNAME=( $(grep -m 1 -- "[[:space:]]${1/%.t[blxg]z/}[[:space:]]" ${TMPDIR}/pkglist) )
	NAMEPKG=${PKGNAME[5]}.${PKGNAME[7]}
	FULLPATH=${PKGNAME[6]}
	CACHEPATH=${ROOT}/${TEMP}/${FULLPATH}
	CACHEPATH="${CACHEPATH#/}" # Remove / in //var/log/packages

	# Create destination dir if it isn't there
	if ! [ -d $CACHEPATH ]; then
		mkdir -p $CACHEPATH
	fi

	if ! [ -e ${CACHEPATH}/${NAMEPKG} ]; then
		echo -e "\nPackage: $1"
		# Check if the mirror are local, if is local, copy files 
		# to CACHEPATH else, download packages from remote host and 
		# put then in CACHEPATH
		#
		getfile ${SOURCE}${FULLPATH}/${NAMEPKG} \
			${CACHEPATH}/${NAMEPKG} 
		if [ "$CHECKGPG" = "on" ]; then
			getfile ${SOURCE}${FULLPATH}/${NAMEPKG}.asc \
				${CACHEPATH}/${NAMEPKG}.asc
		fi

		if ! [ -e ${CACHEPATH}/$1 ]; then
			ERROR="Not found"
			ISOK="0"
			echo -e "${NAMEPKG}:\t$ERROR" >> $TMPDIR/error.log
		fi
	else
		echo -e "\tPackage $1 is already in cache - not downloading" 
	fi

	# Check if we have sufficient disk space to install selected package
        if [ "$CHECKSIZE" = "on" ] && [ "$ISOK" = "1" ]; then
		ISOK=$(checksize ${CACHEPATH}/$1)
		if [ "$ISOK" = "0" ]; then
			ERROR="Insufficient disk space"
			echo -e "${NAMEPKG}:\t$ERROR" >> $TMPDIR/error.log
		fi
	fi

	# If MD5SUM checks are enabled in slackpkg.conf, check the
	# packages md5sum to detect if they are corrupt or not
	#
	if [ "$CHECKMD5" = "on" ] && [ "$ISOK" = "1" ]; then
		ISOK=$(checkmd5 ${CACHEPATH}/$1)
		if [ "$ISOK" = "0" ]; then 
			ERROR="md5sum"
			echo -e "${NAMEPKG}:\t$ERROR" >> $TMPDIR/error.log
		fi
		if [ "$CHECKGPG" = "on" ] && [ "$ISOK" = "1" ]; then
			ISOK=$(checkmd5 ${CACHEPATH}/$1.asc)
			if [ "$ISOK" = "0" ]; then 
				ERROR="md5sum"
				echo -e "${NAMEPKG}.asc:\t$ERROR" >> \
							$TMPDIR/error.log
			fi
		fi
	fi

	# Check the package against its .asc. If you don't like this
	# disable GPG checking in /etc/slackpkg/slackpkg.conf
	#
	if [ "$CHECKGPG" = "on" ] && [ "$ISOK" = "1" ]; then
		ISOK=$(checkgpg ${CACHEPATH}/$1)
		if [ "$ISOK" = "0" ]; then 
			ERROR="gpg"
			echo -e "${NAMEPKG}:\t$ERROR" >> $TMPDIR/error.log
		fi
	fi

	if [ "$ISOK" = "1" ]; then
		case $2 in
			installpkg)
				echo -e "\tInstalling ${1/%.t[blxg]z/}..."
			;;
			upgradepkg)
				echo -e "\tUpgrading ${1/%.t[blxg]z/}..."
			;;
			*)
				echo -e "\c"
			;;
		esac	
		( cd $CACHEPATH && $2 $1 )
	else 
		rm $CACHEPATH/$1 2>/dev/null
		echo -e "\tERROR - Package not installed! $ERROR error!" 
	fi

	# If DELALL is checked, all downloaded files will be erased
	# after installed/upgraded/reinstalled
	#
	if [ "$DELALL" = "on" ]; then
		rm $CACHEPATH/$1 $CACHEPATH/${1}.asc 2>/dev/null
	fi		
}

# Main logic to download and format package list, md5 etc.
#
# Check if anything has changed. If so, return 1, else 0 if no change.
function checkchangelog()
{
	if ! [ -e ${WORKDIR}/CHECKSUMS.md5.asc ]; then
		touch ${WORKDIR}/CHECKSUMS.md5.asc
	fi

	if ! [ -e ${WORKDIR}/ChangeLog.txt ]; then
		touch ${WORKDIR}/ChangeLog.txt
	fi

	# First we will download CHECKSUMS.md5.asc since it is a very small
	# file and if it has not changed, we can know that the ChangeLog
	# has not changed either.
	echo -e "\tDownloading..."
	getfile ${SOURCE}CHECKSUMS.md5.asc $TMPDIR/CHECKSUMS.md5.asc
	if ! grep -q "PGP" $TMPDIR/CHECKSUMS.md5.asc ; then
		echo -e "\
\nError downloading from $SOURCE.\n\
Please check your mirror and try again."
		cleanup
	fi
	if diff --brief ${WORKDIR}/CHECKSUMS.md5.asc $TMPDIR/CHECKSUMS.md5.asc ; then
		return 0
	else
		return 1
	fi
}

function updatefilelists()
{
	echo "Updating the package lists..."
	if checkchangelog ; then
		echo -e "\
\n\t\tNo changes in ChangeLog.txt between your last update and now.\n\
\t\tDo you really want to download all other files (y/N)? \c"
		answer
		if [ "$ANSWER" != "Y" ] && [ "$ANSWER" != "y" ]; then
			cleanup
		fi
	fi
	echo
	#
	# Download ChangeLog.txt first
	#
	echo -e "\tDownloading..."
	getfile ${SOURCE}ChangeLog.txt $TMPDIR/ChangeLog.txt
	if ! grep -q "[a-z]" $TMPDIR/ChangeLog.txt ; then
		echo -e "\
\nError downloading from $SOURCE.\n\
Please check your mirror and try again."
		cleanup
	fi
	#
	# Download MANIFEST, FILELIST.TXT and CHECKSUMS.md5
	#

	# That will be download MANIFEST.bz2 files
	#
	echo -e "\t\tList of all files"
	for i in ${PRIORITY[@]} ; do 
		getfile ${SOURCE}${i}/MANIFEST.bz2 $TMPDIR/${i}-MANIFEST.bz2 && \
			DIRS="$DIRS $i"
	done

	ISOK="1"
	echo -e "\t\tChecksums"
	getfile ${SOURCE}CHECKSUMS.md5 ${TMPDIR}/CHECKSUMS.md5
	getfile ${SOURCE}CHECKSUMS.md5.asc ${TMPDIR}/CHECKSUMS.md5.asc
	if ! [ -e "${TMPDIR}/CHECKSUMS.md5" ]; then
		echo -e "\
\n\t\tWARNING: Your mirror appears incomplete and is missing the\n\
\t\t         CHECKSUMS.md5 file. We recommend you change your mirror\n\
\t\t         so that package integrity can be verified against \n\
\t\t         CHECKSUMS.md5.\n"
		sleep 10
	else
		if [ "$CHECKGPG" = "on" ]; then
			ISOK=$(checkgpg ${TMPDIR}/CHECKSUMS.md5)
			if [ "$ISOK" = "0" ]; then 
				rm $TMPDIR/CHECKSUMS.md5
				rm $TMPDIR/CHECKSUMS.md5.asc
				echo -e "\
\n\t\tERROR: Verification of the  gpg signature on CHECKSUMS.md5\n\
\t\t       failed! This could mean that the file is out of date\n\
\t\t       or has been tampered with. If you use mirrors.slackware.com\n\
\t\t       as your mirror, this could also mean that the mirror to\n\
\t\t       which you got redirected is not yet updated with the most\n\
\t\t       recent changes in the Slackware tree.\n"
				cleanup
			fi
		elif [ "$SLACKKEY" != "" ]; then
			echo -e "\
\n\t\tWARNING: Without CHECKGPG, we can't check if this file is\n\
\t\t         signed by:\n\
\n\t\t         $SLACKKEY.\n\
\n\t\t         Enabling CHECKGPG is highly recommended for best\n\
\t\t         security.\n"
				sleep 10
		fi
	fi

	ISOK="1"
	echo -e "\t\tPackage List"
	getfile ${SOURCE}FILELIST.TXT ${TMPDIR}/FILELIST.TXT
	if [ "$CHECKMD5" = "on" ]; then
		CHECKSUMSFILE=${TMPDIR}/CHECKSUMS.md5
		ISOK=$(checkmd5 ${TMPDIR}/FILELIST.TXT)
	fi
	if [ "$ISOK" = "1" ]; then 
		if ! [ -e ${WORKDIR}/LASTUPDATE ]; then
			echo "742868196" > ${WORKDIR}/LASTUPDATE
		fi
		LASTUPDATE=$(cat ${WORKDIR}/LASTUPDATE)
		ACTUALDATE=$(date -d "$(head -1 $TMPDIR/FILELIST.TXT)" "+%s")
		if [ $ACTUALDATE -lt $LASTUPDATE ]; then
			echo -e "\
\n\t\tFILELIST.TXT seems to be older than the last one.\n\
\t\tDo you really want to continue (y/N)? \c"
			answer
			if [ "$ANSWER" != "Y" ] && [ "$ANSWER" != "y" ]; then
				cleanup
			fi
			echo
		fi
		echo $ACTUALDATE > ${WORKDIR}/LASTUPDATE
	else
		rm $TMPDIR/FILELIST.TXT
	fi
	
	if [ -e $TMPDIR/CHECKSUMS.md5 ]; then
		FILELIST="$TMPDIR/CHECKSUMS.md5"
	elif [ -e $TMPDIR/FILELIST.TXT ]; then
		if [ "$ISOK" = "0" ]; then
			echo -e "\
\n\t\tERROR: CHECKSUMS.md5 signature doesn't match!\n\
\t\t       We strongly recommend that you change your mirror\n\
\t\t       to prevent security problems.\n"
			cleanup
		fi
		sleep 10
	  	FILELIST="$TMPDIR/FILELIST.TXT"
	else
		echo -e "\
\n\t\tERROR: No CHECKSUMS.md5 and no FILELIST.TXT.\n\
\t\t       We strongly recommend that you change your mirror\n\
\t\t       to prevent security problems.\n"
		cleanup
	fi 

	# Download all PACKAGES.TXT files
	# 
	echo -e "\t\tPackage descriptions"
	for i in $DIRS; do
		getfile ${SOURCE}${i}/PACKAGES.TXT $TMPDIR/${i}-PACKAGES.TXT
	done

	# Format FILELIST.TXT
	#
	echo -e "\tFormatting lists to slackpkg style..."
	echo -e "\t\tPackage List: using $( basename $FILELIST ) as source"
	grep "\.t[blxg]z$" $FILELIST| \
		awk -f /usr/libexec/slackpkg/pkglist.awk |\
		sed -e 's/^M//g' > ${TMPDIR}/pkglist
	cp ${TMPDIR}/pkglist ${WORKDIR}/pkglist

	# Create the slackware tree under TEMP directory
	for i in $( cut -f7 -d\  ${WORKDIR}/pkglist | sort -u ) ; do
	  if ! [ -d ${ROOT}/${TEMP}/${i} ]; then
	    mkdir -p ${ROOT}/${TEMP}/${i}
	  fi
	done

	# Format MANIFEST
	#
		
	# bunzip and concatenate all MANIFEST files
	#
	MANFILES=""
	for i in $DIRS; do
		bunzip2 -c $TMPDIR/${i}-MANIFEST.bz2 | awk -f /usr/libexec/slackpkg/filelist.awk | \
			gzip > ${TMPDIR}/${i}-filelist.gz
	done
	cp ${TMPDIR}/*-filelist.gz ${WORKDIR}/

	if [ -r ${WORKDIR}/filelist.gz ]; then
		rm ${WORKDIR}/filelist.gz
		ln -s ${WORKDIR}/${MAIN}-filelist.gz ${WORKDIR}/filelist.gz
	fi

	# Concatenate PACKAGE.TXT files
	#
	echo -e "\t\tPackage descriptions"
	for i in $DIRS; do
		cat $TMPDIR/${i}-PACKAGES.TXT >> $TMPDIR/PACKAGES.TXT
	done
	cp $TMPDIR/PACKAGES.TXT ${WORKDIR}/PACKAGES.TXT

	if [ -e $TMPDIR/CHECKSUMS.md5 ]; then
		cp $TMPDIR/CHECKSUMS.md5 ${WORKDIR}/CHECKSUMS.md5 2>/dev/null
	fi

	if [ -e $TMPDIR/CHECKSUMS.md5.asc ]; then
		cp $TMPDIR/CHECKSUMS.md5.asc \
			${WORKDIR}/CHECKSUMS.md5.asc 2>/dev/null
	fi
	# Finally, copy ChangeLog.txt
	if [ -e $TMPDIR/ChangeLog.txt ]; then
		cp $TMPDIR/ChangeLog.txt \
			${WORKDIR}/ChangeLog.txt 2>/dev/null
	fi
}

function sanity_check() {
	local REVNAME
	local i
	local FILES
	local DOUBLEFILES
	local ANSWER

	touch ${TMPDIR}/waiting
	echo -e "Checking local integrity... \c"

	[ "$SPINNING" = "off" ] || spinning ${TMPDIR}/waiting &

	for i in $(ls -1 $ROOT/var/log/packages/ | \
		grep -E -- "^.*-(${ARCH}|fw|noarch)-[^-]+-upgraded"); do
		REVNAME=$(echo ${i} | awk -F'-upgraded' '{ print $1 }')
		mv $ROOT/var/log/packages/${i} $ROOT/var/log/packages/${REVNAME}
		mv $ROOT/var/log/scripts/${i} $ROOT/var/log/scripts/${REVNAME}
	done
	
	DOUBLEFILES=$( ls -1 $ROOT/var/log/packages/ |
		batchcutpkg | uniq -D | sort -u | sed "s,[+],[+],g" |
		xargs -I '{}' find $ROOT/var/log/packages/ -regextype awk -regex \
		".*/{}-[^-]+-($ARCH|noarch|fw)-[^-]+" | awk -F/ '{print $NF}' |
		applyblacklist )

	rm ${TMPDIR}/waiting
	echo -e "DONE"

	if [ "$DOUBLEFILES" != "" ]; then
		echo -e "\
You have a broken $ROOT/var/log/packages/ - with multiple versions of the same package.\n\
The list of packages duplicated in your machine is shown below:\n"
		printf "%s\n" $DOUBLEFILES

		echo -ne "\n\
You can (R)emove one or more of, or (I)gnore these packages.\n\
Select your action (R/I): "
		read ANSWER
		echo
		case "$ANSWER" in
			R|r)
				showlist "$DOUBLEFILES" remove
				remove_pkg
			;;
			*)
				echo "Remove one or more of OR blacklist the affected packages in order
for slackpkg to work properly.
"
				echo "To blacklist the affected packages, edit /etc/slackpkg/blacklist"
				cleanup
			;;
		esac
	fi
}	

# Checks if a critical package were upgraded by Slackpkg.
# The /var/run/needs_restarting file contains the list of upgraded
# packages.
#
# The file only is created if /var/run filesystem type is tmpfs so
# the reboot will clean it
function needs_restarting() {
	if [ "$(stat -f -c %T /var/run/)" = "tmpfs" ]; then
		find $ROOT/var/log/packages/ -cnewer $TMPDIR/timestamp -type f \( \
			-name "kernel-generic-[0-9]*" -o \
			-name "kernel-huge-[0-9]*" -o \
			-name "openssl-solibs-[0-9]*" -o \
			-name "openssl-[0-9]*" -o \
			-name "glibc-[0-9]*" -o \
			-name "aaa_glibc-solibs-[0-9]*" -o \
			-name "eudev-[0-9]*" -o \
			-name "elogind-[0-9]*" -o \
			-name "dbus-[0-9]*" \) | \
		awk -F/ '{ print $NF }' >> $ROOT/var/run/needs_restarting
	fi
}

function remove_pkg() {
	local i

	for i in $SHOWLIST; do
		echo -e "\nPackage: $i"
		echo -e "\tRemoving... "
		removepkg $i
        done
}

function upgrade_pkg() {
	local i

	if [ "$DOWNLOAD_ALL" = "on" ]; then
		OLDDEL="$DELALL"
		DELALL="off"
		for i in $SHOWLIST; do
			getpkg $i true
		done
		DELALL="$OLDDEL"
	fi
	for i in $SHOWLIST; do
		getpkg $i upgradepkg Upgrading
	done
	needs_restarting
}

function install_pkg() {
	local i

	if [ "$DOWNLOAD_ALL" = "on" ]; then
		OLDDEL="$DELALL"
		DELALL="off"
		for i in $SHOWLIST; do
			getpkg $i true
		done
		DELALL="$OLDDEL"
	fi
	for i in $SHOWLIST; do
		getpkg $i installpkg Installing
	done
}

#
# Template related functions
#
include_includes() {
	TEMPLATEFILE=$1
	COUNT=$((COUNT + 1))
	TMPFILE=$TMPDIR/$(basename $( echo $TEMPLATEFILE | cut -f1,2 -d. )).$COUNT.tmp
	INCLUDELIST="$( grep "^#include" $TEMPLATEFILE | cut -d\  -f2 )"
	if [ "$INCLUDELIST" != "" ]; then
		for INCLUDE in $INCLUDELIST ; do
			echo "#include $INCLUDE" \
				>> ${TMPFILE/.$COUNT/}.header
			cat $INCLUDE > $TMPFILE
			grep -v "^$" $TEMPLATEFILE | grep -v "^#" >> $TMPFILE
			include_includes $TMPFILE
		done
	else
		echo $TEMPLATEFILE
		return
	fi
}

parse_template() {
	if [ "$USE_INCLUDES" = "off" ]; then
		touch $TMPDIR/$1.header
		grep -v "^$" $1 | grep -v "^#" | sort -u > $TMPDIR/$1.tmp
	else
		TMPFILE=$(include_includes $1)
		sort -u $TMPFILE > $TMPDIR/$1.tmp
		if [ -e $TMPDIR/$1.tmp.header ]; then
			sort -u $TMPDIR/$1.tmp.header > $TMPDIR/$1.header
		fi
		rm $TMPDIR/$1.[0-9]*.tmp $TMPDIR/$1.tmp.header 2>/dev/null
	fi
}

generate_template() {
	if [ "$USE_INCLUDES" = "on" ]; then
		(
			cd $TEMPLATEDIR
			if [ "$(ls *.template 2>/dev/null)" != "" ]; then
				echo -e "\tParsing actual template files:"
				for i in *.template ; do
					echo -e "\t\t$i"
					parse_template $i
				done
			fi
		)
	fi

	touch $TMPDIR/allheaders

	touch $TMPDIR/waiting
	echo -e "\tGenerating slackware installed package list (this may take a while) \c"
	[ "$SPINNING" = "off" ] || spinning ${TMPDIR}/waiting &
	for i in $ROOT/var/log/packages/* ; do 
		PKGNAME=$( cutpkg $(basename $i))
		grep -q " $PKGNAME " ${WORKDIR}/pkglist && \
			echo $PKGNAME >> $TMPDIR/$TEMPLATE.work
	done  
	rm $TMPDIR/waiting
	echo " "

	echo -e "\tGenerating $TEMPLATE "
	for TMPLATE in $( wc -l $TMPDIR/* | sort -r | \
			  awk -F/ '/template.tmp/ { print $NF }'); do
		if ! $( grep -q "^#include.*${TMPLATE/.tmp/}" \
			$TMPDIR/allheaders) ; then
			diff -y $TMPDIR/$TEMPLATE.work $TMPDIR/$TMPLATE | \
				awk -vTMPDIR=$TMPDIR \
				 	'!/</ { print $1 > TMPDIR"/same" } 
					 /</ { print $1 > TMPDIR"/notsame" }'
			if $( diff -q 	$TMPDIR/$TMPLATE \
					$TMPDIR/same &>/dev/null ); then
				echo "#include ${TMPLATE/.tmp/}" \
					>> $TMPDIR/$TEMPLATE.header
				cat $TMPDIR/${TMPLATE/.tmp/}.header \
					>> $TMPDIR/allheaders 2>/dev/null
				cat $TMPDIR/same >> $TMPDIR/allfiles
			fi
		fi
	done

	if [ -e $TMPDIR/allfiles ]; then
		sort -u $TMPDIR/allfiles > $TMPDIR/alluniqfiles
	else
		touch $TMPDIR/alluniqfiles
	fi
	if [ -e $TMPDIR/$TEMPLATE.header ]; then
		cat $TMPDIR/$TEMPLATE.header > $TEMPLATEDIR/$TEMPLATE
	fi
	diff $TMPDIR/alluniqfiles $TMPDIR/$TEMPLATE.work |\
		 awk '/>/ { print $2 }' >> $TEMPLATEDIR/$TEMPLATE
}
