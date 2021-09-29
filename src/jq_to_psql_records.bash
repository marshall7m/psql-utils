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

		def psql_type(jq_val):
			{
				"number": "INT", 
				"string": "VARCHAR", 
				"boolean": "BOOL"
			} as $type_map
			| (.value | type) as $jq_type
			| if $jq_type == "array" then (if ($jq_val | map(. | type) | unique) > 1 then "TEXT[]" else "INT[]" end) else $type_map[$jq_val] end;
		
		def psql_cols(in):
			if (in | type) == "array" then 
			map(. | to_entries | map(.key + " " + psql_type(.value))
			else
			in | to_entries | map(.key + " " + psql_type(.value))
			end
			| flatten | unique | join(", ");

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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    jq_to_psql_records "$@"
fi