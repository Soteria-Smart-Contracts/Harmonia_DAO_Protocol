//SPDX-License-Identifier:UNLICENSE
pragma solidity ^0.8.17;

contract HarmoniaDAOTreasury{
    string public Version = "V1";
    address public DAO;
    uint256 public RegisteredAssetLimit;
    Token public CLD;
    Token[] public RegisteredAssets;

    mapping(address => bool) public AssetRegistryMap;


    modifier OnlyDAO{ //This same modifier must be used on external contracts called by this contract 
        require(msg.sender == DAO  || EROSDAO(DAO).CheckErosApproval(msg.sender), "The caller is either not the DAO or not approved by the DAO");
        _;
    }

    //Events
    event AssetRegistered(address NewToken, uint256 CurrentBalance);
    event AssetLimitChange(uint256 NewLimit);
    //Events

    struct Token{
        address TokenAddress;
        uint256 DAObalance;
    }

    constructor(address DAOcontract, address CLDcontract){
        DAO = DAOcontract;
        CLD = Token(CLDcontract, 0);
        RegisteredAssetLimit = 5;
        RegisteredAssets.push(CLD);
    }

    function ChangeRegisteredAssetLimit(uint amount) internal{
        RegisteredAssetLimit = amount;
        // TO DO NewAssetLimit event
    }

    function ReceiveRegisteredAsset(address from, uint AssetId, uint amount) internal {
        ERC20(RegisteredAssets[AssetId].TokenAddress).transferFrom(from, address(this), amount);
        UpdateERC20Balance(AssetId);
        // TO DO assetreceived event
    }

    function RegisterAsset(address tokenAddress, uint256 slot) external OnlyDAO { //make callable from eros
        require(slot <= RegisteredAssetLimit && slot != 0);
        require(AssetRegistryMap[tokenAddress] == false);
        require(RegisteredAssets[slot].TokenAddress == address(0) || ERC20(RegisteredAssets[slot].TokenAddress).balanceOf(address(this)) == 0); //How can I check if a slot is populated?
        
        RegisteredAssets[slot] =  Token(tokenAddress, ERC20(tokenAddress).balanceOf(address(this)));
        AssetRegistryMap[tokenAddress] = true;

        emit AssetRegistered(RegisteredAssets[slot].TokenAddress, RegisteredAssets[slot].DAObalance);
    }

    function UpdateERC20Balance(uint256 AssetID) internal {
        RegisteredAssets[AssetID].DAObalance = ERC20(RegisteredAssets[AssetID].TokenAddress).balanceOf(address(this));
    }

    function TransferETH(uint256 amount, address payable receiver) external OnlyDAO{
       receiver.transfer(amount);
    }

    function TransferERC20(uint256 amount, address receiver) external OnlyDAO{
        
    }



    receive() external payable{
    }

    fallback() external payable{
    }

}

interface ERC20 {
  function balanceOf(address owner) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint value) external returns (bool);
  function transfer(address to, uint value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool); 
  function totalSupply() external view returns (uint);
} 