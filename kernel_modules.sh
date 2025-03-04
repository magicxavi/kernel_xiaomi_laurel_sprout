#!/bin/bash
#
# Copyright (C) 2020 Pig <pig.priv@gmail.com>
#
# Simple script to import/update kernel modules
# Version 0.3
#

# Aliases
cai='git commit --amend --no-edit'
ci='git commit --no-edit'
ds='drivers/staging'
f='git fetch clo'
fn='FETCH_HEAD --no-edit'
mo='git merge --allow-unrelated-histories -s ours --no-commit FETCH_HEAD'
ms='git merge -X subtree'
os='opensource'
qc='qcom'
r='git read-tree --prefix'
rm='https://git.codelinaro.org/clo/la/platform/vendor'
rma='git remote add clo'
sa='git subtree add --prefix'
uf='-u FETCH_HEAD'
wl=$qc-$os/wlan

echo -e "Available modules:\n1.qcacld-3.0\n2.qca-wifi-host-cmn\n3.fw-api\n4.audio-kernel"
read -p "The name of kernel module you want: " num
case $num in 
    1|2|3|4)
        read -p "The git command you want to use: merge (m) / subtree (s) " cmd
        read -p "The tag/branch of module: " br
        read -p "Import (i) / Update (u): " option
        ;;
    *)
        echo "Invalid input, aborting!"
        exit 1
        ;;
esac

# Set module name and directory
case $num in
    1) mod="qcacld-3.0"; dir="$ds/$mod" ;;
    2) mod="qca-wifi-host-cmn"; dir="$ds/$mod" ;;
    3) mod="fw-api"; dir="$ds/$mod" ;;
    4) mod="audio-kernel"; dir="techpack/audio" ;;
esac

case $option in
    import | i)
        if [ "$mod" = "audio-kernel" ]; then
            echo "Importing audio-kernel using subtree add..."
            git subtree add --prefix=techpack/audio https://git.codelinaro.org/clo/la/platform/vendor/opensource/audio-kernel LA.UM.9.1.r1-16400-SMxxx0.QSSI14.0
            echo "Import of audio-kernel done."
            exit 0
        else
            git remote add clo $rm/$wl/$mod
        fi
        echo "Added remote for module $mod."

        case $mod in
            qcacld-3.0 | qca-wifi-host-cmn | fw-api)
                if [ "$cmd" = "s" ]; then
                    git fetch clo $mod $br && git subtree add --prefix=$dir clo/$mod $br && git commit --amend --no-edit
                elif [ "$cmd" = "m" ]; then
                    git fetch clo $mod $br && git merge --allow-unrelated-histories -s ours --no-commit FETCH_HEAD && git read-tree --prefix=$dir -u FETCH_HEAD && git commit --no-edit
                else
                    echo "Invalid command, aborting!"
                    exit 1
                fi
                ;;
        esac
        echo "Import from $br for $mod done."
        ;;
    
    update | u)
        case $mod in
            qcacld-3.0 | qca-wifi-host-cmn | fw-api)
                git fetch clo $mod $br && git merge -X subtree=$dir FETCH_HEAD --no-edit
                echo "Update to $br for module $mod done."
                ;;
            audio-kernel)
                echo "Updating audio-kernel is not supported via this script."
                exit 1
                ;;
        esac
        ;;
    
    *)
        echo "Invalid option, aborting!"
        exit 1
        ;;
esac
