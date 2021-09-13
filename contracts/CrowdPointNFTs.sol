// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "openzeppelin-solidity/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "openzeppelin-solidity/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

contract CrowdPointNFT is ERC721URIStorage, ERC721Enumerable, Ownable {
    using SafeMath for uint256;
    using Address for address;
    using Strings for uint256;

    enum NFT_TYPE {NONE, FIXED_PRICE, AUCTION, UNLIMITED_AUCTION}
    
    struct BidEntity{
        uint256 tokenId;
        address buyer;
        uint256 price;
    }

    struct NFTAttribute{
        NFT_TYPE nftType;
        address creator;
        bool listed;
        uint256 royalty;
        uint256 price;
        uint256 minBidPrice;
        uint256 startTimestamp;
        uint256 endTimestamp;
    }

    IERC20 public paymentToken;
    
    uint256 private mintIndex = 0;

    address public feeAddress;
    uint256 public feePercent = 3;

    mapping (uint256=>NFTAttribute) public mapNFTAttribute;

    mapping (uint256=>BidEntity[]) public bidArrayOfToken;
    mapping (uint256=>mapping(address=>bool)) public bidStatusOfToken;

    string private bulkMintBaseUrl = "";
    uint256 private bulkMintLimit = 0;
    uint256 private bulkMintIndex = 0;



    event MintedFixedToken(address indexed minter, uint256 price, uint256 nftID, uint256 royalty, string uri);
    event PriceUpdate(address indexed owner, uint256 oldPrice, uint256 newPrice, uint256 nftID);
    event Purchase(address indexed previousOwner, address indexed newOwner, uint256 price, uint256 nftID, string uri);
    
    event MintedAuctionToken(address indexed minter, uint256 minBidPrice, uint256 startTime, uint256 endTime, uint256 nftID, uint256 royalty, string uri);
    event AuctionStart(address indexed owner, uint256 minBidPrice, uint256 startTime, uint256 endTime, uint256 nftID);
    event Sell(address indexed previousOwner, address indexed newOwner, uint256 bidPrice, uint256 nftID, string uri);
    event MintedUnlimitedToken(address indexed minter, uint256 nftID, uint256 royalty, string uri);

    event NftListStatus(address indexed owner, uint256 nftID, bool isListed);

    event Burned(uint256 nftID);
    event BidCreate(address indexed buyer, uint nftID, uint price);
    event BidCancel(address indexed buyer, uint nftID);



    constructor(address _paymentToken) ERC721("CrowdPoint NFTs", "CROWDPOINT") {
        feeAddress = _msgSender();
        paymentToken = IERC20(_paymentToken);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override (ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }
    function _burn(uint256 tokenId) internal virtual override (ERC721, ERC721URIStorage){
        super._burn(tokenId);
    }
    function tokenURI(uint256 tokenId) public view virtual override (ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    function supportsInterface(bytes4 interfaceId) public view virtual override (ERC721, ERC721Enumerable) returns (bool) {
        return interfaceId == type(IERC721Enumerable).interfaceId
            || super.supportsInterface(interfaceId);
    }

    modifier _validateBuy(uint256 _id) {
        require(_exists(_id), "Error, wrong tokenId");
        require(mapNFTAttribute[_id].nftType == NFT_TYPE.FIXED_PRICE, "Error, NFT Type Should be Fixed");
        require(mapNFTAttribute[_id].listed, "Item not listed currently");
        require(msg.value >= mapNFTAttribute[_id].price, "Error, the amount is lower");
        require(_msgSender() != ownerOf(_id), "Can not buy what you own");
        _;
    }

    modifier _validateBid(uint256 _id, uint256 _price) {
        require(_exists(_id), "Error, wrong tokenId");
        require(mapNFTAttribute[_id].nftType == NFT_TYPE.AUCTION || mapNFTAttribute[_id].nftType == NFT_TYPE.UNLIMITED_AUCTION, "Error, NFT Type Should be Auction");
        require(mapNFTAttribute[_id].listed, "Item not listed currently");
        require(_price > 0, "Error, the amount is lower than 0");
        require(_msgSender() != ownerOf(_id), "Can not bid what you own");
        require(bidStatusOfToken[_id][_msgSender()] == false, "Can not several bid");
        
        if (mapNFTAttribute[_id].nftType == NFT_TYPE.AUCTION){
            require(block.timestamp >= mapNFTAttribute[_id].startTimestamp && block.timestamp <= mapNFTAttribute[_id].endTimestamp, "Error, Out of Auction Time Range");
            (, uint256 topBidPrice) = getTopBid(_id);
            require(_price > topBidPrice, "Error, bid price should be over than top bid price");
            require(_price > mapNFTAttribute[_id].minBidPrice, "Error, bid price should be over than minimum bid price");
        }            
        _;
    }

    modifier _validateCancelBid(uint256 _id) {
        require(_exists(_id), "Error, wrong tokenId");
        require(mapNFTAttribute[_id].nftType == NFT_TYPE.AUCTION || mapNFTAttribute[_id].nftType == NFT_TYPE.UNLIMITED_AUCTION, "Error, NFT Type Should be Auction");
        require(mapNFTAttribute[_id].listed, "Item not listed currently");
        require(_msgSender() != ownerOf(_id), "Can not cancel bid what you own");
        require(bidStatusOfToken[_id][_msgSender()] == true, "You never bidded");
        _;
    }

    modifier _validateSell(uint256 _id, address _buyer) {
        require(_exists(_id), "Error, wrong tokenId");
        require(mapNFTAttribute[_id].nftType == NFT_TYPE.AUCTION || mapNFTAttribute[_id].nftType == NFT_TYPE.UNLIMITED_AUCTION, "Error, NFT Type Should be Auction");
        require(mapNFTAttribute[_id].listed, "Item not listed currently");
        require(_msgSender() == ownerOf(_id), "Only owner can sell");
        require(bidStatusOfToken[_id][_buyer] == true, "Can sell to only bidder");

        uint256 _bidPrice = getPriceOfBid(_id, _buyer);
        require(_bidPrice <= paymentToken.allowance(_buyer, address(this)), "Error, the allowance amount is lower");
        require(_bidPrice <= paymentToken.balanceOf(_buyer), "Error, the balance is lower");
        _;
    }
    
    modifier _validateStartAuction(uint256 _id) {
        require(_exists(_id), "Error, wrong tokenId");
        require(mapNFTAttribute[_id].nftType == NFT_TYPE.AUCTION, "Error, NFT Type Should be Auction");
        require(mapNFTAttribute[_id].listed == false, "Item is listed currently");
        require(_msgSender() == ownerOf(_id), "Only owner can sell");
        _;
    }

    modifier _validateConfirmAuction(uint256 _id) {
        require(_exists(_id), "Error, wrong tokenId");
        require(mapNFTAttribute[_id].nftType == NFT_TYPE.AUCTION, "Error, NFT Type Should be Unlimited Auction");
        require(mapNFTAttribute[_id].listed, "Item not listed currently");
        require(_msgSender() == ownerOf(_id), "Only owner can sell");
        require(block.timestamp > mapNFTAttribute[_id].endTimestamp, "Error, Auction Time is not ended yet");
        _;
    }

    modifier _validateOwnerOfToken(uint256 _id) {
        require(_exists(_id), "Error, wrong tokenId");
        require(_msgSender() == ownerOf(_id), "Only Owner Can Burn");
        _;
    }

    function setFee(address _feeAddress, uint256 _feePercent) external onlyOwner {
        feeAddress = _feeAddress;
        feePercent = _feePercent;
    }

    function setBulkMintBaseUrl(string memory _bulkMintBaseUrl, uint256 _bulkMintLimit) external onlyOwner {
        bulkMintBaseUrl = _bulkMintBaseUrl;
        bulkMintLimit = _bulkMintLimit;
        bulkMintIndex = 0;
    }
    function bulkMint(uint256 _numberOfToken, uint256 _price, uint256 _royalty) external onlyOwner {
        for(uint i = 0; i < _numberOfToken; i++){
            if (bulkMintIndex >= bulkMintLimit) return;
            string memory _tokenUri = string(abi.encodePacked(bulkMintBaseUrl, bulkMintIndex.toString()));
            mintFixed(_tokenUri, _price, _royalty);
            bulkMintIndex = bulkMintIndex.add(1);
        }
    }
    

    function mintFixed(string memory _tokenURI, uint256 _price, uint256 _royalty) public returns (uint256) {
        uint256 _tokenId = mintIndex;
        mintIndex = mintIndex.add(1);
        mapNFTAttribute[_tokenId].nftType = NFT_TYPE.FIXED_PRICE;
        mapNFTAttribute[_tokenId].creator = _msgSender();
        mapNFTAttribute[_tokenId].royalty = _royalty;
        mapNFTAttribute[_tokenId].listed = true;
        mapNFTAttribute[_tokenId].price = _price;

        _safeMint(_msgSender(), _tokenId);
        _setTokenURI(_tokenId, _tokenURI);

        emit MintedFixedToken(_msgSender(), _price, _tokenId, _royalty, _tokenURI);

        return _tokenId;
    }

    function mintAuction(string memory _tokenURI, uint256 _minBidPrice, uint256 _startTime, uint256 _endTime, uint256 _royalty) external returns (uint256) {
        uint256 _tokenId = mintIndex;
        mintIndex = mintIndex.add(1);
        mapNFTAttribute[_tokenId].nftType = NFT_TYPE.AUCTION;
        mapNFTAttribute[_tokenId].creator = _msgSender();
        mapNFTAttribute[_tokenId].royalty = _royalty;
        mapNFTAttribute[_tokenId].listed = true;
        mapNFTAttribute[_tokenId].minBidPrice = _minBidPrice;
        mapNFTAttribute[_tokenId].startTimestamp = _startTime;
        mapNFTAttribute[_tokenId].endTimestamp = _endTime;

        _safeMint(_msgSender(), _tokenId);
        _setTokenURI(_tokenId, _tokenURI);

        emit MintedAuctionToken(_msgSender(), _minBidPrice, _startTime, _endTime, _tokenId, _royalty, _tokenURI);

        return _tokenId;
    }

    function mintUnlimitedAuction(string memory _tokenURI, uint256 _royalty) external returns (uint256) {
        uint256 _tokenId = mintIndex;
        mintIndex = mintIndex.add(1);
        mapNFTAttribute[_tokenId].nftType = NFT_TYPE.UNLIMITED_AUCTION;
        mapNFTAttribute[_tokenId].creator = _msgSender();
        mapNFTAttribute[_tokenId].royalty = _royalty;
        mapNFTAttribute[_tokenId].listed = true;

        _safeMint(_msgSender(), _tokenId);
        _setTokenURI(_tokenId, _tokenURI);

        emit MintedUnlimitedToken(_msgSender(), _tokenId, _royalty, _tokenURI);

        return _tokenId;
    }

    function burn(uint256 _id) external _validateOwnerOfToken(_id) {
        _burn(_id);
        delete mapNFTAttribute[_id];

        // Remove all Bid List
        for(uint256 i = 0; i < bidArrayOfToken[_id].length; i++)
        {
            bidStatusOfToken[_id][bidArrayOfToken[_id][i].buyer] = false;
        }
        delete bidArrayOfToken[_id];
        
        emit Burned(_id);
    }

    function buy(uint256 _id) external payable _validateBuy(_id) {
        address _previousOwner = ownerOf(_id);
        address _newOwner = _msgSender();

        address payable _buyer = payable(_newOwner);
        address payable _owner = payable(_previousOwner);

        _transfer(_owner, _buyer, _id);

        uint256 _royaltyValue = mapNFTAttribute[_id].price.div(10**2).mul(mapNFTAttribute[_id].royalty);
        uint256 _commissionValue = mapNFTAttribute[_id].price.div(10**2).mul(feePercent);
        uint256 _sellerValue = mapNFTAttribute[_id].price.sub(_commissionValue).sub(_royaltyValue);

        _owner.transfer(_sellerValue);
        payable(feeAddress).transfer(_commissionValue);
        payable(mapNFTAttribute[_id].creator).transfer(_royaltyValue);

        // If buyer sent more than price, we send them back their rest of funds
        if (msg.value > mapNFTAttribute[_id].price) {
            _buyer.transfer(msg.value.sub(mapNFTAttribute[_id].price));
        }

        mapNFTAttribute[_id].listed = false;

        emit Purchase(_previousOwner, _newOwner, mapNFTAttribute[_id].price, _id, tokenURI(_id));
    }

    function bid(uint256 _id, uint256 _price) external _validateBid(_id, _price){
        BidEntity memory newBidEntity = BidEntity(_id, _msgSender(), _price);
        bidArrayOfToken[_id].push(newBidEntity);
        bidStatusOfToken[_id][_msgSender()] = true;

        emit BidCreate(_msgSender(), _id, _price);
    }

    function cancelBid(uint256 _id) external _validateCancelBid(_id){
        for(uint256 i = 0; i < bidArrayOfToken[_id].length; i++)
        {
            if (bidArrayOfToken[_id][i].buyer == _msgSender())
            {
                bidArrayOfToken[_id][i] = bidArrayOfToken[_id][bidArrayOfToken[_id].length - 1];
                bidArrayOfToken[_id].pop();
                break;
            }
        }
        bidStatusOfToken[_id][_msgSender()] = false;

        emit BidCancel(_msgSender(), _id);
    }

    function sell(uint256 _id, address _buyer) public _validateSell(_id, _buyer){
        address _owner = ownerOf(_id);

        _transfer(_owner, _buyer, _id);

        uint256 _price = getPriceOfBid(_id, _buyer);

        uint256 _royaltyValue = _price.div(10**2).mul(mapNFTAttribute[_id].royalty);
        uint256 _commissionValue = _price.div(10**2).mul(feePercent);
        uint256 _sellerValue = _price.sub(_commissionValue).sub(_royaltyValue);

        paymentToken.transferFrom(_buyer, mapNFTAttribute[_id].creator, _royaltyValue);
        paymentToken.transferFrom(_buyer, feeAddress, _commissionValue);
        paymentToken.transferFrom(_buyer, _owner, _sellerValue);

        mapNFTAttribute[_id].listed = false;

        // Remove all Bid List
        for(uint256 i = 0; i < bidArrayOfToken[_id].length; i++)
        {
            bidStatusOfToken[_id][bidArrayOfToken[_id][i].buyer] = false;
        }
        delete bidArrayOfToken[_id];

        emit Sell(_owner, _buyer, _price, _id, tokenURI(_id));
    }

    function startAuction(uint256 _tokenId, uint256 _minBidPrice, uint256 _startTime, uint256 _endTime) external _validateStartAuction(_tokenId){
        mapNFTAttribute[_tokenId].minBidPrice = _minBidPrice;
        mapNFTAttribute[_tokenId].startTimestamp = _startTime;
        mapNFTAttribute[_tokenId].endTimestamp = _endTime;
        mapNFTAttribute[_tokenId].listed = true;

        emit AuctionStart(_msgSender(), _minBidPrice, _startTime, _endTime, _tokenId);
    }

    function claimAuction(uint256 _tokenId) external _validateConfirmAuction(_tokenId){
        (address _topBidder,) = getTopBid(_tokenId);
        if (_topBidder == address(0)){
            mapNFTAttribute[_tokenId].listed = false;

            // Remove all Bid List
            for(uint256 i = 0; i < bidArrayOfToken[_tokenId].length; i++)
            {
                bidStatusOfToken[_tokenId][bidArrayOfToken[_tokenId][i].buyer] = false;
            }
            delete bidArrayOfToken[_tokenId];

            emit NftListStatus(_msgSender(), _tokenId, mapNFTAttribute[_tokenId].listed);
        } else {
            sell(_tokenId, _topBidder);
        }
    }

    function updatePrice(uint256 _tokenId, uint256 _price) external _validateOwnerOfToken(_tokenId){
        require(mapNFTAttribute[_tokenId].nftType == NFT_TYPE.FIXED_PRICE, "NFT Type should be Fixed");
        uint256 oldPrice = mapNFTAttribute[_tokenId].price;
        mapNFTAttribute[_tokenId].price = _price;

        emit PriceUpdate(_msgSender(), oldPrice, _price, _tokenId);
    }

    function updateListingStatus(uint256 _tokenId, bool shouldBeListed) external _validateOwnerOfToken(_tokenId){
        require(mapNFTAttribute[_tokenId].listed != shouldBeListed, "Status is already changed!");
        mapNFTAttribute[_tokenId].listed = shouldBeListed;

        // Remove all Bid List
        for(uint256 i = 0; i < bidArrayOfToken[_tokenId].length; i++)
        {
            bidStatusOfToken[_tokenId][bidArrayOfToken[_tokenId][i].buyer] = false;
        }
        delete bidArrayOfToken[_tokenId];

        emit NftListStatus(_msgSender(), _tokenId, shouldBeListed);
    }

    function getPriceOfBid(uint256 _id, address _buyer) public view returns(uint256){
        for(uint256 i = 0; i < bidArrayOfToken[_id].length; i++)
        {
            if (bidArrayOfToken[_id][i].buyer == _buyer)
            {
                return bidArrayOfToken[_id][i].price;
            }
        }
        return 0;
    }

    function getTopBid(uint256 _id) public view returns(address, uint256){
        address _bidder = address(0);
        uint256 _topBidPrice = 0;
        for(uint256 i = 0; i < bidArrayOfToken[_id].length; i++)
        {
            if (bidArrayOfToken[_id][i].price > _topBidPrice)
            {
                _topBidPrice = bidArrayOfToken[_id][i].price;
                _bidder = bidArrayOfToken[_id][i].buyer;
            }
        }
        return (_bidder, _topBidPrice);
    }
}
