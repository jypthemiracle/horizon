// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "./HarmonyParser.sol";
import "./lib/SafeCast.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
// import "openzeppelin-solidity/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
// import "openzeppelin-solidity/contracts/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

/*
    Harmony Light Client is deployed to Ethereum network.
    
    1. The registered relayers provide updates on the current state of Harmony, as a checkpoint block, to the contract.
    2. The relayers accomplishes the updating duty of harmony checkpoints by appending header data to a mapping of MMR roots.
    3. The contract requires i) checkpoint blocks ii) MMR root to verify Harmony transaction proofs while saving the gas.
*/

contract HarmonyLightClient is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable
{

    // Library Functions on the left side while applicable type on the right side
    using SafeCast for *;
    using SafeMathUpgradeable for uint256;

    // This is a Harmony checkpoint block; representing struct data in a block header
    struct BlockHeader {
        bytes32 parentHash;
        bytes32 stateRoot;
        bytes32 transactionsRoot;
        bytes32 receiptsRoot;
        uint256 number;
        uint256 epoch;
        uint256 shard;
        uint256 time;
        bytes32 mmrRoot;
        bytes32 hash;
    }

    // Relayer call the event everytime when updating the checkpoint of Harmony blockchain
    event CheckPoint(
        bytes32 stateRoot,
        bytes32 transactionsRoot,
        bytes32 receiptsRoot,
        uint256 number,
        uint256 epoch,
        uint256 shard,
        uint256 time,
        bytes32 mmrRoot,
        bytes32 hash
    );

    // The first block header
    BlockHeader firstBlock;

    // the lastest checkpoint block header
    BlockHeader lastCheckPointBlock;

    // epoch to block numbers, as there could be >=1 mmr entries per epoch
    mapping(uint256 => uint256[]) epochCheckPointBlockNumbers;

    // block number to BlockHeader
    mapping(uint256 => BlockHeader) checkPointBlocks;

    // epoch to MMR roots
    mapping(uint256 => mapping(bytes32 => bool)) epochMmrRoots;

    // maximum relayers amount
    uint8 relayerThreshold;

    event RelayerThresholdChanged(uint256 newThreshold);
    event RelayerAdded(address relayer);
    event RelayerRemoved(address relayer);

    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    // the modifiers to set access control
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "sender doesn't have admin role");
        _;
    }

    modifier onlyRelayers() {
        require(hasRole(RELAYER_ROLE, msg.sender), "sender doesn't have relayer role");
        _;
    }

    // pausing and unpausing the light client that only admin can enter into
    function adminPauseLightClient() external onlyAdmin {
        _pause();
    }

    function adminUnpauseLightClient() external onlyAdmin {
        _unpause();
    }

    function renounceAdmin(address newAdmin) external onlyAdmin {
        require(msg.sender != newAdmin, 'cannot renounce self');
        grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // updating the maximum amount of registered relayers allowed
    function adminChangeRelayerThreshold(uint256 newThreshold) external onlyAdmin {
        relayerThreshold = newThreshold.toUint8();
        emit RelayerThresholdChanged(newThreshold);
    }

    // adding relayer who can call submitCheckpoint function to update the status that only admin can register the relayer candidate
    function adminAddRelayer(address relayerAddress) external onlyAdmin {
        require(!hasRole(RELAYER_ROLE, relayerAddress), "addr already has relayer role!");
        grantRole(RELAYER_ROLE, relayerAddress);
        emit RelayerAdded(relayerAddress);
    }

    function adminRemoveRelayer(address relayerAddress) external onlyAdmin {
        require(hasRole(RELAYER_ROLE, relayerAddress), "addr doesn't have relayer role!");
        revokeRole(RELAYER_ROLE, relayerAddress);
        emit RelayerRemoved(relayerAddress);
    }

    // initialize the contract by setting the default value of firstBlock, epochCheckPointBlockNumbers, checkpointBlocks and registered replyers.
    function initialize(
        bytes memory firstRlpHeader,
        address[] memory initialRelayers,
        uint8 initialRelayerThreshold
    ) external initializer {
        HarmonyParser.BlockHeader memory header = HarmonyParser.toBlockHeader(
            firstRlpHeader
        );
        
        // initializing some variables with first block
        firstBlock.parentHash = header.parentHash;
        firstBlock.stateRoot = header.stateRoot;
        firstBlock.transactionsRoot = header.transactionsRoot;
        firstBlock.receiptsRoot = header.receiptsRoot;
        firstBlock.number = header.number;
        firstBlock.epoch = header.epoch;
        firstBlock.shard = header.shardID;
        firstBlock.time = header.timestamp;
        firstBlock.mmrRoot = HarmonyParser.toBytes32(header.mmrRoot);
        firstBlock.hash = header.hash;
        
        // initializing some values with checkpoint
        epochCheckPointBlockNumbers[header.epoch].push(header.number);
        checkPointBlocks[header.number] = firstBlock;

        epochMmrRoots[header.epoch][firstBlock.mmrRoot] = true;

        // initializing relayers; setup and grant role for them
        relayerThreshold = initialRelayerThreshold;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        for (uint256 i; i < initialRelayers.length; i++) {
            grantRole(RELAYER_ROLE, initialRelayers[i]);
        }

    }

    /*
        1. The relayer call this function to update Harmony blockchain status while providing a proper checkpoint block.
        2. The checkpoint block represents that 1 block every x blocks, where 1 ≤ x ≤ 16384, 16384 is the #blocks per epoch, and stored in checkPointBlocks.
        3. These checkpoint blocks is used to verify whether any given transaction is included in blocks or not.
    */ 

    function submitCheckpoint(bytes memory rlpHeader) external onlyRelayers whenNotPaused {
        HarmonyParser.BlockHeader memory header = HarmonyParser.toBlockHeader(
            rlpHeader
        );

        BlockHeader memory checkPointBlock;
        
        // initialize variables related to the checkpoint block
        checkPointBlock.parentHash = header.parentHash;
        checkPointBlock.stateRoot = header.stateRoot;
        checkPointBlock.transactionsRoot = header.transactionsRoot;
        checkPointBlock.receiptsRoot = header.receiptsRoot;
        checkPointBlock.number = header.number;
        checkPointBlock.epoch = header.epoch;
        checkPointBlock.shard = header.shardID;
        checkPointBlock.time = header.timestamp;
        checkPointBlock.mmrRoot = HarmonyParser.toBytes32(header.mmrRoot);
        checkPointBlock.hash = header.hash;
        
        // mappings updated
        epochCheckPointBlockNumbers[header.epoch].push(header.number);
        checkPointBlocks[header.number] = checkPointBlock;

        epochMmrRoots[header.epoch][checkPointBlock.mmrRoot] = true;

        // emitting the checkpoint events
        emit CheckPoint(
            checkPointBlock.stateRoot,
            checkPointBlock.transactionsRoot,
            checkPointBlock.receiptsRoot,
            checkPointBlock.number,
            checkPointBlock.epoch,
            checkPointBlock.shard,
            checkPointBlock.time,
            checkPointBlock.mmrRoot,
            checkPointBlock.hash
        );
    }

    /*
        Retrieving the closest checkpoint block for a given block number and epoch.
    */
    function getLatestCheckPoint(uint256 blockNumber, uint256 epoch)
        public
        view
        returns (BlockHeader memory checkPointBlock)
    {
        require(
            epochCheckPointBlockNumbers[epoch].length > 0,
            "no checkpoints for epoch"
        );
        uint256[] memory checkPointBlockNumbers = epochCheckPointBlockNumbers[epoch];
        uint256 nearest = 0;
        for (uint256 i = 0; i < checkPointBlockNumbers.length; i++) {
            uint256 checkPointBlockNumber = checkPointBlockNumbers[i];
            if (
                checkPointBlockNumber > blockNumber &&
                checkPointBlockNumber < nearest
            ) {
                nearest = checkPointBlockNumber;
            }
        }
        checkPointBlock = checkPointBlocks[nearest];
    }

    /*
        Checking whether a checkpoint is valid or not with utilizing an epoch and MMR root hash.
    */
    function isValidCheckPoint(uint256 epoch, bytes32 mmrRoot) public view returns (bool status) {
        return epochMmrRoots[epoch][mmrRoot];
    }
}
