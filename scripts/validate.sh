#!/usr/bin/env bash

set -e

source ${DAPPER_SOURCE}/scripts/lib/utils
source ${SCRIPTS_DIR}/lib/debug_functions

readonly ADMIRAL_CONSUMERS=(lighthouse submariner)
readonly SHIPYARD_CONSUMERS=(admiral lighthouse submariner submariner-operator)

function validate_release_fields() {
    local errors=0

    function _validate() {
        local key=$1

        if [[ -z "${release[$key]}" ]]; then
            printerr "Missing value for ${key@Q}"
            errors=$((errors+1))
            return 1
        fi
    }

    _validate 'version'
    _validate 'name'
    _validate 'release-notes'
    _validate 'components'
    for project in ${PROJECTS[*]}; do
        if ! _validate "components.${project}"; then
            continue
        fi

        local commit_hash="${release["components.${project}"]}"
        if [[ ! $commit_hash =~ ^([0-9a-f]{7,40}|v[0-9a-z\.\-]+)$ ]]; then
            printerr "Version of ${project} should be either a valid git commit hash or in the form v1.2.3: ${commit_hash}"
            errors=$((errors+1))
        fi
    done

    if [[ $errors -gt 0 ]]; then
        printerr "Found ${errors} errors in the file"
        return 1
    fi
}

function validate_admiral_consumers() {
    local expected_version="$1"
    for project in ${ADMIRAL_CONSUMERS[*]}; do
        local actual_version=$(grep admiral "projects/${project}/go.mod" | cut -f2 -d' ')
        if [[ "${expected_version}" != "${actual_version}" ]]; then
            printerr "Expected Admiral version ${expected_version} but found ${actual_version} in ${project}"
            return 1
        fi
    done
}

function validate_shipyard_consumers() {
    local expected_version="$1"
    for project in ${SHIPYARD_CONSUMERS[*]}; do
        local actual_version=$(head -1 "projects/${project}/Dockerfile.dapper" | cut -f2 -d':')
        if [[ "${expected_version}" != "${actual_version}" ]]; then
            printerr "Expected Shipyard version ${expected_version} but found ${actual_version} in ${project}"
            return 1
        fi
    done
}

function validate_release() {
    validate_release_fields

    version=${release['version']}
    if ! git check-ref-format "refs/tags/${version}"; then
        printerr "Version ${version@Q} is not a valid tag name"
        return 1
    fi

    for project in ${PROJECTS[*]}; do
        clone_repo
    done

# TODO: Uncomment once we're using automated release which makes sure these are in sync
#    validate_admiral_consumers "${release["components.admiral"]}"
#    validate_shipyard_consumers "${release["components.shipyard"]#v}"
}

for file in $(find releases -type f); do
    read_release_file
    validate_release
done
