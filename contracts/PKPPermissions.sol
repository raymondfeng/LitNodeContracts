//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {PKPNFT} from "./PKPNFT.sol";
import {PubkeyRouter} from "./PubkeyRouter.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";

import "hardhat/console.sol";

contract PKPPermissions is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;
    using BytesLib for bytes;
    using BitMaps for BitMaps.BitMap;

    /* ========== STATE VARIABLES ========== */

    PKPNFT public pkpNFT;
    PubkeyRouter public router;

    enum AuthMethodType {
        NULLMETHOD, // 0
        ADDRESS, // 1
        ACTION, // 2
        WEBAUTHN, // 3
        DISCORD, // 4
        GOOGLE, // 5
        GOOGLE_JWT // 6
    }

    struct AuthMethod {
        uint authMethodType; // 1 = address, 2 = action, 3 = WebAuthn, 4 = Discord, 5 = Google, 6 = Google JWT.  Not doing this in an enum so that we can add more auth methods in the future without redeploying.
        bytes id; // the id of the auth method.  For address, this is an eth address.  For action, this is an IPFS CID.  For WebAuthn, this is the credentialId.  For Discord, this is the user's Discord ID.  For Google, this is the user's Google ID.
        bytes userPubkey; // the user's pubkey.  This is used for WebAuthn.
    }

    // map the keccack256(uncompressed pubkey) -> set of auth methods
    mapping(uint => EnumerableSet.UintSet) permittedAuthMethods;

    // map the keccack256(uncompressed pubkey) -> auth_method_id -> scope id
    mapping(uint => mapping(uint => BitMaps.BitMap)) permittedAuthMethodScopes;

    // map the keccack256(authMethodType, userId) -> the actual AuthMethod struct
    mapping(uint => AuthMethod) public authMethods;

    // map the AuthMethod hash to the pubkeys that it's allowed to sign for
    // this makes it possible to be given a discord id and then lookup all the pubkeys that are allowed to sign for that discord id
    mapping(uint => EnumerableSet.UintSet) authMethodToPkpIds;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _pkpNft, address _router) {
        pkpNFT = PKPNFT(_pkpNft);
        router = PubkeyRouter(_router);
    }

    /* ========== VIEWS ========== */

    /// get the eth address for the keypair, as long as it's an ecdsa keypair
    function getEthAddress(uint tokenId) public view returns (address) {
        return router.getEthAddress(tokenId);
    }

    /// includes the 0x04 prefix so you can pass this directly to ethers.utils.computeAddress
    function getPubkey(uint tokenId) public view returns (bytes memory) {
        return router.getPubkey(tokenId);
    }

    function getAuthMethodId(
        uint authMethodType,
        bytes memory id
    ) public pure returns (uint) {
        return uint(keccak256(abi.encode(authMethodType, id)));
    }

    /// get the user's pubkey given their authMethodType and userId
    function getUserPubkeyForAuthMethod(
        uint authMethodType,
        bytes memory id
    ) external view returns (bytes memory) {
        uint authMethodId = getAuthMethodId(authMethodType, id);
        AuthMethod memory am = authMethods[authMethodId];
        return am.userPubkey;
    }

    function getTokenIdsForAuthMethod(
        uint authMethodType,
        bytes memory id
    ) external view returns (uint[] memory) {
        uint authMethodId = getAuthMethodId(authMethodType, id);

        uint pkpIdsLength = authMethodToPkpIds[authMethodId].length();
        uint[] memory allPkpIds = new uint[](pkpIdsLength);

        for (uint i = 0; i < pkpIdsLength; i++) {
            allPkpIds[i] = authMethodToPkpIds[authMethodId].at(i);
        }

        return allPkpIds;
    }

    function getPermittedAuthMethods(
        uint tokenId
    ) external view returns (AuthMethod[] memory) {
        uint permittedAuthMethodsLength = permittedAuthMethods[tokenId]
            .length();
        AuthMethod[] memory allPermittedAuthMethods = new AuthMethod[](
            permittedAuthMethodsLength
        );

        for (uint i = 0; i < permittedAuthMethodsLength; i++) {
            uint authMethodHash = permittedAuthMethods[tokenId].at(i);
            allPermittedAuthMethods[i] = authMethods[authMethodHash];
        }

        return allPermittedAuthMethods;
    }

    function getPermittedAuthMethodScopes(
        uint tokenId,
        uint authMethodType,
        bytes memory id,
        uint maxScopeId
    ) public view returns (bool[] memory) {
        uint authMethodId = getAuthMethodId(authMethodType, id);
        BitMaps.BitMap
            storage permittedScopesBitMap = permittedAuthMethodScopes[tokenId][
                authMethodId
            ];
        bool[] memory allScopes = new bool[](maxScopeId);

        for (uint i = 0; i < maxScopeId; i++) {
            allScopes[i] = permittedScopesBitMap.get(i);
        }

        return allScopes;
    }

    function getPermittedActions(
        uint tokenId
    ) public view returns (bytes[] memory) {
        uint permittedAuthMethodsLength = permittedAuthMethods[tokenId]
            .length();

        // count the number of auth methods that are actions
        uint permittedActionsLength = 0;
        for (uint i = 0; i < permittedAuthMethodsLength; i++) {
            uint authMethodHash = permittedAuthMethods[tokenId].at(i);
            AuthMethod memory am = authMethods[authMethodHash];
            if (am.authMethodType == uint(AuthMethodType.ACTION)) {
                permittedActionsLength++;
            }
        }

        bytes[] memory allPermittedActions = new bytes[](
            permittedActionsLength
        );

        uint permittedActionsIndex = 0;
        for (uint i = 0; i < permittedAuthMethodsLength; i++) {
            uint authMethodHash = permittedAuthMethods[tokenId].at(i);
            AuthMethod memory am = authMethods[authMethodHash];
            if (am.authMethodType == uint(AuthMethodType.ACTION)) {
                allPermittedActions[permittedActionsIndex] = am.id;
                permittedActionsIndex++;
            }
        }

        return allPermittedActions;
    }

    function getPermittedAddresses(
        uint tokenId
    ) public view returns (address[] memory) {
        uint permittedAuthMethodsLength = permittedAuthMethods[tokenId]
            .length();

        // count the number of auth methods that are addresses
        uint permittedAddressLength = 0;
        for (uint i = 0; i < permittedAuthMethodsLength; i++) {
            uint authMethodHash = permittedAuthMethods[tokenId].at(i);
            AuthMethod memory am = authMethods[authMethodHash];
            if (am.authMethodType == uint(AuthMethodType.ADDRESS)) {
                permittedAddressLength++;
            }
        }

        bool tokenExists = pkpNFT.exists(tokenId);
        address[] memory allPermittedAddresses;
        uint permittedAddressIndex = 0;
        if (tokenExists) {
            // token is not burned, so add the owner address
            allPermittedAddresses = new address[](permittedAddressLength + 1);

            // always add nft owner in first slot
            address nftOwner = pkpNFT.ownerOf(tokenId);
            allPermittedAddresses[0] = nftOwner;
            permittedAddressIndex++;
        } else {
            // token is burned, so don't add the owner address
            allPermittedAddresses = new address[](permittedAddressLength);
        }

        for (uint i = 0; i < permittedAuthMethodsLength; i++) {
            uint authMethodHash = permittedAuthMethods[tokenId].at(i);
            AuthMethod memory am = authMethods[authMethodHash];
            if (am.authMethodType == uint(AuthMethodType.ADDRESS)) {
                address parsed;
                bytes memory id = am.id;

                // address was packed using abi.encodedPacked(address), so you need to pad left to get the correct bytes back
                assembly {
                    parsed := div(
                        mload(add(id, 32)),
                        0x1000000000000000000000000
                    )
                }
                allPermittedAddresses[permittedAddressIndex] = parsed;
                permittedAddressIndex++;
            }
        }

        return allPermittedAddresses;
    }

    /// get if a user is permitted to use a given pubkey.  returns true if it is permitted to use the pubkey in the permittedAuthMethods[tokenId] struct.
    function isPermittedAuthMethod(
        uint tokenId,
        uint authMethodType,
        bytes memory id
    ) public view returns (bool) {
        uint authMethodId = getAuthMethodId(authMethodType, id);
        bool permitted = permittedAuthMethods[tokenId].contains(authMethodId);
        if (!permitted) {
            return false;
        }
        return true;
    }

    function isPermittedAuthMethodScopePresent(
        uint tokenId,
        uint authMethodType,
        bytes memory id,
        uint scopeId
    ) public view returns (bool) {
        uint authMethodId = getAuthMethodId(authMethodType, id);
        bool present = permittedAuthMethodScopes[tokenId][authMethodId].get(
            scopeId
        );
        return present;
    }

    function isPermittedAction(
        uint tokenId,
        bytes memory ipfsCID
    ) public view returns (bool) {
        return
            isPermittedAuthMethod(
                tokenId,
                uint(AuthMethodType.ACTION),
                ipfsCID
            );
    }

    function isPermittedAddress(
        uint tokenId,
        address user
    ) public view returns (bool) {
        return
            isPermittedAuthMethod(
                tokenId,
                uint(AuthMethodType.ADDRESS),
                abi.encodePacked(user)
            ) || pkpNFT.ownerOf(tokenId) == user;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// Add a permitted auth method for a given pubkey
    function addPermittedAuthMethod(
        uint tokenId,
        uint authMethodType,
        bytes memory id,
        bytes memory userPubkey,
        uint[] memory scopes
    ) public {
        // check that user is allowed to set this
        address nftOwner = pkpNFT.ownerOf(tokenId);
        require(
            msg.sender == nftOwner,
            "Only the PKP NFT owner can add and remove permitted auth methods"
        );

        AuthMethod memory am = AuthMethod(authMethodType, id, userPubkey);
        uint authMethodId = getAuthMethodId(authMethodType, id);

        // we need to ensure that someone with the same auth method type and id can't add a different pubkey
        require(
            authMethods[authMethodId].userPubkey.length == 0 ||
                keccak256(authMethods[authMethodId].userPubkey) ==
                keccak256(userPubkey),
            "Cannot add a different pubkey for the same auth method type and id"
        );

        authMethods[authMethodId] = am;

        EnumerableSet.UintSet
            storage newPermittedAuthMethods = permittedAuthMethods[tokenId];
        newPermittedAuthMethods.add(authMethodId);

        EnumerableSet.UintSet storage newPkpIds = authMethodToPkpIds[
            authMethodId
        ];
        newPkpIds.add(tokenId);

        for (uint i = 0; i < scopes.length; i++) {
            uint scopeId = scopes[i];

            permittedAuthMethodScopes[tokenId][authMethodId].set(scopeId);

            emit PermittedAuthMethodScopeAdded(
                tokenId,
                authMethodId,
                id,
                scopeId
            );
        }

        emit PermittedAuthMethodAdded(tokenId, authMethodType, id, userPubkey);
    }

    // Remove a permitted auth method for a given pubkey
    function removePermittedAuthMethod(
        uint tokenId,
        uint authMethodType,
        bytes memory id
    ) public {
        // check that user is allowed to set this
        address nftOwner = pkpNFT.ownerOf(tokenId);
        require(
            msg.sender == nftOwner,
            "Only the PKP NFT owner can add and remove permitted addresses"
        );

        uint authMethodId = getAuthMethodId(authMethodType, id);

        EnumerableSet.UintSet
            storage newPermittedAuthMethods = permittedAuthMethods[tokenId];
        newPermittedAuthMethods.remove(authMethodId);

        EnumerableSet.UintSet storage newPkpIds = authMethodToPkpIds[
            authMethodId
        ];
        newPkpIds.remove(tokenId);

        emit PermittedAuthMethodRemoved(tokenId, authMethodId, id);
    }

    function addPermittedAuthMethodScope(
        uint tokenId,
        uint authMethodType,
        bytes memory id,
        uint scopeId
    ) public {
        // check that user is allowed to set this
        address nftOwner = pkpNFT.ownerOf(tokenId);
        require(
            msg.sender == nftOwner,
            "Only the PKP NFT owner can add and remove permitted auth method scoped"
        );

        uint authMethodId = getAuthMethodId(authMethodType, id);

        permittedAuthMethodScopes[tokenId][authMethodId].set(scopeId);

        emit PermittedAuthMethodScopeAdded(tokenId, authMethodId, id, scopeId);
    }

    function removePermittedAuthMethodScope(
        uint tokenId,
        uint authMethodType,
        bytes memory id,
        uint scopeId
    ) public {
        // check that user is allowed to set this
        address nftOwner = pkpNFT.ownerOf(tokenId);
        require(
            msg.sender == nftOwner,
            "Only the PKP NFT owner can add and remove permitted auth method scopes"
        );

        uint authMethodId = getAuthMethodId(authMethodType, id);

        permittedAuthMethodScopes[tokenId][authMethodId].unset(scopeId);

        emit PermittedAuthMethodScopeRemoved(
            tokenId,
            authMethodType,
            id,
            scopeId
        );
    }

    /// Add a permitted action for a given pubkey
    function addPermittedAction(
        uint tokenId,
        bytes memory ipfsCID,
        uint[] memory scopes
    ) public {
        addPermittedAuthMethod(
            tokenId,
            uint(AuthMethodType.ACTION),
            ipfsCID,
            "",
            scopes
        );
    }

    function removePermittedAction(uint tokenId, bytes memory ipfsCID) public {
        removePermittedAuthMethod(
            tokenId,
            uint(AuthMethodType.ACTION),
            ipfsCID
        );
    }

    function addPermittedAddress(
        uint tokenId,
        address user,
        uint[] memory scopes
    ) public {
        addPermittedAuthMethod(
            tokenId,
            uint(AuthMethodType.ADDRESS),
            abi.encodePacked(user),
            "",
            scopes
        );
    }

    function removePermittedAddress(uint tokenId, address user) public {
        removePermittedAuthMethod(
            tokenId,
            uint(AuthMethodType.ADDRESS),
            abi.encodePacked(user)
        );
    }

    function setPkpNftAddress(address newPkpNftAddress) public onlyOwner {
        pkpNFT = PKPNFT(newPkpNftAddress);
    }

    function setRouterAddress(address newRouterAddress) public onlyOwner {
        router = PubkeyRouter(newRouterAddress);
    }

    /* ========== EVENTS ========== */

    event PermittedAuthMethodAdded(
        uint indexed tokenId,
        uint authMethodType,
        bytes id,
        bytes userPubkey
    );
    event PermittedAuthMethodRemoved(
        uint indexed tokenId,
        uint authMethodType,
        bytes id
    );
    event PermittedAuthMethodScopeAdded(
        uint indexed tokenId,
        uint authMethodType,
        bytes id,
        uint scopeId
    );
    event PermittedAuthMethodScopeRemoved(
        uint indexed tokenId,
        uint authMethodType,
        bytes id,
        uint scopeId
    );
}
