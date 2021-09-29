load "${BATS_TEST_DIRNAME}/../load.bash"
load "${BATS_TEST_DIRNAME}/../node_modules/bash-utils/load.bash"

load "${BATS_TEST_DIRNAME}/../node_modules/bats-support/load.bash"
load "${BATS_TEST_DIRNAME}/../node_modules/bats-assert/load.bash"
load "${BATS_TEST_DIRNAME}/../node_modules/bats-utils/load.bash"

setup_file() {
    load 'common_setup'

    _common_setup
    export script_logging_level="DEBUG"
    load 'common_setup'

    _common_setup
    log "FUNCNAME=$FUNCNAME" "DEBUG"
}

teardown_file() {
    log "FUNCNAME=$FUNCNAME" "DEBUG"
    teardown_test_file_tmp_dir
}

setup() {
    # run_only_test 1
}

teardown() {
    log "FUNCNAME=$FUNCNAME" "DEBUG"
    # drop_tables
    teardown_test_case_tmp_dir
}

@test "Script is runnable" {
    run jq_to_psql_records.bash
    assert_success
}


@test "invalid jq input" {
    in="foo"
    table="table_$BATS_TEST_NUMBER"
    run jq_to_psql_records.bash "$in" "$table"
    assert_success
}

@test "jq array value" {
    in=$(jq -n '
    {
        "foo": "bar",
        "baz": ["doo"]
    }
    ')
    table="table_$BATS_TEST_NUMBER"
    run jq_to_psql_records.bash "$in" "$table"
    assert_success
}