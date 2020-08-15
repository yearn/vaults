// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/Controller.sol";
import "../interfaces/Vault.sol";
import "../interfaces/Aave.sol";

/*

 A strategy must implement the following calls;

 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()

 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller

*/

contract StrategyVaultTUSD {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address constant public want = address(0x0000000000085d4780B73119b644AE5ecd22b376);
    address constant public vault = address(0x37d19d1c4E1fa9DC47bD1eA12f742a0887eDa74a);

    address public constant aave = address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8);

    address public governance;
    address public controller;

    constructor(address _controller) public {
        governance = msg.sender;
        controller = _controller;
    }

    function deposit() external {
        uint _balance = IERC20(want).balanceOf(address(this));
        if (_balance > 0) {
            IERC20(want).safeApprove(address(vault), 0);
            IERC20(want).safeApprove(address(vault), _balance);
            Vault(vault).deposit(_balance);
        }
    }

    function getAave() public view returns (address) {
        return LendingPoolAddressesProvider(aave).getLendingPool();
    }

    function getName() external pure returns (string memory) {
        return "StrategyVaultTUSD";
    }

    function debt() external view returns (uint) {
        (,uint currentBorrowBalance,,,,,,,,) = Aave(getAave()).getUserReserveData(want, Controller(controller).vaults(address(this)));
        return currentBorrowBalance;
    }

    function have() external view returns (uint) {
        uint _have = balanceOf();
        _have = _have.mul(999).div(1000); // Adjust for yVault fee
        return _have;
    }

    function skimmable() external view returns (uint) {
        (,uint currentBorrowBalance,,,,,,,,) = Aave(getAave()).getUserReserveData(want, Controller(controller).vaults(address(this)));
        uint _have = balanceOf();
        _have = _have.mul(999).div(1000); // Adjust for yVault fee
        if (_have > currentBorrowBalance) {
            return _have.sub(currentBorrowBalance);
        } else {
            return 0;
        }
    }

    function skim() external {
        require(msg.sender == controller, "!controller");
        (,uint currentBorrowBalance,,,,,,,,) = Aave(getAave()).getUserReserveData(want, Controller(controller).vaults(address(this)));
        uint _have = balanceOf();
        _have = _have.mul(999).div(1000); // Adjust for yVault fee
        if (_have > currentBorrowBalance) {
            uint _balance = IERC20(want).balanceOf(address(this));
            uint _amount = _have.sub(currentBorrowBalance);
            if (_balance < _amount) {
                _amount = _withdrawSome(_amount.sub(_balance));
                _amount = _amount.add(_balance);
            }
            IERC20(want).safeTransfer(controller, _amount);
        }
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(address(_asset) != address(want), "!want");
        require(address(_asset) != address(vault), "!want");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        require(msg.sender == controller, "!controller");
        uint _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }
        address _vault = Controller(controller).vaults(address(this));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, _amount);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();
        balance = IERC20(want).balanceOf(address(this));
        address _vault = Controller(controller).vaults(address(this));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }

    function _withdrawAll() internal {
        Vault(vault).withdraw(IERC20(vault).balanceOf(address(this)));
    }

    function _withdrawSome(uint256 _amount) internal returns (uint) {
        uint _redeem = IERC20(vault).balanceOf(address(this)).mul(_amount).div(balanceSavingsInToken());
        uint _before = IERC20(want).balanceOf(address(this));
        Vault(vault).withdraw(_redeem);
        uint _after = IERC20(want).balanceOf(address(this));
        return _after.sub(_before);
    }

    function balanceOf() public view returns (uint) {
        return IERC20(want).balanceOf(address(this))
                .add(balanceSavingsInToken());
    }

    function balanceSavingsInToken() public view returns (uint256) {
        return IERC20(vault).balanceOf(address(this)).mul(Vault(vault).getPricePerFullShare()).div(1e18);
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}
