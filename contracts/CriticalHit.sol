// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Access control
import "@openzeppelin/contracts/access/Ownable.sol";

// Token
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Chainlink VRF
import { VRFConsumerBase } from '@chainlink/contracts/src/v0.8/VRFConsumerBase.sol';

// Utils
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// String encoding libraries
import { Base64 } from "./libraries/Base64.sol";

/**
 *  - Select character
 *  - Attack
 */

contract CriticalHit is Ownable, VRFConsumerBase, ERC721 {

    /// @dev Declare library usage.
    using EnumerableSet for EnumerableSet.UintSet;

    /// @dev Game configs    
    uint MAX_HP = 1000;
    uint MAX_ATTACK = 100;
    uint CRITICAL_HIT_BPS = 100; // 10%
    uint CRITICAL_HIT_CHANCE = 10; // 10%
    uint CRITICAL_HIT_MULTIPLIER = 2; // 2x damage

    /// @dev The tokenId of the next NFT to be minted.
    uint public nextTokenId;

    /// @dev Chainlink VRF variables.
    bytes32 vrfKeyHash;
    uint vrfFees;

    /// @dev Purpose of a random number
    enum RequestType { None, SelectCharacter, AttackBoss }

    /// @dev Character selection request.
    struct CharacterRequest {
        uint characterId;
        bytes32 chainlinkRequestId;
        uint reservedTokenId;
        address minter;
    }

    /// @dev Attack request
    struct AttackRequest {
        uint tokenId;
        bytes32 chainlinkRequestId;
    }

    /// @dev Character's fixed attributes
    struct AttributeConfig {
        string name;
        string imageURI;
    }

    /// @dev Character's variable attributes
    struct CharacterAttributes {
        string name;
        string imageURI;        
        uint hp;
        uint attackDamage;
    }

    // Boss attributes
    CharacterAttributes boss;

    /// @dev Mapping from address => number of NFTs they currently own.
    mapping(address => EnumerableSet.UintSet) internal tokenIdsOfOwned;

    /// @dev Mapping from Chainlink requestId => CharacterRequest.
    mapping(bytes32 => CharacterRequest) public characterRequests;

    /// @dev Mapping from Chainlink requestId => AttackRequest.
    mapping(bytes32 => AttackRequest) public attackRequests;

    /// @dev Mapping from Chainlink requestId => purpose of request
    mapping(bytes32 => RequestType) public requestType;

    /// @dev Mapping from address => requestId of in-flight Chainlink request, if any.
    mapping(address => bytes32) public requestInFlight;

    /// @dev Mapping from characterId => fixed attributes
    mapping(uint => AttributeConfig) public attributeConfigs;

    /// @dev Mapping from NFT tokenId => attributes
    mapping(uint => CharacterAttributes) public characterAttributes;

    /// @dev Events
    event BossReset(CharacterAttributes boss);
    event CharacterRequested(CharacterRequest request, uint indexed characterId, address indexed requestor);
    event CharacterAssigned(CharacterAttributes charAttributes, uint indexed tokenId, address indexed minter);
    event AttackRequested(AttackRequest attackRequest, uint indexed tokenId, address indexed requestor);
    event AttackExecuted(CharacterAttributes updatedCharAttributes, CharacterAttributes updatedBossAttributes, address indexed attacker);
    
    constructor(
        string memory _name, // ERC 721 NFT configs
        string memory _symbol,

        address _vrfCoordinator, // Chainlink VRF configs
        address _linkToken,
        bytes32 _keyHash,
        uint _fees,

        uint[] memory characterIds,
        string[] memory characterNames,
        string[] memory characterImageURIs
    )
        ERC721(_name, _symbol)
        VRFConsumerBase(_vrfCoordinator, _linkToken)
    {
        // Set Chainlink variables.
        vrfKeyHash = _keyHash;
        vrfFees = _fees;

        // Set character image URIs
         // Set character image URIs
        require(
            characterIds.length == characterImageURIs.length && characterIds.length == characterNames.length, 
            "CriticalHit: unequal character configs."
        );

        for(uint i = 0; i < characterIds.length; i += 1) {
            attributeConfigs[characterIds[i]] = AttributeConfig({
                name: characterNames[i],
                imageURI: characterImageURIs[i]
            });
        }
    }

    /**
     *  NFT display funcitons
     */

    /// @dev Returns the URI for the NFT with id `tokenId`
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        
        CharacterAttributes memory charAttributes = characterAttributes[_tokenId];

        string memory strHp = uint2str(charAttributes.hp);
        string memory strAttackDamage = uint2str(charAttributes.attackDamage);

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "',
                        charAttributes.name,
                        '", "description": "CriticalHit is a turn-based NFT game where you take turns to attack the boos.", "image": "',
                        charAttributes.imageURI,
                        '", "attributes": [ { "trait_type": "Health Points", "value": "',strHp,'"}, { "trait_type": "Attack Damage", "value": "',
                        strAttackDamage,'"} ]}'
                    )
                )
            )
        );

        string memory output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );

        return output;
    }

    /**
     *  Whitelisted function
     */

    /// @dev Lets the owner of the contract reset the boss.
    function resetBoss(string memory _bossName, string memory _bossImageURI) external onlyOwner {

        require(
            boss.hp == 0,
            "CriticalHit: Cannot reset boss while boss is still alive."
        );

        CharacterAttributes memory bossAttributes = CharacterAttributes({
            name: _bossName,
            imageURI: _bossImageURI,
            hp: MAX_HP,
            attackDamage: MAX_ATTACK
        });

        boss = bossAttributes;

        emit BossReset(bossAttributes);
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

        // Set request type
        requestType[requestId] = RequestType.SelectCharacter;

        // Set in-flight request Id for caller
        requestInFlight[_msgSender()] = requestId; 

        emit CharacterRequested(characterRequests[requestId], _characterId, _msgSender());
    }

    /// @dev Lets a character attack the boss
    function attackBoss(uint _tokenId) external /** onlyValidCharacter */ {
        
        require(
            requestInFlight[_msgSender()] == "",
            "CriticalHit: wait for in-flight request to complete."
        );

        // Send chainlink random number request for random attributes
        bytes32 requestId = randomnNumberRequest();

        // Set Attack request
        attackRequests[requestId] = AttackRequest({
            tokenId: _tokenId,
            chainlinkRequestId: requestId
        });

        // Set request type
        requestType[requestId] = RequestType.AttackBoss;

        // Set in-flight request Id for caller
        requestInFlight[_msgSender()] = requestId; 

        emit AttackRequested(attackRequests[requestId], _tokenId, _msgSender());
    }

    /**
     *  Internal functions
     */
    
    /// @dev Runs on every transfer, mint, burn.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) 
        internal 
        override
    {
        // Update `tokenIdsOfOwned`
        if(from != address(0)) {
            EnumerableSet.remove(tokenIdsOfOwned[from], tokenId);
        }

        if(to != address(0)) {
            EnumerableSet.add(tokenIdsOfOwned[to], tokenId);
        }

        super._beforeTokenTransfer(from, to, tokenId);
    }

    /// @dev Requests a random number from Chainlink VRF.
    function randomnNumberRequest() internal returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= vrfFees, "CriticalHit: Not enough LINK to fulfill randomness request.");
        requestId = requestRandomness(vrfKeyHash, vrfFees);
    }

    /// @dev Called by Chainlink VRF with a random number.
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {

        RequestType reqType = requestType[_requestId];

        if(reqType == RequestType.AttackBoss) {
            executeAttack(_requestId, _randomness);
        } else if (reqType == RequestType.SelectCharacter) {
            assignCharacter(_requestId, _randomness);
        } else {
            revert("CriticalHit: invalid request type");
        }

        // Delete in-flight request
        delete requestInFlight[_msgSender()];
    }

    /// @dev Assigns a reserved NFT character to the apporpriate minter.
    function assignCharacter(bytes32 _requestId, uint256 _randomness) internal {
        
        // Get character request and attribute configs
        CharacterRequest memory charRequest = characterRequests[_requestId];
        AttributeConfig memory attributeConfig = attributeConfigs[charRequest.characterId];

        // Mint NFT to minter
        _mint(charRequest.minter, charRequest.reservedTokenId);

        // Get HP and attack damage for character
        CharacterAttributes memory charAttributes = CharacterAttributes({
            name: attributeConfig.name,
            imageURI: attributeConfig.imageURI,
            hp: _randomness % MAX_HP,
            attackDamage: _randomness % MAX_ATTACK
        });

        characterAttributes[charRequest.reservedTokenId] = charAttributes;

        emit CharacterAssigned(charAttributes, charRequest.reservedTokenId, charRequest.minter);
    }

    /// @dev Executes an attack on the boss.
    function executeAttack(bytes32 _requestId, uint256 _randomness) internal {

        // Split randomness
        uint[] memory randomnNumbers = expand(_randomness, 2);

        // Get attack request
        AttackRequest memory attackRequest = attackRequests[_requestId];
        // Get attacker character's attributes
        CharacterAttributes memory charAttributes = characterAttributes[attackRequest.tokenId];
        // Get Boss attributes
        CharacterAttributes memory bosAttribues = boss;

        // Character attacks boss
        bool isCriticalHit = randomnNumbers[0] % CRITICAL_HIT_BPS < CRITICAL_HIT_CHANCE;
        uint attackMagnitude = isCriticalHit ? charAttributes.attackDamage * 2 : charAttributes.attackDamage;
        uint bossHpAfterAttack = bosAttribues.hp <= attackMagnitude ? 0 : bosAttribues.hp - attackMagnitude;
        
        // Update boss hp
        bosAttribues.hp = bossHpAfterAttack;
        boss = bosAttribues;
        
        // Boss attacks character
        bool willBossHit = randomnNumbers[1] % CRITICAL_HIT_BPS < CRITICAL_HIT_CHANCE;
        uint attackMagnitudeForBoss = willBossHit ? bosAttribues.attackDamage : 0;

        // Update character hp
        charAttributes.hp = charAttributes.hp <= attackMagnitudeForBoss ? 0 : charAttributes.hp - attackMagnitudeForBoss;
        characterAttributes[attackRequest.tokenId] = charAttributes;

        emit AttackExecuted(charAttributes, bosAttribues, ownerOf(attackRequest.tokenId));
    }

    /**
     *  Getter functions
     */
    
    /// @dev Returns the tokenIds owned by an address.
    function getTokenIdsOwned(address _target) external view returns (uint[] memory tokenIdsOwned) {

        // Get set of tokenIds owned
        EnumerableSet.UintSet storage idsOwned = tokenIdsOfOwned[_target];
        uint numOfOwned = EnumerableSet.length(idsOwned);
        
        tokenIdsOwned = new uint[](numOfOwned);

        for(uint i = 0; i < numOfOwned; i += 1) {
            tokenIdsOwned[i] = EnumerableSet.at(idsOwned, i);
        }
    }

    /**
     *  Pure functions
     */

    function expand(uint256 randomValue, uint256 n) public pure returns (uint256[] memory expandedValues) {
        expandedValues = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            expandedValues[i] = uint256(keccak256(abi.encode(randomValue, i)));
        }
        return expandedValues;
    }

    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}