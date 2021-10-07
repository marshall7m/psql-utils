#!/bin/bash
source "$( cd "$( dirname "$BASH_SOURCE[0]" )" && cd "$(git rev-parse --show-toplevel)" >/dev/null 2>&1 && pwd )/node_modules/bash-utils/load.bash"

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

jq_to_psql_records() {
	log "FUNCNAME=$FUNCNAME" "DEBUG"

	local jq_in="$1"
	local table="$2"

	if [ -z "$jq_in" ]; then
		log "jq_in is not set" "ERROR"
		exit 1
	elif [ -z "$table" ]; then
		log "table is not set" "ERROR"
		exit 1
	fi
	
	is_valid_data_type=$(echo "$jq_in" | jq '
	if (. | type) == "array" then
		(if (.[0] | type) == "object" then
			true
		else false
		end)
	elif (. | type) == "object" then
        true
    else
		false
	end
	')

	_=$(echo "$jq_in" | jq '.' 2> /dev/null)
	is_jq=$?
	
	if [ "$is_jq" -ne 0 ] ; then
		log "jq_in must be a jq input" "ERROR"
		exit 1
	elif [ "$is_valid_data_type" == false ]; then
		log "jq_in data type is not one of the following: {} OR [{}]" "ERROR"
		exit 1
	fi

	if table_exists "$table"; then
		log "Adding to existing table" "DEBUG"
	else
		log "Table does not exists -- creating table" "DEBUG"
		
		cols_types=$(echo "$jq_in" | jq '
		def psql_type(jq_val):
			jq_val as $jq_val
			| {
				"number": "INT", 
				"string": "VARCHAR", 
				"boolean": "BOOL"
			} as $type_map
			| if ($jq_val | type) == "array" then
				($jq_val | map(. | type) | unique) as $jq_arr_type
				| if ($jq_arr_type | length) > 1 then
					error("Detected more than one data type" + ($jq_arr_type | tostring))
				elif ($jq_arr_type[0] == "string") then
					"TEXT[]"
				elif $jq_arr_type[0] == "number" then
					"INT[]"
				else
					error("jq type not handled: " + ($jq_arr_type[0] | tostring))
				end
			else
				($jq_val | type) as $jq_type
				| $type_map[$jq_type] // error("jq type not handled: " + $jq_type)	
			end
			;
		
		def psql_cols(in):
			in as $in
			| if ($in | type) == "object" then
				[$in]
			else
				$in
			end
			| map( . | to_entries) | flatten
			| reduce .[] as $d (null; .[$d.key] += [psql_type($d.value)])
			| to_entries 
			| map( 
				if (.value | unique | length) == 1 then
					.key + " " + .value[0] 
				else 
					error("Detected more than one data type: " + .value)
				end
			)
			| join(", ")
			;
		psql_cols(.)
		' | tr -d '"')

		log "Column types: $cols_types" "DEBUG"
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    jq_to_psql_records "$@"
fi
