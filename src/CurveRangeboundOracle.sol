// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

interface CurvePool {
    function price_oracle() external view returns (uint);
}

contract CurveRangeboundOracle {

    /**
     * @dev Current price ceiling for the oracle
     */
    uint public priceCeiling;

    /**
     * @dev maximum amount ceiling can be set above current price, in basis points, above. 1 = 0.01%
     */
    uint public maxBPCeiling;

    /**
     * @dev minimum amount ceiling can be set above current price in, basis points, above current price. 1 = 0.01%
     */
    uint public minBPCeiling;

    /**
     * @dev Current price floor for the oracle
     */
    uint public priceFloor;

    /**
     * @dev maximum amount floor can be set above current price, in basis points, above. 1 = 0.01%
     */
    uint public maxBPFloor;

    /**
     * @dev minimum amount floor can be set above current price in, basis points, above current price. 1 = 0.01%
     */
    uint public minBPFloor;

    /**
     * @dev WETH token contract address.
     */
    address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
     * @dev underlying token contract address.
     */
    address constant public underlying = 0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68;

    /**
     * @dev uniswapV2 pair between underlying and WETH
     */
    CurvePool immutable public pool;

    /**
     * @dev Governance address, can set maxBPCeiling and minBPCeiling
     */
    address public governance;

    /**
     * @dev Guardian address, can raise or lower price ceiling
     */
    address public guardian;

    /**
     * @dev Internal baseUnit used as mantissa, set from decimals of underlying.
     */
    uint immutable private baseUnit;

    constructor(uint maxBPCeiling_, uint minBPCeiling_, uint maxBPFloor_, uint minBPFloor_, uint underlyingDecimals, address curvePool_, address governance_, address guardian_) {
        pool = CurvePool(curvePool_);
        maxBPCeiling = maxBPCeiling_;
        minBPCeiling = minBPCeiling_;
        maxBPFloor = maxBPFloor_;
        minBPFloor = minBPFloor_;
        governance = governance_;
        guardian = guardian_;
        baseUnit = 10 ** underlyingDecimals;
        priceCeiling = pool.price_oracle() * maxBPCeiling / 10000;
    }

    function price() public view returns (uint) {
        //Get exponential moving average
        uint ema = pool.price_oracle();
        return ema < priceCeiling ? ema : priceCeiling;
    }

    // **************************
    // **  GUARDIAN FUNCTIONS  **
    // **************************

    /**
     * @dev Function for setting newPriceCeiling, only callable by guardian
     * @param newPriceCeiling_ The new price ceiling, must be within max and min parameters
     */
    function setPriceCeiling(uint newPriceCeiling_) external {
        require(msg.sender == guardian);
        uint currentPrice = price();
        require(newPriceCeiling_ <= currentPrice + currentPrice*maxBPCeiling/10_000);
        require(newPriceCeiling_ >= currentPrice + currentPrice*minBPCeiling/10_000);
        priceCeiling = newPriceCeiling_;
        emit newPriceCeiling(newPriceCeiling_);
    }

    /**
     * @dev Function for setting newPriceFloor, only callable by guardian
     * @param newPriceFloor_ The new price floor, must be within max and min parameters
     */
    function setPriceFloor(uint newPriceFloor_) external {
        require(msg.sender == guardian);
        uint currentPrice = price();
        require(newPriceFloor_ <= currentPrice - currentPrice*maxBPFloor/10_000);
        require(newPriceFloor_ >= currentPrice - currentPrice*minBPFloor/10_000);
        priceFloor = newPriceFloor_;
        emit newPriceFloor(newPriceFloor_);
    }

    // **************************
    // ** GOVERNANCE FUNCTIONS **
    // **************************

    /**
     * @dev Function for setting new governance, only callable by governance
     * @param newGovernance_ address of the new guardian
     */
    function setGovernance(address newGovernance_) external {
        require(msg.sender == governance);
        governance = newGovernance_;
        emit newGovernance(newGovernance_);
    }

    /**
     * @dev Function for setting new guardian, only callable by governance
     * @param newGuardian_ address of the new guardian
     */
    function setGuardian(address newGuardian_) external {
        require(msg.sender == governance);
        guardian = newGuardian_;
        emit newGuardian(newGuardian_);
    }

    /**
     * @dev Function for setting new max height of price ceiling in basis points. 1 = 0.01%
     * @param newMaxBPCeiling_ New maximum amount a ceiling can go above current price
     */
    function setMaxBPCeiling(uint newMaxBPCeiling_) external {
        require(msg.sender == governance);
        require(newMaxBPCeiling_ >= minBPCeiling);
        maxBPCeiling = newMaxBPCeiling_;
        emit newMaxBPCeiling(newMaxBPCeiling_);
    }

    /**
     * @dev Function for setting new min height of price ceiling in basis points. 1 = 0.01%
     * @param newMinBPCeiling_ New minimum amount a ceiling must be above current price
     */
    function setMinBPCeiling(uint newMinBPCeiling_) external {
        require(msg.sender == governance);
        require(maxBPCeiling >= newMinBPCeiling_);
        minBPCeiling = newMinBPCeiling_;
        emit newMinBPCeiling(newMinBPCeiling_);
    }

    /**
     * @dev Function for setting new max height of price floor in basis points. 1 = 0.01%
     * @param newMaxBPFloor_ New maximum amount a floor must be below current price
     */
    function setMaxBPFloor(uint newMaxBPFloor_) external {
        require(msg.sender == governance);
        require(newMaxBPFloor_ >= minBPFloor);
        maxBPFloor = newMaxBPFloor_;
        emit newMaxBPFloor(newMaxBPFloor_);
    }

    /**
     * @dev Function for setting new min height of price floor in basis points. 1 = 0.01%
     * @param newMinBPFloor_ New minimum amount a floor can be below current price
     */
    function setMinBPFloor(uint newMinBPFloor_) external {
        require(msg.sender == governance);
        require(maxBPFloor >= newMinBPFloor_);
        minBPFloor = newMinBPFloor_;
        emit newMinBPFloor(newMinBPFloor_);
    }

    // ************
    // ** EVENTS **
    // ************
    event newPriceCeiling(uint newPriceCeiling);
    event newPriceFloor(uint newPriceFloor);
    event newGuardian(address newGuardian);
    event newGovernance(address newGovernance);
    event newMaxBPCeiling(uint newMaxBPCeiling);
    event newMinBPCeiling(uint newMinBPCeiling);
    event newMaxBPFloor(uint newMaxBPFloor);
    event newMinBPFloor(uint newMinBPFloor);
}
