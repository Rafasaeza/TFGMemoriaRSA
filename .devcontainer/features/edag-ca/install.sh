#!/bin/sh

set -e

# Print the given message to stderr and abort the build with exit code 1.
fatal()
{
    echo "$@" >&2
    exit 1
}

# Set the TLS-skip flag (--insecure / --no-check-certificate) for the chosen downloader if the verify option is false.
set_insecure_flag() {
    local downloader=$1
    flag=""

    if [ "${VERIFY}" = "false" ]; then
        echo "Ignoring security verification"

        case $downloader in
            curl)
                flag="--insecure"
                ;;
            wget)
                flag="--no-check-certificate"
                ;;
            *)
                fatal "Incorrect downloader executable [${downloader}]"
                ;;
        esac
    fi
}

# Fetch one certificate from the given source URL and save it to the given file path, using wget or curl, whichever exists.
download() {
    local source=$1
    local name=$2

    echo "Downloading certificate from ${source}"
    echo "Save certificate to ${name}"

    if [ -x "$(which wget)" ] ; then
        set_insecure_flag wget
        wget -q $flag $source -O $name
    elif [ -x "$(which curl)" ]; then
        set_insecure_flag curl
        curl -sfL $flag $source -o $name
    else
        fatal "Could not find curl or wget, please install one."
    fi
}

# If the bundle option is true, concatenate all downloaded custom certs (base name plus numbered copies) into one <name>.bundle.crt file.
create_bundle() {
    local filename=$1

    if [ "${BUNDLE}" = "true" ]; then
        local bundle="${filename}.bundle.crt"

        echo "Creating certificate bundle ${bundle}"
        cat $(ls -1 -d "${dest_dir}/"* | grep "${filename}.*") > "${dest_dir}/${bundle}"
    fi
}

echo "Activating feature 'edag-ca'"

counter=0
filename=edag-root-ca
extension=crt
certs=$(echo $SOURCE | tr ',' '\n')
dest_dir=/usr/local/share/ca-certificates

mkdir -p $dest_dir

# Download every configured source: the first saved as <name>.<ext>, any further ones numbered as <name>-1.<ext>, <name>-2.<ext>, and so on.
for i in $certs; do
    if [ $counter -eq 0 ]; then
        download ${i} "${dest_dir}/${filename}.${extension}"
    else
        download ${i} "${dest_dir}/${filename}-${counter}.${extension}"
    fi

    counter=$((counter+1))
done

# Join all downloaded certs into one combined bundle file (does nothing unless the bundle option is true).
create_bundle $filename

# Refresh the system trust store so curl, git, apt and other TLS clients trust the new certificate.
update-ca-certificates
