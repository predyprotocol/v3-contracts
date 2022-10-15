//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/Initializable.sol";
import "./interfaces/IVaultNFT.sol";

/**
 * @notice ERC721 representing ownership of a vault
 */
contract VaultNFT is ERC721, IVaultNFT, Initializable {
    uint256 public override nextId = 1;

    address public controller;
    address private immutable deployer;

    mapping(address => bool) public allowlist;

    modifier onlyAllowedAddress() {
        require(allowlist[msg.sender], "Not Allowed");
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
        _setBaseURI(_baseURI);
    }

    /**
     * @notice Initializes Vault NFT
     * @param _minter Perpetual Market address
     */
    function allow(address _minter) public {
        require(msg.sender == deployer, "Caller is not deployer");
        require(_minter != address(0), "Zero address");

        allowlist[_minter] = true;
    }

    /**
     * @notice mint new NFT
     * @dev auto increment tokenId starts from 1
     * @param _recipient recipient address for NFT
     */
    function mintNFT(address _recipient) external override onlyAllowedAddress returns (uint256 tokenId) {
        _safeMint(_recipient, (tokenId = nextId++));
    }
}
