!/source\// && !/\.asc$/ {
		INPUT=$NF
		fs=FS
		FS="/" ; OFS="/"
		$0=INPUT
		if ( $(NF-3) != "var" ) {
			DIR=$2
			FULLPACK=$NF
		} else {
			DIR="local"
			FULLPACK=$NF".tgz"
		}
		NF=NF-1
		PATH=$0
		FS="-" ; OFS="-"
		$0=FULLPACK
		if ( NF > 3 ) {
			SIZE=split($NF,RELEXT,".")
			EXTENSION=RELEXT[SIZE]
			LAST=length($NF)-4
			RELEASE=substr($NF,1,LAST)
			ARCH=$(NF-1)
			VERSION=$(NF-2)
			NF=NF-3
			NAME=$0
		} else {
			RELEASE=none
			ARCH=none
			VERSION=none
			EXTENSION=tgz
			NAME=$0
		}
		FS=fs 
		print DIR" "NAME" "VERSION" "ARCH" "RELEASE" "NAME"-"VERSION"-"ARCH"-"RELEASE" "PATH" "EXTENSION
}
