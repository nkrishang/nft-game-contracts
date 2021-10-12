// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Token
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Chainlink VRF
import { VRFConsumerBase } from '@chainlink/contracts/src/v0.8/VRFConsumerBase.sol';

// Utils
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 *  - Select character
 *  - Attack
 */

contract CriticalHit is VRFConsumerBase, ERC721 {

    /// @dev Declare library usage.
    using EnumerableSet for EnumerableSet.UintSet;

    /// @dev Game configs
    string bossName = "Godzilla";
    uint MAX_HP = 1000;
    uint MAX_ATTACK = 100;

    /// @dev The tokenId of the next NFT to be minted.
    uint public nextTokenId;

    /// @dev Chainlink VRF variables.
    bytes32 vrfKeyHash;
    uint vrfFees;

    struct CharacterRequest {
        uint characterId;
        bytes32 chainlinkRequestId;
        uint reservedTokenId;
        address minter;
    }

    /// @dev Mapping from characterId => character Image URI
    mapping(uint => string) internal characterImages;

    /// @dev Mapping from NFT tokenId => NFT metadata URI
    mapping(uint => string) public uri;

    /// @dev Mapping from address => number of NFTs they currently own.
    mapping(address => EnumerableSet.UintSet) internal tokenIdsOfOwned;

    /// @dev Mapping from Chainlink requestId => CharacterRequest.
    mapping(bytes32 => CharacterRequest) public characterRequests;

    /// @dev Mapping from Chainlink requestId => AttackRequest.

    /// @dev Mapping from address => requestId of in-flight Chainlink request, if any.

    /// @dev Events
    event CharacterRequested(CharacterRequest request, uint indexed characterId, address indexed requestor);
    
    constructor(
        string memory _name, // ERC 721 NFT configs
        string memory _symbol,

        address _vrfCoordinator, // Chainlink VRF configs
        address _linkToken,
        bytes32 _keyHash,
        uint _fees,

        uint[] memory characterIds,
        string[] memory characterImageURIs
    )
        ERC721(_name, _symbol)
        VRFConsumerBase(_vrfCoordinator, _linkToken)
    {
        // Set Chainlink variables.
        vrfKeyHash = _keyHash;
        vrfFees = _fees;

        // Set character image URIs
        setCharacterImages(characterIds, characterImageURIs);
    }

    /**
     *  External functions
     */
    
    /// @dev Lets the caller mint an NFT character.
    function selectCharacter(uint _characterId) external {

        // Get tokenId for character NFT
        uint reservedTokenId = ++nextTokenId;

        // Send chainlink random number request for random attributes
        bytes32 requestId = randomnNumberRequest();

        // Set CharacterRequest
        characterRequests[requestId] = CharacterRequest({
            characterId: _characterId,
            chainlinkRequestId: requestId,
            reservedTokenId: reservedTokenId,
            minter: _msgSender()
        });

        emit CharacterRequested(characterRequests[requestId], _characterId, _msgSender());
    }

    /// @dev Lets a character attack the boss

    /**
     *  Internal functions
     */
    
    /// @dev Sets the character images on contract creation.
    function setCharacterImages(uint[] memory _characterIds, string[] memory _characterImageURIs) internal {

        // Set character image URIs
        require(
            _characterIds.length == _characterImageURIs.length, 
            "CriticalHit: unequal character configs."
        );

        for(uint i = 0; i < _characterIds.length; i += 1) {
            characterImages[_characterIds[i]] = _characterImageURIs[i];
        }
    }

    /// @dev Requests a random number from Chainlink VRF.
    function randomnNumberRequest() internal returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= vrfFees, "CriticalHit: Not enough LINK to fulfill randomness request.");
        requestId = requestRandomness(vrfKeyHash, vrfFees);
    }

    /// @dev Called by Chainlink VRF with a random number.
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {}
}