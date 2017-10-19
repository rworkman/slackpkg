/^(a|ap|d|e|f|k|kde|kdei|l|mac|n|t|tcl|x|xap|xfce|y)\/([a-zA-Z0-9_\+.\-]+):.* ([Aa]dded|[Ss]plit|[Rr]enamed|[Mm]oved|[Nn]ame [Cc]hange|NAME CHANGE|[Ss]witched).*/ {
	INPUT=$1
	fs=FS
	FS="/" ; OFS="/"
	$0=INPUT
	FULLPACK=$NF
	FS="-" ; OFS="-"
	$0=FULLPACK
	if ( NF > 3 ) { 
		NF=NF-3
	} else {
		FS=":" ; OFS=":"
		$0=$0
		$0=$1
	}
	FS=fs
	CONTINUE=no
	print $0
}

/^(a|ap|d|e|f|k|kde|kdei|l|mac|n|t|tcl|x|xap|xfce|y)\/([a-zA-Z0-9_\+.\-]+): *$/ {
	INPUT=$1
	fs=FS
	FS="/" ; OFS="/"
	$0=INPUT
	FULLPACK=$NF
	FS="-" ; OFS="-"
	$0=FULLPACK
	if ( NF > 3 ) { 
		NF=NF-3
	} else {
		FS=":"
		$0=$1
	}
	FS=fs
	CONTINUE=yes
	NAME=$0
}

/^ *([Aa]dded|[Ss]plit|[Rr]enamed|[Mm]oved|[Nn]ame [Cc]hange|NAME CHANGE|[Ss]witched).*/ {
	if ( CONTINUE==yes ) {
		print NAME
	}
	CONTINUE=no
}
