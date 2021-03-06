#!/bin/sh

# Copyright 2018 Ville Koskela
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# For documentation please refer to:
# https://github.com/KoskiLabs/jdk-wrapper/blob/master/README.md

log_err() {
  l_prefix=$(date  +'%H:%M:%S')
  printf "[%s] %s\n" "${l_prefix}" "$@" 1>&2;
}

log_out() {
  if [ -n "${JDKW_VERBOSE}" ]; then
    l_prefix=$(date  +'%H:%M:%S')
    printf "[%s] %s\n" "${l_prefix}" "$@"
  fi
}

safe_command() {
  l_command=$1
  log_out "${l_command}";
  eval $1
  l_result=$?
  if [ "${l_result}" -ne "0" ]; then
    log_err "ERROR: ${l_command} failed with ${l_result}"
    exit 1
  fi
}

checksum() {
  l_file="$1"
  checksum_exec=""
  if command -v sha256sum > /dev/null; then
    checksum_exec="sha256sum"
  elif command -v shasum > /dev/null; then
    checksum_exec="shasum -a 256"
  elif command -v sha1sum > /dev/null; then
    checksum_exec="sha1sum"
  elif command -v md5 > /dev/null; then
    checksum_exec="md5"
  fi
  if [ -z "${checksum_exec}" ]; then
    log_err "ERROR: No supported checksum command found!"
    exit 1
  fi
  cat "${l_file}" | ${checksum_exec}
}

rand() {
  awk 'BEGIN {srand();printf "%d\n", (rand() * 10^8);}'
}

download_if_needed() {
  file="$1"
  path="$2"
  if [ ! -f "${path}/${file}" ]; then
    jdkw_url="${JDKW_BASE_URI}/releases/download/${JDKW_RELEASE}/${file}"
    log_out "Downloading ${file} from ${jdkw_url}"
    safe_command "curl ${curl_options} -f -k -L -o \"${path}/${file}\" \"${jdkw_url}\""
    safe_command "chmod +x \"${path}/${file}\""
  fi
}

# Default curl options
curl_options=""

# Load properties file in home directory
if [ -f "${HOME}/.jdkw" ]; then
  . "${HOME}/.jdkw"
fi

# Load properties file in working directory
if [ -f ".jdkw" ]; then
  . "./.jdkw"
fi

# Load properties from environment
l_fifo="${TMPDIR:-/tmp}/$$.$(rand)"
safe_command "mkfifo \"${l_fifo}\""
env > "${l_fifo}" &
while IFS='=' read -r name value
do
  jdkw_arg=$(echo "${name}" | grep 'JDKW_.*')
  if [ -n "${jdkw_arg}" ]; then
    eval "${name}=\"${value}\""
  fi
done < "${l_fifo}"
safe_command "rm \"${l_fifo}\""

# Load properties from command line arguments
command=
for arg in "$@"; do
  if [ -z ${in_command} ]; then
    jdkw_arg=$(echo "${arg}" | grep 'JDKW_.*')
    if [ -n "${jdkw_arg}" ]; then
      eval ${arg}
    fi
  fi
  case "${arg}" in
    *\'*)
       arg=`printf "%s" "$arg" | sed "s/'/'\"'\"'/g"`
       ;;
    *) : ;;
  esac
  command="${command} '${arg}'"
done

# Process configuration
if [ -z "${JDKW_BASE_URI}" ]; then
    JDKW_BASE_URI="https://github.com/KoskiLabs/jdk-wrapper"
fi
if [ -z "${JDKW_RELEASE}" ]; then
  JDKW_RELEASE="latest"
  log_out "Defaulted to version ${JDKW_RELEASE}"
fi
if [ -z "${JDKW_TARGET}" ]; then
  JDKW_TARGET="${HOME}/.jdk"
  log_out "Defaulted to target ${JDKW_TARGET}"
fi
if [ -z "${JDKW_VERBOSE}" ]; then
  curl_options="${curl_options} --silent"
fi

# Resolve latest version
if [ "${JDKW_RELEASE}" = "latest" ]; then
  latest_version_json="${TMPDIR:-/tmp}/jdkw-latest-version-$$.$(rand)"
  safe_command "curl ${curl_options} -f -k -L -o \"${latest_version_json}\" -H 'Accept: application/json' \"${JDKW_BASE_URI}/releases/latest\""
  JDKW_RELEASE=$(cat "${latest_version_json}" | sed -e 's/.*"tag_name":"\([^"]*\)".*/\1/')
  rm -f "${latest_version_json}"
  log_out "Resolved latest version to ${JDKW_RELEASE}"
fi

# Ensure target directory exists
jdkw_path="${JDKW_TARGET}/jdkw/${JDKW_RELEASE}"
if [ ! -d "${jdkw_path}" ]; then
  log_out "Creating target directory ${jdkw_path}"
  safe_command "mkdir -p \"${jdkw_path}\""
fi

# Download the jdk wrapper version
jdkw_impl="jdkw-impl.sh"
jdkw_wrapper="jdk-wrapper.sh"
download_if_needed "${jdkw_impl}" "${jdkw_path}"
download_if_needed "${jdkw_wrapper}" "${jdkw_path}"

# Execute the provided command
eval ${jdkw_path}/${jdkw_impl} ${command}
result=$?

# Check whether this wrapper is the one specified for this version
jdkw_download="${jdkw_path}/${jdkw_wrapper}"
jdkw_current="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/$(basename "$0")"
if [ "$(checksum "${jdkw_download}")" != "$(checksum "${jdkw_current}")" ]; then
  printf "\e[0;31m[WARNING]\e[0m Your jdk-wrapper.sh file does not match the one in your JDKW_RELEASE.\n"
  printf "\e[0;32mUpdate your jdk-wrapper.sh to match by running:\e[0m\n"
  printf "cp \"%s\" \"%s\"\n" "${jdkw_download}" "${jdkw_current}"
fi

exit ${result}
