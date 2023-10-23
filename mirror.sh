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

# read config (NAME, SRC_URL, DST_URL, SRC_KEY, DST_KEY)
config=$1
. <(jq -r 'paths(scalars) as $path | "\($path | join("_") | ascii_upcase)=\(getpath($path) | @sh)"' <<< "$config")

# add SSH known hosts
for url in "$SRC_URL" "$DST_URL"; do
    ssh-keyscan "$(grep -oP '\w+@\K.+?(?=:)|https?:\/\/\K.+?(?=\/)' <<< "$url")" >> ~/.ssh/known_hosts
done

# setup SSH agent
eval "$(ssh-agent -s)"

# add SSH private keys
mapfile -t ssh_priv_keys < <(for key in SRC_KEY DST_KEY; do echo "$HOME/.ssh/${!key:-SSH_PRIVATE_KEY}"; done | sort -u)
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
git -C "$cache" push --mirror "$DST_URL"

# cache local git repo
"$cwd/cache.mjs" -k "$key" save "$cache"
