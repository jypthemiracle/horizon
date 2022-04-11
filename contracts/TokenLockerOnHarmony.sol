// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "./EthereumLightClient.sol";
import "./EthereumProver.sol";
import "./TokenLocker.sol";

// Deploying on Harmony network to mint and burn token on Harmony side
// while verify token locking operation happen on Ethereum side
// This contract is a descendant of TokenLocker and may be upgraded using the lightClient.
// It will use a zkp proof to evaluate and execute a submission before sending it through a light client.
contract TokenLockerOnHarmony is TokenLocker, OwnableUpgradeable {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // declare light client on Ethereum side
    EthereumLightClient public lightclient;

    mapping(bytes32 => bool) public spentReceipt;

    // initialize the Ownable
    function initialize() external initializer {
        __Ownable_init();
    }

    // change the light client contract
    function changeLightClient(EthereumLightClient newClient)
        external
        onlyOwner
    {
        lightclient = newClient;
    }

    // change the other bridge side
    function bind(address otherSide) external onlyOwner {
        otherSideBridge = otherSide;
    }

    // The function verifies the locking operation happens spotlessly in Ethereum blockchain.
    // It checks whether the transaction is included in the block by validating merkle proof.
    // @param blockNo: block number for the transaction
    // @param rootHash: receipt root hash of the merkle patricia tree
    // @param mptkey: it is merkle patricia tree key of the node to verify inclusion of transaction
    // @param proof: it is merkle patricia tree proof being decoded to validateMPTProof function to be traversed for the verification.

    function validateAndExecuteProof(
        uint256 blockNo,
        bytes32 rootHash,
        bytes calldata mptkey,
        bytes calldata proof
    ) external {
        // retreive the block hash from the light client
        bytes32 blockHash = bytes32(lightclient.blocksByHeight(blockNo, 0));

        // check whether the receipt hash is valid or not
        require(
            lightclient.VerifyReceiptsHash(blockHash, rootHash),
            "wrong receipt hash"
        );

        // reconstructing the receipt hash using keccak256 hashing function
        bytes32 receiptHash = keccak256(
            abi.encodePacked(blockHash, rootHash, mptkey)
        );

        // checking whether the receipt hash has not been double spending either
        require(spentReceipt[receiptHash] == false, "double spent!");

        // validating whether the transaction is included or not by validaying merkle root hash
        bytes memory rlpdata = EthereumProver.validateMPTProof(
            rootHash,
            mptkey,
            proof
        );

        // flag that the receipt hash is spent already
        spentReceipt[receiptHash] = true;

        // execute the event
        uint256 executedEvents = execute(rlpdata);
        require(executedEvents > 0, "no valid event");
    }
}
