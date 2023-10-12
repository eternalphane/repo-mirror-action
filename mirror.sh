#!/bin/bash -eu
set -o pipefail
cwd="$(dirname "$(realpath -s "${BASH_SOURCE[-1]}")")"

# read config
config="$1"
. <(jq -r 'paths(scalars) as $path | "\($path | join("_") | ascii_upcase)=\(getpath($path) | @sh)"' <<< "$config")

# add SSH known hosts
for url in "$SRC_URL" "$DST_URL"; do
    ssh-keyscan "$(grep -oP '\w+@\K.+?(?=:)|https?:\/\/\K.+?(?=\/)' <<< "$url")" >> ~/.ssh/known_hosts
done

# add SSH private keys
mapfile -t paths < <(for key in SRC_KEY DST_KEY; do echo "$HOME/.ssh/${!key:-SSH_PRIVATE_KEY}"; done | sort -u)
ssh-add "${paths[@]}"
trap "ssh-add -d ${paths[*]@Q}" EXIT

# restore cached git repo
key="mirror-$NAME"
cache="$HOME/.cache/mirror/$(sha1sum <<< "$GITHUB_WORKFLOW_REF" | awk NF=1)/$NAME"
mkdir -p "$cache"
if "$cwd/cache.mjs" -k "$key" restore "$cache"; then
    # cache hit: update
    git -C "$cache" fetch -p origin
else
    # cache miss: clone
    git clone --bare "$SRC_URL" "$cache"
fi

# push to target repo
git -C "$cache" push --mirror "$DST_URL"

# cache local git repo
"$cwd/cache.mjs" -k "$key" save "$cache"
