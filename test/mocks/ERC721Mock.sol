// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
    uint256 public nextTokenId = 1;

    constructor() ERC721("TestToken", "TEST") {}

    // @dev mint 1 token for any request
    function mint(address _to) external {
        _mint(_to, nextTokenId);
        nextTokenId += 1;
    }
}
