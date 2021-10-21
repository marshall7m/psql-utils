#!/bin/bash
source "$( cd "$( dirname "$BASH_SOURCE[0]" )" && cd "$(git rev-parse --show-toplevel)" >/dev/null 2>&1 && pwd )/node_modules/bash-utils/load.bash"
source "$( cd "$( dirname "$BASH_SOURCE[0]" )" && cd "$(git rev-parse --show-toplevel)" >/dev/null 2>&1 && pwd )/node_modules/bats-support/load.bash"
source "$( cd "$( dirname "$BASH_SOURCE[0]" )" && cd "$(git rev-parse --show-toplevel)" >/dev/null 2>&1 && pwd )/node_modules/bats-assert/load.bash"


assert_record_count() {
    declare -A args
    while (( "$#" )); do
        case "$1" in
            --table)
                if [ -n "$2" ]; then
					table="$2"
					shift 2
				else
					echo "Error: Argument for $1 is missing" >&2
					exit 1
				fi
            ;;
            --assert-count)
                if [ -n "$2" ]; then
					assert_count="$2"
					shift 2
				else
					echo "Error: Argument for $1 is missing" >&2
					exit 1
				fi
            ;;
            --*)
                args[$(echo "${1:2}" | tr '-' '_' )]="$2"
                shift 2
            ;;
        esac
    done

    if [ -z "$assert_count" ]; then
        log "--assert_count is not set" "ERROR"
        exit 1
    fi

    count=0
    for key in "${!args[@]}"; do
        if [ $count -eq 0 ]; then
            sql_cond=$(printf '%s' "WHERE $key = ${args[$key]}")
        else
            sql_cond=$(printf '%s\n\t\t%s' "$sql_cond" "AND $key = ${args[$key]}")
        fi
        count=$(( $count + 1))
    done
    sql=$(cat <<EOF
DO \$\$
    BEGIN
        ASSERT (
            SELECT COUNT(*)
            FROM $table
            $sql_cond
        ) = $assert_count;
    END;
\$\$ LANGUAGE plpgsql;
EOF
)
    log "$sql" "DEBUG"

    psql -q -c "$sql" 
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    assert_record_count "$@"
fi