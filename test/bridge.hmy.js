const rlp = require('rlp');
const headerData = require('./headers.json');
const transactions = require('./transaction.json');
const { rpcWrapper, getReceiptProof } = require('../scripts/utils');

const { expect } = require('chai');

// decalring the prover and MMR verifier
let MMRVerifier, HarmonyProver;
let prover, mmrVerifier;

// the util function to convert data from hexadecimal type to bytes
function hexToBytes(hex) {
    for (var bytes = [], c = 0; c < hex.length; c += 2)
        bytes.push(parseInt(hex.substr(c, 2), 16));
    return bytes;
}

describe('HarmonyProver', function () {
    beforeEach(async function () {
        // getting the ABI factory for the MMR verifier
        MMRVerifier = await ethers.getContractFactory("MMRVerifier");
        // deploying the MMR contract using the ABI factory
        mmrVerifier = await MMRVerifier.deploy();
        // waiting for the contract to be deployed
        await mmrVerifier.deployed();

        // await HarmonyProver.link('MMRVerifier', mmrVerifier);
        HarmonyProver = await ethers.getContractFactory(
            "HarmonyProver",
            {
                libraries: {
                    MMRVerifier: mmrVerifier.address
                }
            }
        );
        // deploying the harmony prover contract
        prover = await HarmonyProver.deploy();
        // waiting for the contract to be deployed
        await prover.deployed();
    });

    it('parse rlp block header', async function () {
        // convert header data from hex to bytes and pass it to the prover's block header function
        let header = await prover.toBlockHeader(hexToBytes(headerData.rlpheader));
        // expecting the block header to return block header
        expect(header.hash).to.equal(headerData.hash);
    });

    it('parse transaction receipt proof', async function () {
        // getReceiptProof function to assign as callback function
        let callback = getReceiptProof;
        // declare some args
        let callbackArgs = [
            process.env.LOCALNET,
            prover,
            transactions.hash
        ];
        let isTxn = true;
        // send request to get a proof
        let txProof = await rpcWrapper(
            transactions.hash,
            isTxn,
            callback,
            callbackArgs
        );
        console.log(txProof);
        // validate that the tx proof received is correct
        expect(txProof.header.hash).to.equal(transactions.header);

        // let response = await prover.getBlockRlpData(txProof.header);
        // console.log(response);

        // let res = await test.bar([123, "abc", "0xD6dDd996B2d5B7DB22306654FD548bA2A58693AC"]);
        // // console.log(res);
    });
});

// declare token lockers, light client
let TokenLockerOnEthereum, tokenLocker;
let HarmonyLightClient, lightclient;

describe('TokenLocker', function () {
    beforeEach(async function () {
        // token locker contract factory
        TokenLockerOnEthereum = await ethers.getContractFactory("TokenLockerOnEthereum");
        // deploy the token locker contract
        tokenLocker = await MMRVerifier.deploy();
        await tokenLocker.deployed();

        // bind the token locker address to its address
        await tokenLocker.bind(tokenLocker.address);

        // // await HarmonyProver.link('MMRVerifier', mmrVerifier);
        // HarmonyProver = await ethers.getContractFactory(
        //     "HarmonyProver",
        //     {
        //         libraries: {
        //             MMRVerifier: mmrVerifier.address
        //         }
        //     }
        // );
        // prover = await HarmonyProver.deploy();
        // await prover.deployed();

        
    });

    it('issue map token test', async function () {
        
    });

    it('lock test', async function () {
        
    });

    it('unlock test', async function () {
        
    });

    it('light client upgrade test', async function () {
        
    });
});