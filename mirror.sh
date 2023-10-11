#!/bin/bash -euo pipefail
cwd="$(dirname "$(realpath -s "${BASH_SOURCE[-1]}")")"

# read config
config="$1"
. <(jq -r 'paths(scalars) as $path | "\($path | join("_") | ascii_upcase)=\(getpath($path) | @sh)"' <<< "$config")

# add SSH known hosts
for url in "$SRC_URL" "$DST_URL"; do
    ssh-keyscan "$(grep -oP '\w+@\K.+?(?=:)|https?:\/\/\K.+?(?=\/)' <<< "$url")" >> ~/.ssh/known_hosts
done

# add SSH private keys
for key_var in SRC_KEY DST_KEY; do
    key="${!key_var}"
    ssh-add "~/.ssh/${key:-SSH_PRIVATE_KEY}"
done

# restore cached git repo
key="mirror-$NAME"
cache="/var/cache/mirror/$(sha1sum "$GITHUB_WORKFLOW_REF" | awk NF=1)/$NAME"
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
