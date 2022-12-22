#!/bin/bash

yarn install
yarn compile

BASE_DIR=`dirname "$0"`
TARGET_DIR="${BASE_DIR}/../../collabland/collabland-monorepo"

filePath='packages/contracts/src/contracts/lit'

for i in artifacts/contracts/*; do
    file=`basename $i .sol`
    target=''
    case ${file} in
        AccessControlConditions)
            target='access-control-conditions.json'
            ;;
        Multisender)
            target='multi-sender.json'
            ;;
        PKPHelper)
            target='pkp-helper.json'
            ;;   
        PKPNFT)
            target='pkp-nft.json'
            ;;   
        PKPPermissions)
            target='pkp-permissions.json'
            ;;   
        PKPNFTMetadata)
            target='pkp-nft-metadata.json'
            ;;   
        PubkeyRouter)
            target='pubkey-router.json'
            ;;  
        RateLimitNFT)
            target='rate-limit-nft.json'
            ;;
        *)
            target=''
            ;;                                                         
    esac  
    if [ ! -z ${target} ]; then
        echo Updating "${TARGET_DIR}/${filePath}/${target}"
        data=`node ./update-json.js "artifacts/contracts/${file}.sol/${file}.json" "${TARGET_DIR}/${filePath}/${target}"`
    fi
done

