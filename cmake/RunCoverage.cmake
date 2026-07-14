if(NOT DEFINED CTEST_COMMAND OR NOT DEFINED BUILD_DIR OR NOT DEFINED PROFILE_DIR)
    message(FATAL_ERROR "coverage runner requires CTEST_COMMAND, BUILD_DIR, and PROFILE_DIR")
endif()

file(REMOVE_RECURSE "${PROFILE_DIR}")
file(MAKE_DIRECTORY "${PROFILE_DIR}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
        "LLVM_PROFILE_FILE=${PROFILE_DIR}/elixir-%p.profraw"
        "QT_QPA_PLATFORM=offscreen"
        "QSG_RHI_BACKEND=software"
        "${CTEST_COMMAND}" --test-dir "${BUILD_DIR}" --output-on-failure
    RESULT_VARIABLE test_result
    OUTPUT_VARIABLE test_output
    ERROR_VARIABLE test_error)
if(NOT test_result EQUAL 0)
    message(FATAL_ERROR "CTest failed while collecting client coverage\n${test_output}\n${test_error}")
endif()

file(GLOB profile_files "${PROFILE_DIR}/elixir-*.profraw")
if(NOT profile_files)
    message(FATAL_ERROR "coverage run produced no LLVM profile data")
endif()
execute_process(
    COMMAND "${LLVM_PROFDATA}" merge -sparse ${profile_files} -o "${PROFILE_DIR}/elixir.profdata"
    RESULT_VARIABLE merge_result)
if(NOT merge_result EQUAL 0)
    message(FATAL_ERROR "llvm-profdata failed")
endif()

string(REPLACE "|" ";" coverage_binaries "${COVERAGE_BINARIES}")
list(POP_FRONT coverage_binaries primary_binary)
set(object_arguments)
foreach(binary IN LISTS coverage_binaries)
    list(APPEND object_arguments -object "${binary}")
endforeach()
execute_process(
    COMMAND "${LLVM_COV}" report "${primary_binary}" ${object_arguments}
        "-instr-profile=${PROFILE_DIR}/elixir.profdata"
        "-ignore-filename-regex=(.*/tests/|.*/_deps/|.*/Qt/|.*_autogen/)"
    RESULT_VARIABLE report_result)
if(NOT report_result EQUAL 0)
    message(FATAL_ERROR "llvm-cov report failed")
endif()
