// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/GSN/Context.sol";

import "../interfaces/Controller.sol";
import "../interfaces/Aave.sol";

contract yDelegatedVault is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;

    address public governance;
    address public controller;
    uint public insurance;
    uint public healthFactor = 4;

    uint public ltv = 65;
    uint public max = 100;

    address public constant aave = address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8);

    constructor (address _token, address _controller) public ERC20(
        string(abi.encodePacked("yearn ", ERC20(_token).name())),
        string(abi.encodePacked("y", ERC20(_token).symbol()))
    ) {
        _setupDecimals(ERC20(_token).decimals());
        token = IERC20(_token);
        governance = msg.sender;
        controller = _controller;
    }

    function debt() public view returns (uint) {
        address _reserve = Controller(controller).want(address(this));
        (,uint currentBorrowBalance,,,,,,,,) = Aave(getAave()).getUserReserveData(_reserve, address(this));
        return currentBorrowBalance;
    }

    function credit() public view returns (uint) {
        return Controller(controller).balanceOf(address(this));
    }

    // % of tokens locked and cannot be withdrawn per user
    // this is impermanent locked, unless the debt out accrues the strategy
    function locked() public view returns (uint) {
        return credit().mul(1e18).div(debt());
    }

    function debtShare(address _lp) public view returns (uint) {
        return debt().mul(balanceOf(_lp)).mul(totalSupply());
    }

    function getAave() public view returns (address) {
        return LendingPoolAddressesProvider(aave).getLendingPool();
    }

    function getAaveCore() public view returns (address) {
        return LendingPoolAddressesProvider(aave).getLendingPoolCore();
    }

    function setHealthFactor(uint _hf) external {
        require(msg.sender == governance, "!governance");
        healthFactor = _hf;
    }

    function activate() public {
        Aave(getAave()).setUserUseReserveAsCollateral(underlying(), true);
    }

    function repay(address reserve, uint amount) public  {
        // Required for certain stable coins (USDT for example)
        IERC20(reserve).approve(address(getAaveCore()), 0);
        IERC20(reserve).approve(address(getAaveCore()), amount);
        Aave(getAave()).repay(reserve, amount, address(uint160(address(this))));
    }

    function repayAll() public {
        address _reserve = reserve();
        uint _amount = IERC20(_reserve).balanceOf(address(this));
        repay(_reserve, _amount);
    }

    // Used to swap any borrowed reserve over the debt limit to liquidate to 'token'
    function harvest(address reserve, uint amount) external {
        require(msg.sender == controller, "!controller");
        require(reserve != address(token), "token");
        IERC20(reserve).safeTransfer(controller, amount);
    }

    // Ignore insurance fund for balance calculations
    function balance() public view returns (uint) {
        return token.balanceOf(address(this)).sub(insurance);
    }

    function setGovernance(address _governance) external {
      require(msg.sender == governance, "!governance");
      governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function getAaveOracle() public view returns (address) {
        return LendingPoolAddressesProvider(aave).getPriceOracle();
    }

    function getReservePriceETH(address reserve) public view returns (uint) {
        return Oracle(getAaveOracle()).getAssetPrice(reserve);
    }

    function shouldRebalance() external view returns (bool) {
        return (over() > 0);
    }

    function over() public view returns (uint) {
        over(0);
    }

    function getUnderlyingPriceETH(uint _amount) public view returns (uint) {
        _amount = _amount.mul(getUnderlyingPrice()).div(uint(10)**ERC20(address(token)).decimals()); // Calculate the amount we are withdrawing in ETH
        return _amount.mul(ltv).div(max).div(healthFactor);
    }

    function over(uint _amount) public view returns (uint) {
        address _reserve = reserve();
        uint _eth = getUnderlyingPriceETH(_amount);
        (uint _maxSafeETH,uint _totalBorrowsETH,) = maxSafeETH();
        _maxSafeETH = _maxSafeETH.mul(105).div(100); // 5% buffer so we don't go into a earn/rebalance loop
        if (_eth > _maxSafeETH) {
            _maxSafeETH = 0;
        } else {
            _maxSafeETH = _maxSafeETH.sub(_eth); // Add the ETH we are withdrawing
        }
        if (_maxSafeETH < _totalBorrowsETH) {
            uint _over = _totalBorrowsETH.mul(_totalBorrowsETH.sub(_maxSafeETH)).div(_totalBorrowsETH);
            _over = _over.mul(uint(10)**ERC20(_reserve).decimals()).div(getReservePrice());
            return _over;
        } else {
            return 0;
        }
    }

    function _rebalance(uint _amount) internal {
        uint _over = over(_amount);
        if (_over > 0) {
            if (_over > credit()) {
                _over = credit();
            }
            if (_over > 0) {
                Controller(controller).withdraw(address(this), _over);
                repayAll();
            }
        }
    }

    function rebalance() external {
        _rebalance(0);
    }

    function claimInsurance() external {
        require(msg.sender == controller, "!controller");
        token.safeTransfer(controller, insurance);
        insurance = 0;
    }

    function maxSafeETH() public view returns (uint maxBorrowsETH, uint totalBorrowsETH, uint availableBorrowsETH) {
         (,,uint _totalBorrowsETH,,uint _availableBorrowsETH,,,) = Aave(getAave()).getUserAccountData(address(this));
        uint _maxBorrowETH = (_totalBorrowsETH.add(_availableBorrowsETH));
        return (_maxBorrowETH.div(healthFactor), _totalBorrowsETH, _availableBorrowsETH);
    }

    function shouldBorrow() external view returns (bool) {
        return (availableToBorrowReserve() > 0);
    }

    function availableToBorrowETH() public view returns (uint) {
        (uint _maxSafeETH,uint _totalBorrowsETH, uint _availableBorrowsETH) = maxSafeETH();
        _maxSafeETH = _maxSafeETH.mul(95).div(100); // 5% buffer so we don't go into a earn/rebalance loop
        if (_maxSafeETH > _totalBorrowsETH) {
            return _availableBorrowsETH.mul(_maxSafeETH.sub(_totalBorrowsETH)).div(_availableBorrowsETH);
        } else {
            return 0;
        }
    }

    function availableToBorrowReserve() public view returns (uint) {
        address _reserve = reserve();
        uint _available = availableToBorrowETH();
        if (_available > 0) {
            return _available.mul(uint(10)**ERC20(_reserve).decimals()).div(getReservePrice());
        } else {
            return 0;
        }
    }

    function getReservePrice() public view returns (uint) {
        return getReservePriceETH(reserve());
    }

    function getUnderlyingPrice() public view returns (uint) {
        return getReservePriceETH(underlying());
    }

    function earn() external {
        address _reserve = reserve();
        uint _borrow = availableToBorrowReserve();
        if (_borrow > 0) {
            Aave(getAave()).borrow(_reserve, _borrow, 2, 7);
        }
        //rebalance here
        uint _balance = IERC20(_reserve).balanceOf(address(this));
        if (_balance > 0) {
            IERC20(_reserve).safeTransfer(controller, _balance);
            Controller(controller).earn(address(this), _balance);
        }
    }

    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    function deposit(uint _amount) public {
        uint _pool = balance();
        token.safeTransferFrom(msg.sender, address(this), _amount);

        // 0.5% of deposits go into an insurance fund incase of negative profits to protect withdrawals
        // At a 4 health factor, this is a -2% position
        uint _insurance = _amount.mul(50).div(10000);
        _amount = _amount.sub(_insurance);
        insurance = insurance.add(_insurance);


        //Controller can claim insurance to liquidate to cover interest

        uint shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
    }

    function reserve() public view returns (address) {
        return Controller(controller).want(address(this));
    }

    function underlying() public view returns (address) {
        return AaveToken(address(token)).underlyingAssetAddress();
    }

    function withdrawAll() public {
        withdraw(balanceOf(msg.sender));
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint _shares) public {
        uint r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);
        _rebalance(r);
        token.safeTransfer(msg.sender, r);
    }

    function getPricePerFullShare() external view returns (uint) {
        return balance().mul(1e18).div(totalSupply());
    }
}
