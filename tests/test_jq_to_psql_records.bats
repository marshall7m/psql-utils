load "${BATS_TEST_DIRNAME}/../load.bash"
load "${BATS_TEST_DIRNAME}/../node_modules/bash-utils/load.bash"

load "${BATS_TEST_DIRNAME}/../node_modules/bats-support/load.bash"
load "${BATS_TEST_DIRNAME}/../node_modules/bats-assert/load.bash"
load "${BATS_TEST_DIRNAME}/../node_modules/bats-utils/load.bash"

setup_file() {
    load 'common_setup.bash'

    _common_setup
    export script_logging_level="DEBUG"

    log "FUNCNAME=$FUNCNAME" "DEBUG"

    psql() {
        echo "MOCK: FUNCNAME=$FUNCNAME"
    }

    export -f psql
}

teardown_file() {
    log "FUNCNAME=$FUNCNAME" "DEBUG"
    teardown_test_file_tmp_dir
}

setup() {
    log "FUNCNAME=$FUNCNAME" "DEBUG"
    # run_only_test 4
}

teardown() {
    log "FUNCNAME=$FUNCNAME" "DEBUG"
    # drop_tables
    teardown_test_case_tmp_dir
}

@test "Script is runnable" {
    run jq_to_psql_records.bash
}

@test "invalid jq input" {
    in="foo"
    table="table_$BATS_TEST_NUMBER"
    run jq_to_psql_records.bash "$in" "$table"
    assert_failure
}



@test "jq object with array value" {
    in=$(jq -n '
    {
        "foo": "bar",
        "baz": ["daz", "zaz"]
    }
    ')
    table="table_$BATS_TEST_NUMBER"
    run jq_to_psql_records.bash "$in" "$table"
    assert_success

    assert_output -p "Column types: foo VARCHAR, baz TEXT[]"

    run psql -c "SELECT * FROM $table;"
    assert_success

    psql -c "DROP TABLE $table;"
}


@test "jq array with array value" {
    in=$(jq -n '
    [
        {
            "foo": "bar",
            "baz": ["daz", "zaz"]
        },
        {
            "foo": "nar",
            "baz": ["doo", "zoo"]
        }
    ]
    ')
    table="table_$BATS_TEST_NUMBER"

    run jq_to_psql_records.bash "$in" "$table"
    assert_success

    assert_output -p "Column types: foo VARCHAR, baz TEXT[]"

    run psql -c "SELECT * FROM $table;"
    assert_success

    psql -c "DROP TABLE $table;"
}