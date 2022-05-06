// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import "../lib/openzeppelin-contracts-upgradeable/contracts/math/SafeMathUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

import "src/IUniswapV2Pair.sol";

/**
 * @title UniswapTwapPriceOracleV2Ceiling
 * @dev based on UniswapTwapPriceOracleRoot by David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice Stores cumulative prices and returns TWAPs for assets on Uniswap V2 pairs.
 */
contract UniswapTwapPriceOracleV2Ceiling {
    using SafeMathUpgradeable for uint256;

    /**
     * @dev Current price ceiling for the oracle
     */
    uint public priceCeiling;

    /**
     * @dev maximum amount ceilining can be set above current price, in basis points, above. 1 = 0.01%
     */
    uint public maxBPCeiling;

    /**
     * @dev minimum amount ceiling can be set above current price in, basis points, above current price. 1 = 0.01%
     */
    uint public minBPCeiling;

    /**
     * @dev WETH token contract address.
     */
    address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
     * @dev underlying token contract address.
     */
    address immutable public underlying;

    /**
     * @dev uniswapV2 pair between underlying and WETH
     */
    address immutable public pair;

    /**
     * @dev Governance address, can set maxBPCeiling and minBPCeiling
     */
    address public governance;

    /**
     * @dev Guardian address, can raise or lower price ceiling
     */
    address public guardian;

    /**
     * @dev Minimum TWAP interval.
     */
    uint256 public immutable MIN_TWAP_TIME;

    constructor(uint MIN_TWAP_TIME_, uint maxBPCeiling_, uint minBPCeiling_, address pair_, address governance_, address guardian_) public{
        MIN_TWAP_TIME = MIN_TWAP_TIME_;
        maxBPCeiling = maxBPCeiling_;
        minBPCeiling = minBPCeiling_;
        governance = governance_;
        guardian = guardian_;
        pair = pair_;
        underlying = IUniswapV2Pair(pair_).token0() == WETH ? IUniswapV2Pair(pair_).token1() : IUniswapV2Pair(pair_).token0();
    }

    /**
     * @dev Return the TWAP value price0. Revert if TWAP time range is not within the threshold.
     * Copied from: https://github.com/AlphaFinanceLab/homora-v2/blob/master/contracts/oracle/BaseKP3ROracle.sol
     * @param observationsToDiscard Number of observations to discard when getting price. Discard 1 to get official price, discard 0 when getting current observation price.
     */
    function price0TWAP(uint observationsToDiscard) internal view returns (uint) {
        uint length = observationCount;
        require(length > 0, 'No length-1 TWAP observation.');//TODO: A lot of checking to do for something that's only relevant when 0 observations have been made
        require(observationsToDiscard < 2);
        Observation memory lastObservation = observations[(length - observationsToDiscard) % OBSERVATION_BUFFER];
        if (lastObservation.timestamp > now - MIN_TWAP_TIME) {
            require(length > 1, 'No length-2 TWAP observation.');//TODO: A lot of checking to do for something that's only relevant when 0 observations have been made
            lastObservation = observations[(length - 1 - observationsToDiscard) % OBSERVATION_BUFFER];
        }
        uint elapsedTime = now - lastObservation.timestamp;
        require(elapsedTime >= MIN_TWAP_TIME, 'Bad TWAP time.');
        return (currentPx0Cumu() - lastObservation.price0Cumulative) / (now - lastObservation.timestamp); // overflow is desired
    }

    /**
     * @dev Return the TWAP value price1. Revert if TWAP time range is not within the threshold.
     * Copied from: https://github.com/AlphaFinanceLab/homora-v2/blob/master/contracts/oracle/BaseKP3ROracle.sol
     * @param observationsToDiscard Number of observations to discard when getting price. Discard 1 to get official price, discard 0 when getting current observation price.
     */
    function price1TWAP(uint observationsToDiscard) internal view returns (uint) {
        uint length = observationCount;
        require(length > 0, 'No length-1 TWAP observation.'); //TODO: A lot of checking to do for something that's only relevant when 0 observations have been made
        require(observationsToDiscard < 2);
        Observation memory lastObservation = observations[(length - observationsToDiscard) % OBSERVATION_BUFFER];
        if (lastObservation.timestamp > now - MIN_TWAP_TIME) {
            require(length > 1, 'No length-2 TWAP observation.');//TODO: A lot of checking to do for something that's only relevant when 0 observations have been made
            lastObservation = observations[(length - 1 - observationsToDiscard) % OBSERVATION_BUFFER];
        }
        uint elapsedTime = now - lastObservation.timestamp;
        require(elapsedTime >= MIN_TWAP_TIME, 'Bad TWAP time.');
        return (currentPx1Cumu() - lastObservation.price1Cumulative) / (now - lastObservation.timestamp); // overflow is desired
    }

    /**
     * @dev Return the current price0 cumulative value on Uniswap.
     * Copied from: https://github.com/AlphaFinanceLab/homora-v2/blob/master/contracts/oracle/BaseKP3ROracle.sol
     */
    function currentPx0Cumu() internal view returns (uint px0Cumu) {
        uint32 currTime = uint32(now);
        px0Cumu = IUniswapV2Pair(pair).price0CumulativeLast();
        (uint reserve0, uint reserve1, uint32 lastTime) = IUniswapV2Pair(pair).getReserves();
        if (lastTime != now) {
            uint32 timeElapsed = currTime - lastTime; // overflow is desired
            px0Cumu += uint((reserve1 << 112) / reserve0) * timeElapsed; // overflow is desired
        }
    }

    /**
     * @dev Return the current price1 cumulative value on Uniswap.
     * Copied from: https://github.com/AlphaFinanceLab/homora-v2/blob/master/contracts/oracle/BaseKP3ROracle.sol
     */
    function currentPx1Cumu() internal view returns (uint px1Cumu) {
        uint32 currTime = uint32(now);
        px1Cumu = IUniswapV2Pair(pair).price1CumulativeLast();
        (uint reserve0, uint reserve1, uint32 lastTime) = IUniswapV2Pair(pair).getReserves();
        if (lastTime != currTime) {
            uint32 timeElapsed = currTime - lastTime; // overflow is desired
            px1Cumu += uint((reserve0 << 112) / reserve1) * timeElapsed; // overflow is desired
        }
    }
    
    /**
     * @dev Returns the price of `underlying` in terms of `baseToken` given `factory`.
     */
    function price() public view returns (uint) {
        // Return ERC20/ETH TWAP
        uint256 baseUnit = 10 ** uint256(ERC20Upgradeable(underlying).decimals());
        return (underlying < WETH ? price0TWAP(1) : price1TWAP(1)).div(2 ** 56).mul(baseUnit).div(2 ** 56); // Scaled by 1e18, not 2 ** 112
    }

    function observationPrice() internal view returns (uint) {
        // Return ERC20/ETH TWAP
        uint256 baseUnit = 10 ** uint256(ERC20Upgradeable(underlying).decimals());
        return (underlying < WETH ? price0TWAP(0) : price1TWAP(0)).div(2 ** 56).mul(baseUnit).div(2 ** 56); // Scaled by 1e18, not 2 ** 112
    }

    /**
     * @dev Struct for cumulative price observations.
     */
    struct Observation {
        uint32 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    /**
     * @dev Length after which observations roll over to index 0.
     */
    uint8 public constant OBSERVATION_BUFFER = 4;

    /**
     * @dev Total observation count for each pair.
     */
    uint256 public observationCount;

    /**
     * @dev Array of cumulative price observations for each pair.
     */
    Observation[OBSERVATION_BUFFER] public observations;


    /// @notice Check which of multiple pairs are workable/updatable.
    function workable( uint256 minPeriod, uint256 deviationThreshold) external view returns (bool) {
        return _workable(minPeriod, deviationThreshold);
    }
    
    /// @dev Internal function to check if a pair is workable (updateable AND reserves have changed AND deviation threshold is satisfied).
    function _workable(uint256 minPeriod, uint256 deviationThreshold) internal view returns (bool) {
        // Workable if:
        // 1) We have no observations
        // 2) The elapsed time since the last observation is > minPeriod AND reserves have changed AND deviation threshold is satisfied 
        // Note that we loop observationCount[pair] around OBSERVATION_BUFFER so we don't waste gas on new storage slots
        if (observationCount <= 0) return true;
        (, , uint32 lastTime) = IUniswapV2Pair(pair).getReserves();
        return (block.timestamp - observations[(observationCount - 1) % OBSERVATION_BUFFER].timestamp) > (minPeriod >= MIN_TWAP_TIME ? minPeriod : MIN_TWAP_TIME) &&
            lastTime != observations[(observationCount - 1) % OBSERVATION_BUFFER].timestamp &&
            _deviation() >= deviationThreshold;
    }

    /// @dev Internal function to check if a pair's spot price's deviation from its TWAP price as a ratio scaled by 1e18
    function _deviation() internal view returns (uint256) {
        // Get token base unit
        bool useToken0Price = IUniswapV2Pair(pair).token0() != WETH;
        uint256 baseUnit = 10 ** uint256(ERC20Upgradeable(underlying).decimals());

        // Get TWAP price
        uint256 twapPrice = (useToken0Price ? price0TWAP(1) : price1TWAP(1)).div(2 ** 56).mul(baseUnit).div(2 ** 56); // Scaled by 1e18, not 2 ** 112
    
        // Get spot price
        (uint reserve0, uint reserve1, ) = IUniswapV2Pair(pair).getReserves();
        uint256 spotPrice = useToken0Price ? reserve1.mul(baseUnit).div(reserve0) : reserve0.mul(baseUnit).div(reserve1);

        // Get ratio and return deviation
        uint256 ratio = spotPrice.mul(1e18).div(twapPrice);
        return ratio >= 1e18 ? ratio - 1e18 : 1e18 - ratio;
    }
    
    /// @dev Internal function to check if a pair is updatable at all.
    function _updateable() internal view returns (bool) {
        // Updateable if:
        // 1) We have no observations
        // 2) The elapsed time since the last observation is > MIN_TWAP_TIME
        // Note that we loop observationCount[pair] around OBSERVATION_BUFFER so we don't waste gas on new storage slots
        if(observationCount <= 0 || (block.timestamp - observations[(observationCount - 1) % OBSERVATION_BUFFER].timestamp) > MIN_TWAP_TIME){
            return observationPrice() < priceCeiling;        
        } else {
            return false;
        }
    }

    /// @notice Update one pair.
    function update() external {
        require(_update(), "Failed to update pair.");
    }


    /// @dev Internal function to update a single pair.
    function _update() internal returns (bool) {
        // Check if workable
        if (!_updateable()) return false;

        // Get cumulative price(s)
        uint256 price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        uint256 price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();
        
        // Loop observationCount[pair] around OBSERVATION_BUFFER so we don't waste gas on new storage slots
        (, , uint32 lastTime) = IUniswapV2Pair(pair).getReserves();
        observations[observationCount % OBSERVATION_BUFFER] = Observation(lastTime, price0Cumulative, price1Cumulative);
        observationCount++;
        return true;
    }
    // **************************
    // **  GUARDIAN FUNCTIONS  **
    // **************************

    /**
     * @dev Function for setting newPriceCeiling, only callable by guardian
     * @param newPriceCeiling The new price ceiling, must be within max and min parameters
     */
    function setPriceCeiling(uint newPriceCeiling) external {
        require(msg.sender == guardian);
        uint currentPrice = price();
        require(newPriceCeiling <= currentPrice + currentPrice*maxBPCeiling/10_000);
        require(newPriceCeiling >= currentPrice + currentPrice*minBPCeiling/10_000);
        priceCeiling = newPriceCeiling;
    }

    // **************************
    // ** GOVERNANCE FUNCTIONS **
    // **************************

    /**
     * @dev Function for setting new guardian, only callable by governance
     * @param newGuardian address of the new guardian
     */
    function setGuardian(address newGuardian) external {
        require(msg.sender == governance);
        guardian = newGuardian;
    }

    /**
     * @dev Function for setting new max height of price ceiling in basis points. 1 = 0.01%
     * @param newMaxBPCeiling New maximum amount a ceiling can go above current price
     */
    function setMaxBPCeiling(uint newMaxBPCeiling) external {
        require(msg.sender == governance);
        require(newMaxBPCeiling >= minBPCeiling);
        maxBPCeiling = newMaxBPCeiling;
    }

    /**
     * @dev Function for setting new min height of price ceiling in basis points. 1 = 0.01%
     * @param newMinBPCeiling New minimum amount a ceiling must be above current price
     */
    function setMinBPCeiling(uint newMinBPCeiling) external {
        require(msg.sender == governance);
        require(maxBPCeiling >= newMinBPCeiling);
        minBPCeiling = newMinBPCeiling;
    }
}