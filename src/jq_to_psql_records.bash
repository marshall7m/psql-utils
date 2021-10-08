#!/bin/bash
source "$( cd "$( dirname "$BASH_SOURCE[0]" )" && cd "$(git rev-parse --show-toplevel)" >/dev/null 2>&1 && pwd )/node_modules/bash-utils/load.bash"

parse_args() {
	#TODO: Create flag for setting default postgres type for undetected arrays/values and cases where arr = [] or value = null
	# (e.g. --arr-default "TEXT[]" --val-default "VARCHAR")
	log "FUNCNAME=$FUNCNAME" "DEBUG"
	while (( "$#" )); do
		case "$1" in 
			--jq-input)
				if [ -n "$2" ]; then
					jq_in="$2"
					shift 2
				else
					echo "Error: Argument for $1 is missing" >&2
					exit 1
				fi
			;;
			--table)
				if [ -n "$2" ]; then
					table="$2"
					shift 2
				else
					echo "Error: Argument for $1 is missing" >&2
					exit 1
				fi
			;;
			--type-map)
				if [ -n "$2" ]; then
					type_map="$2"
					shift 2
				else
					echo "Error: Argument for $1 is missing" >&2
					exit 1
				fi
			;;
			*)
				echo "Unknown Option: $1"
				exit 1
			;;
		esac
	done
}

table_exists() {
	log "FUNCNAME=$FUNCNAME" "DEBUG"

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

	parse_args "$@"

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

	if ! table_exists "$table"; then
		log "Table does not exists -- creating table" "INFO"
		
		cols_types=$(echo "$jq_in" | jq --arg type_map "$type_map" '
		def psql_type(jq_val):
			jq_val as $jq_val
			| {
				"number": "INT", 
				"string": "VARCHAR", 
				"boolean": "BOOL",
				"null": "VARCHAR"
			} as $type_map
			| if ($jq_val | type) == "array" then
				($jq_val | map(. | type) | unique) as $jq_arr_type
				| if ($jq_arr_type | length) > 1 then
					error("Detected more than one data type" + ($jq_arr_type | tostring))
				elif ($jq_arr_type[0] == "string") then
					"TEXT[]"
				elif $jq_arr_type[0] == "number" then
					"INT[]"
				elif $jq_arr_type[0] == null then
					empty
				else
					error("jq type not handled: " + ($jq_arr_type[0] | tostring))
				end
			else
				($jq_val | type) as $jq_type
				| $type_map[$jq_type] // error("jq type not handled: " + ($jq_type | tostring))	
			end
			;
		
		(try ($type_map | fromjson) // {}) as $type_map
		| if (. | type) == "object" then
			[.]
		else
			.
		end
		| map( . | to_entries) | flatten
		| reduce .[] as $d (null; .[$d.key] += ([$type_map[$d.key] // psql_type($d.value)]))
		| to_entries 
		| map( 
			if (.value | unique | length) == 1 then
				.key + " " + .value[0]
			elif (.value | unique | length) > 1 then
				error("Detected more than one data type: " + .value)
			else
				error("Detected no data type")
			end
		)
		| join(", ")
		') || exit 1
		
		
		cols_types=$(echo "$cols_types" | tr -d '"')
		
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
