#!/usr/bin/env bats
load "${BATS_TEST_DIRNAME}/../load.bash"
load "${BATS_TEST_DIRNAME}/../node_modules/bash-utils/load.bash"

load "${BATS_TEST_DIRNAME}/../node_modules/bats-support/load.bash"
load "${BATS_TEST_DIRNAME}/../node_modules/bats-assert/load.bash"
load "${BATS_TEST_DIRNAME}/../node_modules/bats-utils/load.bash"

setup_file() {
    export script_logging_level="DEBUG"
    
    load 'common_setup.bash'
    _common_setup
}

teardown_file() {
    log "FUNCNAME=$FUNCNAME" "DEBUG"
    teardown_test_file_tmp_dir
}

setup() {
    log "FUNCNAME=$FUNCNAME" "DEBUG"
    export table=test_table

    log "Creating table: $table" "DEBUG"
    psql -q -c """
    SELECT 
        'baz' AS bar,
        'zoo koo' AS foo,
        4 AS num,
        ARRAY['kii', 'rii'] AS arr,
        false AS bol
    INTO $table;
    """
    # run_only_test 3
}

teardown() {
    log "FUNCNAME=$FUNCNAME" "DEBUG"

    psql -q -c "DROP TABLE $table;"
    teardown_test_case_tmp_dir
}

@test "Script is runnable" {
    run assert_record_count.bash
}

@test "Query meets conditions" {

    run assert_record_count.bash --table "$table" --assert-count 1 \
        --bar "'baz'" \
        --foo "'zoo koo'" \
        --num 4 \
        --bol 'false' \
        --arr "ARRAY['kii', 'rii']"
    assert_success
}

@test "Query doesn't conditions" {

    run assert_record_count.bash --table "$table" --assert-count 1 \
        --bar "'baz'" \
        --foo "'zoo koo'" \
        --num 1 \
        --arr "ARRAY['kii', 'rii']"
    assert_failure
}