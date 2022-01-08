// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./MasterChef.sol";
import "./ISafeswapFactory.sol";
import "./ISafeswapRouter.sol";

contract Trade {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Address of Staking contract
    address public masterChef;
    // The COSMI TOKEN!
    address public sfmr;
    // Cosmipay Growth Fund
    address public growthFund;
    address public owner;

    mapping(address => address) referrerOf;

    constructor(
        address _sfmr,
        address _growthFund,
        address _masterChef
    ) public {
        sfmr = _sfmr;
        owner = msg.sender;
        growthFund = _growthFund;
        masterChef = _masterChef;
    }

    // Need to call this when signing up to cosmipay using a paylink
    function setReferrer(address _paylinkHolder) public {
        referrerOf[msg.sender] = _paylinkHolder;
    }

    /*
     * Accept incoming payment from the buyer
     *
     * Deduct fees as per business model
     *
     * Send the tokens to the seller, fund growth, referrer & buyer
     */
    function sendTokens(
        address _token,
        uint256 _amount,
        address payable _to
    ) external payable {
        if (_token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            // ** IMPORTANT ** _amount = 0;
            uint256 amount = msg.value;
            // funtion to handle bnb transaction
            bnbTransaction(_token, amount, _to);
        } else {
            require(
                IERC20(_token).balanceOf(msg.sender) >= _amount,
                "!! Balance not enough !!"
            );
            require(
                IERC20(_token).allowance(msg.sender, address(this)) >= _amount,
                "!! Increase my _allowance_ OR _approve_ my spending limit !!"
            );
            // funtion to handle token transaction
            tokenTransaction(_token, _amount, _to);
        }
    }

    function ethForTokens(uint256 amt)
        internal
        returns (uint256[] memory output)
    {
        address[] memory path = new address[](2);
        path[0] = address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);
        path[1] = sfmr;

        uint256 deadline = block.timestamp.add(500);

        ISafeswapRouter02 pr =
            ISafeswapRouter02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);

        uint256[] memory amounts =
            pr.swapExactETHForTokens{value: amt}(
                0,
                path,
                address(this),
                deadline
            );
        return amounts;
    }

    function bnbTransaction(address token, uint256 amount, address payable seller) internal {
        // Pancake Interface
        ISafeswapFactory pf =
            ISafeswapFactory(0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc);

        // check if (BNB/COS) pair present in pancakeswap
        address pair =
            pf.getPair(sfmr, 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);
        require(pair != address(0), "!! BNB/COS pair not found !!");

        bool sellerStake = isSellerStaking(token, amount, seller);
        bool refStake = isReferrerStaking(token, amount, seller);

        address ref = referrerOf[seller];

        // 99% of amount
        uint256 amt99 = amount.mul(99).div(100);
        // 98% of amount
        uint256 amt98 = amount.mul(98).div(100);
        // Pending 1% of amount
        uint256 pendingAmt1 = amount.sub(amt99);
        // Pending 2% of amount
        uint256 pendingAmt2 = amount.sub(amt98);

        if (sellerStake && refStake) {
            // 99 % to seller
            seller.transfer(amt99);

            // swap Exact BNB For Tokens
            uint256[] memory output = ethForTokens(pendingAmt1);
            require(
                output[1] != 0,
                "!! Recieved 0 sfmr tokens from pancake !!"
            );
            //send 0.5% to buyer and referrer each
            uint256 amt = output[1].div(2);
            uint256 amtLeftover = output[1].sub(amt);
            IERC20(sfmr).transfer(msg.sender, amt);
            IERC20(sfmr).transfer(ref, amtLeftover);

        } else if (sellerStake && !refStake) {
            // 99 % to seller
            seller.transfer(amt99);

            // swap Exact BNB For Tokens
            uint256[] memory output = ethForTokens(pendingAmt1);
            require(
                output[1] != 0,
                "!! Recieved 0 sfmr tokens from pancake !!"
            );

            //send 0.5% to buyer
            uint256 amt = output[1].div(2);
            IERC20(sfmr).transfer(msg.sender, amt);

            // Burn 0.25% sfmr tokens
            // Deposit 0.25% to fund growth
            uint256 amtLeftover = output[1].sub(amt);
            uint256 amtLeft1 = amtLeftover.div(2);
            uint256 amtLeft2 = amtLeftover.sub(amtLeft1);
            IERC20(sfmr).transfer(growthFund, amtLeft1);
            IERC20(sfmr).burn(amtLeft2);

        } else if (!sellerStake && refStake) {
            // 98 % to seller
            seller.transfer(amt98);

            // swap Exact BNB For Tokens
            uint256[] memory output = ethForTokens(pendingAmt2);
            require(
                output[1] != 0,
                "!! Recieved 0 sfmr tokens from pancake !!"
            );

            //send 1% to buyer and referrer each
            uint256 amt = output[1].div(2);
            uint256 amtLeftover = output[1].sub(amt);
            IERC20(sfmr).transfer(msg.sender, amt);
            IERC20(sfmr).transfer(ref, amtLeftover);

        } else {
            // (!sellerStake && !refStake)

            // 98 % to seller
            seller.transfer(amt98);

            // swap Exact BNB For Tokens
            uint256[] memory output = ethForTokens(pendingAmt2);
            require(
                output[1] != 0,
                "!! Recieved 0 sfmr tokens from pancake !!"
            );

            //send 1% to buyer
            uint256 amt = output[1].div(2);
            IERC20(sfmr).transfer(msg.sender, amt);

            // Burn 0.5% sfmr tokens
            // Deposit 0.5% to fund growth
            uint256 amtLeftover = output[1].sub(amt);
            uint256 amtLeft1 = amtLeftover.div(2);
            uint256 amtLeft2 = amtLeftover.sub(amtLeft1);
            IERC20(sfmr).transfer(growthFund, amtLeft1);
            IERC20(sfmr).burn(amtLeft2);
        }
    }

    function tokensForTokens(address token, uint256 amt)
        internal
        returns (uint256[] memory output)
    {
        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);
        path[2] = sfmr;

        uint256 deadline = block.timestamp.add(500);
        IERC20(token).transferFrom(msg.sender, address(this), amt);
        IERC20(token).approve(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3, amt);

        ISafeswapRouter02 pr =
            ISafeswapRouter02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);

        uint256[] memory amounts =
            pr.swapExactTokensForTokens(amt, 0, path, address(this), deadline);

        return amounts;
    }

    function tokenTransaction(
        address token,
        uint256 amount,
        address seller
    ) internal {
        // Pancake Interface
        ISafeswapFactory pf =
            ISafeswapFactory(0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc);

        // check if (BNB/'Token sent by buyer') pair present in pancakeswap
        address pair1 =
            pf.getPair(token, 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);
        require(
            pair1 != address(0),
            "!! BNB/'Token sent by buyer' pair not found !!"
        );

        // check if (BNB/COS) pair present in pancakeswap
        address pair2 =
            pf.getPair(sfmr, 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);
        require(pair2 != address(0), "!! BNB/COS pair not found !!");

        bool sellerStake = isSellerStaking(token, amount, seller);
        bool refStake = isReferrerStaking(token, amount, seller);

        address ref = referrerOf[seller];

        // 99% of amount
        uint256 amt99 = amount.mul(99).div(100);
        // 98% of amount
        uint256 amt98 = amount.mul(98).div(100);
        // Pending 1% of amount
        uint256 pendingAmt1 = amount.sub(amt99);
        // Pending 2% of amount
        uint256 pendingAmt2 = amount.sub(amt98);

        if (sellerStake && refStake) {
            // 99 % to seller
            IERC20(token).transferFrom(msg.sender, seller, amt99);
            // swapping incoming token with sfmr
            uint256[] memory outputSFMR = tokensForTokens(token, pendingAmt1);
            require(
                outputSFMR[2] != 0,
                "!! Recieved 0 sfmr tokens from pancake !!"
            );
            // send 0.5% to buyer and referrer each
            uint256 amt = outputSFMR[2].div(2);
            uint256 amtLeftover = outputSFMR[2].sub(amt);
            IERC20(sfmr).transfer(msg.sender, amt);
            IERC20(sfmr).transfer(ref, amtLeftover);

        } else if (sellerStake && !refStake) {
            // 99 % to seller
            IERC20(token).transferFrom(msg.sender, seller, amt99);
            // swapping incoming token with sfmr
            uint256[] memory outputSFMR = tokensForTokens(token, pendingAmt1);
            require(
                outputSFMR[2] != 0,
                "!! Recieved 0 cosmi tokens from pancake !!"
            );
            // send 0.5% to buyer
            uint256 amt = outputSFMR[2].div(2);
            IERC20(sfmr).transfer(msg.sender, amt);
            // Burn 0.25% cosmi tokens
            // Deposit 0.25% to fund growth
            uint256 amtLeftover = outputSFMR[2].sub(amt);
            uint256 amtLeft1 = amtLeftover.div(2);
            uint256 amtLeft2 = amtLeftover.sub(amtLeft1);
            IERC20(sfmr).transfer(growthFund, amtLeft1);
            IERC20(sfmr).burn(amtLeft2);

        } else if (!sellerStake && refStake) {
            // 98 % to seller
            IERC20(token).transferFrom(msg.sender, seller, amt98);
            // swapping incoming token with sfmr
            uint256[] memory outputSFMR = tokensForTokens(token, pendingAmt2);
            require(
                outputSFMR[2] != 0,
                "!! Recieved 0 sfmr tokens from pancake !!"
            );
            // send 1% to buyer and referrer each
            uint256 amt = outputSFMR[2].div(2);
            uint256 amtLeftover = outputSFMR[2].sub(amt);
            IERC20(sfmr).transfer(msg.sender, amt);
            IERC20(sfmr).transfer(ref, amtLeftover);

        } else {
            // (!sellerStake && !refStake)
            // 98 % to seller
            IERC20(token).transferFrom(msg.sender, seller, amt98);
            // swapping incoming token with sfmr
            uint256[] memory outputSFMR= tokensForTokens(token, pendingAmt2);
            require(
                outputSFMR[2] != 0,
                "!! Recieved 0 sfmr tokens from pancake !!"
            );
            // send 1% to buyer
            uint256 amt = outputSFMR[2].div(2);
            IERC20(sfmr).transfer(msg.sender, amt);
            // Burn 0.5% sfmr tokens
            // Deposit 0.5% to fund growth
            uint256 amtLeftover = outputSFMR[2].sub(amt);
            uint256 amtLeft1 = amtLeftover.div(2);
            uint256 amtLeft2 = amtLeftover.sub(amtLeft1);
            IERC20(sfmr).transfer(growthFund, amtLeft1);
            IERC20(sfmr).burn(amtLeft2);
        }
    }

    function amountsOut(address token, uint256 amount)
        internal
        view
        returns (uint256[] memory output)
    {
        address[] memory pathbnb = new address[](2);
        pathbnb[0] = address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);
        pathbnb[1] = sfmr;

        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);
        path[2] = sfmr;

        ISafeswapRouter02 pr =
            ISafeswapRouter02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);

        if (token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            uint256[] memory amounts = pr.getAmountsOut(amount, pathbnb);
            return amounts;
        } else {
            uint256[] memory amounts = pr.getAmountsOut(amount, path);
            return amounts;
        }
    }

    // Check if seller is staking 1.5% sfmr tokens of the amount sent by the buyer
    function isSellerStaking(address token, uint256 amount, address seller)
        public
        view
        returns (bool)
    {
        uint256 amt;
        uint256[] memory output = amountsOut(token, amount);
        MasterChef mc = MasterChef(masterChef);
        uint256 sellerStakeAmount = mc.userStakingAmount(seller);

        if (token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            amt = output[1].mul(15).div(1000);
        } else {
            amt = output[2].mul(15).div(1000);
        }

        if (sellerStakeAmount >= amt) {
            return true;
        } else {
            return false;
        }
    }

    // Check if referrer has staked 150% of 0.5% of amount buyer sends
    function isReferrerStaking(address token, uint256 amount, address seller)
        public
        view
        returns (bool)
    {
        uint256 amt;
        uint256[] memory output = amountsOut(token, amount);
        MasterChef mc = MasterChef(masterChef);
        require(
                referrerOf[seller] != address(0),
                "!! Referrer dosen't exist !!"
            );
        address ref = referrerOf[seller];
        uint256 referrerStakeAmount = mc.userStakingAmount(ref);

        if (token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            amt = output[1].mul(5).div(1000);
        } else {
            amt = output[2].mul(5).div(1000);
        }

        uint256 amtb = amt.mul(15).div(10);
        if (referrerStakeAmount >= amtb) {
            return true;
        } else {
            return false;
        }
    }

     function addLiquidity(address _rewardToken, address _token, uint256 _rewardTokenAmt, uint256 _tokenAmt) public returns(bool){

        IERC20(_rewardToken).transferFrom(msg.sender, address(this), _rewardTokenAmt);
        IERC20(_token).transferFrom(msg.sender, address(this), _tokenAmt);

        uint256 deadline = block.timestamp+(500);
        IERC20(_rewardToken).approve(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3, _rewardTokenAmt);
        IERC20(_token).approve(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3, _tokenAmt);

         ISafeswapRouter02 pr =
         ISafeswapRouter02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);

        pr.addLiquidity(address(_token),address(_rewardToken),_tokenAmt,_rewardTokenAmt,0,0, address(this), deadline);
    }

    function tokensForTokens(address token,address rewardToken, uint256 amt,uint256 amountOutMin)public returns (uint256[] memory output){
        ISafeswapFactory pf =
            ISafeswapFactory(0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc);

        // check if (BNB/'Token sent by buyer') pair present in pancakeswap
        address pair =
            pf.getPair(rewardToken, token);
        require(
            pair != address(0),
            "!! SFMR/'Safemoon' pair not found !!"
        );
        address[] memory path = new address[](2);
        path[0] = rewardToken;
        path[1] = token;

        uint256 deadline = block.timestamp+(500);
        IERC20(rewardToken).transferFrom(msg.sender, address(this), amt);
        IERC20(rewardToken).approve(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3, amt);

        ISafeswapRouter02 pr =
            ISafeswapRouter02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);

        uint256[] memory amounts =
            pr.swapExactTokensForTokens(amt, amountOutMin, path,msg.sender, deadline);

        return amounts;
    }
}
