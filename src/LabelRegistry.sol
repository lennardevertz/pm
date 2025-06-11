// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

contract LabelRegistry {
    mapping(bytes32 => bool) public isValidLabel;

    constructor() {
        isValidLabel[keccak256(abi.encodePacked("api"))] = true;
        isValidLabel[keccak256(abi.encodePacked("tweet"))] = true;
        isValidLabel[keccak256(abi.encodePacked("news"))] = true;
        isValidLabel[keccak256(abi.encodePacked("hearsay"))] = true;
        isValidLabel[keccak256(abi.encodePacked("original"))] = true;
    }

    function addLabel(string calldata label) external {
        isValidLabel[keccak256(abi.encodePacked(label))] = true;
    }

    function removeLabel(string calldata label) external {
        isValidLabel[keccak256(abi.encodePacked(label))] = false;
    }
}
