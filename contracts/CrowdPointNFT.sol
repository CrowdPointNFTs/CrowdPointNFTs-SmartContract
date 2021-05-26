// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract CrowdPointNFT is ERC721, Ownable {
    address payable public _contractOwner;

    mapping (uint => uint) public price;
    mapping (uint => bool) public listedMap;
    mapping (uint => NFT_TYPE) public nftTypeMap;
    mapping (uint => uint) public expireAuctionMap;
    mapping (uint => mapping(address => Bid)) public bidMap;
    mapping (uint => Bid[]) public bidArray;
    
    IERC20 public wBNBToken;

    enum NFT_TYPE {BUY, AUCTION}
    enum BID_STATUS {OPEN, CLOSED, CANCELLED}
    
    struct Bid {
        uint id; //Index in Array of TokenId's Bid
        uint tokenId;
        address bidder;
        uint price;
        BID_STATUS status;
    }

    event Purchase(address indexed previousOwner, address indexed newOwner, uint price, uint nftID, string uri);

    event Minted(address indexed minter, uint price, uint nftID, string uri, uint nftType);

    event PriceUpdate(address indexed owner, uint oldPrice, uint newPrice, uint nftID);

    event NftListStatus(address indexed owner, uint nftID, bool isListed);

    event BidCreated(address indexed buyer, uint nftID, uint price);

    event BidCancelled(address indexed buyer, uint nftID);

    event AuctionStarted(uint nftID, uint expireAt);



    constructor() ERC721("CrowdPointNFTs", "CPN") {
        _contractOwner = msg.sender;
        // wBNBToken = IERC20("0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"); //BSC WBNB
        wBNBToken = IERC20(address(0xd0A1E359811322d97991E03f863a0C30C2cF029C)); //Kovan WETH
    }

    function mint(string memory _tokenURI, uint _price, uint _type) public returns (uint) {
        require(_type < 2, "Nor Supported NFT Type");
        
        uint _tokenId = totalSupply() + 1;
        price[_tokenId] = _price;
        listedMap[_tokenId] = true;
        if (_type == 0)
        {
            nftTypeMap[_tokenId] = NFT_TYPE.BUY;
        }
        else if (_type == 1)
        {
            nftTypeMap[_tokenId] = NFT_TYPE.AUCTION;
        }

        _safeMint(msg.sender, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);

        emit Minted(msg.sender, _price, _tokenId, _tokenURI, _type);

        return _tokenId;
    }

    function startAuction(uint _id, uint _duration) external {
        _validateAuction(_id, _duration);

        expireAuctionMap[_id] = block.timestamp + _duration;

        emit AuctionStarted(_id, expireAuctionMap[_id]);
    }

    function buy(uint _id) external payable {
        _validateBuy(_id);

        address _previousOwner = ownerOf(_id);
        address _newOwner = msg.sender;

        _trade(_id);

        emit Purchase(_previousOwner, _newOwner, price[_id], _id, tokenURI(_id));
    }

    function bid(uint _id, uint _price) external {
        _validateBid(_id, _price);

        uint bidId = bidArray[_id].length;
        Bid memory newBid = Bid(bidId, _id, msg.sender, _price, BID_STATUS.OPEN);
        bidArray[_id].push(newBid);
        bidMap[_id][msg.sender] = newBid;

        emit BidCreated(msg.sender, _id, _price);
    }

    function cancelBid(uint _id) external {
        _validateCancelBid(_id);

        _cancelBid(_id, msg.sender);

        emit BidCancelled(msg.sender, _id);
    }

    function sell(uint _id, address _buyer) external {
        _validateSell(_id, _buyer);

        address _previousOwner = ownerOf(_id);
        address _newOwner = _buyer;

        _sell(_id, _buyer, bidMap[_id][_buyer].price);
        _cleanBid(_id);

        emit Purchase(_previousOwner, _newOwner, price[_id], _id, tokenURI(_id));
    }

    function onTimer() external onlyOwner
    {
        _processAuction();
    }

    function updatePrice(uint _tokenId, uint _price) public returns (bool) {
        uint oldPrice = price[_tokenId];
        require(msg.sender == ownerOf(_tokenId), "Error, you are not the owner");
        price[_tokenId] = _price;

        emit PriceUpdate(msg.sender, oldPrice, _price, _tokenId);
        return true;
    }

    function updateListingStatus(uint _tokenId, bool shouldBeListed) public returns (bool) {
        require(msg.sender == ownerOf(_tokenId), "Error, you are not the owner");

        listedMap[_tokenId] = shouldBeListed;

        emit NftListStatus(msg.sender, _tokenId, shouldBeListed);

        return true;
    }


    function _validateBuy(uint _id) internal {
        require(_exists(_id), "Error, wrong tokenId");
        require(nftTypeMap[_id] == NFT_TYPE.BUY, "Can not buy Auction NFT");
        require(msg.sender != ownerOf(_id), "Can not buy what you own");
        require(listedMap[_id], "Item not listed currently");
        require(msg.value >= price[_id], "Error, the amount is lower");
    }

    function _validateAuction(uint _id, uint _duraction) internal {
        require(_exists(_id), "Error, wrong tokenId");
        require(nftTypeMap[_id] == NFT_TYPE.AUCTION, "Can not Auction for Buy NFT");
        require(msg.sender == ownerOf(_id), "Can not auction for other's");
        require(_duraction > 0, "Can not auction for minus duration");
        require(listedMap[_id], "Item not listed currently");
    }

    function _validateBid(uint _id, uint _price) internal {
        require(_exists(_id), "Error, wrong tokenId");
        require(msg.sender != ownerOf(_id), "Can not buy what you own");
        require(listedMap[_id], "Item not listed currently");
        require(bidMap[_id][msg.sender].status != BID_STATUS.OPEN, "Error, Already existing Bid");
        require(nftTypeMap[_id] == NFT_TYPE.BUY || (nftTypeMap[_id] == NFT_TYPE.AUCTION && expireAuctionMap[_id] > block.timestamp), "Can bid for only Buy or Enabled Auction");


        uint allowanceAmount = wBNBToken.allowance(msg.sender, address(this));

        require(_price <= allowanceAmount, "Error, the allowance amount is lower");
        require(_price <= wBNBToken.balanceOf(msg.sender), "Error, the balance is lower");
        
    }

    function _validateCancelBid(uint _id) internal {
        require(_exists(_id), "Error, wrong tokenId");
        require(nftTypeMap[_id] == NFT_TYPE.BUY, "Can not cancel bid for Auction NFT");
        require(msg.sender != ownerOf(_id), "Can not buy what you own");
        require(bidMap[_id][msg.sender].status == BID_STATUS.OPEN, "Error, Not existing Bid");
    }

    function _validateSell(uint _id, address _buyer) internal {
        require(_exists(_id), "Error, wrong tokenId");
        require(nftTypeMap[_id] == NFT_TYPE.BUY, "Can not sell manually for Auction NFT");
        require(msg.sender == ownerOf(_id), "Can not sell other's one");
        require(listedMap[_id], "Item not listed currently");
        
        require(bidMap[_id][msg.sender].status == BID_STATUS.OPEN, "Not exist bid");
        
        uint _price = bidMap[_id][_buyer].price;
        uint allowanceAmount = wBNBToken.allowance(_buyer, address(this));

        require(_price <= allowanceAmount, "Error, the allowance amount is lower");
        require(_price <= wBNBToken.balanceOf(_buyer), "Error, the balance is lower");
    }



    function _trade(uint _id) internal {
        address payable _buyer = payable(msg.sender);
        address payable _owner = payable(ownerOf(_id));

        _transfer(_owner, _buyer, _id);

        // 2.5% commission cut
        uint _commissionValue = price[_id] / 40 ;
        uint _sellerValue = price[_id] - _commissionValue;

        _owner.transfer(_sellerValue);
        _contractOwner.transfer(_commissionValue);

        // If buyer sent more than price, we send them back their rest of funds
        if (msg.value > price[_id]) {
            _buyer.transfer(msg.value - price[_id]);
        }

        listedMap[_id] = false;
    }

    function _sell(uint _id, address _buyer, uint _price) internal {
        address _owner = payable(ownerOf(_id));

        _transfer(_owner, _buyer, _id);

        // 2.5% commission cut
        uint _commissionValue = _price / 40 ;
        uint _sellerValue = _price - _commissionValue;

        wBNBToken.transferFrom(_buyer, _contractOwner, _commissionValue);
        wBNBToken.transferFrom(_buyer, _owner, _sellerValue);

        // listedMap[_id] = false;
    }

    function _cancelBid (uint _id, address _buyer) internal {
        Bid memory _bid = bidMap[_id][_buyer];
        uint _bidId = _bid.id;
        bidArray[_id][_bidId].status = BID_STATUS.CANCELLED;

        delete bidMap[_id][_buyer];
    }

    function _cleanBid(uint _id) internal {

        for (uint i = 0; i < bidArray[_id].length; i++)
        {
            Bid memory _bid = bidArray[_id][i];
            address _buyer = _bid.bidder;
            
            delete bidMap[_id][_buyer];
        }
        
        delete bidArray[_id];
    }

    function _processAuction() internal {
        uint curTimeStamp = block.timestamp;
        for (uint _tokenId = 0; _tokenId < totalSupply(); _tokenId++)
        {
            if (_exists(_tokenId))
            {
                if (nftTypeMap[_tokenId] == NFT_TYPE.AUCTION && expireAuctionMap[_tokenId] < curTimeStamp)
                {
                    uint top_price = 0;
                    address top_buyer;

                    for (uint i = 0; i < bidArray[_tokenId].length; i++)
                    {
                        Bid memory _bid = bidArray[_tokenId][i];
                        if (_bid.status == BID_STATUS.OPEN && top_price < _bid.price && wBNBToken.allowance(_bid.bidder, address(this)) >= _bid.price && wBNBToken.balanceOf(_bid.bidder) > _bid.price)
                        {
                            top_price = _bid.price;
                            top_buyer = _bid.bidder;
                        }
                    }

                    if (top_price > 0)
                    {
                        _sell(_tokenId, top_buyer, top_price);
                        _cleanBid(_tokenId);

                        address _previousOwner = ownerOf(_tokenId);
                        address _newOwner = top_buyer;

                        emit Purchase(_previousOwner, _newOwner, top_price, _tokenId, tokenURI(_tokenId));
                    }
                }
            }
        }
    }
    


} 