#!/bin/bash -eu
set -o pipefail
[ "$DEBUG" == 1 ] && set -x
cwd=$(dirname "$(realpath -s "${BASH_SOURCE[-1]}")")
workflow_hash=$(sha1sum <<< "$GITHUB_WORKFLOW_REF" | awk NF=1)

# cleanup
_cleanup() {
    set +eu
    ssh-add -d "${ssh_priv_keys[@]}"
    rm -f "$SSH_AUTH_SOCK"
    rm -f "${ssh_priv_keys[@]}"
}
trap _cleanup EXIT

# read config (NAME, SRC_URL, DST_URLS, SRC_KEY, DST_KEYS)
config=$1
. <(yq -r '"NAME=" + .name, "SRC_URL=" + .src.url, "SRC_KEY=" + .src.key // "", "DST_URLS=" + ([.dst[].url] | join(",")), "DST_KEYS=" + ([.dst[] | (.key // "")] | join(","))' <<< "$config")
mapfile -td, DST_URLS <<< "$DST_URLS"
mapfile -td, DST_KEYS <<< "$DST_KEYS"

# add SSH known hosts
for url in "$SRC_URL" "${DST_URLS[@]}"; do
    host=$(grep -oP '\w+@\K.+?(?=:)|https?:\/\/\K.+?(?=\/)' <<< "$url")
    if ! { ssh-keygen -F "$host" > /dev/null || ssh-keyscan -T10 "$host" >> ~/.ssh/known_hosts; }; then
        echo "::warning::ssh-keyscan failed for $host"
        [ "$UNSAFE_SSH" != 1 ] && exit 1
        export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no'
    fi
done

# setup SSH agent
eval "$(ssh-agent -s)"

# add SSH private keys
mapfile -t ssh_priv_keys < <(for key in "$SRC_KEY" "${DST_KEYS[@]}"; do echo "$HOME/.ssh/${key:-$SSH_PRIVATE_KEY}"; done | sort -u)
ssh-add "${ssh_priv_keys[@]}"
trap "ssh-add -d ${ssh_priv_keys[*]@Q}" EXIT

# restore cached git repo
key="mirror-$NAME"
cache="$HOME/.cache/mirror/$workflow_hash/$NAME"
mkdir -p "$cache"
if "$cwd/cache.mjs" -k "$key" restore "$cache"; then
    # cache hit: update
    git -C "$cache" fetch -p origin
else
    # cache miss: clone
    git clone --bare "$SRC_URL" "$cache"
fi

# push to target repo
for url in "${DST_URLS[@]}"; do
    git -C "$cache" push --mirror "$url"
done

# cache local git repo
"$cwd/cache.mjs" -k "$key" save "$cache"
