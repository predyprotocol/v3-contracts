//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IVaultNFT.sol";

/**
 * @notice ERC721 representing ownership of a vault
 */
contract VaultNFT is ERC721, IVaultNFT, Initializable {
    uint256 public override nextId = 1;

    address public controller;
    address private immutable deployer;

    string internal baseURI;

    modifier onlyController() {
        require(msg.sender == controller, "Not Controller");
        _;
    }

    /**
     * @notice Vault NFT constructor
     * @param _name token name for ERC721
     * @param _symbol token symbol for ERC721
     * @param _baseURI base URI
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI
    ) ERC721(_name, _symbol) {
        deployer = msg.sender;

        baseURI = _baseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @notice Initializes Vault NFT
     * @param _controller Perpetual Market address
     */
    function init(address _controller) public initializer {
        require(msg.sender == deployer, "Caller is not deployer");
        require(_controller != address(0), "Zero address");
        controller = _controller;
    }

    /**
     * @notice mint new NFT
     * @dev auto increment tokenId starts from 1
     * @param _recipient recipient address for NFT
     */
    function mintNFT(address _recipient) external override onlyController returns (uint256 tokenId) {
        _safeMint(_recipient, (tokenId = nextId++));
    }
}
