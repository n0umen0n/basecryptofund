
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IWETH 
{
    function deposit() external payable;
    function withdraw(uint amount) external;
    function approve(address to, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
}

contract FundManagement is ERC20Burnable {
    address public owner;
    uint256 public totalWethValue;
    ISwapRouter public immutable swapRouter;
    address private constant WETH = 0x4200000000000000000000000000000000000006; // Adjust for network
    address private constant ETH_USD_POOL = 0xd0b53D9277642d899DF5C87A3966A349A798F224;
    IWETH public wethToken = IWETH(WETH);

    struct TokenAllocation {
        address token;
        uint256 percentage;
        uint24 poolfee;
        address pool;
    }

    TokenAllocation[] public allocations;

    struct Investment {
    uint256 amountInvested;
    uint256 usdValueAtInvestment;
}

// Mapping from investor address to their investments
mapping(address => Investment[]) public investments;
// Mapping to track whether a transaction hash has already been used
mapping(bytes32 => bool) public transactionHashes;



    // Events
    event TokensIssued(address indexed recipient, uint256 amount);
    event EthAllocatedForTokenPurchase(address indexed token, uint256 ethAmount, address pool);
    event SwapExecuted(uint256 amountIn, uint256 amountOut);
    event DebugUint(string message, uint256 value);
    event DebugString(string message);

    
    constructor(ISwapRouter _swapRouter) ERC20("FundToken", "FUND") {
        owner = msg.sender;
        swapRouter = _swapRouter;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    event ReceivedEther(address sender, uint256 amount);

    receive() external payable 
    {
    emit ReceivedEther(msg.sender, msg.value);
    }

    function listAllocatedTokens() public view returns (address[] memory tokens, uint256[] memory percentages, uint24[] memory poolfees, address[] memory pools) {
        uint256 length = allocations.length;
        tokens = new address[](length);
        percentages = new uint256[](length);
        poolfees = new uint24[](length);
        pools = new address[](length);

        for (uint i = 0; i < length; i++) {
            TokenAllocation storage allocation = allocations[i];
            tokens[i] = allocation.token;
            percentages[i] = allocation.percentage;
            poolfees[i] = allocation.poolfee;
            pools[i] = allocation.pool;
        }

        return (tokens, percentages, poolfees, pools);
    }

    function addTokenAllocation(address token, uint256 percentage, uint24 poolfee, address pool) public onlyOwner 
    {
    require(percentage <= 100, "Percentage must be between 0 and 100");
    for (uint i = 0; i < allocations.length; i++) {
        require(allocations[i].token != token, "Token already allocated");
    }
    allocations.push(TokenAllocation(token, percentage, poolfee, pool));
    }

    function removeTokenAllocation(address token) public onlyOwner 
    {
    uint256 index = allocations.length; // Initialize to an invalid index
    for (uint i = 0; i < allocations.length; i++) {
        if (allocations[i].token == token) {
            index = i;
            break;
        }
    }
    require(index < allocations.length, "Token not found");
    
    // Remove the element at index and shift left
    for (uint i = index; i < allocations.length - 1; i++) {
        allocations[i] = allocations[i + 1];
    }
    allocations.pop(); // Remove the last element
    }
/*
function getPriceFromUniswap(address token, address poolAddress) private view returns (uint256) {
    IUniswapV3Pool tokenPool = IUniswapV3Pool(poolAddress);
    (uint160 sqrtPriceX96,,,,,,) = tokenPool.slot0();
    address token0 = tokenPool.token0();
    uint256 tokenPriceInWETH;

    if (token == token0) {
        // Correctly handle the square of the sqrtPrice
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        tokenPriceInWETH = (sqrtPrice * sqrtPrice) >> 96 >> 96;  // Equivalent to / 2**192 but broken into two shifts for clarity
    } else {
        // Correctly handle the inverse of the price
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        uint256 priceSquared = (sqrtPrice * sqrtPrice) >> 96 >> 96;  // First scale down the square
        tokenPriceInWETH = 1e36 / priceSquared;  // 1e18 for scaling * 1e18 for price inversion
    }

    return tokenPriceInWETH;
}

function getPriceFromUniswap(address token, address poolAddress) private view returns (uint256) {
    IUniswapV3Pool tokenPool = IUniswapV3Pool(poolAddress);
    (uint160 sqrtPriceX96,,,,,,) = tokenPool.slot0();
    address token0 = tokenPool.token0();
    uint256 tokenPriceInWETH;

    // Reduce the scale of sqrtPriceX96 before squaring to avoid overflow
    uint256 price = uint256(sqrtPriceX96) >> 48;  // Adjust the scale
    uint256 priceSquared = price * price;  // Now safe to square
    uint256 adjustedPrice = priceSquared * (1e18 >> 48 >> 48);  // Adjust back after squaring

    if (token == token0) {
        tokenPriceInWETH = adjustedPrice;
    } else {
        // Check for zero to avoid division by zero
        if (adjustedPrice == 0) return type(uint256).max;  // Indicate an error or special case
        tokenPriceInWETH = 1e36 / adjustedPrice;  // Adjust for units if token is not token0
    }

    return tokenPriceInWETH;
}
*/

    function getPriceFromUniswap(address token, address poolAddress) private view returns (uint256) {
        IUniswapV3Pool tokenPool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96,,,,,,) = tokenPool.slot0();
        address token0 = tokenPool.token0();
        uint256 tokenPriceInWETH;

        if (token == token0) {
            tokenPriceInWETH = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / 1e18;
        } else {
            tokenPriceInWETH = 1e18 / (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / 1e18);
        }

        return tokenPriceInWETH;
    }

    function getEthPrice() public view returns (uint256) {
        IUniswapV3Pool ethUsdPool = IUniswapV3Pool(ETH_USD_POOL);
        (uint160 sqrtPriceX96,,,,,,) = ethUsdPool.slot0();
        uint256 ethPriceInUsd = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18 >> (96 * 2);
        return ethPriceInUsd;
    }

    function getTokenDecimals(address token) private view returns (uint8) 
    {
    return IERC20Extended(token).decimals();
    }


function updateTotalWethValue() private {
    // Start with the current total instead of zero
    uint256 newTotalWethValue = totalWethValue;

    for (uint i = 0; i < allocations.length; i++) {
        uint256 tokenBalance = IERC20(allocations[i].token).balanceOf(address(this));
        uint256 tokenPriceInWETH = getPriceFromUniswap(allocations[i].token, allocations[i].pool);
        uint8 decimals = getTokenDecimals(allocations[i].token);
        newTotalWethValue += (tokenPriceInWETH * tokenBalance) / (10 ** uint256(decimals));
    }
    totalWethValue = newTotalWethValue;
}

    function getTotalUsdValue() public view returns (uint256) {
        return totalWethValue * getEthPrice() / 1e18;
    }

    function getFundTokenUsdValue(address holder) public view returns (uint256) {
        uint256 holderBalance = balanceOf(holder);
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) return 0;
        return (holderBalance * getTotalUsdValue()) / totalSupply;
    }

function invest(uint256 ethAmount, address recipient, bytes32 trxHash) external onlyOwner {
    require(!transactionHashes[trxHash], "Transaction already processed");
    transactionHashes[trxHash] = true;
    require(ethAmount > 0 && address(this).balance >= ethAmount, "Insufficient ETH in contract");
    emit DebugString("ETH received for investment.");

    // Convert ETH to WETH
    wethToken.deposit{value: ethAmount}();
    emit DebugUint("WETH deposited", ethAmount);

    uint256 usdValue = (ethAmount * getEthPrice()) / 1e18;

    // Record the investment
    investments[recipient].push(Investment({
        amountInvested: ethAmount,
        usdValueAtInvestment: usdValue
    }));

    // Update WETH balance
    uint256 wethAmount = ethAmount;
    updateTotalWethValue();
    emit DebugUint("Updated total WETH value", totalWethValue);

    uint256 fundTokensToIssue = (totalWethValue == 0) ? wethAmount : (wethAmount * totalSupply()) / totalWethValue;
    totalWethValue += wethAmount;
    _mint(recipient, fundTokensToIssue);
    emit DebugUint("Fund tokens issued", fundTokensToIssue);

    // Allocate WETH according to the specified allocations
    for (uint i = 0; i < allocations.length; i++) {
        uint256 wethAmountForToken = (wethAmount / 100) * allocations[i].percentage;
        emit DebugUint("WETH amount calculated for token", wethAmountForToken);

        swapEthForToken(wethAmountForToken, allocations[i].token, allocations[i].poolfee);
        emit EthAllocatedForTokenPurchase(allocations[i].token, wethAmountForToken, allocations[i].pool);
    }
}


function swapEthForToken(uint256 wethAmount, address tokenOut, uint24 poolFee) private {
    emit DebugString("Starting token swap.");
    IWETH(WETH).approve(address(swapRouter), wethAmount);
    emit DebugUint("WETH approved for swap", wethAmount);

    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
        tokenIn: WETH,
        tokenOut: tokenOut,
        fee: poolFee,
        recipient: address(this),
        amountIn: wethAmount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
    });

    uint256 amountOut = swapRouter.exactInputSingle(params);
    emit DebugUint("Tokens received from swap", amountOut);
    emit SwapExecuted(wethAmount, amountOut);
}

/*
function redeem(uint256 fundTokenAmount) external {
    require(fundTokenAmount > 0, "Cannot redeem 0 tokens");
    require(balanceOf(msg.sender) >= fundTokenAmount, "Insufficient token balance");

    // Record the initial WETH balance to calculate the net WETH received from swaps
    uint256 initialWethBalance = IERC20(WETH).balanceOf(address(this));

    // Burn the FUND tokens first to avoid reentrancy issues
    _burn(msg.sender, fundTokenAmount);

    // Redeem each allocated token on Uniswap based on their proportion in the total allocations
    for (uint i = 0; i < allocations.length; i++) {
        uint256 tokenAmount = IERC20(allocations[i].token).balanceOf(address(this));
        uint256 tokenAmountToSell = (tokenAmount * fundTokenAmount) / totalSupply();

        // Approve the router to spend the tokens to be sold
        IERC20(allocations[i].token).approve(address(swapRouter), tokenAmountToSell);

        // Set up swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: allocations[i].token,
            tokenOut: WETH,
            fee: allocations[i].poolfee,
            recipient: address(this),
            amountIn: tokenAmountToSell,
            amountOutMinimum: 0,  // Consider setting a minimum amount out based on current market conditions
            sqrtPriceLimitX96: 0  // No price limit
        });

        // Perform the swap
        swapRouter.exactInputSingle(params);
    }

    // Calculate the WETH received from swaps
    uint256 finalWethBalance = IERC20(WETH).balanceOf(address(this));
    uint256 wethReceived = finalWethBalance - initialWethBalance;

    // Withdraw only the WETH received from token sales to ETH and send to the user
    IWETH(WETH).withdraw(wethReceived); 
    (bool success, ) = msg.sender.call{value: wethReceived}("");
    require(success, "Failed to send ETH");
}
*/


function redeem(uint256 usdAmount) external {
    uint256 userTotalUsdValue = getFundTokenUsdValue(msg.sender);  // Get the current USD value of the user's holdings
    require(userTotalUsdValue >= usdAmount, "Requested USD amount exceeds holdings");

    uint256 initialWethBalance = IERC20(WETH).balanceOf(address(this));


    uint256 userTokenBalance = balanceOf(msg.sender);  // User's current token balance

    // Calculate the percentage of the user's total value they wish to redeem
    uint256 percentageOfHoldings = (usdAmount * 1e18) / userTotalUsdValue;  // Scaled up for precision

    // Determine the number of tokens that corresponds to
    uint256 tokensToRedeem = (userTokenBalance * percentageOfHoldings) / 1e18;  // Scale back down

    require(tokensToRedeem > 0, "The amount to redeem is too small.");
    require(tokensToRedeem <= userTokenBalance, "Insufficient tokens to redeem.");

    require(balanceOf(msg.sender) >= tokensToRedeem, "Insufficient token balance");


    _burn(msg.sender, tokensToRedeem);

    // Redeem each allocated token on Uniswap based on their proportion in the total allocations
    for (uint i = 0; i < allocations.length; i++) {
        uint256 tokenAmount = IERC20(allocations[i].token).balanceOf(address(this));
        uint256 tokenAmountToSell = (tokenAmount * tokensToRedeem) / totalSupply();

        // Approve the router to spend the tokens to be sold
        IERC20(allocations[i].token).approve(address(swapRouter), tokenAmountToSell);

        // Set up swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: allocations[i].token,
            tokenOut: WETH,
            fee: allocations[i].poolfee,
            recipient: address(this),
            amountIn: tokenAmountToSell,
            amountOutMinimum: 0,  // Consider setting a minimum amount out based on current market conditions
            sqrtPriceLimitX96: 0  // No price limit
        });

        // Perform the swap
        swapRouter.exactInputSingle(params);
    }

    // Calculate the WETH received from swaps
    uint256 finalWethBalance = IERC20(WETH).balanceOf(address(this));
    uint256 wethReceived = finalWethBalance - initialWethBalance;

    // Withdraw only the WETH received from token sales to ETH and send to the user
    IWETH(WETH).withdraw(wethReceived); 
    (bool success, ) = msg.sender.call{value: wethReceived}("");
    require(success, "Failed to send ETH");
}

function calculateProfitOrLoss(address investor) public view returns (int256) {
    uint256 totalUsdValueNow = getFundTokenUsdValue(investor);
    uint256 totalInvestedUsdValue = 0;

    for (uint i = 0; i < investments[investor].length; i++) {
        totalInvestedUsdValue += investments[investor][i].usdValueAtInvestment;
    }

    // Calculate profit or loss
    int256 profitOrLoss = int256(totalUsdValueNow) - int256(totalInvestedUsdValue);
    return profitOrLoss;
}


function ownerSwapTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint24 poolFee,
    uint256 amountOutMin,
    uint160 sqrtPriceLimitX96
) external onlyOwner {
    // Ensure the contract has enough tokens to perform the swap
    require(IERC20(tokenIn).balanceOf(address(this)) >= amountIn, "Insufficient tokens");

    // Approve the swap router to use the specified amount of the input token
    IERC20(tokenIn).approve(address(swapRouter), amountIn);

    // Set up the swap parameters
    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        fee: poolFee,
        recipient: address(this),  // Tokens will be returned to the contract
        amountIn: amountIn,
        amountOutMinimum: amountOutMin,
        sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    // Execute the swap
    uint256 amountOut = swapRouter.exactInputSingle(params);
    emit SwapExecuted(amountIn, amountOut);
}

}
