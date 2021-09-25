#!/bin/bash

table_exists() {
	echo >&2 "FUNCNAME=$FUNCNAME"

	local table=$1

	res=$(psql -qtAX -c """
	SELECT EXISTS (
		SELECT 
			1 
		FROM 
			information_schema.tables 
		WHERE 
			table_schema = 'public' 
		AND 
			table_name = '$table'
	);
	""")

	echo >&2 "results: $res"

	if [ "$res" == 't' ]; then
		return 0
	else
		return 1
	fi
}

bash_arr_to_psql_arr() {
    log "FUNCNAME=$FUNCNAME" "DEBUG"
    
	local arr=$1
	printf -v psql_array "'%s'," "${arr[@]//\'/\'\'}"
	# remove the trailing ,
	psql_array=${psql_array%,}

	echo "($psql_array)"
}

jq_to_psql_records() {
	log "FUNCNAME=$FUNCNAME" "DEBUG"

	local jq_in=$1
	local table=$2

	if [ -z "$jq_in" ]; then
		log "jq_in is not set" "ERROR"
		exit 1
	elif [ -z "$table" ]; then
		log "table is not set" "ERROR"
		exit 1
	fi

	if table_exists "$table"; then
		log "Adding to existing table" "DEBUG"
	else
		log "Table does not exists -- creating table" "DEBUG"

		cols_types=$(echo "$jq_in" | jq '
		def psql_cols(in):
			{
			"number": "INT", 
			"string": "VARCHAR", 
			"array": "ARRAY[]",
			"boolean": "BOOL"
			} as $psql_types
			| if (in | type) == "array" then 
			map(. | to_entries | map(.key + " " + (.value | type | $psql_types[.])))
			else
			in | to_entries | map(.key + " " + (.value | type | $psql_types[.]))
			end
			| flatten | unique | join(", ")
			;
		psql_cols(.)
		' | tr -d '"')

		log "Columns Types: $cols_types" "DEBUG"

		psql -c "CREATE TABLE IF NOT EXISTS $table ( $cols_types );"
	fi

	# get array of cols for psql insert/select for explicit column ordering
	col_order=$(echo "$jq_in" | jq 'if (. | type) == "array" then map(keys) else keys end | flatten | unique')
	log "Column order: $col_order" "DEBUG"

	csv_table=$(echo "$jq_in" | jq -r --arg col_order "$col_order" '
	($col_order | fromjson) as $col_order
	| if (. | type) == "array" then .[] else . end
	| map_values(if (. | type) == "array" then . |= "{" + join(", ") + "}" else . end) as $stage
	| $col_order | map($stage[.]) | @csv
	')

	log "JQ transformed to CSV strings" "DEBUG"
	log "$csv_table" "DEBUG"

	psql_cols=$(echo "$col_order" | jq 'join(", ")' | tr -d '"')
	log "Loading to table" "INFO"
	echo "$csv_table" | psql -c "COPY $table ($psql_cols) FROM STDIN DELIMITER ',' CSV"
}