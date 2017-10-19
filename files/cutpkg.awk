OFS="-" { 
	if ( NF > 3 ) { 
		NF=NF-3
		print $0 
	} else {
		print $0
	}
}
