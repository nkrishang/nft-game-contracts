// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Token
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Chainlink VRF
import { VRFConsumerBase } from '@chainlink/contracts/src/v0.8/VRFConsumerBase.sol';

contract CriticalHit is VRFConsumerBase, ERC721 {

    /// @dev Chainlink VRF variables.
    bytes32 keyHash;
    uint vrfFees;
    
    constructor(
        string memory _name, // ERC 721 NFT configs
        string memory _symbol,

        address _vrfCoordinator, // Chainlink VRF configs
        address _linkToken,
        bytes32 _keyHash,
        uint _fees
    )
        ERC721(_name, _symbol)
        VRFConsumerBase(_vrfCoordinator, _linkToken)
    {
        // Set Chainlink variables.
        keyHash = _keyHash;
        vrfFees = _fees;
    }

    /// @dev Called by Chainlink VRF with a random number.
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {}
}