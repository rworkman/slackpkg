showdiff() {
	BASENAME=$(basename $i .new)
	FILEPATH=$(dirname $i)
	FULLNAME="${FILEPATH}/${BASENAME}"

	if [ -e ${FULLNAME} ]; then
	    diff -u ${FULLNAME} ${FULLNAME}.new | $MORECMD
	else
	    echo "file $FULLNAME doesn't exist"
	fi
}

showmenu() {
	echo -e "$1 - \c"
	tput sc
	shift
	while [ $# -gt 0 ]; do
		echo -e "$1"
		tput rc
		shift
	done
}

mergenew() {
	BASENAME=$(basename $i .new)
	FILEPATH=$(dirname $i)
	FULLNAME="${FILEPATH}/${BASENAME}"

	if [ -e "${FULLNAME}" ]; then
		# in media res. we do the merging right away, but we later allow the user to redo it, if not satisfied with the results.
		rm -f "${FULLNAME}.smerge"
		echo "Enter '?' in the prompt (%) to display help."
		cp -p "${FULLNAME}.new" "${FULLNAME}.smerge" # <- this is so that the installed merged file will have the same permissions as the .new file
		sdiff -s -o "${FULLNAME}.smerge" "${FULLNAME}" "${FULLNAME}.new"

		GOEXM=0
		while [ $GOEXM -eq 0 ]; do
			showmenu $i "(E)dit the merged file" "(I)nstall the merged file" "View a diff between the merged and the (N)ew file" "View a diff between the (O)ld and the merged file" "(R)edo the merge" "(V)iew the merged file" "(B)ack to previous menu, and delete the merged file"
			read ANSWER
			case "$ANSWER" in
				E|e)
					if [ -f "${FULLNAME}.smerge" ]; then
						$EDITCMD "${FULLNAME}.smerge"
					else
						echo -e "Nothing was merged yet..."
					fi
				;;
				I|i)
					if [ -f "${FULLNAME}.smerge" ]; then
						if [ -e "${FULLNAME}" ] && [ "$ORIG_BACKUPS" != "off" ]; then
							mv "${FULLNAME}" "${FULLNAME}.orig"
						fi
						mv "${FULLNAME}.smerge" "${FULLNAME}"
						rm -f "${FULLNAME}.new"
						GOEXM=1
						GOEX=1
					else
						echo -e "Nothing was merged yet..."
					fi
				;;
				N|n)
					if [ -f "${FULLNAME}.smerge" ]; then
						diff -u "${FULLNAME}.smerge" "${FULLNAME}.new" | $MORECMD
					else
						echo -e "Nothing was merged yet..."
					fi
				;;
				O|o)
					if [ -f "${FULLNAME}.smerge" ]; then
						diff -u "${FULLNAME}" "${FULLNAME}.smerge" | $MORECMD
					else
						echo -e "Nothing was merged yet..."
					fi
				;;
				R|r)
					rm -f "${FULLNAME}.smerge"
					echo "Enter '?' in the prompt (%) to display help."
					cp -p "${FULLNAME}.new" "${FULLNAME}.smerge" # <- this is so that the installed merged file will have the same permissions as the .new file
					sdiff -s -o "${FULLNAME}.smerge" "${FULLNAME}" "${FULLNAME}.new"
				;;
				V|v)
					if [ -f "${FULLNAME}.smerge" ]; then
						$MORECMD "${FULLNAME}.smerge"
					else
						echo -e "Nothing was merged yet..."
					fi
				;;
				B|b)
					rm -f "${FULLNAME}.smerge"
					GOEXM=1
				;;
			esac
		done
	else
		echo "file $FULLNAME doesn't exist"
	fi
}

overold() {
	BASENAME=$(basename $i .new)
	FILEPATH=$(dirname $i)
	FULLNAME="${FILEPATH}/${BASENAME}"

	if [ -e ${FULLNAME} ] && [ "$ORIG_BACKUPS" != "off" ]; then
	    mv ${FULLNAME} ${FULLNAME}.orig
	fi
	mv ${FULLNAME}.new ${FULLNAME}
}

removeold() {
	rm $i
}

runvimdiff() {
        BASENAME=$(basename $i .new)
        FILEPATH=$(dirname $i)
        FULLNAME="${FILEPATH}/${BASENAME}"

        if [ -e ${FULLNAME} ]; then
            vimdiff ${FULLNAME} ${FULLNAME}.new
        else
            echo "file $FULLNAME doesn't exist"
        fi
}

looknew() {
	local ROWS SIZE FILES PROMPTTEXT TEXTLINES MAXROWS
	local newcount f n fn
	f=0
	n=0

	# with ONLY_NEW_DOTNEW set, slackpkg will search only for
	# .new files installed in actual slackpkg's execution
	if [ "$ONLY_NEW_DOTNEW" = "on" ]; then
		ONLY_NEW_DOTNEW="-cnewer $TMPDIR/timestamp"
	else
		ONLY_NEW_DOTNEW=""
	fi

	printf "%s\n" "Searching for NEW configuration files..."

	FILES=$( find \
		${ROOT}/etc \
		${ROOT}/var/yp \
		${ROOT}/usr/share/vim \
		-name "*.new" \
		${ONLY_NEW_DOTNEW} \
		-not -name "rc.inet1.conf.new" \
		-not -name "group.new" \
		-not -name "passwd.new" \
		-not -name "shadow.new" \
		-not -name "gshadow.new" 2>/dev/null |
		sort -V 2>/dev/null )

	if [ -n "$FILES" ]; then
		newcount=$( echo "$FILES" | wc -l )
		SIZE=$( stty size )
		ROWS=${SIZE% *}

		# Set here so we can count the No. of lines
		PROMPTTEXT="\n\
What do you want (K/O/R/P)?

	(K)eep the old files and consider .new files later

	(O)verwrite all old files with the new ones"

		[ "$ORIG_BACKUPS" != "off" ] && PROMPTTEXT+=". The
	   old files will be stored with the suffix .orig"

		PROMPTTEXT+="\n\n\
	(R)emove all .new files

	(P)rompt K, O, R selection for every single file\n"

		printf "%s %s\n\n" "Some packages had new configuration" \
			"files installed ($newcount new files):"

		# No. of prompt etc. lines to print.
		TEXTLINES=$(( $( printf %b "$PROMPTTEXT" | wc -l ) + 3 ))

		if [ $(( newcount + TEXTLINES )) -lt $ROWS ]; then
			# All files will fit on screen.
			printf "%s\n" "$FILES"
		else
			# Won't all fit, so scroll a screenfull at a time.
			# No. of lines minus 'Searching for' + 'Press SPACE...'
			MAXROWS=$(( ROWS - 5 ))

			for fn in $FILES; do
				junk=" "
				f=$(( f + 1 ))
				n=$(( n + 1 ))
				echo "$fn"

				# Stop printing at bottom of screen
				if [ $f -ge $MAXROWS ]; then

					# No. of lines minus 'Press SPACE...'
					MAXROWS=$(( ROWS - 2 ))
					f=0
					IFS=$( printf "\n" ) read -rn 1 -p "
	Press SPACE for more, ENTER to skip" junk

					# Enter pressed
					if [ -z "$junk" ]; then
						tput -S <<EOF
						cuu 1
						el 2
						cuu 1
						el 2
EOF
						break
					else
						# Space pressed
						printf "\n"
						tput -S <<EOF
						cuu 1
						el 2
						cuu 1
						el 2
EOF
					fi
				fi
			done

			# Final prompt to stop list scrolling off the top
			if [ ! -z "$junk" ] && [ $f -ne 0 ]; then
				IFS=$( printf "\n" ) read -rn 1 -p "
	Press any key to continue" junk
				printf "\n"
				tput -S <<EOF
				cuu 1
				el 2
				cuu 1
				el 2
EOF
			fi
		fi

		printf %b "$PROMPTTEXT"
		answer
		case $ANSWER in
			K|k)
				break
			;;
			O|o)
				for i in $FILES; do
					overold $i
				done
				break
			;;
			R|r)
				for i in $FILES; do
					removeold $i
				done
				break
			;;
			P|p)
				echo "Select what you want file-by-file"
				for i in $FILES; do
					GOEX=0
					while [ $GOEX -eq 0 ]; do
						echo
						showmenu $i "(K)eep" "(O)verwrite" "(R)emove" "(D)iff" "(M)erge" "(V)imdiff"
						read ANSWER
						case $ANSWER in
							O|o)
								overold $i
								GOEX=1
							;;
							R|r)
								removeold $i
								GOEX=1
							;;
							D|d)
								showdiff $1
							;;
							M|m)
								mergenew $1
							;;
							V|v)
								runvimdiff $1
							;;
							K|k|*)
								GOEX=1
							;;
						esac
					done
				done
				break
			;;
			*)
				echo "
OK! Your choice is nothing! slackpkg will Keep the old files \
for you to deal with later"
			;;
		esac
	else
		echo -e "\t\tNo .new files found."
	fi
}

lookkernel() {
	NEWKERNELMD5=$(md5sum /boot/vmlinuz 2>/dev/null)
	if [ "$KERNELMD5" != "$NEWKERNELMD5" ]; then
		if [ -x /sbin/lilo ] && [ -r /etc/lilo.conf ] && grep -q initrd /etc/lilo.conf ; then
			echo -e "\n
Your kernel image was updated, and your /etc/lilo.conf indicates
the use of an initrd for at least one of your kernels. Be sure to
regenerate the initrd for the new kernel and handle any needed 
updates to your bootloader.
"
		elif [ -x /sbin/lilo ] && [ -r /etc/lilo.conf ] ; then
			echo -e "\n
Your kernel image was updated.  Be sure to handle any needed updates
to your bootloader (possibly as simple as running /sbin/lilo).
"
		else
			echo -e "\n
Your kernel image was updated, and lilo does not appear to be used on 
your system.  You may need to adjust your boot manager (like GRUB) to 
boot the appropriate kernel (after generating an initrd if required)."
		fi
		echo -e "Press the \"Enter\" key to continue...\n "
		read _junk
	fi
}
