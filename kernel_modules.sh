#!/bin/bash
#
# Copyright (C) 2020 Pig <pig.priv@gmail.com>
# Copyright (C) 2025 Magicxavi <rolfpeterkesche@gmail.com>
#
# Simple script to import/update kernel modules
# Version 0.6
#

# Aliases
cai='git commit --amend --no-edit'
ci='git commit --no-edit'
ds='drivers/staging'
mo='git merge --allow-unrelated-histories -s ours --no-commit FETCH_HEAD'
ms='git merge -X subtree'
os='opensource'
qc='qcom-opensource'
rm='https://git.codelinaro.org/clo/la/platform/vendor'
rma='git remote add clo'
sa='git subtree add --prefix'
wl="$qc/wlan"

echo -e "Available modules:\n1.qcacld-3.0\n2.qca-wifi-host-cmn\n3.fw-api\n4.audio-kernel"
read -p "The name of kernel module you want: " num

case $num in 
    1) mod="qcacld-3.0"; dir="$ds/$mod" ;;
    2) mod="qca-wifi-host-cmn"; dir="$ds/$mod" ;;
    3) mod="fw-api"; dir="$ds/$mod" ;;
    4) mod="audio-kernel"; dir="techpack/audio" ;;
    *)
        echo "Invalid input, aborting!"
        exit 1
        ;;
esac

read -p "The git command you want to use: merge (m) / subtree (s) " cmd
read -p "The tag/branch of module: " br
read -p "Import (i) / Update (u): " option

# Define the correct remote URL
if [ "$mod" = "audio-kernel" ]; then
    remote_url="$rm/$os/$mod.git"
else
    remote_url="$rm/$wl/$mod.git"
fi

# Add remote if not already added
if ! git remote | grep -q "^clo$"; then
    echo "Adding remote 'clo' with URL: $remote_url"
    git remote add clo "$remote_url"
fi

# Fetch and check if the branch exists
echo "Fetching from remote 'clo'..."
if ! git fetch clo "$br"; then
    echo "Error: Branch '$br' not found in remote repository. Aborting!"
    exit 1
fi

case $option in
    import | i)
        echo "Importing module: $mod"
        if [ "$mod" = "audio-kernel" ]; then
            git subtree add --prefix="$dir" "$remote_url" "$br"
        else
            if [ "$cmd" = "s" ]; then
                git subtree add --prefix="$dir" clo "$br"
            elif [ "$cmd" = "m" ]; then
                $mo && git read-tree --prefix="$dir" -u FETCH_HEAD
            else
                echo "Invalid command, aborting!"
                exit 1
            fi
        fi
        git commit --amend --no-edit
        echo "Import completed for $mod."
        ;;
    
    update | u)
        echo "Updating module: $mod"
        if [ "$mod" = "audio-kernel" ]; then
            git subtree pull --prefix="$dir" "$remote_url" "$br"
        else
            git merge -X subtree="$dir" FETCH_HEAD --no-edit
        fi
        echo "Update completed for $mod."
        ;;
    
    *)
        echo "Invalid option, aborting!"
        exit 1
        ;;
esac
