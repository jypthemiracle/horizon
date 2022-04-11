// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "./HarmonyLightClient.sol";
import "./lib/MMRVerifier.sol";
import "./HarmonyProver.sol";
import "./TokenLocker.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Deploying on Ethereum side. It locks and unlocks the Ethereum-network token of the user.
// while proving token burning operation on Harmony side.
contract TokenLockerOnEthereum is TokenLocker, OwnableUpgradeable {

    // declaring light client on Harmony side
    HarmonyLightClient public lightclient;

    // utilizing this type to prevent double spending
    mapping(bytes32 => bool) public spentReceipt;

    function initialize() external initializer {
        __Ownable_init();
    }

    // possibly change light client contract if and only if the caller is contract owner
    function changeLightClient(HarmonyLightClient newClient)
        external
        onlyOwner
    {
        lightclient = newClient;
    }

    // could change the bridge of other side if and only if the caller is contract owner
    function bind(address otherSide) external onlyOwner {
        otherSideBridge = otherSide;
    }

    // verifying token burning operation on Harmony side
    // The function checks whether the transaction is included on MMR tree and merkle hash proof.
    // @param header: checkpoint block header that includes the transaction
    // @param mmrProof: mmr proof
    // @param receiptdata: merkle proof
    function validateAndExecuteProof(
        HarmonyParser.BlockHeader memory header,
        MMRVerifier.MMRProof memory mmrProof,
        MPT.MerkleProof memory receiptdata
    ) external {
        require(lightclient.isValidCheckPoint(header.epoch, mmrProof.root), "checkpoint validation failed");
        // retrieving the hash from the block header
        bytes32 blockHash = HarmonyParser.getBlockHash(header);
        // retrieving the receipt root hash
        bytes32 rootHash = header.receiptsRoot;
        // verifying the block header whether it is included in MMR root or not
        (bool status, string memory message) = HarmonyProver.verifyHeader(
            header,
            mmrProof
        );

        // ensure the block header was valid or not
        require(status, "block header could not be verified");

        // reorganizing receiptHash using keccak256 hashing function
        bytes32 receiptHash = keccak256(
            abi.encodePacked(blockHash, rootHash, receiptdata.key)
        );
        require(spentReceipt[receiptHash] == false, "double spent!");

        // verifying the receipt whether it is included in receiptsRoot of block header
        (status, message) = HarmonyProver.verifyReceipt(header, receiptdata);

        // ensuring whether the receipt is valid or not
        require(status, "receipt data could not be verified");

        // marking the receipt hash is already spent so that preventing double spending is possible
        spentReceipt[receiptHash] = true;

        // executing the event
        uint256 executedEvents = execute(receiptdata.expectedValue);
        require(executedEvents > 0, "no valid event");
    }
}
