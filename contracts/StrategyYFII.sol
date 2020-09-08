// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/Controller.sol";
import "../interfaces/Yfii.sol";
import "../interfaces/Balancer.sol";
import "../interfaces/yVault.sol";
import "../interfaces/Curve.sol";

/*

 A strategy must implement the following calls;

 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()

 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller

*/

contract StrategyYfii {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address constant public want = address(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);
    address constant public pool = address(0xb81D3cB2708530ea990a287142b82D058725C092);
    address constant public yfii = address(0xa1d0E215a23d7030842FC67cE582a6aFa3CCaB83);
    address constant public balancer = address(0x16cAC1403377978644e78769Daa49d8f6B6CF565);
    address constant public curve = address(0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51);

    address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address constant public ydai = address(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01);

    uint public fee = 500;
    uint constant public max = 10000;

    address public governance;
    address public controller;

    constructor(address _controller) public {
        governance = msg.sender;
        controller = _controller;
    }

    function getName() external pure returns (string memory) {
        return "StrategyYfii";
    }

    function setFee(uint _fee) external {
        require(msg.sender == governance, "!governance");
        fee = _fee;
    }

    function deposit() external {
        IERC20(want).safeApprove(pool, 0);
        IERC20(want).safeApprove(pool, IERC20(want).balanceOf(address(this)));
        Yfii(pool).stake(IERC20(want).balanceOf(address(this)));
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
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


        uint _fee = _amount.mul(fee).div(max);
        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();
        balance = IERC20(want).balanceOf(address(this));

        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);

    }

    function _withdrawAll() internal {
        Yfii(pool).exit();
    }

    function harvest() public {
        Yfii(pool).getReward();
        IERC20(yfii).safeApprove(balancer, 0);
        IERC20(yfii).safeApprove(balancer, IERC20(yfii).balanceOf(address(this)));
        Balancer(balancer).swapExactAmountIn(yfii, IERC20(yfii).balanceOf(address(this)), dai, 0, uint(-1));
        IERC20(dai).safeApprove(ydai, 0);
        IERC20(dai).safeApprove(ydai, IERC20(dai).balanceOf(address(this)));
        yERC20(ydai).deposit(IERC20(dai).balanceOf(address(this)));
        IERC20(ydai).safeApprove(curve, 0);
        IERC20(ydai).safeApprove(curve, IERC20(ydai).balanceOf(address(this)));
        uint _before = IERC20(want).balanceOf(address(this));
        ICurveFi(curve).add_liquidity([IERC20(ydai).balanceOf(address(this)),0,0,0],0);
        uint _after = IERC20(want).balanceOf(address(this));
        uint _fee = _after.sub(_before).mul(fee).div(max);
        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        IERC20(want).safeApprove(pool, 0);
        IERC20(want).safeApprove(pool, IERC20(want).balanceOf(address(this)));
        Yfii(pool).stake(IERC20(want).balanceOf(address(this)));
    }

    function _withdrawSome(uint256 _amount) internal returns (uint) {
        Yfii(pool).withdraw(_amount);
        return _amount;
    }

    function balanceOfCurve() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfYfii() public view returns (uint) {
        return Yfii(pool).balanceOf(address(this));
    }

    function balanceOf() public view returns (uint) {
        return balanceOfCurve()
               .add(balanceOfYfii());
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
