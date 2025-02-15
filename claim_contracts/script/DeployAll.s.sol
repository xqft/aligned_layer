// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../src/AlignedToken.sol";
import "../src/ClaimableAirdrop.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Script.sol";
import {Utils} from "./Utils.sol";

contract DeployAll is Script {
    function run(string memory config) public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/script-config/config.",
            config,
            ".json"
        );
        string memory config_json = vm.readFile(path);

        bytes32 _salt = stdJson.readBytes32(config_json, ".salt");
        address _deployer = stdJson.readAddress(config_json, ".deployer");
        address _foundation = stdJson.readAddress(config_json, ".foundation");
        address _safe = _foundation;
        address _claim = stdJson.readAddress(config_json, ".tokenDistributor");
        uint256 _claimPrivateKey = vm.envUint("CLAIM_SUPPLIER_PRIVATE_KEY");
        uint256 _limitTimestampToClaim = stdJson.readUint(
            config_json,
            ".limitTimestampToClaim"
        );
        bytes32 _claimMerkleRoot = stdJson.readBytes32(
            config_json,
            ".claimMerkleRoot"
        );

        TransparentUpgradeableProxy _tokenProxy = deployAlignedTokenProxy(
            address(_safe),
            _salt,
            _deployer,
            _foundation,
            _claim
        );

        TransparentUpgradeableProxy _airdropProxy = deployClaimableAirdropProxy(
            address(_safe),
            _safe,
            _foundation,
            _salt,
            _deployer,
            address(_tokenProxy),
            _limitTimestampToClaim,
            _claimMerkleRoot
        );

        approve(address(_tokenProxy), address(_airdropProxy), _claimPrivateKey);
    }

    function deployProxyAdmin(
        address _safe,
        bytes32 _salt,
        address _deployer
    ) internal returns (ProxyAdmin) {
        bytes memory _proxyAdminDeploymentData = Utils.proxyAdminDeploymentData(
            _safe
        );
        address _proxyAdminCreate2Address = Utils.deployWithCreate2(
            _proxyAdminDeploymentData,
            _salt,
            _deployer
        );

        console.log(
            "Proxy Admin Address:",
            _proxyAdminCreate2Address,
            "Owner:",
            _safe
        );
        vm.serializeAddress("proxyAdmin", "address", _proxyAdminCreate2Address);
        vm.serializeBytes(
            "proxyAdmin",
            "deploymentData",
            _proxyAdminDeploymentData
        );

        return ProxyAdmin(_proxyAdminCreate2Address);
    }

    function deployAlignedTokenProxy(
        address _proxyOwner,
        bytes32 _salt,
        address _deployer,
        address _foundation,
        address _claim
    ) internal returns (TransparentUpgradeableProxy) {
        vm.broadcast();
        AlignedToken _token = new AlignedToken();

        bytes memory _alignedTokenDeploymentData = Utils
            .alignedTokenProxyDeploymentData(
                _proxyOwner,
                address(_token),
                _foundation,
                _claim
            );
        address _alignedTokenProxy = Utils.deployWithCreate2(
            _alignedTokenDeploymentData,
            _salt,
            _deployer
        );

        address _proxyAdmin = Utils.getAdminAddress(_alignedTokenProxy);

        console.log(
            "AlignedToken proxy deployed with address: ",
            _alignedTokenProxy,
            " and admin: ",
            _proxyAdmin
        );
        vm.serializeAddress("alignedToken", "address", _alignedTokenProxy);
        vm.serializeAddress("alignedTokenAdmin", "address", _proxyAdmin);
        vm.serializeBytes(
            "alignedToken",
            "deploymentData",
            _alignedTokenDeploymentData
        );

        return TransparentUpgradeableProxy(payable(_alignedTokenProxy));
    }

    function deployClaimableAirdropProxy(
        address _proxyOwner,
        address _owner,
        address _tokenOwner,
        bytes32 _salt,
        address _deployer,
        address _token,
        uint256 _limitTimestampToClaim,
        bytes32 _claimMerkleRoot
    ) internal returns (TransparentUpgradeableProxy) {
        vm.broadcast();
        ClaimableAirdrop _airdrop = new ClaimableAirdrop();

        bytes memory _airdropDeploymentData = Utils
            .claimableAirdropProxyDeploymentData(
                _proxyOwner,
                address(_airdrop),
                _owner,
                _token,
                _tokenOwner,
                _limitTimestampToClaim,
                _claimMerkleRoot
            );
        address _airdropProxy = Utils.deployWithCreate2(
            _airdropDeploymentData,
            _salt,
            _deployer
        );

        address _proxyAdmin = Utils.getAdminAddress(_airdropProxy);

        console.log(
            "ClaimableAirdrop proxy deployed with address:",
            _airdropProxy,
            "and admin:",
            _proxyAdmin
        );
        vm.serializeAddress("claimableAirdrop", "address", _airdropProxy);
        vm.serializeAddress("claimableAirdropAdmin", "address", _proxyAdmin);
        vm.serializeBytes(
            "claimableAirdrop",
            "deploymentData",
            _airdropDeploymentData
        );

        return TransparentUpgradeableProxy(payable(_airdropProxy));
    }

    function approve(
        address _tokenContractProxy,
        address _airdropContractProxy,
        uint256 _claimPrivateKey
    ) public {
        vm.startBroadcast(_claimPrivateKey);
        (bool success, bytes memory data) = address(_tokenContractProxy).call(
            abi.encodeCall(
                IERC20.approve,
                (address(_airdropContractProxy), 1 ether)
            )
        );
        bool approved;
        assembly {
            approved := mload(add(data, 0x20))
        }

        if (!success || !approved) {
            revert("Failed to give approval to airdrop contract");
        }
        vm.stopBroadcast();

        console.log("Succesfully gave approval to airdrop contract");
    }
}
