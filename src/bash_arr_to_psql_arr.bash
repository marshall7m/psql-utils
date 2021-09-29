bash_arr_to_psql_arr() {
    log "FUNCNAME=$FUNCNAME" "DEBUG"
    
	local arr=$1
	printf -v psql_array "'%s'," "${arr[@]//\'/\'\'}"
	# remove the trailing ,
	psql_array=${psql_array%,}

	echo "($psql_array)"
}