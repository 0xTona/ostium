// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @dev Minimal ERC20 mock used as the vault's underlying asset (e.g. USDC)
contract MockAsset is ERC20Upgradeable {
    function initialize() public initializer {
        __ERC20_init("MockUSDC", "USDC");
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Minimal registry mock – returns openPnl address for any key
contract MockRegistry {
    address public openPnlAddr;
    address public govAddr;

    constructor(address _openPnl, address _gov) {
        openPnlAddr = _openPnl;
        govAddr = _gov;
    }

    function getContractAddress(bytes32) external view returns (address) {
        return openPnlAddr;
    }

    function gov() external view returns (address) {
        return govAddr;
    }
}

/// @dev Minimal OpenPnl mock – always returns 0 for nextEpochValuesRequestCount
///      so that makeWithdrawRequest and maxRedeem are unblocked.
contract MockOpenPnl {
    function newOpenPnlRequestOrEpoch() external {}

    function nextEpochValuesRequestCount() external pure returns (uint256) {
        return 0;
    }
}
