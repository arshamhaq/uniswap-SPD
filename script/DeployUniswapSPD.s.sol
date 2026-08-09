// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20SPD} from "@spd/ERC20SPD.sol";

import {RouterSPD} from "../src/RouterSPD.sol";
import {SPD_USD_LP} from "../src/SPD_USD_LP.sol";
import {ISPD_USD_LP} from "../src/interfaces/ISPD_USD_LP.sol";
import {MockUSD} from "../src/tokens/MockUSD.sol";

/// @notice Deploys a complete local system or the Pair and Router on Sepolia.
contract DeployUniswapSPD is Script {
    // Existing Sepolia deployments. Environment values may override both.
    address internal constant DEFAULT_SPD_SEPOLIA = 0x805540aC3b8AE7dE3c991Df03999AD6fa36ca914;
    address internal constant DEFAULT_USDT_SEPOLIA = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;

    error InvalidTestMode();
    error WrongChain(uint256 expected, uint256 actual);
    error NotAContract(address account);

    function run() external returns (IERC20 spd, IERC20 usd, SPD_USD_LP pair, RouterSPD router) {
        uint256 testMode = vm.envOr("TEST_MODE", uint256(1));
        if (testMode > 1) revert InvalidTestMode();

        bool isLocal = testMode == 1;
        uint256 deployerPrivateKey = vm.envUint(isLocal ? "PRIVATE_KEY_ANVIL" : "PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        if (isLocal) {
            vm.startBroadcast(deployerPrivateKey);

            // Local mode owns every SPD role so the Anvil deployer can exercise the token.
            ERC20SPD localSpd =
                new ERC20SPD(deployer, deployer, deployer, vm.envUint("INITIAL_SUPPLY"), vm.envUint("MAXIMUM_SUPPLY"));
            MockUSD localUsd = new MockUSD();
            localUsd.mint(deployer, vm.envUint("MOCK_USD_INITIAL_SUPPLY"));

            spd = IERC20(address(localSpd));
            usd = IERC20(address(localUsd));
            pair = new SPD_USD_LP(address(spd), address(usd));
            router = new RouterSPD(spd, usd, ISPD_USD_LP(address(pair)));

            vm.stopBroadcast();
        } else {
            if (block.chainid != SEPOLIA_CHAIN_ID) {
                revert WrongChain(SEPOLIA_CHAIN_ID, block.chainid);
            }

            spd = IERC20(vm.envOr("SPD_SEPOLIA_ADDRESS", DEFAULT_SPD_SEPOLIA));
            usd = IERC20(vm.envOr("USDT_SEPOLIA_ADDRESS", DEFAULT_USDT_SEPOLIA));
            _requireContract(address(spd));
            _requireContract(address(usd));

            vm.startBroadcast(deployerPrivateKey);
            pair = new SPD_USD_LP(address(spd), address(usd));
            router = new RouterSPD(spd, usd, ISPD_USD_LP(address(pair)));
            vm.stopBroadcast();
        }

        console2.log("Deployer:", deployer);
        console2.log("SPD:", address(spd));
        console2.log(isLocal ? "MockUSD:" : "Sepolia USDT:", address(usd));
        console2.log("SPD_USD_LP:", address(pair));
        console2.log("RouterSPD:", address(router));
    }

    function _requireContract(address account) private view {
        if (account.code.length == 0) revert NotAContract(account);
    }
}
